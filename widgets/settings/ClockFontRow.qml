import QtQuick
import QtQuick.Controls

// Settings → Region & Clock. One face in the clock-font combo.
ItemDelegate {
    id: row

    required property int index
    required property string modelData

    readonly property var fontView: ListView.view

    width: row.fontView ? row.fontView.rowWidth : implicitWidth
    height: 30
    highlighted: ListView.isCurrentItem

    contentItem: Text {
        text: row.modelData
        color: row.fontView ? row.fontView.rowText : "#ffffff"
        font.family: row.index === 0
                     ? (row.fontView ? row.fontView.defaultFont : row.modelData)
                     : row.modelData
        font.pixelSize: 12
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        color: row.highlighted
               ? (row.fontView ? row.fontView.rowActive : "transparent")
               : "transparent"
        radius: 4
    }
}
