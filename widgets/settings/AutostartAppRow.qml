import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// One installed app in the Autostart picker. Colors and the add action sit on the column.
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

    width: parent ? parent.width : 0
    height: 34
    radius: row.colProp("chipR", 8)
    color: addAsMa.containsMouse ? row.colProp("hoverBg", "transparent") : Qt.rgba(0.10, 0.10, 0.12, 0.45)
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
            source: row.modelData.icon
                   ? (String(row.modelData.icon).indexOf("file:") === 0
                      ? row.modelData.icon
                      : ("file://" + row.modelData.icon))
                   : ""
            fillMode: Image.PreserveAspectFit
            smooth: true
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
        id: addAsMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // Don't steal vertical drag from asAppFlick
        preventStealing: false
        onClicked: {
            const fn = row.colProp("addApp", null)
            if (typeof fn === "function")
                fn(row.modelData)
        }
        ToolTip.visible: containsMouse
        ToolTip.delay: row.colProp("tooltipDelay", 0)
        ToolTip.text: "Add " + (row.modelData.name || "") + " to login autostart"
    }
}
