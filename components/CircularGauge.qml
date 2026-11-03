import QtQuick

// Theme import must be top-level (QML rule). Provides fallback for colors.
import "../Config.qml" as ConfigModule

// =============================================================================
// CircularGauge.qml — Reusable circular progress gauge for system metrics
// =============================================================================
//
// Purpose:
//   Dashboard-style circular gauge (270° bottom-open arc) with threshold-based
//   3-stop color ramp. Used by HyprlandInspectorPanel *MonitorView tabs (CPU/GPU/memory/temp).
//
// Theme Properties Consumed (via fallback):
//   - Theme.gaugeLow / Theme.gaugeMid / Theme.gaugeHigh  (color ramp)
//   - (size, stroke, label etc remain component props for flexibility)
//
// Dependencies:
//   - import "../Config.qml" as ConfigModule  (for direct standalone use)
//   - Optional overrides: lowColor, midColor, highColor props
//
// Notes:
//   - Follows unidirectional read from theme (no writes).
//   - Canvas repaints on value/color changes.
//   - Adapted from standalone sysmon backup with centralized theming + full
//     header/section/inline comment standard applied.
//   - Kept API identical for easy reuse (value 0-100, size, subValue, etc).
// =============================================================================

Item {
    id: root

    // === Public API (kept stable for reuse) ===
    property real value: 0
    property string label: ""
    property string subValue: ""
    // Empty keeps the numeric center. Set this when the sample is missing.
    property string valueText: ""
    property string unitLabel: "%"
    property int size: 92
    property int strokeWidth: 9

    // === Theme fallback (VolumeBar/MiniVolumeBar pattern) ===
    // Placed early so the readonly t can be used in default expressions below.
    readonly property QtObject t: ConfigModule.Config

    // Color ramp (override to customize per gauge, e.g. GPU uses same ramp).
    // Defaults pulled from Theme so a single edit in Theme.qml retunes all gauges.
    property color bgColor: Qt.rgba(1, 1, 1, 0.07)
    property color lowColor:  (t && t.gaugeLow)  ? t.gaugeLow  : "#2ee59a"
    property color midColor:  (t && t.gaugeMid)  ? t.gaugeMid  : "#f0d060"
    property color highColor: (t && t.gaugeHigh) ? t.gaugeHigh : "#FF3D8A"

    // === Derived state (clamped + color selection) ===
    readonly property real clamped: Math.max(0, Math.min(100, value))
    readonly property color gaugeColor: clamped > 85 ? highColor : (clamped > 65 ? midColor : lowColor)
    property color valueColor: gaugeColor

    implicitWidth: size
    implicitHeight: size

    // === Section: Canvas rendering (270° arc gauge) ===
    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()

            const w = width
            const h = height
            const cx = w / 2
            const cy = h / 2
            const radius = (Math.min(w, h) / 2) - (root.strokeWidth / 2) - 1

            const startAngle = -Math.PI * 0.75
            const endAngle = Math.PI * 0.75
            const fullSweep = endAngle - startAngle
            const progress = root.clamped / 100
            const currentAngle = startAngle + fullSweep * progress

            // Background track (subtle)
            ctx.beginPath()
            ctx.arc(cx, cy, radius, startAngle, endAngle, false)
            ctx.lineWidth = root.strokeWidth
            ctx.strokeStyle = root.bgColor
            ctx.lineCap = "round"
            ctx.stroke()

            // Progress arc (only if meaningful)
            if (progress > 0.005) {
                ctx.beginPath()
                ctx.arc(cx, cy, radius, startAngle, currentAngle, false)
                ctx.lineWidth = root.strokeWidth
                ctx.strokeStyle = root.gaugeColor
                ctx.lineCap = "round"
                ctx.stroke()
            }

            // Subtle inner highlight ring for depth
            ctx.beginPath()
            ctx.arc(cx, cy, radius - root.strokeWidth * 0.55, startAngle, endAngle, false)
            ctx.lineWidth = 1.5
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.05)
            ctx.stroke()
        }
    }

    // === Section: Center text block (percentage + optional label + subValue) ===
    Column {
        anchors.centerIn: parent
        spacing: -1

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.valueText.length ? root.valueText : (root.clamped.toFixed(0) + root.unitLabel)
            font.pixelSize: root.size * 0.30
            font.bold: true
            color: root.valueColor
            font.family: "JetBrains Mono Nerd Font, monospace"  // consistent with bar
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            font.pixelSize: root.size * 0.14
            color: "#f0f4fc"
            opacity: 0.9
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.subValue !== ""
            text: root.subValue
            font.pixelSize: root.size * 0.12
            color: "#a8b4c8"
        }
    }

    // === Reactive repaints (explicit, no hidden two-way) ===
    onValueChanged: canvas.requestPaint()
    onGaugeColorChanged: canvas.requestPaint()
    Component.onCompleted: canvas.requestPaint()
}
