import QtQuick
import Quickshell

// Hover tip outside the pill. A Qt Popup parented to Overlay.overlay looped
// on `parent` and never opened. PopupWindow is a real layer, so the bar mask
// does not clip it.

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
            Qt.callLater(root.placeTip)
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
                Qt.callLater(root.placeTip)
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

    function placeTip() {
        if (!pop.visible || !bar || !root.anchorItem)
            return
        if (typeof bar.placePopup !== "function")
            return
        const w = Math.max(pop.implicitWidth, tipLabel.implicitWidth + root.padding * 2)
        const h = Math.max(pop.implicitHeight, tipLabel.implicitHeight + root.padding * 2)
        const side = root.resolvedSide()
        const anc = root.anchorItem
        if (side === "above" || side === "below") {
            bar.placePopup(pop, anc, w, h, 6, anc.width / 2)
            return
        }
        bar.placePopup(pop, anc, w, h, 6, anc.width / 2)
        let originX = 0
        try {
            const chrome = bar.chromeForItem(anc)
            const pos = anc.mapToItem(chrome, 0, 0)
            originX = (chrome ? chrome.x : 0) + pos.x
        } catch (e) {
            originX = pop.anchor.rect.x
        }
        if (side === "left")
            pop.anchor.rect.x = Math.max(8, originX - w - 6)
        else
            pop.anchor.rect.x = originX + anc.width + 6
    }

    PopupWindow {
        id: pop
        anchor.window: bar
        anchor.rect.width: 1
        anchor.rect.height: 1
        implicitWidth: tipLabel.implicitWidth + root.padding * 2
        implicitHeight: tipLabel.implicitHeight + root.padding * 2
        visible: root.visible && root._show && String(root.text || "").length > 0
        color: "transparent"
        grabFocus: false

        onVisibleChanged: {
            if (visible)
                Qt.callLater(root.placeTip)
        }
        onImplicitWidthChanged: if (visible) root.placeTip()
        onImplicitHeightChanged: if (visible) root.placeTip()

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: (bar && bar.glassPopupBg !== undefined)
                   ? bar.glassPopupBg
                   : Qt.rgba(0.06, 0.08, 0.12, 0.96)
            border.width: 1
            border.color: (bar && bar.glassPopupBorder !== undefined)
                           ? bar.glassPopupBorder
                           : Qt.rgba(1, 1, 1, 0.12)
            Text {
                id: tipLabel
                anchors.fill: parent
                anchors.margins: root.padding
                text: root.text
                font.pixelSize: (bar && bar.fontTiny !== undefined) ? bar.fontTiny : 11
                font.family: (bar && bar.fontFamily) ? bar.fontFamily : font.family
                color: (bar && bar.text !== undefined) ? bar.text : "#f0f4fc"
                wrapMode: Text.WordWrap
                width: Math.min(implicitWidth, 280)
            }
        }
    }
}
