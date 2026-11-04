import QtQuick

// Settings → Display. One refresh-rate group of resolution chips.
Column {
    id: group

    required property var modelData

    width: parent.width
    spacing: 6

    Text {
        width: group.width
        text: group.modelData.title
        color: group.modelData.titleColor
        font.pixelSize: 11
        font.bold: true
        font.family: group.modelData.titleFont
    }

    Flow {
        width: group.width
        spacing: 6
        Repeater {
            model: group.modelData.chips
            delegate: DisplayModeChip {}
        }
    }
}
