// Focused-window pill: top-left, Hyprland-only.
// Shows the focused window's app icon, class and title; hides when nothing is focused.
// Loaded by shell.qml as a per-screen overlay above application windows.
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

Variants {
    id: windows

    // Main bar PanelWindow (theme tokens + geometry). Set by shell.qml.
    required property var hostBar

    // Visibility + screen corner. shell.qml binds these to the persisted pref.
    property bool shown: true
    property string corner: "topLeft"
    // Classes, app ids, and titles that hide the pill. * is a wildcard.
    property var excludes: []

    // Case-insensitive. Without * the whole field must match, so a short
    // entry cannot hide a longer class. * matches any run of characters.
    function patternMatches(pattern, value) {
        var text = String(value || "")
        var pat = String(pattern || "").trim()
        if (pat.length < 2 || text.length === 0)
            return false
        if (pat.indexOf("*") < 0)
            return text.toLowerCase() === pat.toLowerCase()
        if (pat.replace(/\*/g, "").trim().length < 2)
            return false
        var escaped = pat.replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*")
        try {
            return new RegExp("^" + escaped + "$", "i").test(text)
        } catch (e) {
            return false
        }
    }

    // Inset from the screen edges. shell.qml centers the pill in the bar strip.
    property int topMargin: 6
    property int bottomMargin: 6
    property int leftMargin: 6
    property int rightMargin: 6
    // When set, the pill is vertically centered in a strip that starts at the edge.
    property int stripHeight: 0

    readonly property bool atTop: corner !== "bottomLeft" && corner !== "bottomRight"
    readonly property bool atLeft: corner !== "topRight" && corner !== "bottomRight"
    readonly property int edgeInset: {
        var base = atTop ? topMargin : bottomMargin
        if (stripHeight > pillHeight)
            return base + Math.round((stripHeight - pillHeight) / 2)
        return base
    }

    readonly property int pillHeight: (hostBar && hostBar.pillHeight > 0)
                                      ? hostBar.pillHeight : 30
    readonly property int hPadding: (hostBar && hostBar.pillHPadding > 0)
                                    ? Math.max(10, Math.round(hostBar.pillHPadding * 0.72)) : 12
    readonly property int iconGap: (hostBar && hostBar.iconTextGap > 0)
                                   ? hostBar.iconTextGap : 6
    readonly property int titleGap: (hostBar && hostBar.widgetSpacing > 0)
                                    ? Math.max(4, Math.round(hostBar.widgetSpacing * 0.75)) : 8
    readonly property int iconSize: (hostBar && hostBar.iconSizePill > 0)
                                    ? hostBar.iconSizePill : 18
    readonly property int fontSize: (hostBar && hostBar.fontBarFace > 0)
                                    ? hostBar.fontBarFace : 13
    readonly property int maxTitleWidth: {
        var screenWidth = (Quickshell.screens.length > 0) ? Quickshell.screens[0].width : 1920
        return Math.max(160, Math.min(480, Math.round(screenWidth * 0.30)))
    }

    readonly property color pillBg: (hostBar && hostBar.pillBg) ? hostBar.pillBg : "#cc1a1b26"
    readonly property color pillBorder: (hostBar && hostBar.pillBorder) ? hostBar.pillBorder : "#33ffffff"
    readonly property color fg: (hostBar && hostBar.barText) ? hostBar.barText : "#f0f4fc"
    readonly property color accent: (hostBar && hostBar.accent) ? hostBar.accent : "#00F0E0"
    readonly property int radius: (hostBar && hostBar.pillRadius > 0) ? hostBar.pillRadius : 8
    readonly property int borderWidth: (hostBar && hostBar.controlBorderWidth > 0)
                                       ? hostBar.controlBorderWidth : 1
    readonly property string fontFamily: {
        if (hostBar && hostBar.fontBarResolved && String(hostBar.fontBarResolved).length)
            return hostBar.fontBarResolved
        if (hostBar && hostBar.fontFamily && String(hostBar.fontFamily).length)
            return hostBar.fontFamily
        return "sans-serif"
    }

    // Hyprland's cached client "class" is not live. Games, the Calibre viewer,
    // and COSMIC apps often set it after the window is mapped.
    function refreshClasses() {
        Hyprland.refreshToplevels()
    }

    model: Quickshell.screens

    // Variants takes one delegate. Connections and the timer live inside it
    // so they are not treated as extra delegates.
    PanelWindow {
        id: activeWindowPanel
        required property var modelData
        screen: modelData

        Connections {
            target: Hyprland
            function onActiveToplevelChanged() {
                windows.refreshClasses()
                classRefresh.restart()
                activeWindowPanel.hasFocusedWindow = Hyprland.activeToplevel !== null
            }
            function onRawEvent(event) {
                if (event.name === "activewindowv2") {
                    activeWindowPanel.hasFocusedWindow = String(event.data || "").trim() !== ""
                } else if (event.name === "activewindow") {
                    const data = String(event.data || "")
                    const comma = data.indexOf(",")
                    activeWindowPanel.hasFocusedWindow = comma > 0 && data.slice(0, comma).trim() !== ""
                } else {
                    return
                }
                windows.refreshClasses()
                classRefresh.restart()
            }
        }

        // Quickshell 0.3.2 keeps the last toplevel when an empty workspace is
        // focused, so track Hyprland's activewindow events for the true state.
        property bool hasFocusedWindow: Hyprland.activeToplevel !== null

        Timer {
            id: classRefresh
            interval: 350
            repeat: false
            onTriggered: windows.refreshClasses()
        }

        Component.onCompleted: windows.refreshClasses()

        // Active window state. Class can arrive late, so check the live Wayland
        // app id, then the IPC class, then the title.
        readonly property var toplevel: Hyprland.activeToplevel
        readonly property var waylandToplevel: toplevel ? toplevel.wayland : null

        function field(obj, key) {
            if (!obj)
                return ""
            var value = obj[key]
            if (value === undefined || value === null)
                return ""
            return String(value)
        }

        function desktopEntryFor(id) {
            var name = String(id || "")
            if (name === "")
                return null
            if (name.slice(-8) === ".desktop")
                name = name.slice(0, -8)
            var entry = DesktopEntries.byId(name)
            if (!entry)
                entry = DesktopEntries.heuristicLookup(name)
            return entry
        }

        function iconUrl(iconName) {
            var name = String(iconName || "")
            if (name === "")
                return ""
            var path = Quickshell.iconPath(name, true)
            if (!path || path.length === 0)
                return ""
            if (path.indexOf("://") >= 0)
                return path
            if (path.charAt(0) === "/")
                return "file://" + path
            return path
        }

        readonly property string ipcClass: field(toplevel ? toplevel.lastIpcObject : null, "class")
        readonly property string ipcInitialClass: field(toplevel ? toplevel.lastIpcObject : null, "initialClass")
        readonly property string waylandAppId: waylandToplevel ? String(waylandToplevel.appId || "") : ""
        readonly property string winClass: {
            if (waylandAppId !== "")
                return waylandAppId
            if (ipcClass !== "")
                return ipcClass
            return ipcInitialClass
        }
        readonly property string winTitle: {
            var live = toplevel ? String(toplevel.title || "") : ""
            if (live !== "")
                return live
            var waylandTitle = waylandToplevel ? String(waylandToplevel.title || "") : ""
            if (waylandTitle !== "")
                return waylandTitle
            return field(toplevel ? toplevel.lastIpcObject : null, "initialTitle")
        }
        readonly property bool steamGame: winClass.indexOf("steam_app_") === 0
        readonly property string classLabel: {
            if (steamGame && winTitle !== "")
                return winTitle
            if (winClass !== "")
                return winClass
            return winTitle
        }
        readonly property var entry: {
            var found = desktopEntryFor(winClass)
            if (found)
                return found
            found = desktopEntryFor(ipcClass)
            if (found)
                return found
            return desktopEntryFor(ipcInitialClass)
        }
        readonly property string iconSource: {
            var fromEntry = entry ? iconUrl(entry.icon) : ""
            if (fromEntry !== "")
                return fromEntry
            if (steamGame)
                return iconUrl("steam")
            return iconUrl(winClass)
        }
        readonly property bool excluded: {
            var list = windows.excludes
            if (!list || list.length === 0)
                return false
            var fields = [waylandAppId, ipcClass, ipcInitialClass, winTitle, classLabel]
            for (var i = 0; i < list.length; i++) {
                var pattern = list[i]
                for (var f = 0; f < fields.length; f++) {
                    if (windows.patternMatches(pattern, fields[f]))
                        return true
                }
            }
            return false
        }

        // Only show on the monitor that holds the focused window
        readonly property bool onThisMonitor: {
            var focused = Hyprland.focusedMonitor
            if (!focused)
                return false
            if (focused.name === modelData.name)
                return true
            var mine = Hyprland.monitorFor(modelData)
            return mine !== null && mine.name === focused.name
        }

        visible: windows.shown && hasFocusedWindow && toplevel !== null && classLabel !== "" && onThisMonitor && !excluded

        anchors.top: windows.atTop
        anchors.bottom: !windows.atTop
        anchors.left: windows.atLeft
        anchors.right: !windows.atLeft
        margins.top: windows.atTop ? windows.edgeInset : 0
        margins.bottom: windows.atTop ? 0 : windows.edgeInset
        margins.left: windows.atLeft ? windows.leftMargin : 0
        margins.right: windows.atLeft ? 0 : windows.rightMargin
        // Stay on the screen edge and above normal windows. Overlay keeps it
        // visible over fullscreen games, which cover the normal top layer.
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        color: "transparent"
        implicitWidth: pill.implicitWidth
        implicitHeight: windows.pillHeight

        Rectangle {
            id: pill
            anchors.fill: parent
            implicitWidth: row.implicitWidth + windows.hPadding * 2
            radius: windows.radius
            color: windows.pillBg
            border.width: windows.borderWidth
            border.color: windows.pillBorder

            RowLayout {
                id: row
                anchors.centerIn: parent
                spacing: windows.iconGap

                Image {
                    visible: activeWindowPanel.iconSource !== ""
                    source: activeWindowPanel.iconSource
                    sourceSize.width: windows.iconSize
                    sourceSize.height: windows.iconSize
                    Layout.preferredWidth: windows.iconSize
                    Layout.preferredHeight: windows.iconSize
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    text: activeWindowPanel.classLabel
                    color: windows.accent
                    font.family: windows.fontFamily
                    font.pixelSize: windows.fontSize
                    font.bold: true
                }

                Text {
                    visible: activeWindowPanel.winTitle !== "" && activeWindowPanel.winTitle !== activeWindowPanel.classLabel
                    text: activeWindowPanel.winTitle
                    color: windows.fg
                    font.family: windows.fontFamily
                    font.pixelSize: windows.fontSize
                    elide: Text.ElideRight
                    Layout.maximumWidth: windows.maxTitleWidth
                    Layout.leftMargin: windows.titleGap
                }
            }
        }
    }
}
