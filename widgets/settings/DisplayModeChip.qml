import QtQuick

// Settings → Display. One resolution chip.
Rectangle {
    id: chip

    required property var modelData

    width: chipLabel.implicitWidth + 14
    height: 26
    radius: chip.modelData.radius
    color: chip.modelData.selected
           ? chip.modelData.activeBg
           : (chipMa.containsMouse ? chip.modelData.hoverBg : chip.modelData.idleBg)
    border.width: 1
    border.color: chip.modelData.border

    Text {
        id: chipLabel
        anchors.centerIn: parent
        text: chip.modelData.label
        color: chip.modelData.fg
        font.pixelSize: 11
        font.family: chip.modelData.font
    }

    MouseArea {
        id: chipMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.modelData.pick(chip.modelData.res, chip.modelData.rate)
    }
}
