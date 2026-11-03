import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io as Io
import "../components"

// SysStatsPill — CPU / Memory / GPU / VRAM on the bar; the configured mouse
// button (Options → Stats; Config statLaunchButton) launches btop / nvtop in
// the configured terminal (Config statTerminal). The other button does nothing.
// The launched window gets the app name as its window class + title (e.g. "btop")
// where the terminal supports it, so Hyprland rules / window lists match the app.
// Options: showStatCpu/Vram/Mem/Gpu, showStatGauges (bar).
// Face text: bar.barText / fontBarResolved / fontBarFace.

Rectangle {
    id: root

    required property var bar

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
    readonly property bool _showVram: bar.showStatVram !== undefined ? !!bar.showStatVram : true
    readonly property bool _showMem: bar.showStatMem !== undefined ? !!bar.showStatMem : true
    readonly property bool _showGpu: bar.showStatGpu !== undefined ? !!bar.showStatGpu : true
    // Options: util bars on the bar face
    readonly property bool _showGauges: bar.showStatGauges !== undefined ? !!bar.showStatGauges : true
    // Option: which mouse button launches btop/nvtop ("left" or "right")
    readonly property string _launchBtn: String(bar.statLaunchButton || "right").toLowerCase() === "left" ? "left" : "right"
    readonly property int _nSec: (_showCpu ? 1 : 0) + (_showMem ? 1 : 0) + (_showGpu ? 1 : 0) + (_showVram ? 1 : 0)
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
        var vramW = _showVram ? _sectionW(vramInner) : 0
        return cpuW + memW + gpuW + vramW + _nSep * _sepW
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
    visible: sysStatsReady && _nSec > 0
    implicitWidth: Layout.preferredWidth
    implicitHeight: Layout.preferredHeight
    radius: bar.pillRadius
    // Outer chrome is stable; CPU/Mem/GPU sections highlight individually.
    color: bar.glassPillBg
    border.width: bar.controlBorderWidth
    border.color: bar.pillBorder
    clip: true

    // ===== Stats State & Polling (pill display) =====
    property real cpuUtil: 0
    property int  cpuTemp: 0
    property real vramUtil: 0
    property real vramUsedGib: 0
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
        if (d.vram) {
            vramUtil = Number(d.vram.util) || 0
            vramUsedGib = Number(d.vram.used_gib) || 0
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
        command: [Quickshell.shellPath("scripts/bar-stats.sh")]
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
        // Bar pill refresh — CPU | Memory | GPU | VRAM
        interval: 2000
        running: true
        repeat: true
        onTriggered: {
            if (!statsPoller.running) statsPoller.running = true
        }
    }

    Component.onCompleted: {
        Qt.callLater(function() {
            if (!statsPoller.running) statsPoller.running = true
        })
    }

    // === Terminal launches (right-click) ===
    // Runs `app` (btop / nvtop) in the terminal picked in Options → Stats
    // (bar.statTerminal; Config statTerminal default). Where the terminal
    // supports it, the window class/app_id AND title are set to the app name
    // (e.g. "btop") so Hyprland rules and window lists match the app, not the
    // terminal. Unsupported flags are deliberately omitted — an unknown flag
    // would abort the launch — so those terminals fall back to plain `-e`.
    function terminalArgv(app) {
        const term = String(bar.statTerminal || "kitty")
        switch (term) {
        case "kitty":          return [term, "--class", app, "--name", app, "--title", app, "-e", app]
        case "foot":           return [term, "--app-id", app, "--title", app, app]
        case "footclient":     return [term, "--app-id", app, "--title", app, app]
        case "alacritty":      return [term, "--class", app, "-t", app, "-e", app]
        case "ghostty":        return [term, "--class=" + app, "--title=" + app, "-e", app]
        case "wezterm":        return [term, "start", "--class", app, "--", app]
        case "gnome-terminal": return [term, "--title", app, "--", app]
        case "xfce4-terminal": return [term, "--title", app, "-x", app]
        case "mate-terminal":  return [term, "--title", app, "-x", app]
        case "terminator":     return [term, "--title", app, "-x", app]
        case "st":             return [term, "-n", app, "-T", app, "-e", app]
        case "xterm":          return [term, "-name", app, "-T", app, "-e", app]
        case "urxvt":          return [term, "-name", app, "-title", app, "-e", app]
        default:               return [term, "-e", app]
        }
    }

    function launchInTerminal(app) {
        Quickshell.execDetached(terminalArgv(app))
    }

    // True when `button` (Qt.LeftButton/Qt.RightButton) is the configured
    // launch button. The other button is accepted but does nothing.
    function clickLaunches(button) {
        return (_launchBtn === "left") ? (button === Qt.LeftButton) : (button === Qt.RightButton)
    }

    function launchHint(app) {
        return (_launchBtn === "left" ? "Left: " : "Right: ") + app
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
                    if (root.clickLaunches(mouse.button))
                        root.launchInTerminal("btop")
                }
                BarToolTip {
                    bar: root.bar
                    widgetId: "stats"
                    visible: cpuClick.containsMouse
                    text: root.launchHint("btop")
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
                        color: bar.statUtilColor(root.cpuUtil, "cpu")

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
                        color: bar.statUtilColor(root.cpuUtil, "cpu")
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
            visible: root._showCpu && (root._showMem || root._showGpu || root._showVram)
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
                    if (root.clickLaunches(mouse.button))
                        root.launchInTerminal("btop")
                }
                BarToolTip {
                    bar: root.bar
                    widgetId: "stats"
                    visible: memClick.containsMouse
                    text: root.launchHint("btop")
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
                        color: bar.statUtilColor(root.memUtil, "mem")

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
                        color: bar.statUtilColor(root.memUtil, "mem")
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
            visible: root._showMem && (root._showGpu || root._showVram)
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
                    if (root.clickLaunches(mouse.button))
                        root.launchInTerminal("nvtop")
                }
                BarToolTip {
                    bar: root.bar
                    widgetId: "stats"
                    visible: gpuClick.containsMouse
                    text: root.launchHint("nvtop")
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
                        color: bar.statUtilColor(root.gpuUtil, "gpu")

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
                        color: bar.statUtilColor(root.gpuUtil, "gpu")
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

        // Separator slot between GPU and VRAM.
        Item {
            visible: root._showGpu && root._showVram
            width: root._sepW
            height: root._secH

            Rectangle {
                width: 1
                height: Math.max(12, Math.round(15 * root._ws))
                anchors.centerIn: parent
                color: bar.divider
            }
        }

        // ----- VRAM -----
        Rectangle {
            id: vramSection
            visible: root._showVram
            width: root._sectionW(vramInner)
            height: root._secH
            radius: bar.workspaceRadius
            color: vramClick.containsMouse ? bar.iconHoverBg : "transparent"
            border.width: vramClick.containsMouse ? bar.controlBorderWidth : 0
            border.color: vramClick.containsMouse ? bar.accent : "transparent"

            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }
            Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

            MouseArea {
                id: vramClick
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (root.clickLaunches(mouse.button))
                        root.launchInTerminal("nvtop")
                }
                BarToolTip {
                    bar: root.bar
                    widgetId: "stats"
                    visible: vramClick.containsMouse
                    text: root.launchHint("nvtop")
                    anchorItem: vramClick
                }
            }

            Row {
                id: vramInner
                anchors.centerIn: parent
                spacing: root._rowGap

                Text {
                    text: "VRAM"
                    font.pixelSize: root._font
                    font.bold: true
                    font.family: root._faceFont
                    color: vramClick.containsMouse ? bar.accent
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
                        width: Math.max(2, Math.min(parent.width, parent.width * (root.vramUtil / 100)))
                        height: root._gaugeH
                        radius: bar.statGaugeRadius
                        color: bar.statUtilColor(root.vramUtil, "vram")

                        Behavior on width {
                            NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
                        }
                    }
                }

                Row {
                    spacing: root._valGap
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: Math.round(root.vramUtil) + "%"
                        font.pixelSize: root._font
                        font.bold: true
                        font.family: root._faceFont
                        color: bar.statUtilColor(root.vramUtil, "vram")
                    }
                    Text {
                        text: "|"
                        font.pixelSize: root._font
                        font.family: root._faceFont
                        color: bar.statValueSeparator
                    }
                    Text {
                        text: root.vramUsedGib.toFixed(1) + "G"
                        font.pixelSize: root._font
                        font.bold: true
                        font.family: root._faceFont
                        color: (bar.barText !== undefined) ? bar.barText : bar.text
                    }
                }
            }
        }
    }
}
