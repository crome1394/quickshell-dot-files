import QtQuick

// Tiny G9-ish monitor glyph: classic = one bottom bar; dual = top + bottom.
Item {
    id: root
    property string mode: "classic"
    property color bezelColor: "#2a3038"
    property color screenColor: "#10141c"
    property color barColor: "#7dd3fc"
    property bool selected: false

    implicitWidth: 168
    implicitHeight: 112

    Rectangle {
        id: bezel
        anchors.fill: parent
        anchors.bottomMargin: 10
        radius: 8
        color: root.bezelColor
        border.width: 2
        border.color: root.selected ? root.barColor : Qt.lighter(root.bezelColor, 1.35)

        Rectangle {
            id: screen
            anchors.fill: parent
            anchors.margins: 7
            anchors.bottomMargin: 12
            radius: 3
            color: root.screenColor

            // Wallpaper hint
            Rectangle {
                anchors.fill: parent
                anchors.margins: 0
                radius: 3
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0.18, 0.28, 0.42, 0.55) }
                    GradientStop { position: 1.0; color: Qt.rgba(0.06, 0.08, 0.12, 0.2) }
                }
            }

            Rectangle {
                visible: root.mode === "dual"
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: 5
                color: root.barColor
                opacity: 0.92
            }
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: root.mode === "dual" ? 7 : 8
                color: root.barColor
                opacity: 0.95
            }
        }
    }

    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: bezel.bottom
        anchors.topMargin: -1
        width: 28
        height: 5
        radius: 1
        color: Qt.darker(root.bezelColor, 1.15)
    }
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: bezel.bottom
        anchors.topMargin: 3
        width: 48
        height: 4
        radius: 1
        color: Qt.darker(root.bezelColor, 1.25)
    }
}
