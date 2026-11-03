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

    // Matches the history list. SwayNC's own count includes notifications
    // that never appear in this window.
    readonly property int count: historyItems ? historyItems.length : 0
    property bool dnd: false
    property bool inhibited: false

    // Local history (from notification-history.py watch / list)
    property var historyItems: []
    property bool allExpanded: false
    property int historyCursor: 0

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

    function notificationBody(raw) {
        const s = String(raw || "")
        if (s.indexOf("<") < 0)
            return s
        // Telegram sends "<b>sender</b>\\nmessage". Rich text drops the newline
        // unless it is a break tag.
        return s.split("\n").join("<br>")
    }

    function historyScriptPath() {
        try {
            const local = Qt.resolvedUrl("../scripts/notification-history.py").toString().replace("file://", "")
            if (local && local.length)
                return local
        } catch (e) {}
        return Quickshell.shellPath("scripts/notification-history.py")
    }

    function applyState(j) {
        if (j === undefined || j === null) return
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
                image: String(it.image || ""),
                urgency: Number(it.urgency) || 1,
                expanded: root.keepMessagesExpanded() ? true : !!it.expanded
            })
        }
        // Newest first
        out.sort(function (a, b) { return (b.ts || 0) - (a.ts || 0) })
        root.historyItems = out
        root.syncAllExpandedFlag()
        root.clampHistoryCursor()
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
                image: String(it.image || ""),
                urgency: Number(it.urgency) || 1,
                expanded: root.keepMessagesExpanded()
            })
            if (root.historyCursor >= 0)
                root.historyCursor = root.historyCursor + 1
            while (list.length > 80)
                list.pop()
            root.historyItems = list
            root.syncAllExpandedFlag()
            root.clampHistoryCursor()
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
            image: it.image || "",
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
                image: it.image || "",
                urgency: it.urgency,
                expanded: !!on
            }
        }
        root.historyItems = list
        root.allExpanded = !!on && list.length > 0
    }

    function localImageUrl(raw) {
        raw = String(raw || "").trim()
        if (!raw.length)
            return ""
        if (raw.indexOf("file://") === 0)
            raw = raw.substring(7)
        if (raw.charAt(0) !== "/")
            return ""
        var lower = raw.toLowerCase()
        var dot = lower.lastIndexOf(".")
        var ext = dot >= 0 ? lower.substring(dot) : ""
        if (ext !== ".png" && ext !== ".jpg" && ext !== ".jpeg"
                && ext !== ".webp" && ext !== ".gif" && ext !== ".bmp")
            return ""
        return "file://" + raw
    }

    function historyImageUrl(item) {
        if (!item)
            return ""
        var direct = root.localImageUrl(item.image)
        if (direct.length)
            return direct
        var fromIcon = root.localImageUrl(item.icon)
        if (fromIcon.length)
            return fromIcon
        var body = String(item.body || "")
        var match = body.match(/(\/[^\s'"<>]+?\.(?:png|jpe?g|webp|gif|bmp))/i)
        if (match && match[1])
            return root.localImageUrl(match[1])
        return ""
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
        var imagePath = root.historyImageUrl(item)
        if (imagePath.indexOf("file://") === 0)
            imagePath = imagePath.substring(7)
        var mime = ""
        const lower = imagePath.toLowerCase()
        if (lower.endsWith(".png"))
            mime = "image/png"
        else if (lower.endsWith(".jpg") || lower.endsWith(".jpeg"))
            mime = "image/jpeg"
        else if (lower.endsWith(".webp"))
            mime = "image/webp"
        else if (lower.endsWith(".gif"))
            mime = "image/gif"
        else if (lower.endsWith(".bmp"))
            mime = "image/bmp"
        // A row with a picture copies that picture. Text-only rows copy the text.
        if (imagePath.length && mime.length) {
            Quickshell.execDetached([
                "sh", "-c",
                'if [ -f "$2" ]; then wl-copy --type "$1" < "$2" || xclip -selection clipboard -t "$1" -i "$2"; elif [ -n "$3" ]; then printf "%s" "$3" | wl-copy 2>/dev/null || printf "%s" "$3" | xclip -selection clipboard 2>/dev/null || true; fi',
                "copy",
                mime,
                imagePath,
                text
            ])
            return
        }
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
        root.historyCursor = 0
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
        root.clampHistoryCursor()
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
        visible: count > 0 && (!bar || bar.notificationShowCount !== false)
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

    function keepMessagesExpanded() {
        return !!(bar && bar.notificationAutoExpand)
    }

    function clampHistoryCursor() {
        const n = (root.historyItems || []).length
        if (n <= 0) {
            root.historyCursor = 0
            return
        }
        if (root.historyCursor < 0)
            root.historyCursor = 0
        if (root.historyCursor >= n)
            root.historyCursor = n - 1
    }

    function revealHistoryCursor() {
        const n = (root.historyItems || []).length
        if (n <= 0)
            return
        root.clampHistoryCursor()
        historyList.positionViewAtIndex(root.historyCursor, ListView.Contain)
    }

    function moveHistoryCursor(delta) {
        const n = (root.historyItems || []).length
        if (n <= 0)
            return
        let next = root.historyCursor + delta
        if (next < 0)
            next = 0
        if (next >= n)
            next = n - 1
        root.historyCursor = next
        root.revealHistoryCursor()
    }

    function historyAtCursor() {
        const list = root.historyItems || []
        if (root.historyCursor < 0 || root.historyCursor >= list.length)
            return null
        return list[root.historyCursor]
    }

    function dismissSelected() {
        const item = root.historyAtCursor()
        if (item)
            root.dismissHistoryItem(item.id)
    }

    function toggleSelectedExpanded() {
        const item = root.historyAtCursor()
        if (!item)
            return
        root.setSelectedExpanded(!item.expanded)
    }

    function setSelectedExpanded(on) {
        const item = root.historyAtCursor()
        if (!item || !!item.expanded === !!on)
            return
        root.setItemExpanded(root.historyCursor, !!on)
        Qt.callLater(root.revealHistoryCursor)
    }

    function historyRowColor(index, selected, stagger) {
        const base = (bar.surface !== undefined) ? bar.surface : Qt.rgba(0.08, 0.10, 0.14, 1)
        const alt = !!stagger && ((index % 2) === 1)
        let r = base.r
        let g = base.g
        let b = base.b
        if (alt) {
            r = Math.min(1, r * 0.72 + 0.16)
            g = Math.min(1, g * 0.78 + 0.20)
            b = Math.min(1, b * 0.82 + 0.28)
        } else {
            r = Math.min(1, r * 0.92 + 0.04)
            g = Math.min(1, g * 0.92 + 0.04)
            b = Math.min(1, b * 0.92 + 0.05)
        }
        let a = alt ? 0.78 : 0.48
        if (selected && bar.accent) {
            r = Math.min(1, r * 0.62 + bar.accent.r * 0.38)
            g = Math.min(1, g * 0.62 + bar.accent.g * 0.38)
            b = Math.min(1, b * 0.62 + bar.accent.b * 0.38)
            a = Math.min(1, a + 0.12)
        }
        return Qt.rgba(r, g, b, a)
    }

    function handleHistoryKey(event) {
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
        const alt = (event.modifiers & Qt.AltModifier) !== 0
        const meta = (event.modifiers & Qt.MetaModifier) !== 0
        if (alt || meta)
            return
        if (ctrl && event.key === Qt.Key_C) {
            const item = root.historyAtCursor()
            if (item)
                root.copyNotification(item)
            event.accepted = true
            return
        }
        if (ctrl && event.key === Qt.Key_Delete) {
            root.clearHistoryLocal()
            event.accepted = true
            return
        }
        if (ctrl)
            return
        switch (event.key) {
        case Qt.Key_A:
            root.expandAllHistory(true)
            Qt.callLater(root.revealHistoryCursor)
            break
        case Qt.Key_C:
            root.expandAllHistory(false)
            break
        case Qt.Key_D:
            root.toggleDoNotDisturb()
            break
        case Qt.Key_Delete:
        case Qt.Key_Backspace:
            root.dismissSelected()
            break
        case Qt.Key_Up:
        case Qt.Key_K:
            root.moveHistoryCursor(-1)
            break
        case Qt.Key_Down:
        case Qt.Key_J:
            root.moveHistoryCursor(1)
            break
        case Qt.Key_Right:
            root.setSelectedExpanded(true)
            break
        case Qt.Key_Left:
            root.setSelectedExpanded(false)
            break
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            root.toggleSelectedExpanded()
            break
        case Qt.Key_Escape:
            root.hideHistoryPanel()
            break
        default:
            return
        }
        event.accepted = true
    }

    function focusHistoryKeys() {
        Qt.callLater(function() {
            if (histKeyGrab)
                histKeyGrab.forceActiveFocus()
        })
    }

    function hideHistoryPanel() {
        historyPopup.visible = false
    }

    function openHistoryPanel() {
        root.loadHistoryOnce()
        if (root.keepMessagesExpanded())
            root.expandAllHistory(true)
        root.historyCursor = 0

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
        root.focusHistoryKeys()
        Qt.callLater(root.revealHistoryCursor)
    }

    function showHistoryPanel() {
        if (historyPopup.visible) {
            hideHistoryPanel()
            return
        }
        root.openHistoryPanel()
    }

    function toggleHistory() {
        root.showHistoryPanel()
    }

    function showHistory() {
        if (historyPopup.visible) {
            root.focusHistoryKeys()
            return
        }
        root.openHistoryPanel()
    }

    function hideHistory() {
        root.hideHistoryPanel()
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
        implicitWidth: 437
        implicitHeight: 488
        visible: false
        grabFocus: true
        color: "transparent"
        onVisibleChanged: {
            if (visible)
                root.focusHistoryKeys()
        }

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

            Item {
                id: histKeyGrab
                z: 5
                anchors.fill: parent
                focus: historyPopup.visible
                Keys.onPressed: (event) => root.handleHistoryKey(event)
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

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 48

                    Text {
                        anchors.centerIn: parent
                        width: parent.width
                        visible: !(root.historyItems && root.historyItems.length)
                        text: "No notifications captured yet.\nNew ones appear here as they arrive."
                        color: bar.subtext
                        font.pixelSize: 12
                        font.family: bar.fontFamily
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }

                ListView {
                    id: historyList
                    anchors.fill: parent
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
                        color: root.historyRowColor(index, index === root.historyCursor, bar.notificationStaggerRows !== false)
                        border.width: index === root.historyCursor ? 2 : 1
                        border.color: index === root.historyCursor ? bar.accent : bar.dividerStrong

                        // Clicks on the text expand the row. Copy and dismiss sit
                        // inside this area and keep their own clicks.
                        MouseArea {
                            id: rowClick
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.historyCursor = index
                                root.setItemExpanded(index, !modelData.expanded)
                                root.focusHistoryKeys()
                            }

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
                                        onClicked: {
                                            root.historyCursor = index
                                            root.setItemExpanded(index, !modelData.expanded)
                                            root.focusHistoryKeys()
                                        }
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
                                        onClicked: {
                                            root.historyCursor = index
                                            root.copyNotification(modelData)
                                            root.focusHistoryKeys()
                                        }
                                        BarToolTip {
                                            bar: root.bar
                                            preferSide: "above"
                                            visible: copyMa.containsMouse
                                            text: "Copy image, or the text if there is no image"
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
                                        onClicked: {
                                            root.historyCursor = index
                                            root.dismissHistoryItem(modelData.id)
                                            root.focusHistoryKeys()
                                        }
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

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    id: histThumbFrame
                                    readonly property string thumbUrl: modelData.expanded
                                                                     ? root.historyImageUrl(modelData) : ""
                                    visible: thumbUrl.length > 0 && histThumb.status !== Image.Error
                                    Layout.preferredWidth: 112
                                    Layout.preferredHeight: 72
                                    Layout.alignment: Qt.AlignTop
                                    radius: 6
                                    clip: true
                                    color: Qt.rgba(0, 0, 0, 0.25)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    Image {
                                        id: histThumb
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        smooth: true
                                        mipmap: true
                                        sourceSize.width: 224
                                        sourceSize.height: 144
                                        source: histThumbFrame.thumbUrl
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.summary || "(no title)"
                                        color: bar.text
                                        font.pixelSize: 12
                                        font.bold: true
                                        font.family: bar.fontFamily
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: modelData.expanded ? 10000 : 2
                                        elide: modelData.expanded ? Text.ElideNone : Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        visible: (modelData.body || "").length > 0
                                                 && (modelData.expanded || (modelData.summary || "").length === 0)
                                        text: root.notificationBody(modelData.body)
                                        textFormat: (modelData.body || "").indexOf("<") >= 0
                                                    ? Text.RichText : Text.PlainText
                                        color: bar.subtext
                                        font.pixelSize: 11
                                        font.family: bar.fontFamily
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: modelData.expanded ? 10000 : 3
                                        elide: modelData.expanded ? Text.ElideNone : Text.ElideRight
                                    }
                                }
                            }
                        }
                        } // row click
                    }
                }
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "↑↓ move · → expand · ← collapse · a all · c collapse all · d DND · Del remove · Ctrl+C copy · Ctrl+Del clear · Esc close"
                    color: bar.subtext
                    font.pixelSize: 10
                    font.family: bar.fontFamily
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
                            onClicked: {
                                root.expandAllHistory(!root.allExpanded)
                                root.focusHistoryKeys()
                            }
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
                            onClicked: {
                                root.toggleDoNotDisturb()
                                root.focusHistoryKeys()
                            }
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
                            onClicked: {
                                root.clearHistoryLocal()
                                root.focusHistoryKeys()
                            }
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
