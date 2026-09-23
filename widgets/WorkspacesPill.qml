import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../components"
import "../components/dockFx.js" as DockFx

// =============================================================================
// WorkspacesPill.qml — Dynamic workspace pills
// =============================================================================
//
// Purpose:
//   Shows numbered Hyprland workspace pills and an optional magic-space pill.
//   Display rules come from config.qml (via bar.*): minimum count, active-only
//   mode, and magic pill visibility (config default + IPC override).
//
// Config / bar properties consumed:
//   - bar.wsMinimumShown, bar.wsShowOnlyActive, bar.showMagicWorkspacePill
//   - bar.wsIconForId(id), bar.wsIconSpecial, bar.wsSpecialName, bar.wsIsSpecialName(name)
//   - bar.pillRadius, bar.glassPillBg, bar.pillBorder, bar.glassHover, bar.controlBorderWidth
//   - bar.wsButtonWidth, bar.wsButtonHeight, bar.workspaceRadius
//   - bar.wsSpacing, bar.wsIconSize, bar.wsNumberSize
//   - bar.wsActiveBg, bar.wsActiveBorder, bar.wsActiveText
//   - bar.iconHoverBg, bar.clock, bar.fontFamily
//
// IPC (runtime magic pill toggle):
//   qs ipc call shell setShowMagicWorkspacePill false
//   qs ipc call shell toggleShowMagicWorkspacePill
//
// Notes:
//   - Workspace icons live in config.qml (wsIcon1…wsIcon10, wsIconSpecial).
//   - Activation uses root.activateEntry() — do not store functions on model
//     objects (QML Repeater strips them from plain JS objects).
//   - After DPMS/idle, property signals can stall: raw socket2 events + a light
//     heartbeat (refreshWorkspaces) keep the pill in sync without a full qs restart.
// =============================================================================

