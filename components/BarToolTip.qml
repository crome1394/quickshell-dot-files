import QtQuick
import QtQuick.Controls

// =============================================================================
// BarToolTip.qml — hover tip that sits outside the anchor and never covers it
// =============================================================================
// Default: below a top bar, above a bottom bar (dual uses the pill's edge).
// Optional preferSide / widgetId override: "above" | "below" | "left" | "right".
// Implemented as a click-through Popup so clipped pills still show the tip.
// =============================================================================

Item {
    id: root

    property var bar: null
    property Item anchorItem: parent
    property string preferSide: ""
    property string widgetId: ""
    property string text: ""
    property int delay: (bar && bar.tooltipDelay !== undefined) ? bar.tooltipDelay : 400
    property int timeout: 4500
    property int padding: 8

    // Zero-size host so we never steal clicks on the icon
    width: 0
    height: 0
    z: 80

    property bool _show: false

    Timer {
        id: showTimer
        interval: Math.max(0, root.delay)
        repeat: false
        onTriggered: {
            root._show = true
            hideTimer.restart()
        }
    }
    Timer {
        id: hideTimer
        interval: Math.max(200, root.timeout)
        repeat: false
        onTriggered: root._show = false
    }

    onVisibleChanged: root._syncTimers()
    onTextChanged: root._syncTimers()
    onDelayChanged: {
        if (visible && text.length)
            root._syncTimers()
    }

    function _syncTimers() {
        if (visible && root.text && String(root.text).length) {
            if (root.delay <= 0) {
                root._show = true
                hideTimer.restart()
            } else {
                root._show = false
                showTimer.restart()
            }
        } else {
            showTimer.stop()
            hideTimer.stop()
            root._show = false
        }
    }

    function resolvedSide() {
        if (root.widgetId && bar && typeof bar.tooltipAlignFor === "function") {
            const a = String(bar.tooltipAlignFor(root.widgetId) || "")
            if (a === "above" || a === "below" || a === "left" || a === "right")
                return a
        }
        if (root.preferSide === "above" || root.preferSide === "below"
                || root.preferSide === "left" || root.preferSide === "right")
            return root.preferSide
        var edge = "top"
        if (bar && typeof bar.edgeForItem === "function")
            edge = bar.edgeForItem(root.anchorItem)
        else if (bar && bar.barPosition === "bottom")
            edge = "bottom"
        if (bar && bar.layoutEpoch !== undefined)
            void bar.layoutEpoch
        return (edge === "bottom") ? "above" : "below"
    }

    Popup {
        id: pop
        padding: root.padding
        modal: false
        focus: false
        dim: false
        enabled: false
        closePolicy: Popup.NoAutoClose
        visible: root.visible && root._show && String(root.text || "").length > 0
        parent: (typeof Overlay !== "undefined" && Overlay.overlay) ? Overlay.overlay : root

        function place() {
            const anc = root.anchorItem
            if (!anc || !visible)
                return
            let pos = { x: 0, y: 0 }
            try {
                pos = anc.mapToItem(pop.parent, 0, 0)
            } catch (e) {
                pos = { x: 0, y: 0 }
            }
            const gap = 6
            const w = Math.max(pop.width, pop.implicitWidth)
            const h = Math.max(pop.height, pop.implicitHeight)
            const side = root.resolvedSide()
            if (side === "left") {
                x = pos.x - w - gap
                y = pos.y + (anc.height - h) / 2
            } else if (side === "right") {
                x = pos.x + anc.width + gap
                y = pos.y + (anc.height - h) / 2
            } else if (side === "above") {
                x = pos.x + (anc.width - w) / 2
                y = pos.y - h - gap
            } else {
                x = pos.x + (anc.width - w) / 2
                y = pos.y + anc.height + gap
            }
        }

        onWidthChanged: place()
        onHeightChanged: place()
        onVisibleChanged: {
            if (visible)
                Qt.callLater(place)
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
            text: root.text
            font.pixelSize: (bar && bar.fontTiny !== undefined) ? bar.fontTiny : 11
            font.family: (bar && bar.fontFamily) ? bar.fontFamily : font.family
            color: (bar && bar.text !== undefined) ? bar.text : "#f0f4fc"
            wrapMode: Text.WordWrap
            width: Math.min(implicitWidth, 280)
        }
    }
}
