import QtQuick
import QtQuick.Layouts

// =============================================================================
// NetworkListItem.qml — one row in the network popup
// =============================================================================
//
// Used for Wi-Fi networks, saved networks, and VPN profiles.
// Pass `bar` so colors, radius, and fonts match the rest of the shell.
// `checkable` draws a switch on the right (VPN on/off). Otherwise `badge`
// is a trailing glyph (lock, check).
// =============================================================================

Rectangle {
    id: root

    required property var bar
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property string sideText: ""
    property string badge: ""
    property bool active: false
    property bool checkable: false
    property bool checked: false
    property bool dimmed: false

    signal clicked()
    signal badgeClicked()

    implicitHeight: Math.max(44, row.implicitHeight + 12)
    radius: bar.buttonRadius
    color: {
        if (ma.containsMouse)
            return bar.popupButtonHoverBg
        if (active)
            return bar.controlActiveBg
        return Qt.rgba(0.10, 0.10, 0.12, 0.45)
    }
    border.width: 1
    border.color: (active || ma.containsMouse) ? bar.accent : bar.dividerStrong
    opacity: dimmed ? 0.55 : 1

    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutQuad } }
    Behavior on border.color { ColorAnimation { duration: 120; easing.type: Easing.OutQuad } }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: 6
        anchors.bottomMargin: 6
        spacing: 8

        Text {
            visible: root.icon.length > 0
            text: root.icon
            color: root.active ? bar.accent : (bar.iconColor !== undefined ? bar.iconColor : bar.subtext)
            font.pixelSize: 16
            font.family: bar.fontFamily
            Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 1

            Text {
                text: root.title
                color: bar.text
                font.pixelSize: 13
                font.bold: root.active
                font.family: bar.fontFamily
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                visible: root.subtitle.length > 0
                text: root.subtitle
                color: bar.subtext
                font.pixelSize: bar.popupHintSize
                font.family: bar.fontFamily
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        Text {
            visible: root.sideText.length > 0
            text: root.sideText
            color: bar.subtext
            font.pixelSize: 11
            font.family: bar.fontFamily
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            visible: !root.checkable && root.badge.length > 0
            text: root.badge
            color: root.active ? bar.accent : bar.subtext
            font.pixelSize: 14
            font.family: bar.fontFamily
            Layout.alignment: Qt.AlignVCenter
        }

        // Pill switch. The knob slides; the track takes the accent when on.
        Rectangle {
            visible: root.checkable
            Layout.preferredWidth: 36
            Layout.preferredHeight: 20
            Layout.alignment: Qt.AlignVCenter
            radius: 10
            color: root.checked ? bar.accent : Qt.rgba(1, 1, 1, 0.08)
            border.width: 1
            border.color: root.checked ? bar.accent : bar.dividerStrong

            Rectangle {
                width: 14
                height: 14
                radius: 7
                color: root.checked ? bar.bg : bar.subtext
                anchors.verticalCenter: parent.verticalCenter
                x: root.checked ? parent.width - width - 3 : 3
                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.badgeClicked()
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        z: -1
        onClicked: root.clicked()
    }
}
