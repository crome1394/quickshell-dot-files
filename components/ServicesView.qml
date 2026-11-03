import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io as Io

// systemd service status table with filter and start/stop/restart controls.
Item {
    id: root

    property string globalFilter: ""
    property bool active: false

    property color textColor: "#f0f4fc"
    property color subtextColor: "#a8b4c8"
    property color accentColor: "#00F0E0"
    property color surfaceColor: "#141a24"
    property color overlayColor: "#6e7a90"
    property color okColor: "#2ee59a"
    property color warnColor: "#f0d060"
    property color errorColor: "#FF3D8A"

    readonly property string pollerScript: Quickshell.shellPath("scripts/services-poller.sh")
    readonly property string controlScript: Quickshell.shellPath("scripts/services-control.sh")
    readonly property var filterModes: [
        { id: "all", label: "All" },
        { id: "running", label: "Running" },
        { id: "failed", label: "Failed" }
    ]

    property var services: []
    property string filterMode: "all"
    property string selectedServiceKey: ""
    property bool loading: false
    property bool acting: false
    property string lastError: ""
    property string lastAction: ""
    property int dataVersion: 0

    property bool _loadHandled: false
    property bool _actionHandled: false
    property int _lastActionExitCode: 0

    readonly property int rowHeight: 22
    readonly property int headerHeight: 20
    readonly property int tblSpacing: 4
    readonly property int colStatusW: 54
    readonly property int colStateW: 54
    readonly property int colSinceW: 138

    function serviceKey(svc) {
        return svc ? (svc.scope + ":" + svc.id) : ""
    }

    function selectedService() {
        if (!selectedServiceKey) return null
        for (let i = 0; i < services.length; i++) {
            if (serviceKey(services[i]) === selectedServiceKey) return services[i]
        }
        return null
    }

    function filterQuery() {
        return (globalFilter && globalFilter.trim()) ? globalFilter.toLowerCase().trim() : ""
    }

    function matchesMode(svc) {
        const active = (svc.active_state || "").toLowerCase()
        const sub = (svc.sub_state || "").toLowerCase()
        if (filterMode === "running") {
            return active === "active" && (sub === "running" || sub === "exited")
        }
        if (filterMode === "failed") {
            return active === "failed" || sub.indexOf("fail") !== -1 || sub === "auto-restart"
        }
        return true
    }

    function matchesSearch(svc) {
        const q = filterQuery()
        if (!q) return true
        const hay = [
            svc.id, svc.name, svc.description, svc.scope,
            svc.active_state, svc.sub_state, svc.unit_file_state
        ].join(" ").toLowerCase()
        return hay.indexOf(q) !== -1
    }

    function filteredServices() {
        const tick = dataVersion + "|" + filterMode + "|" + globalFilter + "|" + services.length
        if (!services || !services.length) return []
        const out = []
        for (let i = 0; i < services.length; i++) {
            const svc = services[i]
            if (matchesMode(svc) && matchesSearch(svc)) out.push(svc)
        }
        return out
    }

    function shortName(id) {
        if (!id) return "--"
        return id.endsWith(".service") ? id.substring(0, id.length - 8) : id
    }

    function formatSince(ts) {
        if (!ts || !ts.length) return "--"
        if (ts.length > 22) return ts.substring(0, 22)
        return ts
    }

    function statusColor(svc) {
        const active = (svc.active_state || "").toLowerCase()
        const sub = (svc.sub_state || "").toLowerCase()
        if (active === "failed" || sub.indexOf("fail") !== -1) return root.errorColor
        if (active === "active") return root.okColor
        if (active === "inactive" || active === "deactivating" || sub === "dead") return root.warnColor
        return root.textColor
    }

    function stateColor(svc) {
        const sub = (svc.sub_state || "").toLowerCase()
        if (sub === "running" || sub === "exited") return root.okColor
        if (sub.indexOf("fail") !== -1 || sub === "auto-restart") return root.errorColor
        if (sub === "dead" || sub === "start") return root.warnColor
        return root.subtextColor
    }

    function nameColWidth(totalWidth) {
        const fixed = colStatusW + colStateW + colSinceW + tblSpacing * 4 + 8
        const desc = Math.max(100, Math.floor((totalWidth - fixed) * 0.38))
        return Math.max(110, totalWidth - fixed - desc)
    }

    function descColWidth(totalWidth) {
        const fixed = colStatusW + colStateW + colSinceW + tblSpacing * 4 + 8
        const name = nameColWidth(totalWidth)
        return Math.max(100, totalWidth - fixed - name)
    }

    function canStart(svc) {
        if (!svc || svc.load_state === "not-found") return false
        const active = (svc.active_state || "").toLowerCase()
        return active !== "active"
    }

    function canStop(svc) {
        if (!svc || svc.load_state === "not-found") return false
        const active = (svc.active_state || "").toLowerCase()
        return active === "active" || active === "activating"
    }

    function canRestart(svc) {
        return svc && svc.load_state === "loaded"
    }

    function refresh() {
        if (pollProcess.running) return
        loading = true
        lastError = ""
        _loadHandled = false
        pollProcess.running = false
        pollProcess.running = true
    }

    function runAction(action) {
        const svc = selectedService()
        if (!svc || acting || pollProcess.running) return
        acting = true
        lastAction = ""
        lastError = ""
        _actionHandled = false
        actionProcess.running = false
        actionProcess.command = [root.controlScript, action, svc.scope, svc.id]
        actionProcess.running = true
    }

    function finishPoll() {
        if (_loadHandled) return
        _loadHandled = true
        loading = false
        const raw = (pollStdout.text || "").trim()
        if (!raw) {
            lastError = "Empty response from services poller"
            return
        }
        try {
            const parsed = JSON.parse(raw)
            services = parsed.services || []
            dataVersion++
            const keys = {}
            for (let i = 0; i < services.length; i++) keys[serviceKey(services[i])] = true
            if (selectedServiceKey && !keys[selectedServiceKey]) selectedServiceKey = ""
        } catch (e) {
            lastError = "Failed to parse services JSON"
        }
    }

    function finishAction(exitCode) {
        if (_actionHandled) return
        _actionHandled = true
        acting = false
        const code = exitCode !== undefined ? exitCode : _lastActionExitCode
        if (code !== 0) {
            const err = (actionStderr.text || actionStdout.text || "").trim()
            lastError = err.length ? err : "Service action failed (exit " + code + ")"
            return
        }
        lastAction = "Action completed"
        Qt.callLater(function() { root.refresh() })
    }

    function resetScroll() {
        servicesFlickable.contentY = 0
    }

    function focusScroll() {
        servicesFlickable.forceActiveFocus()
    }

    function pageScroll(direction) {
        const maxY = Math.max(0, servicesFlickable.contentHeight - servicesFlickable.height)
        if (maxY <= 0) return
        const page = Math.max(80, servicesFlickable.height * 0.85)
        servicesFlickable.contentY = Math.max(0, Math.min(maxY, servicesFlickable.contentY + direction * page))
    }

    function lineScroll(direction) {
        const maxY = Math.max(0, servicesFlickable.contentHeight - servicesFlickable.height)
        if (maxY <= 0) return
        const step = Math.max(root.rowHeight * 2, 24)
        servicesFlickable.contentY = Math.max(0, Math.min(maxY, servicesFlickable.contentY + direction * step))
    }

    onActiveChanged: {
        if (active && !services.length) {
            refresh()
        } else if (!active) {
            if (pollProcess.running)
                pollProcess.running = false
            loading = false
        }
    }

    onVisibleChanged: {
        if (visible && active) Qt.callLater(function() { root.focusScroll() })
    }

    onFilterModeChanged: {
        const rows = filteredServices()
        if (selectedServiceKey) {
            let found = false
            for (let i = 0; i < rows.length; i++) {
                if (serviceKey(rows[i]) === selectedServiceKey) { found = true; break }
            }
            if (!found) selectedServiceKey = ""
        }
    }

    Io.Process {
        id: pollProcess
        command: [root.pollerScript]
        running: false
        stdout: Io.StdioCollector {
            id: pollStdout
            onStreamFinished: root.finishPoll()
        }
        onExited: root.finishPoll()
    }

    Io.Process {
        id: actionProcess
        running: false
        stdout: Io.StdioCollector { id: actionStdout }
        stderr: Io.StdioCollector { id: actionStderr }
        onExited: (code) => {
            root._lastActionExitCode = code
            root.finishAction(code)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ComboBox {
                id: filterCombo
                Layout.preferredWidth: 110
                model: root.filterModes
                textRole: "label"

                onActivated: function(index) {
                    root.filterMode = root.filterModes[index].id
                }

                Component.onCompleted: {
                    for (let i = 0; i < root.filterModes.length; i++) {
                        if (root.filterModes[i].id === root.filterMode) {
                            currentIndex = i
                            break
                        }
                    }
                }

                contentItem: Text {
                    leftPadding: 8
                    rightPadding: filterCombo.indicator.width + filterCombo.spacing
                    text: filterCombo.displayText
                    font.pixelSize: 12
                    color: root.textColor
                    verticalAlignment: Text.AlignVCenter
                }

                indicator: Canvas {
                    x: filterCombo.width - width - filterCombo.rightPadding
                    y: filterCombo.topPadding + (filterCombo.availableHeight - height) / 2
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

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredWidth: 52
                Layout.preferredHeight: 28
                radius: 6
                color: startMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                opacity: root.canStart(root.selectedService()) && !root.acting ? 1 : 0.35

                Text {
                    anchors.centerIn: parent
                    text: "Start"
                    color: root.okColor
                    font.pixelSize: 11
                }

                MouseArea {
                    id: startMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.canStart(root.selectedService()) && !root.acting && !root.loading
                    onClicked: root.runAction("start")
                }
            }

            Rectangle {
                Layout.preferredWidth: 46
                Layout.preferredHeight: 28
                radius: 6
                color: stopMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                opacity: root.canStop(root.selectedService()) && !root.acting ? 1 : 0.35

                Text {
                    anchors.centerIn: parent
                    text: "Stop"
                    color: root.errorColor
                    font.pixelSize: 11
                }

                MouseArea {
                    id: stopMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.canStop(root.selectedService()) && !root.acting && !root.loading
                    onClicked: root.runAction("stop")
                }
            }

            Rectangle {
                Layout.preferredWidth: 58
                Layout.preferredHeight: 28
                radius: 6
                color: restartMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                opacity: root.canRestart(root.selectedService()) && !root.acting ? 1 : 0.35

                Text {
                    anchors.centerIn: parent
                    text: "Restart"
                    color: root.accentColor
                    font.pixelSize: 11
                }

                MouseArea {
                    id: restartMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.canRestart(root.selectedService()) && !root.acting && !root.loading
                    onClicked: root.runAction("restart")
                }
            }

            Rectangle {
                Layout.preferredWidth: 68
                Layout.preferredHeight: 28
                radius: 6
                color: refreshMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                opacity: root.loading || root.acting ? 0.55 : 1

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
                    enabled: !root.loading && !root.acting
                    onClicked: root.refresh()
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
                id: servicesFlickable
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: Math.max(height, servicesTable.implicitHeight)

                property int _dataTick: root.dataVersion
                property string _filterTick: root.globalFilter + "|" + root.filterMode

                focus: true

                WheelHandler {
                    onWheel: function(event) {
                        const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                        if (delta === 0) return
                        const maxY = Math.max(0, servicesFlickable.contentHeight - servicesFlickable.height)
                        if (maxY > 0) {
                            const ticks = delta / 120
                            servicesFlickable.contentY = Math.max(0, Math.min(maxY, servicesFlickable.contentY - ticks * 28))
                        }
                        event.accepted = true
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: servicesFlickable.contentHeight > servicesFlickable.height + 1 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: parent.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                    }
                }

                Column {
                    id: servicesTable
                    width: parent.width
                    spacing: 0

                    Rectangle {
                        width: parent.width
                        height: root.headerHeight
                        radius: 3
                        color: Qt.rgba(0.55, 0.70, 0.96, 0.12)

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            spacing: root.tblSpacing

                            Text { width: root.nameColWidth(parent.width - 8); height: parent.height; text: "Service"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                            Text { width: root.colStatusW; height: parent.height; text: "Status"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                            Text { width: root.colStateW; height: parent.height; text: "State"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                            Text { width: root.colSinceW; height: parent.height; text: "Loaded Since"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                            Text { width: root.descColWidth(parent.width - 8); height: parent.height; text: "Description"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                        }
                    }

                    Text {
                        width: parent.width
                        visible: root.loading && root.filteredServices().length === 0
                        text: "Loading services..."
                        color: root.overlayColor
                        font.pixelSize: 11
                        font.family: "monospace"
                        topPadding: 6
                    }

                    Text {
                        width: parent.width
                        visible: !root.loading && root.lastError.length > 0 && root.filteredServices().length === 0
                        text: root.lastError
                        color: root.errorColor
                        font.pixelSize: 11
                        font.family: "monospace"
                        wrapMode: Text.Wrap
                        topPadding: 6
                    }

                    Text {
                        width: parent.width
                        visible: !root.loading && root.filteredServices().length === 0 && root.lastError.length === 0
                        text: "(no matching services)"
                        color: root.overlayColor
                        font.pixelSize: 11
                        font.family: "monospace"
                        topPadding: 6
                    }

                    Repeater {
                        model: root.filteredServices()
                        delegate: Item {
                            id: svcRow
                            width: parent.width
                            height: root.rowHeight

                            readonly property bool isSelected: root.serviceKey(modelData) === root.selectedServiceKey
                            readonly property bool rowHover: rowMa.containsMouse

                            Rectangle {
                                anchors.fill: parent
                                radius: 2
                                color: svcRow.isSelected ? Qt.rgba(0.55, 0.70, 0.96, 0.18)
                                    : (svcRow.rowHover ? Qt.rgba(1, 1, 1, 0.04) : (index % 2 === 0 ? "transparent" : Qt.rgba(1, 1, 1, 0.02)))
                            }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                spacing: root.tblSpacing

                                Text {
                                    width: root.nameColWidth(parent.width - 8)
                                    height: parent.height
                                    text: root.shortName(modelData.id) + (modelData.scope === "system" ? " [sys]" : "")
                                    color: svcRow.isSelected ? root.accentColor : root.textColor
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    font.bold: svcRow.isSelected
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: root.colStatusW
                                    height: parent.height
                                    text: modelData.active_state || "--"
                                    color: root.statusColor(modelData)
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    font.bold: true
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                Text {
                                    width: root.colStateW
                                    height: parent.height
                                    text: modelData.sub_state || "--"
                                    color: root.stateColor(modelData)
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                Text {
                                    width: root.colSinceW
                                    height: parent.height
                                    text: root.formatSince(modelData.loaded_since)
                                    color: root.subtextColor
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: root.descColWidth(parent.width - 8)
                                    height: parent.height
                                    text: modelData.description || "--"
                                    color: root.subtextColor
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.selectedServiceKey = root.serviceKey(modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}