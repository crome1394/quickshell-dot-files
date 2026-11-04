import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// One pinned Quick Launch entry. Colors and the move/remove actions sit on the column.
Rectangle {
    id: row

    required property var modelData

    function colProp(name, fallback) {
        const p = row.parent
        if (!p)
            return fallback
        const v = p[name]
        return v === undefined ? fallback : v
    }

    readonly property int appIndex: row.modelData.index

    Layout.fillWidth: true
    Layout.preferredHeight: 40
    radius: row.colProp("chipR", 8)
    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
    border.width: row.colProp("controlBorderWidth", 1)
    border.color: row.colProp("dividerStrong", "#333")

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 6
        spacing: 6

        Rectangle {
            Layout.preferredWidth: 28
            Layout.preferredHeight: 26
            radius: 4
            color: rmMa.containsMouse ? Qt.rgba(0.97, 0.44, 0.44, 0.18) : "transparent"
            border.width: 1
            border.color: row.colProp("offRed", "#FF3D8A")
            Text {
                anchors.centerIn: parent
                text: "✕"
                color: row.colProp("offRed", "#FF3D8A")
                font.pixelSize: 13
                font.bold: true
            }
            MouseArea {
                id: rmMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const fn = row.colProp("removeApp", null)
                    if (typeof fn === "function")
                        fn(row.appIndex)
                }
                ToolTip.visible: containsMouse
                ToolTip.delay: row.colProp("tooltipDelay", 0)
                ToolTip.text: "Remove"
            }
        }

        Image {
            visible: (row.modelData.icon || "").length > 0
            Layout.preferredWidth: 22
            Layout.preferredHeight: 22
            source: row.modelData.icon || ""
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }
        Text {
            visible: !(row.modelData.icon || "").length
            Layout.preferredWidth: 22
            horizontalAlignment: Text.AlignHCenter
            text: row.modelData.glyph || "󰣆"
            font.pixelSize: 16
            font.family: row.colProp("fontFamily", "")
            color: row.colProp("subtext", "#aaa")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: row.modelData.tooltip || "(unnamed)"
                color: row.colProp("textColor", "#fff")
                font.pixelSize: 12
                font.family: row.colProp("fontFamily", "")
            }
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: row.modelData.commandText
                color: row.colProp("subtext", "#aaa")
                font.pixelSize: 10
                font.family: row.colProp("fontMono", "")
            }
        }

        Rectangle {
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            radius: 4
            color: upLMa.containsMouse ? row.colProp("glassHover", "transparent") : row.colProp("buttonFill", "transparent")
            border.width: 1
            border.color: row.colProp("pillBorder", "#333")
            Text {
                anchors.centerIn: parent
                text: "↑"
                color: row.colProp("subtext", "#aaa")
                font.pixelSize: 12
            }
            MouseArea {
                id: upLMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const fn = row.colProp("moveApp", null)
                    if (typeof fn === "function")
                        fn(row.appIndex, -1)
                }
            }
        }
        Rectangle {
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            radius: 4
            color: dnLMa.containsMouse ? row.colProp("glassHover", "transparent") : row.colProp("buttonFill", "transparent")
            border.width: 1
            border.color: row.colProp("pillBorder", "#333")
            Text {
                anchors.centerIn: parent
                text: "↓"
                color: row.colProp("subtext", "#aaa")
                font.pixelSize: 12
            }
            MouseArea {
                id: dnLMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    const fn = row.colProp("moveApp", null)
                    if (typeof fn === "function")
                        fn(row.appIndex, 1)
                }
            }
        }
    }
}