Rectangle {
    id: root

    required property var bar

    // === Layout (works in any bar zone — left, center, or right) ===
    // Horizontal size only — chip widths/gaps scale; outer width matches once (no transform double-scale)
    readonly property real _ws: (bar.widgetScale ? bar.widgetScale("workspaces") : 1.0)
    readonly property int _btnW: Math.max(18, Math.round(bar.wsButtonWidth * _ws))
    readonly property int _btnH: bar.wsButtonHeight
    readonly property int _gap: Math.max(2, Math.round((bar.wsSpacing || 4) * _ws))
    Layout.preferredWidth: wsRow.implicitWidth + 16
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: Layout.preferredWidth
    implicitHeight: Layout.preferredHeight
    clip: false
    property real dockHoverX: -1

    HoverHandler {
        id: dockLeaveGuard
        enabled: {
            void bar.dockEffect
            void bar.dockScope
            return bar && typeof bar.dockMagnifyOn === "function" && bar.dockMagnifyOn()
                && typeof bar.dockScopeAll === "function" && bar.dockScopeAll()
        }
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
            root.dockHoverX = root.mapToItem(wsRow, p.x, p.y).x
        }
    }
    Timer {
        interval: 50
        running: dockLeaveGuard.enabled && root.dockHoverX >= 0
        repeat: true
        onTriggered: {
            if (!root.dockPointerInPill())
                root.dockHoverX = -1
        }
    }

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
        return DockFx.neighborMag(bar, root.dockHoverX, cell, root.dockPointerInPill(), true)
    }

    // === Appearance via config (bar aliases) ===
    // Outer chrome is stable; per-workspace buttons handle their own hover highlight.
    color: bar.glassPillBg
    radius: bar.pillRadius
    border.width: bar.controlBorderWidth
    border.color: bar.pillBorder

    // ===== Workspace logic (tightly coupled to this widget) =====
    property var shownWorkspaces: []

    // Live magic-overlay state. Do NOT snapshot this only into the model and hope
    // focusedWorkspace/valuesChanged fires — special is an overlay, so focus often
    // stays on the numbered workspace underneath and those signals never run.
    // Also: lastIpcObject.specialWorkspace is stale until refreshMonitors() finishes
    // asynchronously (see Quickshell HyprlandMonitor docs). Prefer activespecial events.
    property bool specialActive: false

    function workspaceHasWindows(w) {
        if (!w || !w.toplevels) return false;
        if (typeof w.toplevels.count === "number") return w.toplevels.count > 0;
        if (w.toplevels.values && typeof w.toplevels.values.length === "number") return w.toplevels.values.length > 0;
        return false;
    }

    // Extra numbered workspaces (6+) only appear when occupied or active.
    function shouldShowExtraWorkspace(w) {
        if (!w || w.id <= 0) return false;
        return workspaceHasWindows(w) || w.active || w.focused;
    }

    function makePlaceholderWorkspace(id, focusedId) {
        return {
            id: id,
            isSpecial: false,
            active: false,
            focused: focusedId === id
        };
    }

    // Magic is an overlay — focusedWorkspace often stays on the numbered ws below.
    // focus(N) alone is a no-op when N is already focused, so magic never closes.
    function closeMagicIfOpen() {
        if (root.specialActive) {
            Hyprland.dispatch("hl.dsp.workspace.toggle_special('" + bar.wsSpecialName + "')");
        }
    }

    // Central activation path — plain JS model objects cannot keep function props.
    // Hyprland 0.55+ lua configs require hl.dsp.* dispatch strings (legacy
    // "workspace N" / "togglespecialworkspace" IPC is rejected by hl.dispatch).
    function activateEntry(entry) {
        if (!entry) return;

        if (entry.isSpecial) {
            Hyprland.dispatch("hl.dsp.workspace.toggle_special('" + bar.wsSpecialName + "')");
            return;
        }

        if (entry.id > 0) {
            root.closeMagicIfOpen();
            // Guard: skip no-op focus when already on this workspace (reload-safe habits).
            const focused = Hyprland.focusedWorkspace;
            if (focused && focused.id === entry.id)
                return;
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + entry.id + " })");
        }
    }

    function refreshMonitors() {
        Hyprland.refreshMonitors()
    }

    // Read special workspace name from cached monitor IPC (may be stale until refresh).
    function specialNameFromMonitorIpc() {
        const mon = Hyprland.focusedMonitor
        if (!mon || !mon.lastIpcObject)
            return ""
        const sw = mon.lastIpcObject.specialWorkspace
        if (!sw)
            return ""
        return sw.name || ""
    }

    function isSpecialWorkspaceActive() {
        return root.specialActive
    }

    // Apply special-active state; rebuild pills only when it actually flips.
    function setSpecialActive(active) {
        const next = !!active
        if (root.specialActive === next)
            return
        root.specialActive = next
        root.updateShownWorkspaces()
    }

    function setSpecialActiveFromName(name) {
        const n = name || ""
        root.setSpecialActive(n.length > 0 && bar.wsIsSpecialName(n))
    }

    // Fallback sync after async refreshMonitors() (lastIpcObject updates later).
    function syncSpecialActiveFromMonitors() {
        root.setSpecialActiveFromName(root.specialNameFromMonitorIpc())
    }

    function requestSpecialSync() {
        root.refreshMonitors()
        specialSyncTimer.restart()
    }

    function findSpecialWorkspace() {
        if (!Hyprland.workspaces || !Hyprland.workspaces.values) return null;
        const values = Hyprland.workspaces.values;
        for (let i = 0; i < values.length; i++) {
            const w = values[i];
            if (w && w.id < 0 && bar.wsIsSpecialName(w.name)) return w;
        }
        return null;
    }

    function makeSpecialWorkspaceEntry() {
        const hyprWs = root.findSpecialWorkspace();
        const specialActive = root.specialActive;

        if (hyprWs) {
            return {
                id: hyprWs.id,
                isSpecial: true,
                active: specialActive,
                focused: specialActive
            };
        }

        return {
            id: -1,
            isSpecial: true,
            active: specialActive,
            focused: specialActive
        };
    }

    function workspaceMatchesFocus(entry, focusedWs) {
        if (!entry) return false;
        if (entry.isSpecial) return root.specialActive;
        if (root.specialActive) return false;
        if (!focusedWs || focusedWs.id <= 0) return false;
        return entry.id === focusedWs.id;
    }

    function updateShownWorkspaces() {
        const wsById = {};
        const idsToShow = {};

        if (Hyprland.workspaces && Hyprland.workspaces.values) {
            Hyprland.workspaces.values.forEach(function(w) {
                if (!w || w.id <= 0) return;
                wsById[w.id] = w;
                if (shouldShowExtraWorkspace(w)) idsToShow[w.id] = true;
            });
        }

        // config.wsShowOnlyActive false → always show pills 1..wsMinimumShown
        if (!bar.wsShowOnlyActive) {
            const minimum = Math.max(1, bar.wsMinimumShown || 1);
            for (let i = 1; i <= minimum; i++) {
                idsToShow[i] = true;
            }
        }

        const focusedId = (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id > 0)
            ? Hyprland.focusedWorkspace.id
            : 1;

        const sortedIds = Object.keys(idsToShow).map(Number).sort(function(a, b) { return a - b; });
        const result = [];
        if (bar.showMagicWorkspacePill) {
            result.push(root.makeSpecialWorkspaceEntry());
        }
        for (let i = 0; i < sortedIds.length; i++) {
            const id = sortedIds[i];
            result.push(wsById[id] || root.makePlaceholderWorkspace(id, focusedId));
        }

        root.shownWorkspaces = result;
    }

    // Match ~/.config/hypr/scripts/cycle-workspace.sh — cycle Hyprland workspaces
    // directly, not the visible pill list (which shrinks with wsShowOnlyActive and
    // breaks when magic is open: focus stayed on magic entry → only magic ↔ ws1).
    function switchToRelative(delta) {
        const onMagic = root.specialActive;
        const focusedWs = Hyprland.focusedWorkspace;
        const wsId = (focusedWs && focusedWs.id > 0) ? focusedWs.id : 1;
        const special = bar.wsSpecialName;

        if (delta > 0) {
            if (onMagic) {
                // Right from magic: close overlay, then land on ws 1 (cycle-workspace.sh)
                root.closeMagicIfOpen();
                Hyprland.dispatch("hl.dsp.focus({ workspace = 1 })");
            } else {
                Hyprland.dispatch("hl.dsp.focus({ workspace = \"+1\" })");
            }
        } else {
            if (onMagic) {
                root.closeMagicIfOpen();
            } else if (wsId === 1) {
                Hyprland.dispatch("hl.dsp.workspace.toggle_special('" + special + "')");
            } else {
                Hyprland.dispatch("hl.dsp.focus({ workspace = \"-1\" })");
            }
        }
    }

    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { root.updateShownWorkspaces(); }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            // Focus change can close magic without always pairing a useful valuesChanged.
            root.requestSpecialSync()
            root.updateShownWorkspaces();
        }
        function onActiveToplevelChanged() { root.updateShownWorkspaces(); }
        function onFocusedMonitorChanged() {
            root.requestSpecialSync()
            root.updateShownWorkspaces();
        }
        // Event instance is reused after this handler returns — copy fields first.
        function onRawEvent(event) {
            const name = event.name
            if (name === "activespecial" || name === "activespecialv2") {
                const argc = name === "activespecialv2" ? 3 : 2
                const args = event.parse(argc)
                // activespecial:    WORKSPACENAME, MONNAME
                // activespecialv2:  WORKSPACEID, WORKSPACENAME, MONNAME
                const wsName = name === "activespecialv2" ? (args[1] || "") : (args[0] || "")
                const monName = name === "activespecialv2" ? (args[2] || "") : (args[1] || "")
                const mon = Hyprland.focusedMonitor
                // Special is per-monitor; only the focused monitor drives the pill.
                if (monName && mon && mon.name && monName !== mon.name)
                    return
                root.setSpecialActiveFromName(wsName)
                // Keep lastIpcObject in sync for any other readers.
                root.refreshMonitors()
                return
            }
            // If property signals stall after DPMS/idle, socket2 events still recover the UI.
            if (name === "workspace" || name === "workspacev2"
                || name === "focusedmon" || name === "focusedmonv2"
                || name === "createworkspace" || name === "createworkspacev2"
                || name === "destroyworkspace" || name === "destroyworkspacev2"
                || name === "moveworkspace" || name === "moveworkspacev2"
                || name === "activewindow" || name === "activewindowv2"
                || name === "openwindow" || name === "closewindow") {
                root.updateShownWorkspaces()
            }
        }
    }
    // After refreshMonitors(), lastIpcObject updates asynchronously — re-sync then.
    Connections {
        target: Hyprland.focusedMonitor
        function onLastIpcObjectChanged() {
            root.syncSpecialActiveFromMonitors()
        }
    }
    Connections {
        target: bar
        function onShowMagicWorkspacePillChanged() { root.updateShownWorkspaces(); }
    }

    // Brief delay so refreshMonitors() can populate lastIpcObject before we read it.
    Timer {
        id: specialSyncTimer
        interval: 40
        repeat: false
        onTriggered: {
            root.syncSpecialActiveFromMonitors()
            root.updateShownWorkspaces()
        }
    }

    property int _wsColdPollCount: 0
    Timer {
        id: wsColdStartPoller
        interval: 130
        repeat: true
        onTriggered: {
            root.requestSpecialSync();
            root.updateShownWorkspaces();
            root._wsColdPollCount += 1;
            if (root._wsColdPollCount >= 7) {
                stop();
                root._wsColdPollCount = 0;
            }
        }
    }

    // Heartbeat: after long idle/DPMS, Hyprland property signals can go quiet while
    // the process stays up. Soft-refresh workspace state every few seconds so the
    // pill cannot stay permanently stuck (cheap vs. full bar restart).
    Timer {
        id: wsHeartbeat
        interval: 2500
        running: true
        repeat: true
        onTriggered: {
            try {
                Hyprland.refreshWorkspaces()
            } catch (e) {}
            root.syncSpecialActiveFromMonitors()
            root.updateShownWorkspaces()
        }
    }

    Component.onCompleted: {
        root.requestSpecialSync();
        root.updateShownWorkspaces();
        wsColdStartPoller.start();
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            const delta = (event.angleDelta.y > 0) ? 1 : -1;
            root.switchToRelative(delta);
        }
    }

    Row {
        id: wsRow
        anchors.centerIn: parent
        spacing: root._gap

        Repeater {
            model: root.shownWorkspaces
            delegate: Rectangle {
                id: wsBtn
                required property var modelData
                required property int index
                property bool isSpecial: !!(modelData && modelData.isSpecial)
                // Magic uses live root.specialActive (model snapshot was often stale).
                // While magic is open, the numbered ws underneath still reports focused
                // — don't light it as active so the 🪄 pill is the clear selection.
                property bool isActive: {
                    if (isSpecial)
                        return root.specialActive
                    if (root.specialActive)
                        return false
                    return !!(modelData && (modelData.active || modelData.focused))
                }
                property bool isHovered: wsMouse.containsMouse

                width: root._btnW
                height: root._btnH
                radius: bar.workspaceRadius
                color: isActive ? bar.wsActiveBg :
                       (isHovered ? bar.iconHoverBg : "transparent")
                border.width: (isActive || isHovered) ? bar.controlBorderWidth : 0
                border.color: isActive ? bar.wsActiveBorder
                              : (isHovered ? bar.accent : bar.dividerStrong)
                clip: false
                DockFace {
                    id: dockFx
                    bar: root.bar
                    host: wsBtn
                    hovered: root.dockPointerInPill()
                    useNeighbor: true
                    neighborScale: root.dockScaleFor(wsBtn)
                }
                z: Math.round((dockFx.mag - 1) * 24)
                transform: [
                    Scale {
                        xScale: dockFx.mag
                        yScale: dockFx.mag
                        origin.x: wsBtn.width / 2
                        origin.y: dockFx.growUp ? wsBtn.height : 0
                    },
                    Translate {
                        y: dockFx.jumpY
                    }
                ]

                Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }
                Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

                MouseArea {
                    id: wsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        dockFx.jump()
                        root.activateEntry(modelData)
                    }
                    onContainsMouseChanged: {
                        if (!containsMouse && !root.dockPointerInPill())
                            root.dockHoverX = -1
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 3

                    Text {
                        text: isSpecial
                              ? bar.wsIconSpecial
                              : bar.wsIconForId(modelData ? modelData.id : 0)
                        font.pixelSize: bar.wsIconSize
                        color: isActive ? bar.wsActiveText :
                               (isHovered ? (bar.buttonTextActive !== undefined ? bar.buttonTextActive : bar.accent)
                                          : (bar.wsInactiveText !== undefined ? bar.wsInactiveText : bar.text))
                        font.family: bar.fontFamily
                        font.bold: true
                    }
                    Text {
                        visible: !isSpecial
                        text: modelData ? modelData.id : ""
                        font.pixelSize: bar.wsNumberSize || 15
                        font.bold: true
                        color: isActive ? bar.wsActiveText :
                               (isHovered ? (bar.buttonTextActive !== undefined ? bar.buttonTextActive : bar.accent)
                                          : (bar.wsInactiveText !== undefined ? bar.wsInactiveText : bar.text))
                    }
                }
            }
        }
    }
}