import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Live GPU monitoring tab content (SysMonService + gauge + sparkline).
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
    // When false: hide circular gauge + history sparkline; keep summary + process list
    property bool showGraphs: true

    readonly property int cardRadius: 6
    readonly property int cardMargin: 10
    readonly property int sectionSpacing: 8

    readonly property int summaryHeight: Math.max(68, Math.min(94, Math.round(height * 0.12)))
    readonly property int middleHeight: showGraphs
        ? Math.max(124, Math.min(260, Math.round(height * 0.34)))
        : Math.max(160, Math.round(height * 0.72))

    readonly property var gpuProcessRows: {
        const tick = service && service.data ? service.data.timestamp : 0
        if (!service || !service.data || !service.data.top_gpu) return []
        return service.data.top_gpu
    }

    function gpuMetricKnown(field) {
        const g = service && service.data ? service.data.gpu : null
        if (!g || g.available === false) return false
        const v = g[field]
        return v !== null && v !== undefined
    }

    function resetScroll() {}

    function pageScroll(direction) {}

    function lineScroll(direction) {}

    ColumnLayout {
        anchors.fill: parent
        spacing: root.sectionSpacing

        property int _gpuTick: service ? service.gpuHistory.length : 0
        property var _dataBind: service ? service.data : ({})

        // GPU Summary
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
                    text: "GPU SUMMARY"
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
                            text: "Model: " + (service.data.gpu_info && service.data.gpu_info.name ? service.data.gpu_info.name : "--")
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: "VRAM: " + (service.data.gpu && service.data.gpu.vram_total
                                ? ((service.data.gpu.vram_total || 0) / 1024).toFixed(0) + " GB"
                                : "--")
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                        Text {
                            text: "Driver: " + (service.data.gpu_info && service.data.gpu_info.driver ? service.data.gpu_info.driver : "--")
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: root.gpuMetricKnown("util")
                            ? ((service.data.gpu.util || 0).toFixed(0) + "%")
                            : "N/A"
                        color: root.textColor
                        font.pixelSize: 25
                        font.bold: true
                        font.family: "monospace"
                    }
                }
            }
        }

        // Gauge + Top GPU Processes
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.middleHeight
            Layout.minimumHeight: 116
            spacing: root.sectionSpacing

            Rectangle {
                visible: root.showGraphs
                Layout.preferredWidth: root.showGraphs
                    ? Math.max(150, Math.min(200, root.width * 0.22)) : 0
                Layout.fillHeight: true
                radius: root.cardRadius
                color: root.surfaceColor
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.cardMargin
                    spacing: 2

                    Text {
                        text: "GPU USAGE"
                        color: root.accentColor
                        font.pixelSize: 11
                        font.bold: true
                        font.family: "monospace"
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        property int gaugeSz: Math.max(56, Math.min(140, Math.min(width, height) * 0.88))

                        CircularGauge {
                            anchors.centerIn: parent
                            size: parent.gaugeSz
                            strokeWidth: Math.max(6, parent.gaugeSz / 10)
                            value: root.gpuMetricKnown("util") ? (service.data.gpu.util || 0) : 0
                            valueText: root.gpuMetricKnown("util") ? "" : "N/A"
                            subValue: root.gpuMetricKnown("temp")
                                ? ((service.data.gpu.temp || 0).toFixed(0) + "°C")
                                : "N/A"
                            lowColor: root.gaugeLowColor
                            midColor: root.gaugeMidColor
                            highColor: root.gaugeHighColor
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

                TopProcessPanel {
                    anchors.fill: parent
                    anchors.margins: root.cardMargin
                    title: "Top GPU Processes"
                    mode: "gpu"
                    rows: root.gpuProcessRows
                    emptyText: "No GPU compute processes reported"
                    textColor: root.textColor
                    subtextColor: root.subtextColor
                    accentColor: root.accentColor
                    surfaceColor: root.surfaceColor
                    overlayColor: root.overlayColor
                }
            }
        }

        // GPU Usage History — fills remaining vertical space
        Rectangle {
            visible: root.showGraphs
            Layout.fillWidth: true
            Layout.fillHeight: root.showGraphs
            Layout.minimumHeight: root.showGraphs ? 88 : 0
            Layout.preferredHeight: root.showGraphs ? -1 : 0
            radius: root.cardRadius
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.cardMargin
                spacing: 4

                Text {
                    text: "GPU Usage History"
                    color: root.accentColor
                    font.pixelSize: 11
                    font.bold: true
                    font.family: "monospace"
                }

                Sparkline {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 48
                    history: service.gpuHistory
                    fixedRange: true
                    minValue: 0
                    maxValue: 100
                    drawGrid: true
                    gridStep: 10
                    chartTitle: ""
                    titleColor: root.textColor
                    lineColor: root.gaugeLowColor
                    fillColor: Qt.rgba(0.65, 0.89, 0.63, 0.22)
                    leftPadding: 30
                    lineWidth: 1.2
                }
            }
        }
    }
}