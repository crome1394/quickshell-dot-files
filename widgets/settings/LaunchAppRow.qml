import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// One installed app in the App Launcher picker. Colors and the add action sit on the column.
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

    Layout.fillWidth: true
    Layout.preferredHeight: 34
    radius: row.colProp("chipR", 8)
    color: addAppMa.containsMouse ? row.colProp("hoverBg", "transparent") : Qt.rgba(0.10, 0.10, 0.12, 0.45)
    border.width: 1
    border.color: row.colProp("dividerStrong", "#333")

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        spacing: 8
        Image {
            visible: (row.modelData.icon || "").length > 0
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            source: row.modelData.icon || ""
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
        Text {
            visible: !(row.modelData.icon || "").length
            text: "󰣆"
            font.pixelSize: 14
            font.family: row.colProp("fontFamily", "")
            color: row.colProp("subtext", "#aaa")
        }
        Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: row.modelData.name || row.modelData.id
            color: row.colProp("textColor", "#fff")
            font.pixelSize: 12
            font.family: row.colProp("fontFamily", "")
        }
        Text {
            text: "+"
            color: row.colProp("onGreen", "#2ee59a")
            font.pixelSize: 16
            font.bold: true
        }
    }
    MouseArea {
        id: addAppMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            const fn = row.colProp("addApp", null)
            if (typeof fn === "function")
                fn(row.modelData)
        }
        ToolTip.visible: containsMouse
        ToolTip.delay: row.colProp("tooltipDelay", 0)
        ToolTip.text: "Add " + (row.modelData.name || "")
    }
}
