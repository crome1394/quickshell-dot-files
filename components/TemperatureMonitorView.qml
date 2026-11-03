import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Live temperature / sensor monitoring tab (SysMonService + gauges + sparklines).
Item {
    id: root

    required property var service

    property color textColor: "#f0f4fc"
    property color subtextColor: "#a8b4c8"
    property color accentColor: "#00F0E0"
    property color surfaceColor: "#141a24"
    property color overlayColor: "#6e7a90"
    property color gaugeLowColor: "#2ee59a"
    property color gaugeMidColor: "#f0d060"
    property color gaugeHighColor: "#FF3D8A"
    property color cpuSparkColor: "#00F0E0"
    property color gpuSparkColor: "#2ee59a"

    readonly property int cardRadius: 6
    readonly property int cardMargin: 10
    readonly property int sensorRowHeight: 15
    readonly property int sensorHeaderHeight: 17
    readonly property int sectionSpacing: 8
    readonly property int tblSpacing: 4
    readonly property int colSensorW: 120
    readonly property int colValueW: 52
    readonly property int colStatusW: 56

    function sensorTableFixedWidth() {
        return colSensorW + colValueW + colStatusW + tblSpacing * 3
    }

    function sensorNameColWidth(totalWidth) {
        return Math.max(72, totalWidth - colValueW - colStatusW - tblSpacing * 3 - 8)
    }

    function tempColor(c) {
        const v = Number(c) || 0
        if (v > 85) return root.gaugeHighColor
        if (v > 65) return root.gaugeMidColor
        return root.gaugeLowColor
    }

    function tempStatus(c) {
        const v = Number(c) || 0
        if (v > 85) return "Critical"
        if (v > 65) return "Warm"
        return "OK"
    }

    function formatChipName(chip) {
        if (!chip) return "Sensor"
        const c = String(chip).toLowerCase()
        if (c.indexOf("spd5118") !== -1) return "RAM"
        if (c.indexOf("mt7925") !== -1 || c.indexOf("mt76") !== -1) return "WiFi"
        if (c.indexOf("r8169") !== -1 || c.indexOf("r8125") !== -1) return "NIC"
        if (c.indexOf("amdgpu") !== -1) return "GPU Chip"
        if (c.indexOf("nvme") !== -1) return "NVMe"
        const short = c.replace(/-pci-[0-9a-f]+$/i, "").replace(/-i2c-[0-9a-f-]+$/i, "")
        return short.length ? short : chip
    }

    function formatSensorLabel(chip, label) {
        const base = formatChipName(chip)
        if (!label || label === base) return base
        return base + " · " + label
    }

    function formatNvmeKey(key) {
        if (!key) return "NVMe"
        const m = String(key).match(/nvme-pci-([0-9a-f]+)/i)
        return m ? "NVMe " + m[1].toUpperCase() : "NVMe"
    }

    function formatFanName(key) {
        if (!key) return "Fan"
        const m = String(key).match(/fan([0-9]+)_input/i)
        return m ? "Fan " + m[1] : key.replace(/_input$/i, "")
    }

    function formatTemp(c) {
        const v = Number(c) || 0
        return v > 0 ? v.toFixed(0) + "°C" : "--"
    }

    function formatValue(row) {
        if (!row) return "--"
        if (row.kind === "fan_pct") return Number(row.value || 0).toFixed(0) + "%"
        if (row.kind === "fan_rpm") return Math.round(Number(row.value || 0)).toLocaleString() + " RPM"
        return formatTemp(row.value)
    }

    function collectTemps() {
        if (!service || !service.data) return []
        const temps = []
        const cpu = service.data.cpu || {}
        if (cpu.temp > 0) temps.push(cpu.temp)
        if (cpu.tccd1 > 0) temps.push(cpu.tccd1)
        if (cpu.tccd2 > 0) temps.push(cpu.tccd2)
        const gpu = service.data.gpu || {}
        if (gpu.temp > 0) temps.push(gpu.temp)
        const sensors = service.data.sensors || {}
        const nvme = sensors.nvme || []
        for (let i = 0; i < nvme.length; i++) {
            const n = nvme[i]
            const t = Number(n.composite || n.sensor1 || 0)
            if (t > 0) temps.push(t)
        }
        const extra = sensors.extra || []
        for (let i = 0; i < extra.length; i++) {
            const t = Number(extra[i].temp_c || 0)
            if (t > 0) temps.push(t)
        }
        return temps
    }

    readonly property var sensorRows: {
        const tick = service && service.data ? service.data.timestamp : 0
        if (!service || !service.data) return []
        const rows = []
        const cpu = service.data.cpu || {}
        if (cpu.tccd1 > 0) rows.push({ name: "CPU CCD1", value: cpu.tccd1, kind: "temp" })
        if (cpu.tccd2 > 0) rows.push({ name: "CPU CCD2", value: cpu.tccd2, kind: "temp" })
        const sensors = service.data.sensors || {}
        const nvme = sensors.nvme || []
        for (let i = 0; i < nvme.length; i++) {
            const n = nvme[i]
            const t = Number(n.composite || n.sensor1 || 0)
            if (t > 0) rows.push({ name: formatNvmeKey(n.key), value: t, kind: "temp" })
        }
        const extra = sensors.extra || []
        for (let i = 0; i < extra.length; i++) {
            const e = extra[i]
            if (Number(e.temp_c || 0) > 0) {
                rows.push({
                    name: formatSensorLabel(e.chip, e.label),
                    value: e.temp_c,
                    kind: "temp"
                })
            }
        }
        const gpu = service.data.gpu || {}
        if (gpu.fan > 0) rows.push({ name: "GPU Fan", value: gpu.fan, kind: "fan_pct" })
        const fansStr = sensors.fans || ""
        if (fansStr) {
            const parts = fansStr.split(",")
            for (let i = 0; i < parts.length; i++) {
                const part = parts[i].trim()
                if (!part) continue
                const idx = part.indexOf(":")
                if (idx < 0) continue
                const key = part.substring(0, idx)
                const rpm = parseInt(part.substring(idx + 1), 10) || 0
                if (rpm > 0) rows.push({ name: formatFanName(key), value: rpm, kind: "fan_rpm" })
            }
        }
        return rows
    }

    readonly property real cpuTemp: service && service.data && service.data.cpu ? Number(service.data.cpu.temp || 0) : 0
    readonly property bool gpuTempKnown: {
        const g = service && service.data ? service.data.gpu : null
        return !!(g && g.available !== false && g.temp !== null && g.temp !== undefined)
    }
    readonly property real gpuTemp: root.gpuTempKnown ? (Number(root.service.data.gpu.temp) || 0) : 0
    readonly property real maxTemp: {
        const temps = collectTemps()
        if (!temps.length) return 0
        return Math.max.apply(null, temps)
    }
    readonly property int warmCount: {
        const temps = collectTemps()
        let n = 0
        for (let i = 0; i < temps.length; i++) {
            if (temps[i] > 65 && temps[i] <= 85) n++
        }
        return n
    }
    readonly property int criticalCount: {
        const temps = collectTemps()
        let n = 0
        for (let i = 0; i < temps.length; i++) {
            if (temps[i] > 85) n++
        }
        return n
    }

    readonly property int summaryHeight: Math.max(68, Math.min(94, Math.round(height * 0.12)))
    readonly property int middleHeight: Math.max(124, Math.min(260, Math.round(height * 0.34)))
    readonly property int gaugeSize: Math.max(48, Math.min(84, Math.round(Math.min((middleHeight - 40) / 2.2, width * 0.11))))
    readonly property int gaugePanelWidth: Math.max(108, Math.min(gaugeSize + 28, width * 0.22))

    property var _sensorFlickable: null

    function resetScroll() {
        if (_sensorFlickable) _sensorFlickable.contentY = 0
    }

    function pageScroll(direction) {
        if (!_sensorFlickable) return
        const page = Math.max(40, _sensorFlickable.height * 0.85)
        const maxY = Math.max(0, _sensorFlickable.contentHeight - _sensorFlickable.height)
        _sensorFlickable.contentY = Math.max(0, Math.min(maxY, _sensorFlickable.contentY + direction * page))
    }

    function lineScroll(direction) {
        if (!_sensorFlickable) return
        const step = root.sensorRowHeight
        const maxY = Math.max(0, _sensorFlickable.contentHeight - _sensorFlickable.height)
        _sensorFlickable.contentY = Math.max(0, Math.min(maxY, _sensorFlickable.contentY + direction * step))
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: root.sectionSpacing

        property int _cpuTempTick: service ? service.cpuTempHistory.length : 0
        property int _gpuTempTick: service ? service.gpuTempHistory.length : 0
        property var _dataBind: service ? service.data : ({})

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.summaryHeight
            Layout.minimumHeight: 64
            radius: root.cardRadius
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.cardMargin
                spacing: 4

                Text {
                    text: "TEMPERATURE SUMMARY"
                    color: root.accentColor
                    font.pixelSize: 12
                    font.bold: true
                    font.family: "monospace"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    ColumnLayout {
                        spacing: 1
                        Text {
                            text: "CPU: " + root.formatTemp(root.cpuTemp)
                            color: root.tempColor(root.cpuTemp)
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                        Text {
                            text: "GPU: " + (root.gpuTempKnown ? root.formatTemp(root.gpuTemp) : "N/A")
                            color: root.tempColor(root.gpuTemp)
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                        Text {
                            text: "Peak: " + (root.maxTemp > 0 ? root.maxTemp.toFixed(0) + "°C" : "--")
                            color: root.tempColor(root.maxTemp)
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                    }

                    Item { Layout.fillWidth: true }

                    ColumnLayout {
                        spacing: 1
                        Text {
                            text: (root.warmCount > 0 ? root.warmCount + " warm" : "0 warm")
                            color: root.warmCount > 0 ? root.gaugeMidColor : root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                            horizontalAlignment: Text.AlignRight
                        }
                        Text {
                            text: (root.criticalCount > 0 ? root.criticalCount + " critical" : "0 critical")
                            color: root.criticalCount > 0 ? root.gaugeHighColor : root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                            horizontalAlignment: Text.AlignRight
                        }
                        Text {
                            text: root.sensorRows.length + " sensors"
                            color: root.overlayColor
                            font.pixelSize: 10
                            font.family: "monospace"
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.middleHeight
            Layout.minimumHeight: 116
            spacing: root.sectionSpacing

            Rectangle {
                Layout.preferredWidth: root.gaugePanelWidth
                Layout.fillHeight: true
                radius: root.cardRadius
                color: root.surfaceColor
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Column {
                            anchors.centerIn: parent
                            spacing: 5

                            CircularGauge {
                                anchors.horizontalCenter: parent.horizontalCenter
                                size: root.gaugeSize
                                strokeWidth: Math.max(4, root.gaugeSize / 13)
                                value: root.cpuTemp
                                unitLabel: "°C"
                                label: ""
                                subValue: ""
                                valueColor: root.textColor
                                bgColor: Qt.rgba(1, 1, 1, 0.05)
                                lowColor: root.gaugeLowColor
                                midColor: root.gaugeMidColor
                                highColor: root.gaugeHighColor
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "CPU"
                                color: root.subtextColor
                                font.pixelSize: 10
                                font.family: "monospace"
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        color: Qt.rgba(1, 1, 1, 0.06)
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Column {
                            anchors.centerIn: parent
                            spacing: 5

                            CircularGauge {
                                anchors.horizontalCenter: parent.horizontalCenter
                                size: root.gaugeSize
                                strokeWidth: Math.max(4, root.gaugeSize / 13)
                                value: root.gpuTempKnown ? root.gpuTemp : 0
                                valueText: root.gpuTempKnown ? "" : "N/A"
                                unitLabel: "°C"
                                label: ""
                                subValue: ""
                                valueColor: root.textColor
                                bgColor: Qt.rgba(1, 1, 1, 0.05)
                                lowColor: root.gaugeLowColor
                                midColor: root.gaugeMidColor
                                highColor: root.gaugeHighColor
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "GPU"
                                color: root.subtextColor
                                font.pixelSize: 10
                                font.family: "monospace"
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: root.cardRadius
                color: root.surfaceColor
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.cardMargin
                    spacing: 4

                    Text {
                        text: "Sensors & Fans"
                        color: root.accentColor
                        font.pixelSize: 11
                        font.bold: true
                        font.family: "monospace"
                    }

                    Flickable {
                        id: sensorFlickable
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentWidth: width
                        contentHeight: sensorTable.implicitHeight

                        Component.onCompleted: root._sensorFlickable = sensorFlickable

                        Column {
                            id: sensorTable
                            width: parent.width
                            spacing: 0

                            Rectangle {
                                width: parent.width
                                height: root.sensorHeaderHeight
                                radius: 3
                                color: Qt.rgba(0.55, 0.70, 0.96, 0.12)

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    anchors.rightMargin: 4
                                    spacing: root.tblSpacing

                                    Text { width: root.sensorNameColWidth(parent.width - 8); height: parent.height; text: "Sensor"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                    Text { width: root.colValueW; height: parent.height; text: "Value"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                    Text { width: root.colStatusW; height: parent.height; text: "Status"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                }
                            }

                            Text {
                                width: parent.width
                                visible: root.sensorRows.length === 0
                                text: "No additional sensors reported"
                                color: root.overlayColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                topPadding: 4
                            }

                            Repeater {
                                model: root.sensorRows
                                delegate: Item {
                                    width: parent.width
                                    height: root.sensorRowHeight

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 2
                                        color: index % 2 === 0 ? "transparent" : Qt.rgba(1, 1, 1, 0.02)
                                    }

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 4
                                        anchors.rightMargin: 4
                                        spacing: root.tblSpacing

                                        Text {
                                            width: root.sensorNameColWidth(parent.width - 8)
                                            height: parent.height
                                            text: modelData.name
                                            color: root.subtextColor
                                            font.pixelSize: 10
                                            font.family: "monospace"
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            width: root.colValueW
                                            height: parent.height
                                            text: root.formatValue(modelData)
                                            color: modelData.kind === "temp" ? root.tempColor(modelData.value) : root.accentColor
                                            font.pixelSize: 10
                                            font.family: "monospace"
                                            verticalAlignment: Text.AlignVCenter
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        Text {
                                            width: root.colStatusW
                                            height: parent.height
                                            text: modelData.kind === "temp" ? root.tempStatus(modelData.value) : "—"
                                            color: modelData.kind === "temp" ? root.tempColor(modelData.value) : root.overlayColor
                                            font.pixelSize: 10
                                            font.family: "monospace"
                                            verticalAlignment: Text.AlignVCenter
                                            horizontalAlignment: Text.AlignRight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 88
            radius: root.cardRadius
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.cardMargin
                spacing: 4

                Text {
                    text: "Temperature History"
                    color: root.accentColor
                    font.pixelSize: 11
                    font.bold: true
                    font.family: "monospace"
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: root.sectionSpacing

                    Sparkline {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 48
                        history: service.cpuTempHistory
                        fixedRange: true
                        minValue: 20
                        maxValue: 100
                        drawGrid: true
                        gridStep: 10
                        chartTitle: "CPU °C"
                        titleColor: root.textColor
                        lineColor: root.cpuSparkColor
                        fillColor: Qt.rgba(0.53, 0.71, 0.98, 0.22)
                        leftPadding: 30
                        lineWidth: 1.2
                    }

                    Sparkline {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 48
                        history: service.gpuTempHistory
                        fixedRange: true
                        minValue: 20
                        maxValue: 100
                        drawGrid: true
                        gridStep: 10
                        chartTitle: "GPU °C"
                        titleColor: root.textColor
                        lineColor: root.gpuSparkColor
                        fillColor: Qt.rgba(0.65, 0.89, 0.63, 0.22)
                        leftPadding: 30
                        lineWidth: 1.2
                    }
                }
            }
        }
    }
}