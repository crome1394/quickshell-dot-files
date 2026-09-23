import QtQuick
import "../components"
import "../components/dockFx.js" as DockFx
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland

// =============================================================================
// QuickLaunchPill.qml — Quick launch row
// =============================================================================
//
// Purpose:
//   Horizontal row of icon buttons inside a pill. Apps and icons are defined in
//   Config.qml defaults (search QUICK LAUNCH); runtime list is bar.quickLaunchApps
//   (editable from BarControlBar → Launch, persisted in bar-layout.json).
//
//   Running apps get a Mac-dock-style accent dot under the icon (any workspace,
//   including magic). Icons stay the same size and baseline; focused is the same
//   dot, a bit brighter — no workspace-chip fill.
//
// Theme Properties Consumed:
//   - bar.pillRadius, bar.pillBg, bar.pillBorder, bar.accent, bar.wsActiveBg
//   - bar.iconHoverBg, bar.workspaceRadius  (per-icon hover; Config.qml)
//   - bar.quickLaunchIcon, bar.quickLaunchSpacing, bar.quickLaunchPaddingH
//   - bar.quickLaunchApps, bar.fontFamily, bar.controlBorderWidth, bar.tooltipDelay
// =============================================================================

Rectangle {
    id: root

    required property var bar

    // Local copy so Repeater rebinds when shell replaces the array
    property var appsModel: bar.quickLaunchApps || []

    // Bumped when Hyprland toplevels change so icon cells re-evaluate running/focus.
    property int toplevelTick: 0
    property int _qlColdPollCount: 0

    // Horizontal scale only. Cell sizes already include _ws — do NOT multiply the
    // total width by _ws again (that was shrinking the chrome under the icons).
    readonly property real _ws: (bar.widgetScale ? bar.widgetScale("quickLaunch") : 1.0)
    readonly property int _icon: Math.max(12, Math.round(bar.quickLaunchIcon * _ws))
    readonly property int _pad: Math.max(4, Math.round(bar.quickLaunchPaddingH * _ws))
    readonly property int _gap: Math.max(2, Math.round(bar.quickLaunchSpacing * _ws))
    Layout.preferredWidth: Math.max(_icon + _pad * 2, appsRow.implicitWidth + _pad * 2)
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter
    // Magnify uses a scale transform; clipping would chop the icon.
    clip: false

    readonly property string _dockEffect: String(bar.dockEffect || "off")
    readonly property bool _dockMagnify: _dockEffect === "magnify" || _dockEffect === "both"
    property real dockHoverX: -1

    function dockPointerInPill() {
        if (!dockLeaveGuard.hovered)
            return false
        try {
            const p = dockLeaveGuard.point.position
            return p.x >= 0 && p.x <= root.width && p.y >= 0 && p.y <= root.height
        } catch (e) {
            return false
        }
    }

    function dockScaleFor(cell) {
        return DockFx.neighborMag(bar, root.dockHoverX, cell, root.dockPointerInPill(), false)
    }

    radius: bar.pillRadius
    // Outer chrome is stable; each app icon highlights on its own.
    color: bar.pillBg
    border.width: bar.controlBorderWidth
    border.color: bar.pillBorder

    Connections {
        target: bar
        function onQuickLaunchAppsChanged() {
            root.appsModel = bar.quickLaunchApps || [];
        }
    }

    function bumpToplevels() {
        root.toplevelTick++;
    }

    function foldToken(s) {
        return String(s || "").toLowerCase().replace(/[\s_]+/g, "-").trim();
    }

    function addMatchToken(tokens, s) {
        const t = root.foldToken(s);
        if (!t)
            return;
        if (tokens.indexOf(t) === -1)
            tokens.push(t);
        const last = t.split(".").pop();
        const skipLast = last === "desktop" || last === "application" || last === "electron" || last === "wayland";
        if (last && last !== t && last.length >= 4 && !skipLast && tokens.indexOf(last) === -1)
            tokens.push(last);
        const stripped = t.replace(/-stable$/, "").replace(/-bin$/, "");
        if (stripped && stripped !== t && tokens.indexOf(stripped) === -1)
            tokens.push(stripped);
    }

    function commandArgs(cmd) {
        const args = [];
        if (typeof cmd === "string") {
            const parts = cmd.split(/\s+/);
            for (let i = 0; i < parts.length; i++) {
                if (parts[i].length)
                    args.push(parts[i]);
            }
            return args;
        }
        if (!cmd || cmd.length === undefined)
            return args;
        for (let i = 0; i < cmd.length; i++)
            args.push(String(cmd[i]));
        return args;
    }

    function entryMatchTokens(entry) {
        const tokens = [];
        if (!entry)
            return tokens;

        const mc = entry.matchClass;
        if (typeof mc === "string") {
            root.addMatchToken(tokens, mc);
        } else if (mc && mc.length !== undefined) {
            for (let i = 0; i < mc.length; i++)
                root.addMatchToken(tokens, mc[i]);
        }

        const args = root.commandArgs(entry.command);
        let i = 0;
        if (args[0] === "env") {
            i = 1;
            while (i < args.length && args[i].indexOf("=") !== -1)
                i++;
        }
        if (args[i] === "gtk-launch" && args[i + 1]) {
            root.addMatchToken(tokens, String(args[i + 1]).replace(/\.desktop$/i, ""));
        } else if (args[i] === "flatpak") {
            for (let j = i + 1; j < args.length; j++) {
                if (args[j] === "run" || args[j].charAt(0) === "-")
                    continue;
                root.addMatchToken(tokens, args[j]);
                break;
            }
        } else if (args[i]) {
            const base = args[i].split("/").pop();
            root.addMatchToken(tokens, base);
        }
        return tokens;
    }

    function toplevelMatchTokens(tl) {
        const tokens = [];
        if (!tl)
            return tokens;
        const ipc = tl.lastIpcObject || {};
        root.addMatchToken(tokens, ipc["class"]);
        root.addMatchToken(tokens, ipc.initialClass);
        if (tl.wayland)
            root.addMatchToken(tokens, tl.wayland.appId);
        return tokens;
    }

    function tokensHit(entryTokens, tlTokens) {
        if (!entryTokens || !tlTokens)
            return false;
        for (let i = 0; i < entryTokens.length; i++) {
            const a = entryTokens[i];
            for (let j = 0; j < tlTokens.length; j++) {
                const b = tlTokens[j];
                if (a === "steam" || b === "steam") {
                    if (a === "steam" && b === "steam")
                        return true;
                    continue;
                }
                if (a === b)
                    return true;
                const aLast = a.split(".").pop();
                const bLast = b.split(".").pop();
                if (aLast === b || bLast === a)
                    return true;
                if (aLast === bLast && aLast.length >= 4)
                    return true;
            }
        }
        return false;
    }

    function entryMatchesToplevel(entry, tl) {
        return root.tokensHit(root.entryMatchTokens(entry), root.toplevelMatchTokens(tl));
    }

    function entryIsRunning(entry, tick) {
        void tick;
        if (!entry || !Hyprland.toplevels || !Hyprland.toplevels.values)
            return false;
        const values = Hyprland.toplevels.values;
        for (let i = 0; i < values.length; i++) {
            if (root.entryMatchesToplevel(entry, values[i]))
                return true;
        }
        return false;
    }

    function entryIsFocused(entry, tick) {
        void tick;
        return root.entryMatchesToplevel(entry, Hyprland.activeToplevel);
    }

    function launchEntry(entry) {
        if (!entry || entry.command === undefined || entry.command === null)
            return;
        const cmd = entry.command;
        // String form: "gtk-launch firefox" (runs through shell)
        if (typeof cmd === "string") {
            if (cmd.length > 0)
                Quickshell.execDetached(["sh", "-c", cmd]);
            return;
        }

        // List form from Config.qml — QML lists are not JS arrays (Array.isArray is false).
        const args = [];
        const len = cmd.length;
        if (len === undefined || len <= 0)
            return;
        for (let i = 0; i < len; i++)
            args.push(cmd[i]);
        if (args.length > 0)
            Quickshell.execDetached(args);
    }

    function entryUsesGlyph(entry) {
        return entry && (!entry.icon || entry.icon.length === 0) && entry.glyph && entry.glyph.length > 0;
    }

    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() {
            root.bumpToplevels();
        }
    }
    Connections {
        target: Hyprland
        function onActiveToplevelChanged() {
            root.bumpToplevels();
        }
        function onRawEvent(event) {
            const name = event.name;
            if (name === "openwindow" || name === "closewindow" || name === "activewindow" || name === "activewindowv2" || name === "movewindow" || name === "movewindowv2" || name === "urgent") {
                root.bumpToplevels();
            }
        }
    }

    Timer {
        id: qlColdStartPoller
        interval: 150
        repeat: true
        running: true
        onTriggered: {
            Hyprland.refreshToplevels();
            root.bumpToplevels();
            root._qlColdPollCount += 1;
            if (root._qlColdPollCount >= 8)
                stop();
        }
    }

    Component.onCompleted: {
        Hyprland.refreshToplevels();
        root.bumpToplevels();
    }

    HoverHandler {
        id: dockLeaveGuard
        enabled: root._dockMagnify
        onHoveredChanged: {
            if (!hovered)
                root.dockHoverX = -1
        }
        onPointChanged: {
            const p = point.position
            if (!hovered || p.x < 0 || p.x > root.width || p.y < 0 || p.y > root.height) {
                root.dockHoverX = -1
                return
            }
            root.dockHoverX = root.mapToItem(appsRow, p.x, p.y).x
        }
    }

    // Scaled last-icon hit boxes can miss the leave event; poll the unscaled pill.
    Timer {
        interval: 50
        running: root._dockMagnify && root.dockHoverX >= 0
        repeat: true
        onTriggered: {
            if (!root.dockPointerInPill())
                root.dockHoverX = -1
        }
    }

    Row {
        id: appsRow
        anchors.centerIn: parent
        spacing: root._gap

        Repeater {
            model: root.appsModel

            // Per-icon hover; running is a Mac-style dot, not a workspace chip.
            Rectangle {
                id: dockCell
                required property var modelData
                required property int index

                readonly property bool isRunning: root.entryIsRunning(modelData, root.toplevelTick)
                readonly property bool isFocused: root.entryIsFocused(modelData, root.toplevelTick)
                DockFace {
                    id: dockFx
                    bar: root.bar
                    host: dockCell
                    hovered: root.dockPointerInPill()
                    useNeighbor: true
                    neighborScale: root.dockScaleFor(dockCell)
                    respectScope: false
                }
                z: Math.round((dockFx.mag - 1) * 24)
                transform: [
                    Scale {
                        xScale: dockFx.mag
                        yScale: dockFx.mag
                        origin.x: dockCell.width / 2
                        origin.y: dockFx.growUp ? dockCell.height : 0
                    },
                    Translate { y: dockFx.jumpY }
                ]

                // Square cells, same size for every icon. Running is a Mac-style
                // dot in the bottom gutter — do not shift the icon for it.
                readonly property int _dot: Math.max(3, Math.round(root._icon * 0.2))
                width: root._icon + 10
                height: root._icon + 10
                radius: bar.workspaceRadius
                color: launchClick.containsMouse ? bar.iconHoverBg : "transparent"
                border.width: launchClick.containsMouse ? bar.controlBorderWidth : 0
                border.color: launchClick.containsMouse ? bar.accent : "transparent"
                Behavior on border.color {
                    ColorAnimation {
                        duration: 140
                        easing.type: Easing.OutQuad
                    }
                }
                clip: false

                Behavior on color {
                    ColorAnimation {
                        duration: 140
                        easing.type: Easing.OutQuad
                    }
                }

                Image {
                    visible: !root.entryUsesGlyph(modelData)
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 2
                    width: root._icon
                    height: root._icon
                    source: modelData.icon || ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }

                Text {
                    visible: root.entryUsesGlyph(modelData)
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 2
                    width: root._icon
                    height: root._icon
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.glyph || ""
                    font.pixelSize: root._icon
                    font.family: bar.fontFamily
                    color: launchClick.containsMouse ? bar.accent : (bar.iconColor !== undefined ? bar.iconColor : bar.subtext)
                }

                Rectangle {
                    visible: isRunning
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    width: dockCell._dot
                    height: dockCell._dot
                    radius: dockCell._dot / 2
                    color: isFocused
                           ? bar.accent
                           : Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.72)
                    Behavior on color {
                        ColorAnimation {
                            duration: 140
                            easing.type: Easing.OutQuad
                        }
                    }
                }

                MouseArea {
                    id: launchClick
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        dockFx.jump()
                        root.launchEntry(modelData)
                    }
                    onPositionChanged: (mouse) => {
                        if (!root._dockMagnify || !root.dockPointerInPill())
                            return
                        const p = mapToItem(appsRow, mouse.x, mouse.y)
                        root.dockHoverX = p.x
                    }
                    onContainsMouseChanged: {
                        if (!containsMouse && !root.dockPointerInPill())
                            root.dockHoverX = -1
                    }

                    BarToolTip {
                        bar: root.bar
                        widgetId: "quickLaunch"
                        visible: launchClick.containsMouse && (modelData.tooltip || "").length > 0
                        text: modelData.tooltip || ""
                        anchorItem: launchClick
                    }
                }
            }
        }
    }
}
