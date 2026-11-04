import QtQuick
import QtQuick.Layouts

// Settings → Region & Clock. One format preset row.
Rectangle {
    id: row

    required property var modelData

    Layout.fillWidth: true
    Layout.preferredHeight: 36
    radius: row.modelData.radius
    color: rowMa.containsMouse ? row.modelData.hoverBg : row.modelData.idleBg
    border.width: row.modelData.borderWidth
    border.color: row.modelData.active ? row.modelData.activeBorder : row.modelData.idleBorder

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        spacing: 0
        Text {
            text: row.modelData.label
            color: row.modelData.titleColor
            font.pixelSize: 12
            font.bold: row.modelData.active
            font.family: row.modelData.font
        }
        Text {
            text: row.modelData.tip
            color: row.modelData.tipColor
            font.pixelSize: 10
            font.family: row.modelData.font
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }

    MouseArea {
        id: rowMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.modelData.pick(row.modelData.format)
    }
}
