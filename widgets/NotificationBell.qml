import QtQuick
import "../components"
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io as Io

// NotificationBell — SwayNC badge + history panel.
// Left-click: history (expand / copy / dismiss). Right-click: toggle DND.
// Daemon commands: Config.qml → NOTIFICATION BELL.
// History (survives reboot): scripts/notification-history.py
//   → ~/.local/state/quickshell/notification-history.json

Rectangle {
    id: root

    required property var bar
    required property Item barBg

    property int count: 0
    property bool dnd: false
    property bool inhibited: false

    // Local history (from notification-history.py watch / list)
    property var historyItems: []
    property bool allExpanded: false

    readonly property string bellGlyph: {
        if (dnd) return count > 0 ? "󰂠" : "󰪓"
        return count > 0 ? "󱅫" : "󰂜"
    }

    readonly property real _ws: (bar.widgetScale ? bar.widgetScale("notifications") : 1.0)
    Layout.preferredWidth: Math.round(42 * _ws)
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter
    clip: false
    DockFace {
        id: dockFx
        bar: root.bar
        host: root
        hovered: bellMouse.containsMouse
    }
    transform: [
        Scale {
            xScale: dockFx.mag
            yScale: dockFx.mag
            origin.x: root.width / 2
            origin.y: dockFx.growUp ? root.height : 0
        },
        Translate { y: dockFx.jumpY }
    ]

    radius: bar.pillRadius
    color: dnd
           ? (bellMouse.containsMouse ? Qt.rgba(0.55, 0.14, 0.14, 0.45) : Qt.rgba(0.40, 0.10, 0.10, 0.32))
           : (bellMouse.containsMouse ? bar.glassHover : bar.pillBg)
    border.width: bar.controlBorderWidth
    border.color: dnd
                  ? bar.notificationDndAccent
                  : (bellMouse.containsMouse ? bar.accent : bar.pillBorder)

    function historyScriptPath() {
        try {
            const local = Qt.resolvedUrl("../scripts/notification-history.py").toString().replace("file://", "")
            if (local && local.length)
                return local
        } catch (e) {}
        return "/home/crome/.config/quickshell/scripts/notification-history.py"
    }

    function applyState(j) {
        if (j === undefined || j === null) return
        if (j.count !== undefined && j.count !== null)
            root.count = Math.max(0, Number(j.count) || 0)
        if (j.dnd !== undefined && j.dnd !== null) {
            if (typeof j.dnd === "boolean")
                root.dnd = j.dnd
            else
                root.dnd = String(j.dnd).toLowerCase() === "true"
        }
        if (j.inhibited !== undefined && j.inhibited !== null) {
            if (typeof j.inhibited === "boolean")
                root.inhibited = j.inhibited
            else
                root.inhibited = String(j.inhibited).toLowerCase() === "true"
        }
    }

    function finishSyncPoll() {
        const line = (syncStdout.text || "").trim()
        if (!line.startsWith("{")) return
        try {
            root.applyState(JSON.parse(line))
        } catch (e) {}
    }

    function startSyncPoll() {
        if (!bar.notificationSyncEnabled() || syncProcess.running)
            return
        const args = bar.notificationCmdArray("sync")
        if (args.length <= 0)
            return
        syncProcess.exec(args)
    }

    function startSubscribe() {
        if (!bar.notificationUsesLiveSubscribe() || subscribeProcess.running)
            return
        const args = bar.notificationCmdArray("subscribe")
        if (args.length <= 0)
            return
        subscribeProcess.exec(args)
    }

    function startHistoryWatch() {
        if (historyWatchProcess.running)
            return
        const script = root.historyScriptPath()
        if (!script.length)
            return
        historyWatchProcess.exec(["python3", script, "watch"])
    }

    function loadHistoryOnce() {
        if (historyListProcess.running)
            return
        const script = root.historyScriptPath()
        if (!script.length)
            return
        historyListProcess.exec(["python3", script, "list"])
    }

    function applyHistoryList(arr) {
        if (!arr || arr.length === undefined)
            return
        const out = []
        for (let i = 0; i < arr.length; i++) {
            const it = arr[i]
            if (!it) continue
            out.push({
                id: it.id || ("n" + i),
                ts: Number(it.ts) || 0,
                app: String(it.app || "Notification"),
                summary: String(it.summary || ""),
                body: String(it.body || ""),
                icon: String(it.icon || ""),
                urgency: Number(it.urgency) || 1,
                expanded: !!it.expanded
            })
        }
        // Newest first
        out.sort(function (a, b) { return (b.ts || 0) - (a.ts || 0) })
        root.historyItems = out
        root.syncAllExpandedFlag()
    }

    function handleHistoryEvent(j) {
        if (!j) return
        if (j.type === "snapshot" && j.items)
            root.applyHistoryList(j.items)
        else if (j.type === "add" && j.item) {
            const list = root.historyItems.slice()
            const it = j.item
            const newId = String(it.id || ("n" + Date.now()))
            for (let i = 0; i < list.length; i++) {
                if (String(list[i].id || "") === newId)
                    return
            }
            list.unshift({
                id: newId,
                ts: Number(it.ts) || Math.floor(Date.now() / 1000),
                app: String(it.app || "Notification"),
                summary: String(it.summary || ""),
                body: String(it.body || ""),
                icon: String(it.icon || ""),
                urgency: Number(it.urgency) || 1,
                expanded: false
            })
            while (list.length > 80)
                list.pop()
            root.historyItems = list
            root.syncAllExpandedFlag()
        } else if ((j.type === "remove" || j.type === "dismiss") && j.id) {
            root.removeHistoryItemLocal(j.id)
        }
    }

    function refreshState() {
        root.startSyncPoll()
    }

    function syncAllExpandedFlag() {
        const list = root.historyItems || []
        if (!list.length) {
            root.allExpanded = false
            return
        }
        let all = true
        for (let i = 0; i < list.length; i++) {
            if (!list[i].expanded) {
                all = false
                break
            }
        }
        root.allExpanded = all
    }

    function setItemExpanded(index, on) {
        const list = root.historyItems.slice()
        if (index < 0 || index >= list.length)
            return
        const it = list[index]
        list[index] = {
            id: it.id,
            ts: it.ts,
            app: it.app,
            summary: it.summary,
            body: it.body,
            icon: it.icon,
            urgency: it.urgency,
            expanded: !!on
        }
        root.historyItems = list
        root.syncAllExpandedFlag()
    }

    function expandAllHistory(on) {
        const list = root.historyItems.slice()
        for (let i = 0; i < list.length; i++) {
            const it = list[i]
            list[i] = {
                id: it.id,
                ts: it.ts,
                app: it.app,
                summary: it.summary,
                body: it.body,
                icon: it.icon,
                urgency: it.urgency,
                expanded: !!on
            }
        }
        root.historyItems = list
        root.allExpanded = !!on && list.length > 0
    }

    function copyNotification(item) {
        if (!item)
            return
        const parts = []
        if (item.app)
            parts.push(String(item.app))
        if (item.summary)
            parts.push(String(item.summary))
        if (item.body)
            parts.push(String(item.body))
        const text = parts.join("\n")
        if (!text.length)
            return
        Quickshell.execDetached([
            "sh", "-c",
            'printf "%s" "$1" | wl-copy 2>/dev/null || printf "%s" "$1" | xclip -selection clipboard 2>/dev/null || true',
            "copy",
            text
        ])
    }

    function clearHistoryLocal() {
        const script = root.historyScriptPath()
        if (script.length)
            Quickshell.execDetached(["python3", script, "clear"])
        root.historyItems = []
        root.allExpanded = false
        // Also close SwayNC's live notifications so the badge matches the empty list.
        if (bar.notificationSupportsClearAll())
            root.clearAllNotifications()
    }

    function removeHistoryItemLocal(id) {
        const want = String(id || "")
        if (!want.length)
            return
        const src = root.historyItems || []
        const list = []
        for (let i = 0; i < src.length; i++) {
            if (String(src[i].id || "") !== want)
                list.push(src[i])
        }
        root.historyItems = list
        root.syncAllExpandedFlag()
    }

    function dismissHistoryItem(id) {
        const want = String(id || "")
        if (!want.length)
            return
        const script = root.historyScriptPath()
        if (script.length)
            Quickshell.execDetached(["python3", script, "dismiss", want])
        root.removeHistoryItemLocal(want)
    }

    function formatTime(ts) {
        const n = Number(ts) || 0
        if (!(n > 0))
            return ""
        const d = new Date(n * 1000)
        const hh = String(d.getHours()).padStart(2, "0")
        const mm = String(d.getMinutes()).padStart(2, "0")
        return hh + ":" + mm
    }

    Io.Process {
        id: syncProcess
        running: false
        stdout: Io.StdioCollector {
            id: syncStdout
            onStreamFinished: root.finishSyncPoll()
        }
        onExited: Qt.callLater(root.finishSyncPoll)
    }

    Timer {
        id: syncTimer
        interval: bar.notificationSyncIntervalMs
        running: bar.notificationSyncEnabled()
        repeat: true
        triggeredOnStart: true
        onTriggered: root.startSyncPoll()
    }

    Io.Process {
        id: subscribeProcess
        running: false
        stdout: Io.SplitParser {
            splitMarker: "\n"
            onRead: (data) => {
                const line = data.trim()
                if (!line) return
                try {
                    root.applyState(JSON.parse(line))
                } catch (e) {}
            }
        }
        onExited: {
            if (bar.notificationUsesLiveSubscribe())
                subscribeRestartTimer.restart()
        }
    }

    Timer {
        id: subscribeRestartTimer
        interval: 2000
        onTriggered: root.startSubscribe()
    }

    Io.Process {
        id: historyWatchProcess
        running: false
        stdout: Io.SplitParser {
            splitMarker: "\n"
            onRead: (data) => {
                const line = data.trim()
                if (!line.startsWith("{")) return
                try {
                    root.handleHistoryEvent(JSON.parse(line))
                } catch (e) {}
            }
        }
        onExited: historyWatchRestart.restart()
    }

    Timer {
        id: historyWatchRestart
        interval: 2500
        onTriggered: root.startHistoryWatch()
    }

    Io.Process {
        id: historyListProcess
        running: false
        stdout: Io.StdioCollector {
            id: historyListStdout
            onStreamFinished: {
                const t = (historyListStdout.text || "").trim()
                if (!t.startsWith("[")) return
                try {
                    root.applyHistoryList(JSON.parse(t))
                } catch (e) {}
            }
        }
    }

    Component.onCompleted: {
        Qt.callLater(function() {
            root.startSyncPoll()
            root.startSubscribe()
            root.loadHistoryOnce()
            root.startHistoryWatch()
        })
    }

    Text {
        id: bellIcon
        anchors.centerIn: parent
        text: root.bellGlyph
        font.pixelSize: Math.max(10, Math.round(bar.iconSizePillLarge * root._ws))
        font.family: bar.fontFamily
        color: dnd
               ? bar.notificationDndAccent
               : (bar.iconColor !== undefined ? bar.iconColor : bar.subtext)
    }

    Rectangle {
        visible: count > 0
        z: 1
        width: Math.max(16, countLabel.implicitWidth + 6)
        height: 16
        radius: 8
        color: dnd ? Qt.rgba(0.75, 0.18, 0.18, 0.95) : bar.accent
        anchors.top: bellIcon.top
        anchors.right: bellIcon.right
        anchors.topMargin: -5
        anchors.rightMargin: -8

        Text {
            id: countLabel
            anchors.centerIn: parent
            text: count > 99 ? "99+" : count
            color: "#111111"
            font.pixelSize: bar.fontTiny
            font.bold: true
            font.family: bar.fontMono
        }
    }

    function toggleDoNotDisturb() {
        bar.execNotificationCommand("toggleDnd")
        Qt.callLater(function() { root.refreshState() })
    }

    function clearAllNotifications() {
        bar.execNotificationCommand("clearAll")
        Qt.callLater(function() { root.refreshState() })
    }

    function hideHistoryPanel() {
        historyPopup.visible = false
    }

    function showHistoryPanel() {
        if (historyPopup.visible) {
            hideHistoryPanel()
            return
        }
        root.loadHistoryOnce()

        var popupW = historyPopup.implicitWidth
        if (typeof bar.placePopup === "function") {
            bar.placePopup(historyPopup, root, popupW, historyPopup.implicitHeight, 2, root.width / 2)
        } else {
            var pos = root.mapToItem(barBg, root.width / 2, 0)
            var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920
            var targetX = bar.sideMargin + pos.x - (popupW / 2)
            var minX = 12
            var maxX = screenW - popupW - 12
            historyPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX))
            historyPopup.anchor.rect.y = bar.popupAnchorY(historyPopup.implicitHeight, 2)
        }
        historyPopup.visible = true
    }

    MouseArea {
        id: bellMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        BarToolTip {
            bar: root.bar
            widgetId: "notifications"
            visible: bellMouse.containsMouse && !historyPopup.visible
            anchorItem: bellMouse
            text: {
                if (root.dnd) return root.count + " notifications (DND on) · Left: history · Right: DND"
                if (root.count > 0) return root.count + " notifications · Left: history · Right: DND"
                return "Notifications · Left: history · Right: DND"
            }
        }

        onClicked: (mouse) => {
            dockFx.jump()
            if (mouse.button === Qt.RightButton) {
                root.toggleDoNotDisturb()
            } else {
                showHistoryPanel()
            }
        }
    }

    // ── History panel (expand / copy / dismiss) ───────────────────────────
    PopupWindow {
        id: historyPopup
        anchor.window: bar
        implicitWidth: 380
        implicitHeight: 460
        visible: false
        grabFocus: true
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: bar.popupRadius
            color: bar.glassPopupBg
            border.width: bar.controlBorderWidth
            border.color: bar.glassPopupBorder
            clip: true

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            Rectangle {
                z: 20
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 8
                width: 26
                height: 26
                radius: bar.smallButtonRadius !== undefined ? bar.smallButtonRadius : bar.buttonRadius
                color: histCloseMa.containsMouse
                       ? Qt.rgba(1, 0.24, 0.54, 0.22)
                       : bar.surface
                border.width: 1
                border.color: histCloseMa.containsMouse ? "#FF3D8A" : bar.dividerStrong
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    color: histCloseMa.containsMouse ? "#FF3D8A" : bar.subtext
                    font.pixelSize: 12
                    font.bold: true
                    font.family: bar.fontFamily
                }
                MouseArea {
                    id: histCloseMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.hideHistoryPanel()
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        text: "Notifications"
                        color: bar.text
                        font.pixelSize: bar.popupTitleSize
                        font.bold: true
                        font.family: bar.fontFamily
                    }
                    Text {
                        text: (root.historyItems || []).length + " kept"
                        color: bar.subtext
                        font.pixelSize: 11
                        font.family: bar.fontFamily
                    }
                    Item {
                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: !(root.historyItems && root.historyItems.length)
                    text: "No notifications captured yet.\nNew ones appear here as they arrive."
                    color: bar.subtext
                    font.pixelSize: 12
                    font.family: bar.fontFamily
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                    Layout.topMargin: 40
                }

                ListView {
                    id: historyList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.historyItems && root.historyItems.length > 0
                    clip: true
                    spacing: 6
                    model: root.historyItems
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: historyList.width
                        height: rowCol.implicitHeight + 14
                        radius: bar.buttonRadius
                        color: bar.surface !== undefined
                               ? Qt.rgba(bar.surface.r, bar.surface.g, bar.surface.b, 0.55)
                               : Qt.rgba(0.08, 0.10, 0.14, 0.55)
                        border.width: 1
                        border.color: bar.dividerStrong

                        ColumnLayout {
                            id: rowCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 8
                            spacing: 4

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Text {
                                    text: modelData.app || "App"
                                    color: bar.subtext
                                    font.pixelSize: 10
                                    font.family: bar.fontFamily
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: root.formatTime(modelData.ts)
                                    color: bar.subtext
                                    font.pixelSize: 10
                                    font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                }
                                // Expand / collapse this item
                                Rectangle {
                                    Layout.preferredWidth: 26
                                    Layout.preferredHeight: 22
                                    radius: 4
                                    color: expMa.containsMouse ? bar.popupButtonHoverBg : "transparent"
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.expanded ? "▴" : "▾"
                                        color: bar.text
                                        font.pixelSize: 11
                                    }
                                    MouseArea {
                                        id: expMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setItemExpanded(index, !modelData.expanded)
                                    }
                                }
                                // Copy to clipboard
                                Rectangle {
                                    Layout.preferredWidth: 26
                                    Layout.preferredHeight: 22
                                    radius: 4
                                    color: copyMa.containsMouse ? bar.popupButtonHoverBg : "transparent"
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰆏"
                                        color: bar.text
                                        font.pixelSize: 12
                                        font.family: bar.fontFamily
                                    }
                                    MouseArea {
                                        id: copyMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.copyNotification(modelData)
                                        BarToolTip {
                                            bar: root.bar
                                            preferSide: "above"
                                            visible: copyMa.containsMouse
                                            text: "Copy to clipboard"
                                            anchorItem: copyMa
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.preferredWidth: 26
                                    Layout.preferredHeight: 22
                                    radius: 4
                                    color: dismissMa.containsMouse
                                           ? Qt.rgba(1, 0.24, 0.54, 0.22)
                                           : "transparent"
                                    border.width: 1
                                    border.color: dismissMa.containsMouse ? "#FF3D8A" : bar.dividerStrong
                                    Text {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        color: dismissMa.containsMouse ? "#FF3D8A" : bar.subtext
                                        font.pixelSize: 11
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                    MouseArea {
                                        id: dismissMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.dismissHistoryItem(modelData.id)
                                        BarToolTip {
                                            bar: root.bar
                                            preferSide: "above"
                                            visible: dismissMa.containsMouse
                                            text: "Remove from history"
                                            anchorItem: dismissMa
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.summary || "(no title)"
                                color: bar.text
                                font.pixelSize: 12
                                font.bold: true
                                font.family: bar.fontFamily
                                wrapMode: Text.WordWrap
                                maximumLineCount: modelData.expanded ? 8 : 2
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: (modelData.body || "").length > 0
                                         && (modelData.expanded || (modelData.summary || "").length === 0)
                                text: modelData.body || ""
                                color: bar.subtext
                                font.pixelSize: 11
                                font.family: bar.fontFamily
                                wrapMode: Text.WordWrap
                                maximumLineCount: modelData.expanded ? 24 : 3
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // Bottom actions: Expand all + DND + clear history
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        radius: bar.buttonRadius
                        color: expandAllMa.containsMouse ? bar.popupButtonHoverBg : bar.surface
                        border.width: 1
                        border.color: bar.dividerStrong
                        enabled: (root.historyItems || []).length > 0
                        opacity: enabled ? 1 : 0.5

                        Text {
                            anchors.centerIn: parent
                            text: root.allExpanded ? "Collapse all" : "Expand all"
                            color: bar.text
                            font.pixelSize: 12
                            font.family: bar.fontFamily
                        }
                        MouseArea {
                            id: expandAllMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: parent.enabled
                            onClicked: root.expandAllHistory(!root.allExpanded)
                        }
                    }

                    Rectangle {
                        visible: bar.notificationSupportsDnd()
                        Layout.preferredWidth: 96
                        Layout.preferredHeight: 32
                        radius: bar.buttonRadius
                        color: {
                            if (root.dnd)
                                return dndHistMa.containsMouse
                                       ? Qt.rgba(0.55, 0.14, 0.14, 0.55)
                                       : Qt.rgba(0.40, 0.10, 0.10, 0.40)
                            return dndHistMa.containsMouse ? bar.popupButtonHoverBg : bar.surface
                        }
                        border.width: 1
                        border.color: root.dnd ? bar.notificationDndAccent : bar.dividerStrong

                        Text {
                            anchors.centerIn: parent
                            text: root.dnd ? "DND on" : "DND"
                            color: root.dnd ? bar.notificationDndAccent : bar.text
                            font.pixelSize: 12
                            font.family: bar.fontFamily
                        }
                        MouseArea {
                            id: dndHistMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleDoNotDisturb()
                            BarToolTip {
                                bar: root.bar
                                preferSide: "above"
                                visible: dndHistMa.containsMouse
                                text: root.dnd ? "Turn off Do Not Disturb" : "Turn on Do Not Disturb"
                                anchorItem: dndHistMa
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 110
                        Layout.preferredHeight: 32
                        radius: bar.buttonRadius
                        color: clearHistMa.containsMouse ? bar.popupButtonHoverBg : bar.surface
                        border.width: 1
                        border.color: bar.dividerStrong
                        enabled: (root.historyItems || []).length > 0
                        opacity: enabled ? 1 : 0.5

                        Text {
                            anchors.centerIn: parent
                            text: "Clear list"
                            color: bar.subtext
                            font.pixelSize: 12
                            font.family: bar.fontFamily
                        }
                        MouseArea {
                            id: clearHistMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: parent.enabled
                            onClicked: root.clearHistoryLocal()
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: hideHistoryPanel()
        }
    }
}
