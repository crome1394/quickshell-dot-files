import QtQuick
import QtQuick.Controls

// =============================================================================
// BarToolTip.qml — tooltip that sits above/below the anchor and never covers it
// =============================================================================
// For bar pills: when the bar is on top, tip opens below the pill; when the bar
// is on the bottom, tip opens above. For in-panel controls, pass preferAbove.
// =============================================================================

ToolTip {
    id: tip

    // Optional bar object (for barPosition + tooltipDelay)
    property var bar: null
    // Item the tip is attached to (defaults to parent)
    property Item anchorItem: parent
    // Force side: "" = auto from bar position, "above", "below"
    property string preferSide: ""

    delay: (bar && bar.tooltipDelay !== undefined) ? bar.tooltipDelay : 400
    timeout: 4500
    padding: 8
    font.pixelSize: (bar && bar.fontTiny !== undefined) ? bar.fontTiny : 11
    font.family: (bar && bar.fontFamily) ? bar.fontFamily : font.family

    // Keep the tip out of the clickable anchor
    y: {
        if (!anchorItem)
            return 0
        var h = implicitHeight > 0 ? implicitHeight : height
        var gap = 6
        var side = tip.preferSide
        if (!side || !side.length) {
            var edge = "top"
            if (bar && typeof bar.edgeForItem === "function")
                edge = bar.edgeForItem(anchorItem)
            else if (bar && bar.barPosition === "bottom")
                edge = "bottom"
            if (bar && bar.layoutEpoch !== undefined)
                void bar.layoutEpoch
            side = (edge === "bottom") ? "above" : "below"
        }
        if (side === "above")
            return -h - gap
        return anchorItem.height + gap
    }
    x: {
        if (!anchorItem)
            return 0
        var w = implicitWidth > 0 ? implicitWidth : width
        return Math.round((anchorItem.width - w) / 2)
    }

    background: Rectangle {
        radius: 6
        color: (bar && bar.glassPopupBg !== undefined)
               ? bar.glassPopupBg
               : Qt.rgba(0.06, 0.08, 0.12, 0.96)
        border.width: 1
        border.color: (bar && bar.glassPopupBorder !== undefined)
                      ? bar.glassPopupBorder
                      : Qt.rgba(1, 1, 1, 0.12)
    }
    contentItem: Text {
        text: tip.text
        font: tip.font
        color: (bar && bar.text !== undefined) ? bar.text : "#f0f4fc"
        wrapMode: Text.WordWrap
        width: Math.min(implicitWidth, 280)
    }
}
