import QtQuick
import QtQuick.Layouts

// Shared face of the left and right edge bars.
// The PanelWindow and the exclusive-zone expression stay in shell.qml.
// leading is the left edge. Glass-flush zeros the outer corners.
Rectangle {
    id: edgeBg
    required property var hostBar
    required property var controlBar
    required property bool leading
    required property string barAlign
    required property bool spanFull

    property alias zone: edgeZone
    property alias stack: edgeStack

    readonly property bool spanHeight: !!edgeBg.spanFull
    readonly property int hugMeasured: Math.max(edgeBg.hostBar.sp(80), Math.min(parent.height,
                      edgeStack.height + 2 * edgeBg.hostBar.barContentHMargin))
    property int hugH: 80
    onHugMeasuredChanged: {
        if (!edgeBg.spanHeight && Math.abs(edgeBg.hugMeasured - edgeBg.hugH) >= 16)
            edgeBg.hugH = edgeBg.hugMeasured
    }
    onSpanHeightChanged: edgeBg.hugH = edgeBg.hugMeasured
    Component.onCompleted: edgeBg.hugH = edgeBg.hugMeasured
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.leftMargin: edgeBg.leading ? 0 : edgeBg.hostBar.barContentVMargin
    anchors.rightMargin: edgeBg.leading ? edgeBg.hostBar.barContentVMargin : 0
    y: edgeBg.spanHeight ? 0 : edgeBg.hostBar.alignY(edgeBg.barAlign, parent.height, edgeBg.hugH, edgeBg.hostBar.barContentHMargin)
    height: edgeBg.spanHeight ? parent.height : edgeBg.hugH
    radius: edgeBg.hostBar.barRadius
    topLeftRadius: (edgeBg.leading && edgeBg.hostBar.barGlassFlush) ? 0 : edgeBg.hostBar.barRadius
    bottomLeftRadius: (edgeBg.leading && edgeBg.hostBar.barGlassFlush) ? 0 : edgeBg.hostBar.barRadius
    topRightRadius: (!edgeBg.leading && edgeBg.hostBar.barGlassFlush) ? 0 : edgeBg.hostBar.barRadius
    bottomRightRadius: (!edgeBg.leading && edgeBg.hostBar.barGlassFlush) ? 0 : edgeBg.hostBar.barRadius
    color: edgeBg.hostBar.glassBg
    border.width: Math.max(1, edgeBg.hostBar.controlBorderWidth)
    border.color: edgeBg.hostBar.glassBorder
    clip: true

    Rectangle {
        id: edgeHighlight
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: edgeBg.hostBar.popupHeaderHighlightHeight
        x: edgeBg.leading ? 0 : (parent.width - edgeHighlight.width)
        color: edgeBg.hostBar.glassHighlight
    }

    MouseArea {
        anchors.fill: parent
        z: 0
        acceptedButtons: Qt.RightButton
        hoverEnabled: false
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton)
                edgeBg.controlBar.toggle()
        }
    }

    // Unrotated box is swapped so a 90° clockwise row lands inside it.
    // Left alignment is the top of the screen, where that text starts.
    Item {
        id: edgeStack
        z: 1
        width: Math.max(1, edgeZone.implicitHeight)
        height: Math.max(1, edgeZone.implicitWidth)
        x: Math.max(0, (parent.width - edgeStack.width) / 2)
        y: edgeBg.spanHeight
           ? edgeBg.hostBar.alignY(edgeBg.barAlign, parent.height, edgeStack.height, edgeBg.hostBar.barContentHMargin)
           : Math.max(0, (parent.height - edgeStack.height) / 2)

        RowLayout {
            id: edgeZone
            rotation: 90
            transformOrigin: Item.Center
            spacing: edgeBg.hostBar.widgetSpacing
            x: (edgeStack.width - edgeZone.implicitWidth) / 2
            y: (edgeStack.height - edgeZone.implicitHeight) / 2
            onImplicitWidthChanged: edgeZone.width = edgeZone.implicitWidth
            onImplicitHeightChanged: edgeZone.height = edgeZone.implicitHeight
            Component.onCompleted: {
                edgeZone.width = edgeZone.implicitWidth
                edgeZone.height = edgeZone.implicitHeight
            }
        }
    }
}
