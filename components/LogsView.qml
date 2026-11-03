import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io as Io

// Live log viewer with source picker, line limit, filter, and optional tail refresh.
Item {
    id: root

    property string globalFilter: ""
    property bool active: false

    property color textColor: "#f0f4fc"
    property color subtextColor: "#a8b4c8"
    property color accentColor: "#00F0E0"
    property color surfaceColor: "#141a24"
    property color overlayColor: "#6e7a90"
    property color errorColor: "#FF3D8A"
    property color warnColor: "#f0d060"
    property color infoColor: "#00F0E0"
    property color debugColor: "#6e7a90"

    readonly property string fetchScript: Quickshell.shellPath("scripts/log-fetch.sh")
    readonly property var lineCounts: [50, 100, 200, 500]
    readonly property int liveIntervalMs: 3000

    readonly property var logSources: [
        { id: "hyprland", label: "Hyprland" },
        { id: "journal-user", label: "User Journal" },
        { id: "journal-system", label: "System Journal" },
        { id: "kernel", label: "Kernel" },
        { id: "hyprland-wm", label: "Hyprland (systemd)" },
        { id: "swaync", label: "swaync" },
        { id: "hypridle", label: "hypridle" },
        { id: "hyprpolkitagent", label: "hyprpolkitagent" },
        { id: "pipewire", label: "pipewire" },
        { id: "portal-hyprland", label: "xdg-desktop-portal-hyprland" },
        { id: "quickshell", label: "quickshell" }
    ]

    property string selectedSourceId: "hyprland"
    property int lineCount: 100
    property bool liveTail: false
    property string rawText: ""
    property bool loading: false
    property string lastError: ""
    property int contentVersion: 0

    property bool _loadHandled: false
    property bool _scrollToBottomAfterLoad: false

    readonly property int lineHeight: 15
    readonly property int fontPx: 11

    function filterQuery() {
        return (globalFilter && globalFilter.trim()) ? globalFilter.toLowerCase().trim() : ""
    }

    function currentSource() {
        for (let i = 0; i < logSources.length; i++) {
            if (logSources[i].id === selectedSourceId) return logSources[i]
        }
        return logSources.length ? logSources[0] : null
    }

    function currentSourceLabel() {
        const src = currentSource()
        return src ? src.label : selectedSourceId
    }

    function filteredLines() {
        const tick = rawText + "|" + contentVersion + "|" + globalFilter
        if (!rawText) return []
        const lines = rawText.split("\n")
        const q = filterQuery()
        if (!q) return lines
        return lines.filter(function(line) {
            return line.toLowerCase().indexOf(q) !== -1
        })
    }

    function lineColor(line) {
        const l = (line || "").toLowerCase()
        if (l.indexOf("error") !== -1 || l.indexOf(" err ") !== -1 || l.indexOf("fatal") !== -1 || l.indexOf("failed") !== -1)
            return root.errorColor
        if (l.indexOf("warn") !== -1 || l.indexOf("warning") !== -1)
            return root.warnColor
        if (l.indexOf("info") !== -1)
            return root.infoColor
        if (l.indexOf("debug") !== -1 || l.indexOf("trace") !== -1)
            return root.debugColor
        return root.textColor
    }

    function plainText() {
        return filteredLines().join("\n")
    }

    function scrollableMaxY() {
        return Math.max(0, logFlickable.contentHeight - logFlickable.height)
    }

    function isAtBottom() {
        return logFlickable.contentY >= scrollableMaxY() - 8
    }

    function scrollToBottom() {
        logFlickable.contentY = scrollableMaxY()
    }

    function resetScroll() {
        logFlickable.contentY = 0
        logFlickable.contentX = 0
    }

    function pageScroll(direction) {
        const maxY = scrollableMaxY()
        if (maxY <= 0) return
        const page = Math.max(80, logFlickable.height * 0.85)
        logFlickable.contentY = Math.max(0, Math.min(maxY, logFlickable.contentY + direction * page))
    }

    function lineScroll(direction) {
        const maxY = scrollableMaxY()
        if (maxY <= 0) return
        const step = Math.max(root.lineHeight * 2, 24)
        logFlickable.contentY = Math.max(0, Math.min(maxY, logFlickable.contentY + direction * step))
    }

    function focusNav() {
        navFocus.forceActiveFocus()
    }

    function focusScroll() {
        logFlickable.forceActiveFocus()
    }

    function currentSourceIndex() {
        for (let i = 0; i < logSources.length; i++) {
            if (logSources[i].id === selectedSourceId) return i
        }
        return -1
    }

    function selectSourceId(sourceId) {
        if (!sourceId) return
        selectedSourceId = sourceId
        syncSourceCombo()
    }

    function prevSource() {
        if (!logSources.length) return
        const idx = currentSourceIndex()
        const nextIdx = idx <= 0 ? logSources.length - 1 : idx - 1
        selectSourceId(logSources[nextIdx].id)
    }

    function nextSource() {
        if (!logSources.length) return
        const idx = currentSourceIndex()
        const nextIdx = idx < 0 || idx >= logSources.length - 1 ? 0 : idx + 1
        selectSourceId(logSources[nextIdx].id)
    }

    function handleNavKey(event) {
        if (sourceCombo.popup.opened) return false
        if (event.key === Qt.Key_Left) {
            prevSource()
            event.accepted = true
            return true
        }
        if (event.key === Qt.Key_Right) {
            nextSource()
            event.accepted = true
            return true
        }
        if (event.key === Qt.Key_PageUp) {
            pageScroll(-1)
            event.accepted = true
            return true
        }
        if (event.key === Qt.Key_PageDown) {
            pageScroll(1)
            event.accepted = true
            return true
        }
        if (event.key === Qt.Key_Up) {
            lineScroll(-1)
            event.accepted = true
            return true
        }
        if (event.key === Qt.Key_Down) {
            lineScroll(1)
            event.accepted = true
            return true
        }
        return false
    }

    function syncSourceCombo() {
        for (let i = 0; i < logSources.length; i++) {
            if (logSources[i].id === selectedSourceId) {
                sourceCombo.currentIndex = i
                return
            }
        }
        if (logSources.length > 0) sourceCombo.currentIndex = 0
    }

    function syncLineCombo() {
        const idx = lineCounts.indexOf(lineCount)
        linesCombo.currentIndex = idx >= 0 ? idx : 1
    }

    function refresh(preserveScroll) {
        if (!selectedSourceId || logProcess.running) return
        _scrollToBottomAfterLoad = liveTail && (preserveScroll ? isAtBottom() : true)
        loading = true
        lastError = ""
        _loadHandled = false
        logProcess.running = false
        logProcess.command = [root.fetchScript, selectedSourceId, String(lineCount)]
        logProcess.running = true
    }

    function finishLogLoad() {
        if (_loadHandled) return
        _loadHandled = true
        loading = false
        rawText = logStdout.text || ""
        if (!rawText.trim().length && !lastError.length)
            lastError = "No log output"
        contentVersion++
        if (_scrollToBottomAfterLoad) {
            Qt.callLater(function() { root.scrollToBottom() })
        }
    }

    onSelectedSourceIdChanged: {
        resetScroll()
        refresh(false)
    }

    onLineCountChanged: refresh(false)

    onLiveTailChanged: {
        if (liveTail && active) refresh(true)
    }

    onActiveChanged: {
        if (active) {
            if (!rawText.length) refresh(false)
        } else {
            if (logProcess.running)
                logProcess.running = false
            loading = false
        }
    }

    onVisibleChanged: {
        if (visible && active) Qt.callLater(function() { root.focusScroll() })
    }

    Component.onCompleted: {
        syncSourceCombo()
        syncLineCombo()
    }

    Io.Process {
        id: logProcess
        running: false
        stdout: Io.StdioCollector {
            id: logStdout
            onStreamFinished: root.finishLogLoad()
        }
        onExited: (code) => {
            if (code !== 0 && !logStdout.text) {
                root.lastError = "Fetcher exited " + code
            }
            root.finishLogLoad()
        }
    }

    Timer {
        id: liveTimer
        interval: root.liveIntervalMs
        running: root.active && root.liveTail && root.visible
        repeat: true
        onTriggered: root.refresh(true)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Item {
            id: navFocus
            Layout.fillWidth: true
            Layout.preferredHeight: 28

            Keys.onPressed: function(event) {
                root.handleNavKey(event)
            }

            onVisibleChanged: {
                if (visible) Qt.callLater(function() { root.focusScroll() })
            }

            RowLayout {
                anchors.fill: parent
                spacing: 8

            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 28
                radius: 6
                color: prevSourceMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                opacity: root.logSources.length > 0 ? 1 : 0.4

                Text {
                    anchors.centerIn: parent
                    text: "◀"
                    color: root.accentColor
                    font.pixelSize: 12
                }

                MouseArea {
                    id: prevSourceMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.logSources.length > 0
                    onClicked: root.prevSource()
                }
            }

            ComboBox {
                id: sourceCombo
                Layout.fillWidth: true
                model: root.logSources
                textRole: "label"

                onActivated: function(index) {
                    const item = root.logSources[index]
                    if (item) root.selectSourceId(item.id)
                }

                contentItem: Text {
                    leftPadding: 8
                    rightPadding: sourceCombo.indicator.width + sourceCombo.spacing
                    text: sourceCombo.displayText
                    font.pixelSize: 13
                    color: root.textColor
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                indicator: Canvas {
                    x: sourceCombo.width - width - sourceCombo.rightPadding
                    y: sourceCombo.topPadding + (sourceCombo.availableHeight - height) / 2
                    width: 10
                    height: 6
                    contextType: "2d"
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = root.subtextColor
                        ctx.lineWidth = 1.5
                        ctx.beginPath()
                        ctx.moveTo(0, 1)
                        ctx.lineTo(5, 5)
                        ctx.lineTo(10, 1)
                        ctx.stroke()
                    }
                    onWidthChanged: requestPaint()
                }

                background: Rectangle {
                    radius: 6
                    color: root.surfaceColor
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                }
            }

            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 28
                radius: 6
                color: nextSourceMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                opacity: root.logSources.length > 0 ? 1 : 0.4

                Text {
                    anchors.centerIn: parent
                    text: "▶"
                    color: root.accentColor
                    font.pixelSize: 12
                }

                MouseArea {
                    id: nextSourceMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.logSources.length > 0
                    onClicked: root.nextSource()
                }
            }

            ComboBox {
                id: linesCombo
                Layout.preferredWidth: 92
                model: root.lineCounts

                onActivated: function(index) {
                    root.lineCount = root.lineCounts[index]
                }

                displayText: root.lineCount + " lines"

                contentItem: Text {
                    leftPadding: 8
                    rightPadding: linesCombo.indicator.width + linesCombo.spacing
                    text: linesCombo.displayText
                    font.pixelSize: 12
                    color: root.textColor
                    verticalAlignment: Text.AlignVCenter
                }

                indicator: Canvas {
                    x: linesCombo.width - width - linesCombo.rightPadding
                    y: linesCombo.topPadding + (linesCombo.availableHeight - height) / 2
                    width: 10
                    height: 6
                    contextType: "2d"
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = root.subtextColor
                        ctx.lineWidth = 1.5
                        ctx.beginPath()
                        ctx.moveTo(0, 1)
                        ctx.lineTo(5, 5)
                        ctx.lineTo(10, 1)
                        ctx.stroke()
                    }
                    onWidthChanged: requestPaint()
                }

                background: Rectangle {
                    radius: 6
                    color: root.surfaceColor
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                }
            }

            Rectangle {
                Layout.preferredWidth: 52
                Layout.preferredHeight: 28
                radius: 6
                color: root.liveTail ? Qt.rgba(0.55, 0.70, 0.96, 0.18) : (liveMa.containsMouse ? root.surfaceColor : "transparent")
                border.width: 1
                border.color: root.liveTail ? root.accentColor : Qt.rgba(1, 1, 1, 0.1)

                Text {
                    anchors.centerIn: parent
                    text: "Live"
                    color: root.liveTail ? root.accentColor : root.subtextColor
                    font.pixelSize: 12
                    font.bold: root.liveTail
                }

                MouseArea {
                    id: liveMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.liveTail = !root.liveTail
                }
            }

            Rectangle {
                Layout.preferredWidth: 68
                Layout.preferredHeight: 28
                radius: 6
                color: refreshMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                opacity: root.loading ? 0.55 : 1

                Text {
                    anchors.centerIn: parent
                    text: root.loading ? "..." : "Refresh"
                    color: root.accentColor
                    font.pixelSize: 12
                }

                MouseArea {
                    id: refreshMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !root.loading
                    onClicked: root.refresh(true)
                }
            }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 6
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            clip: true

            Flickable {
                id: logFlickable
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick | Flickable.HorizontalFlick
                contentWidth: Math.max(width, logColumn.implicitWidth)
                contentHeight: Math.max(height, logColumn.implicitHeight)

                property string _filterTick: root.globalFilter
                property int _contentTick: root.contentVersion

                focus: true
                Keys.onPressed: function(event) {
                    root.handleNavKey(event)
                }

                WheelHandler {
                    onWheel: function(event) {
                        const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                        if (delta === 0) return
                        const maxY = root.scrollableMaxY()
                        if (maxY > 0) {
                            const ticks = delta / 120
                            logFlickable.contentY = Math.max(0, Math.min(maxY, logFlickable.contentY - ticks * 28))
                        }
                        event.accepted = true
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: logFlickable.contentHeight > logFlickable.height + 1 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: parent.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                    }
                }

                ScrollBar.horizontal: ScrollBar {
                    policy: logFlickable.contentWidth > logFlickable.width + 1 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    contentItem: Rectangle {
                        implicitHeight: 6
                        radius: 3
                        color: parent.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                    }
                }

                Column {
                    id: logColumn
                    width: Math.max(logFlickable.width, implicitWidth)
                    spacing: 0

                    Text {
                        visible: root.loading && root.filteredLines().length === 0
                        width: logFlickable.width
                        text: "Loading logs..."
                        color: root.overlayColor
                        font.pixelSize: root.fontPx
                        font.family: "monospace"
                        topPadding: 4
                    }

                    Text {
                        visible: !root.loading && root.lastError.length > 0 && root.filteredLines().length === 0
                        width: logFlickable.width
                        text: root.lastError
                        color: root.errorColor
                        font.pixelSize: root.fontPx
                        font.family: "monospace"
                        wrapMode: Text.Wrap
                        topPadding: 4
                    }

                    Text {
                        visible: !root.loading && root.filteredLines().length === 0 && root.lastError.length === 0
                        width: logFlickable.width
                        text: "(no log lines)"
                        color: root.overlayColor
                        font.pixelSize: root.fontPx
                        font.family: "monospace"
                        topPadding: 4
                    }

                    Repeater {
                        model: root.filteredLines()
                        delegate: Text {
                            required property int index
                            required property string modelData
                            width: implicitWidth
                            text: modelData.length ? modelData : " "
                            color: root.lineColor(modelData)
                            font.pixelSize: root.fontPx
                            font.family: "monospace"
                            lineHeight: 1.15
                            lineHeightMode: Text.FixedHeight
                        }
                    }
                }
            }
        }
    }
}