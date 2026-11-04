import QtQuick
import QtQuick.Layouts

// Settings → Display. One refresh-rate or bit-depth row.
Rectangle {
    id: row

    required property var modelData

    Layout.fillWidth: true
    Layout.preferredHeight: 28
    radius: row.modelData.radius
    color: row.modelData.active
           ? row.modelData.activeBg
           : (rowMa.containsMouse ? row.modelData.hoverBg : row.modelData.idleBg)
    border.width: 1
    border.color: row.modelData.border

    Text {
        visible: !row.modelData.centered
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: row.modelData.label
        color: row.modelData.fg
        font.pixelSize: 11
        font.family: row.modelData.font
        font.bold: row.modelData.active
    }

    Text {
        visible: row.modelData.centered
        anchors.centerIn: parent
        text: row.modelData.label
        color: row.modelData.fg
        font.pixelSize: 11
        font.bold: row.modelData.active
        font.family: row.modelData.font
    }

    MouseArea {
        id: rowMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.modelData.pick(row.modelData.value)
    }
}
