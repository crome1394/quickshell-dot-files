import QtQuick

// Theme import at top level (required by QML). Reserved for future defaults.
import "../Config.qml" as ConfigModule

// =============================================================================
// Sparkline.qml — Compact filled history graph for dashboards
// =============================================================================
//
// Purpose:
//   Small canvas-based sparkline showing recent history trend (e.g. CPU % over
//   last N samples). Filled area under the line for visual weight.
//
// Theme Properties Consumed (via fallback):
//   - None directly required (line/fill passed as props), but can be extended
//     with theme defaults for lineColor if desired in future.
//
// Dependencies:
//   - Used by *MonitorView.qml in HyprlandInspectorPanel (bound to SysMonService.*History)
//   - Can be used standalone.
//
// Notes:
//   - History: array of numbers (most recent at end). Caller manages length.
//   - maxPoints caps display (older data shifted out by service).
//   - Adapted from backup with added header comments + theme import stub for
//     future centralization. No behavior changes.
//   - Repaints only on history change (efficient).
// =============================================================================

Item {
    id: root

    // === Public API ===
    property var history: []
    property int maxPoints: 42
    property color lineColor: "#00F0E0"
    property color fillColor: Qt.rgba(0.53, 0.71, 0.98, 0.18)
    property real lineWidth: 1.5

    // Advanced options for system-monitor style charts (HyprlandInspectorPanel metric tabs)
    property bool fixedRange: false
    property real minValue: 0
    property real maxValue: 100
    property bool drawGrid: false
    property int gridStep: 10
    property string chartTitle: ""
    property color titleColor: "white"
    property color gridColor: Qt.rgba(1, 1, 1, 0.15)
    property color labelColor: "#a8b4c8"
    property int leftPadding: 28   // space for Y labels

    // Theme fallback (for future centralization of sparkline colors)
    readonly property QtObject t: ConfigModule.Config

    implicitWidth: 120
    implicitHeight: 36

    // === Section: Canvas (line + under-fill) ===
    Canvas {
        id: canvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()

            const w = width
            const h = height
            const data = root.history

            const plotLeft = root.leftPadding
            // Reserve bottom room so grid % labels (drawn y+3) don't get cut off at canvas bottom edge.
            // This fixes "history charts cut off" for bottom 0/10/20% labels etc.
            const bottomReserve = 8
            const plotW = Math.max(10, w - plotLeft - 2)  // use nearly full width for chart plot area
            const plotH = Math.max(10, h - (root.chartTitle ? 16 : 0) - 2 - bottomReserve)
            const plotTop = root.chartTitle ? 14 : 2

            if (!data || data.length < 2) {
                // faint placeholder
                ctx.beginPath()
                ctx.moveTo(plotLeft, plotTop + plotH * 0.65)
                ctx.lineTo(plotLeft + plotW, plotTop + plotH * 0.65)
                ctx.lineWidth = 1
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.08)
                ctx.stroke()
                return
            }

            const n = Math.min(data.length, root.maxPoints)
            const stepX = plotW / (n - 1)

            // Range
            let minV = 0, maxV = 100
            if (!root.fixedRange) {
                minV = 100; maxV = 0
                for (let i = 0; i < n; i++) {
                    const v = Math.max(0, Math.min(100, data[i]))
                    if (v < minV) minV = v
                    if (v > maxV) maxV = v
                }
            } else {
                minV = root.minValue
                maxV = root.maxValue
            }
            const range = Math.max(1, maxV - minV)

            // Draw title
            if (root.chartTitle) {
                ctx.fillStyle = root.titleColor
                ctx.font = "10px sans-serif"
                ctx.textAlign = "left"
                ctx.fillText(root.chartTitle, plotLeft, 11)
            }

            // Draw grid and Y labels if requested (fixed 0-100 style)
            if (root.drawGrid) {
                ctx.strokeStyle = root.gridColor
                ctx.lineWidth = 1
                ctx.fillStyle = root.labelColor
                ctx.font = "8px sans-serif"
                ctx.textAlign = "right"

                const steps = Math.floor((maxV - minV) / root.gridStep)
                for (let s = 0; s <= steps; s++) {
                    const val = minV + s * root.gridStep
                    const y = plotTop + plotH - ((val - minV) / range) * plotH
                    // grid line
                    ctx.beginPath()
                    ctx.moveTo(plotLeft, y)
                    ctx.lineTo(plotLeft + plotW, y)
                    ctx.stroke()
                    // label - offset tuned + reserve ensures fully inside canvas h (no bottom cutoff)
                    const ly = y + 2.5
                    if (ly < h - 1) {
                        ctx.fillText(val.toFixed(0) + "%", plotLeft - 2, ly)
                    }
                }
            }

            // Main filled area path (plot area)
            ctx.beginPath()
            for (let i = 0; i < n; i++) {
                const v = Math.max(minV, Math.min(maxV, data[i]))
                const x = plotLeft + i * stepX
                const y = plotTop + plotH - ((v - minV) / range) * plotH
                if (i === 0) ctx.moveTo(x, y)
                else ctx.lineTo(x, y)
            }

            // close to bottom for fill
            ctx.lineTo(plotLeft + plotW, plotTop + plotH)
            ctx.lineTo(plotLeft, plotTop + plotH)
            ctx.closePath()
            ctx.fillStyle = root.fillColor
            ctx.fill()

            // line on top
            ctx.beginPath()
            for (let i = 0; i < n; i++) {
                const v = Math.max(minV, Math.min(maxV, data[i]))
                const x = plotLeft + i * stepX
                const y = plotTop + plotH - ((v - minV) / range) * plotH
                if (i === 0) ctx.moveTo(x, y)
                else ctx.lineTo(x, y)
            }
            ctx.lineWidth = root.lineWidth
            ctx.strokeStyle = root.lineColor
            ctx.lineJoin = "round"
            ctx.lineCap = "round"
            ctx.stroke()
        }
    }

    // === Reactivity ===
    onHistoryChanged: canvas.requestPaint()
    Component.onCompleted: canvas.requestPaint()
}
