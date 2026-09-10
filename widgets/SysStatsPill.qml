import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io as Io
import "../components"

// SysStatsPill — CPU / Memory / GPU on the bar; left-click metrics, right-click btop/nvtop.
// Options: showStatCpu/Mem/Gpu, showStatGauges (bar), showStatMenuGraphs (popups).
// Face text: bar.barText / fontBarResolved / fontBarFace.

Rectangle {
    id: root

    required property var bar
    required property Item barBg
    property bool mediaActive: false

    // Horizontal scale only. Scale section widths, gauges, and fonts together so
    // labels/values never stack on top of each other when shrunk.
    readonly property real _ws: (bar.widgetScale ? bar.widgetScale("stats") : 1.0)
    // Bar widget text size (Themes → Fonts → Bar widget text)
    readonly property int _font: {
        var base = (bar.fontBarFace !== undefined) ? bar.fontBarFace : 13
        return Math.max(9, Math.round(base * _ws))
    }
    readonly property string _faceFont: (bar.fontBarResolved !== undefined && String(bar.fontBarResolved).length)
                                        ? bar.fontBarResolved : bar.fontFamily
    readonly property int _gaugeW: Math.max(18, Math.round(bar.statGaugeWidth * _ws))
    readonly property int _gaugeH: Math.max(4, Math.round(bar.statGaugeHeight * _ws))
    // Optional minimum section width (0 = hug content). Sections never clip.
    readonly property int _secMinW: Math.max(0, Math.round(bar.statPillSectionWidth * _ws))
    readonly property int _rowGap: Math.max(3, Math.round(5 * _ws))
    readonly property int _valGap: Math.max(2, Math.round(3 * _ws))
    readonly property int _secInnerPad: Math.max(3, Math.round(4 * _ws))
    readonly property int _secH: Math.max(20, Math.round(26 * _ws))
    // Options: which sections / util bars appear on the pill
    readonly property bool _showCpu: bar.showStatCpu !== undefined ? !!bar.showStatCpu : true
    readonly property bool _showMem: bar.showStatMem !== undefined ? !!bar.showStatMem : true
    readonly property bool _showGpu: bar.showStatGpu !== undefined ? !!bar.showStatGpu : true
    // Options: util bars on the bar face (independent of menu graphs)
    readonly property bool _showGauges: bar.showStatGauges !== undefined ? !!bar.showStatGauges : true
    // Options: circular gauges + history in metrics popups (process lists always stay)
    readonly property bool _showMenuGraphs: bar.showStatMenuGraphs !== undefined ? !!bar.showStatMenuGraphs : true
    readonly property int _nSec: (_showCpu ? 1 : 0) + (_showMem ? 1 : 0) + (_showGpu ? 1 : 0)
    readonly property int _padH: Math.max(4, Math.round(bar.statPillPaddingH * _ws))
    // Full slot between sections (divider centered inside; Row spacing is 0).
    readonly property int _sepW: Math.max(6, Math.round(bar.statPillSpacing * _ws))
    readonly property int _nSep: Math.max(0, _nSec - 1)
    function _sectionW(inner) {
        return Math.max(_secMinW, Math.ceil(inner.implicitWidth) + _secInnerPad * 2)
    }
    readonly property int _contentW: {
        if (_nSec <= 0)
            return 0
        var cpuW = _showCpu ? _sectionW(cpuInner) : 0
        var memW = _showMem ? _sectionW(memInner) : 0
        var gpuW = _showGpu ? _sectionW(gpuInner) : 0
        return cpuW + memW + gpuW + _nSep * _sepW
    }
    // Snug to content + padding. statPillWidth only expands if set larger intentionally.
    readonly property int _pillW: {
        if (_nSec <= 0)
            return 0
        var fitted = _padH * 2 + _contentW
        var configured = Math.round(bar.statPillWidth * _ws)
        return configured > fitted ? configured : fitted
    }
    Layout.preferredWidth: _pillW
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter
    visible: !mediaActive && sysStatsReady && _nSec > 0
    implicitWidth: Layout.preferredWidth
    implicitHeight: Layout.preferredHeight
    radius: bar.pillRadius
    // Outer chrome is stable; CPU/Mem/GPU sections highlight individually.
    color: bar.glassPillBg
    border.width: bar.controlBorderWidth
    border.color: bar.pillBorder
    clip: true

    readonly property bool metricsPopupOpen: cpuMetricsPopup.visible || memMetricsPopup.visible || gpuMetricsPopup.visible
    property bool cpuLiveUpdates: true
    property bool memLiveUpdates: true
    property bool gpuLiveUpdates: true

    // ===== Stats State & Polling (pill display — unchanged) =====
    property real cpuUtil: 0
    property int  cpuTemp: 0
    property real memUtil: 0
    property real memUsedGib: 0
    property real gpuUtil: 0
    property int  gpuTemp: 0
    property bool sysStatsReady: false

    function updateSysStats(d) {
        if (d.cpu) {
            cpuUtil = Number(d.cpu.util) || 0
            cpuTemp = Math.round(Number(d.cpu.temp) || 0)
        }
        if (d.mem) {
            memUtil = Number(d.mem.util) || 0
            memUsedGib = Number(d.mem.used_gib) || 0
        }
        if (d.gpu) {
            gpuUtil = Number(d.gpu.util) || 0
            gpuTemp = Math.round(Number(d.gpu.temp) || 0)
        }
        sysStatsReady = true
    }

    Io.Process {
        id: statsPoller
        command: ["/home/crome/.config/quickshell/scripts/bar-stats.sh"]
        stdout: Io.SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                const trimmed = line.trim()
                if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) return
                try {
                    const d = JSON.parse(trimmed)
                    root.updateSysStats(d)
                } catch (e) {}
            }
        }
        onExited: (code) => {
            // ready for next timer kick
        }
    }

    Timer {
        id: statsTimer
        interval: 1600
        running: true
        repeat: true
        onTriggered: {
            if (!statsPoller.running) statsPoller.running = true
        }
    }

    Component.onCompleted: {
        Qt.callLater(function() {
            if (!statsPoller.running) statsPoller.running = true
            if (!bar.popupStatsPersistPause) {
                cpuLiveUpdates = bar.popupStatsLiveUpdates
                memLiveUpdates = bar.popupStatsLiveUpdates
                gpuLiveUpdates = bar.popupStatsLiveUpdates
            }
        })
    }

    // ===== Rich metrics (left-click popups; terminal apps on right-click) =====
    Io.FileView {
        id: statsPauseState
        path: bar.popupStatsPersistPause
              ? "/home/crome/.config/quickshell/state/popup-stats.json"
              : ""
        watchChanges: bar.popupStatsPersistPause
        onFileChanged: if (bar.popupStatsPersistPause) reload()
        onAdapterUpdated: if (bar.popupStatsPersistPause) writeAdapter()
        onLoaded: if (bar.popupStatsPersistPause) root.syncLiveUpdatesFromPersisted()
        onLoadFailed: if (bar.popupStatsPersistPause) root.seedPauseStateFromConfig()

        Io.JsonAdapter {
            id: pauseAdapter
            property bool cpuLiveUpdates: bar.popupStatsLiveUpdates
            property bool memLiveUpdates: bar.popupStatsLiveUpdates
            property bool gpuLiveUpdates: bar.popupStatsLiveUpdates
        }
    }

    SysMonService {
        id: sysMonService
        autoPoll: false
    }

    function seedPauseStateFromConfig() {
        pauseAdapter.cpuLiveUpdates = bar.popupStatsLiveUpdates
        pauseAdapter.memLiveUpdates = bar.popupStatsLiveUpdates
        pauseAdapter.gpuLiveUpdates = bar.popupStatsLiveUpdates
        syncLiveUpdatesFromPersisted()
    }

    function syncLiveUpdatesFromPersisted() {
        cpuLiveUpdates = pauseAdapter.cpuLiveUpdates
        memLiveUpdates = pauseAdapter.memLiveUpdates
        gpuLiveUpdates = pauseAdapter.gpuLiveUpdates
        syncMetricsPolling()
    }

    function setLiveUpdates(section, enabled) {
        if (section === "cpu") {
            cpuLiveUpdates = enabled
            if (bar.popupStatsPersistPause)
                pauseAdapter.cpuLiveUpdates = enabled
        } else if (section === "mem") {
            memLiveUpdates = enabled
            if (bar.popupStatsPersistPause)
                pauseAdapter.memLiveUpdates = enabled
        } else if (section === "gpu") {
            gpuLiveUpdates = enabled
            if (bar.popupStatsPersistPause)
                pauseAdapter.gpuLiveUpdates = enabled
        }
    }

    function metricsPollingEnabled() {
        return (cpuMetricsPopup.visible && cpuLiveUpdates)
            || (memMetricsPopup.visible && memLiveUpdates)
            || (gpuMetricsPopup.visible && gpuLiveUpdates)
    }

    function syncMetricsPolling() {
        const poll = metricsPollingEnabled()
        sysMonService.setAutoPoll(poll)
        if (!poll)
            sysMonService.stopPolling()
        else
            sysMonService.refresh()
    }

    // === Public API (shell IPC: qs ipc call sysStatsPill …) ===
    function setCpuLiveUpdates(enabled) {
        setLiveUpdates("cpu", enabled)
        syncMetricsPolling()
    }

    function setMemLiveUpdates(enabled) {
        setLiveUpdates("mem", enabled)
        syncMetricsPolling()
    }

    function setGpuLiveUpdates(enabled) {
        setLiveUpdates("gpu", enabled)
        syncMetricsPolling()
    }

    function setMetricsLiveUpdates(enabled) {
        setLiveUpdates("cpu", enabled)
        setLiveUpdates("mem", enabled)
        setLiveUpdates("gpu", enabled)
        syncMetricsPolling()
    }

    function toggleCpuLiveUpdates() {
        setCpuLiveUpdates(!cpuLiveUpdates)
    }

    function toggleMemLiveUpdates() {
        setMemLiveUpdates(!memLiveUpdates)
    }

    function toggleGpuLiveUpdates() {
        setGpuLiveUpdates(!gpuLiveUpdates)
    }

    function toggleMetricsLiveUpdates() {
        setMetricsLiveUpdates(!(cpuLiveUpdates || memLiveUpdates || gpuLiveUpdates))
    }

    function hideMetricsPopups() {
        cpuMetricsPopup.visible = false
        memMetricsPopup.visible = false
        gpuMetricsPopup.visible = false
        syncMetricsPolling()
    }

    function showMetricsPopup(popup, anchorItem, section) {
        if (popup.visible) {
            popup.visible = false
            syncMetricsPolling()
            return
        }
        if (popup !== cpuMetricsPopup) cpuMetricsPopup.visible = false
        if (popup !== memMetricsPopup) memMetricsPopup.visible = false
        if (popup !== gpuMetricsPopup) gpuMetricsPopup.visible = false
        if (bar.popupStatsPersistPause) {
            if (section === "cpu")
                cpuLiveUpdates = pauseAdapter.cpuLiveUpdates
            else if (section === "mem")
                memLiveUpdates = pauseAdapter.memLiveUpdates
            else if (section === "gpu")
                gpuLiveUpdates = pauseAdapter.gpuLiveUpdates
        }

        var anchorXFrac = section === "cpu" ? bar.popupStatsCpuAnchorX
                        : section === "mem" ? bar.popupStatsMemAnchorX
                        : bar.popupStatsGpuAnchorX
        var anchorWholePill = section === "cpu" ? bar.popupStatsCpuAnchorWholePill
                            : section === "mem" ? bar.popupStatsMemAnchorWholePill
                            : bar.popupStatsGpuAnchorWholePill
        var offsetX = section === "cpu" ? bar.popupStatsCpuOffsetX
                    : section === "mem" ? bar.popupStatsMemOffsetX
                    : bar.popupStatsGpuOffsetX
        var offsetY = section === "cpu" ? bar.popupStatsCpuOffsetY
                    : section === "mem" ? bar.popupStatsMemOffsetY
                    : bar.popupStatsGpuOffsetY
        var barGap = section === "cpu" ? bar.popupStatsCpuBarGap
                   : section === "mem" ? bar.popupStatsMemBarGap
                   : bar.popupStatsGpuBarGap

        var layoutAnchor = anchorWholePill ? root : anchorItem
        var popupW = popup.implicitWidth
        if (typeof bar.placePopup === "function") {
            bar.placePopup(popup, layoutAnchor, popupW, popup.implicitHeight, barGap,
                           layoutAnchor.width * anchorXFrac, offsetX, offsetY)
        } else {
            var pos = layoutAnchor.mapToItem(barBg, layoutAnchor.width * anchorXFrac, 0)
            var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920
            var targetX = bar.sideMargin + pos.x - (popupW / 2) + offsetX
            var minX = 12
            var maxX = screenW - popupW - 12
            popup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX))
            popup.anchor.rect.y = bar.popupAnchorY(popup.implicitHeight, barGap) + offsetY
        }
        popup.visible = true
        syncMetricsPolling()
    }

    // === Appearance via Theme ===
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: bar.glassHighlight
        radius: parent.radius
    }

    // Centered content cluster — snug to text; equal side padding only if
    // statPillWidth intentionally expands the pill past content.
    Row {
        id: statsRow
        anchors.centerIn: parent
        spacing: 0

        // ----- CPU -----
        Rectangle {
            id: cpuSection
            visible: root._showCpu
            width: root._sectionW(cpuInner)
            height: root._secH
            radius: bar.workspaceRadius
            color: cpuClick.containsMouse ? bar.iconHoverBg : "transparent"
            border.width: cpuClick.containsMouse ? bar.controlBorderWidth : 0
            border.color: cpuClick.containsMouse ? bar.accent : "transparent"

            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }
            Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

            MouseArea {
                id: cpuClick
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        root.hideMetricsPopups()
                        Quickshell.execDetached(["kitty", "-e", "btop"])
                    } else {
                        root.showMetricsPopup(cpuMetricsPopup, cpuSection, "cpu")
                    }
                }
                BarToolTip {
                    bar: root.bar
                    visible: cpuClick.containsMouse
                    text: "Left: CPU metrics · Right: btop"
                    anchorItem: cpuClick
                }
            }

            Row {
                id: cpuInner
                anchors.centerIn: parent
                spacing: root._rowGap

                Text {
                    text: "CPU"
                    font.pixelSize: root._font
                    font.bold: true
                    font.family: root._faceFont
                    color: cpuClick.containsMouse ? bar.accent
                           : ((bar.barText !== undefined) ? bar.barText : bar.text)
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                    visible: root._showGauges
                    width: root._gaugeW
                    height: root._gaugeH
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: bar.statGaugeRadius
                        color: bar.statTrack
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(2, Math.min(parent.width, parent.width * (root.cpuUtil / 100)))
                        height: root._gaugeH
                        radius: bar.statGaugeRadius
                        color: bar.statUtilColor(root.cpuUtil)

                        Behavior on width {
                            NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
                        }
                    }
                }

                Row {
                    spacing: root._valGap
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: Math.round(root.cpuUtil) + "%"
                        font.pixelSize: root._font
                        font.bold: true
                        font.family: root._faceFont
                        color: bar.statUtilColor(root.cpuUtil)
                    }
                    Text {
                        text: "|"
                        font.pixelSize: root._font
                        font.family: root._faceFont
                        color: bar.statValueSeparator
                    }
                    Text {
                        text: root.cpuTemp + "°"
                        font.pixelSize: root._font
                        font.bold: true
                        font.family: root._faceFont
                        color: bar.statTempColor(root.cpuTemp)
                    }
                }
            }
        }

        // Separator slot: one gap budget with the divider centered (no double spacing).
        Item {
            visible: root._showCpu && (root._showMem || root._showGpu)
            width: root._sepW
            height: root._secH

            Rectangle {
                width: 1
                height: Math.max(12, Math.round(15 * root._ws))
                anchors.centerIn: parent
                color: bar.divider
            }
        }

        // ----- Memory -----
        Rectangle {
            id: memSection
            visible: root._showMem
            width: root._sectionW(memInner)
            height: root._secH
            radius: bar.workspaceRadius
            color: memClick.containsMouse ? bar.iconHoverBg : "transparent"
            border.width: memClick.containsMouse ? bar.controlBorderWidth : 0
            border.color: memClick.containsMouse ? bar.accent : "transparent"

            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }
            Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

            MouseArea {
                id: memClick
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        root.hideMetricsPopups()
                        Quickshell.execDetached(["kitty", "-e", "btop"])
                    } else {
                        root.showMetricsPopup(memMetricsPopup, memSection, "mem")
                    }
                }
                BarToolTip {
                    bar: root.bar
                    visible: memClick.containsMouse
                    text: "Left: Memory metrics · Right: btop"
                    anchorItem: memClick
                }
            }

            Row {
                id: memInner
                anchors.centerIn: parent
                spacing: root._rowGap

                Text {
                    text: "Memory"
                    font.pixelSize: root._font
                    font.bold: true
                    font.family: root._faceFont
                    color: memClick.containsMouse ? bar.accent
                           : ((bar.barText !== undefined) ? bar.barText : bar.text)
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                    visible: root._showGauges
                    width: root._gaugeW
                    height: root._gaugeH
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: bar.statGaugeRadius
                        color: bar.statTrack
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(2, Math.min(parent.width, parent.width * (root.memUtil / 100)))
                        height: root._gaugeH
                        radius: bar.statGaugeRadius
                        color: bar.statUtilColor(root.memUtil)

                        Behavior on width {
                            NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
                        }
                    }
                }

                Row {
                    spacing: root._valGap
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: Math.round(root.memUtil) + "%"
                        font.pixelSize: root._font
                        font.bold: true
                        font.family: root._faceFont
                        color: bar.statUtilColor(root.memUtil)
                    }
                    Text {
                        text: "|"
                        font.pixelSize: root._font
                        font.family: root._faceFont
                        color: bar.statValueSeparator
                    }
                    Text {
                        text: root.memUsedGib.toFixed(0) + "G"
                        font.pixelSize: root._font
                        font.bold: true
                        font.family: root._faceFont
                        color: (bar.barText !== undefined) ? bar.barText : bar.text
                    }
                }
            }
        }

        Item {
            visible: root._showMem && root._showGpu
            width: root._sepW
            height: root._secH

            Rectangle {
                width: 1
                height: Math.max(12, Math.round(15 * root._ws))
                anchors.centerIn: parent
                color: bar.divider
            }
        }

        // ----- GPU -----
        Rectangle {
            id: gpuSection
            visible: root._showGpu
            width: root._sectionW(gpuInner)
            height: root._secH
            radius: bar.workspaceRadius
            color: gpuClick.containsMouse ? bar.iconHoverBg : "transparent"
            border.width: gpuClick.containsMouse ? bar.controlBorderWidth : 0
            border.color: gpuClick.containsMouse ? bar.accent : "transparent"

            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }
            Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

            MouseArea {
                id: gpuClick
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        root.hideMetricsPopups()
                        Quickshell.execDetached(["kitty", "-e", "nvtop"])
                    } else {
                        root.showMetricsPopup(gpuMetricsPopup, gpuSection, "gpu")
                    }
                }
                BarToolTip {
                    bar: root.bar
                    visible: gpuClick.containsMouse
                    text: "Left: GPU metrics · Right: nvtop"
                    anchorItem: gpuClick
                }
            }

            Row {
                id: gpuInner
                anchors.centerIn: parent
                spacing: root._rowGap

                Text {
                    text: "GPU"
                    font.pixelSize: root._font
                    font.bold: true
                    font.family: root._faceFont
                    color: gpuClick.containsMouse ? bar.accent
                           : ((bar.barText !== undefined) ? bar.barText : bar.text)
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                    visible: root._showGauges
                    width: root._gaugeW
                    height: root._gaugeH
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: bar.statGaugeRadius
                        color: bar.statTrack
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(2, Math.min(parent.width, parent.width * (root.gpuUtil / 100)))
                        height: root._gaugeH
                        radius: bar.statGaugeRadius
                        color: bar.statUtilColor(root.gpuUtil)

                        Behavior on width {
                            NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
                        }
                    }
                }

                Row {
                    spacing: root._valGap
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: Math.round(root.gpuUtil) + "%"
                        font.pixelSize: root._font
                        font.bold: true
                        font.family: root._faceFont
                        color: bar.statUtilColor(root.gpuUtil)
                    }
                    Text {
                        text: "|"
                        font.pixelSize: root._font
                        font.family: root._faceFont
                        color: bar.statValueSeparator
                    }
                    Text {
                        text: root.gpuTemp + "°"
                        font.pixelSize: root._font
                        font.bold: true
                        font.family: root._faceFont
                        color: bar.statTempColor(root.gpuTemp)
                    }
                }
            }
        }
    }

    // ===== CPU METRICS POPUP =====
    PopupWindow {
        id: cpuMetricsPopup
        anchor.window: bar
        implicitWidth: bar.popupStatsCpuWidth
        implicitHeight: bar.popupStatsCpuHeight
        visible: false
        grabFocus: true
        color: "transparent"
        onVisibleChanged: if (!visible) root.syncMetricsPolling()

        Rectangle {
            anchors.fill: parent
            radius: bar.popupRadius
            color: bar.glassPopupBg
            border.width: bar.controlBorderWidth
            border.color: bar.glassPopupBorder

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: bar.popupSpacingTight
                spacing: bar.popupSectionSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: bar.popupSectionSpacing

                    Text {
                        text: "CPU Metrics"
                        color: bar.text
                        font.pixelSize: bar.popupTitleSize
                        font.bold: true
                        font.family: bar.fontFamily
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: cpuLiveBtnLabel.implicitWidth + 16
                        radius: bar.buttonRadius
                        color: cpuLiveBtnMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.6)
                        border.width: bar.controlBorderWidth
                        border.color: bar.dividerStrong

                        Text {
                            id: cpuLiveBtnLabel
                            anchors.centerIn: parent
                            text: cpuLiveUpdates ? "Pause updates" : "Resume updates"
                            color: cpuLiveUpdates ? bar.subtext : bar.accent
                            font.pixelSize: bar.popupHintSize
                            font.bold: !cpuLiveUpdates
                            font.family: bar.fontFamily
                        }

                        MouseArea {
                            id: cpuLiveBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                setLiveUpdates("cpu", !cpuLiveUpdates)
                                syncMetricsPolling()
                            }
                        }
                    }

                    Text {
                        text: (cpuLiveUpdates ? "live" : "paused") + " · click outside to close"
                        color: bar.subtext
                        font.pixelSize: bar.popupHintSize
                        font.family: bar.fontFamily
                    }
                }

                CpuMonitorView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    service: sysMonService
                    showGraphs: root._showMenuGraphs
                    textColor: bar.text
                    subtextColor: bar.subtext
                    accentColor: bar.accent
                    surfaceColor: bar.surface
                    overlayColor: bar.overlay
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: cpuMetricsPopup.visible = false
        }
    }

    // ===== MEMORY METRICS POPUP =====
    PopupWindow {
        id: memMetricsPopup
        anchor.window: bar
        implicitWidth: bar.popupStatsMemWidth
        implicitHeight: bar.popupStatsMemHeight
        visible: false
        grabFocus: true
        color: "transparent"
        onVisibleChanged: if (!visible) root.syncMetricsPolling()

        Rectangle {
            anchors.fill: parent
            radius: bar.popupRadius
            color: bar.glassPopupBg
            border.width: bar.controlBorderWidth
            border.color: bar.glassPopupBorder

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: bar.popupSpacingTight
                spacing: bar.popupSectionSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: bar.popupSectionSpacing

                    Text {
                        text: "Memory Metrics"
                        color: bar.text
                        font.pixelSize: bar.popupTitleSize
                        font.bold: true
                        font.family: bar.fontFamily
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: memLiveBtnLabel.implicitWidth + 16
                        radius: bar.buttonRadius
                        color: memLiveBtnMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.6)
                        border.width: bar.controlBorderWidth
                        border.color: bar.dividerStrong

                        Text {
                            id: memLiveBtnLabel
                            anchors.centerIn: parent
                            text: memLiveUpdates ? "Pause updates" : "Resume updates"
                            color: memLiveUpdates ? bar.subtext : bar.accent
                            font.pixelSize: bar.popupHintSize
                            font.bold: !memLiveUpdates
                            font.family: bar.fontFamily
                        }

                        MouseArea {
                            id: memLiveBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                setLiveUpdates("mem", !memLiveUpdates)
                                syncMetricsPolling()
                            }
                        }
                    }

                    Text {
                        text: (memLiveUpdates ? "live" : "paused") + " · click outside to close"
                        color: bar.subtext
                        font.pixelSize: bar.popupHintSize
                        font.family: bar.fontFamily
                    }
                }

                MemoryMonitorView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    service: sysMonService
                    showGraphs: root._showMenuGraphs
                    textColor: bar.text
                    subtextColor: bar.subtext
                    accentColor: bar.accent
                    surfaceColor: bar.surface
                    overlayColor: bar.overlay
                    gaugeLowColor: bar.gaugeLow
                    gaugeMidColor: bar.gaugeMid
                    gaugeHighColor: bar.gaugeHigh
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: memMetricsPopup.visible = false
        }
    }

    // ===== GPU METRICS POPUP =====
    PopupWindow {
        id: gpuMetricsPopup
        anchor.window: bar
        implicitWidth: bar.popupStatsGpuWidth
        implicitHeight: bar.popupStatsGpuHeight
        visible: false
        grabFocus: true
        color: "transparent"
        onVisibleChanged: if (!visible) root.syncMetricsPolling()

        Rectangle {
            anchors.fill: parent
            radius: bar.popupRadius
            color: bar.glassPopupBg
            border.width: bar.controlBorderWidth
            border.color: bar.glassPopupBorder

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: bar.popupSpacingTight
                spacing: bar.popupSectionSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: bar.popupSectionSpacing

                    Text {
                        text: "GPU Metrics"
                        color: bar.text
                        font.pixelSize: bar.popupTitleSize
                        font.bold: true
                        font.family: bar.fontFamily
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: gpuLiveBtnLabel.implicitWidth + 16
                        radius: bar.buttonRadius
                        color: gpuLiveBtnMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.6)
                        border.width: bar.controlBorderWidth
                        border.color: bar.dividerStrong

                        Text {
                            id: gpuLiveBtnLabel
                            anchors.centerIn: parent
                            text: gpuLiveUpdates ? "Pause updates" : "Resume updates"
                            color: gpuLiveUpdates ? bar.subtext : bar.accent
                            font.pixelSize: bar.popupHintSize
                            font.bold: !gpuLiveUpdates
                            font.family: bar.fontFamily
                        }

                        MouseArea {
                            id: gpuLiveBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                setLiveUpdates("gpu", !gpuLiveUpdates)
                                syncMetricsPolling()
                            }
                        }
                    }

                    Text {
                        text: (gpuLiveUpdates ? "live" : "paused") + " · click outside to close"
                        color: bar.subtext
                        font.pixelSize: bar.popupHintSize
                        font.family: bar.fontFamily
                    }
                }

                GpuMonitorView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    service: sysMonService
                    showGraphs: root._showMenuGraphs
                    textColor: bar.text
                    subtextColor: bar.subtext
                    accentColor: bar.accent
                    surfaceColor: bar.surface
                    overlayColor: bar.overlay
                    gaugeLowColor: bar.gaugeLow
                    gaugeMidColor: bar.gaugeMid
                    gaugeHighColor: bar.gaugeHigh
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: gpuMetricsPopup.visible = false
        }
    }
}