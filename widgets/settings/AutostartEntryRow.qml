import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// One XDG autostart row. Live colors and edit state sit on the column.
// Bracket reads keep the open editor from rebuilding the list.
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

    readonly property bool enabledNow: !!row.modelData.enabled
    readonly property bool editing: row.colProp("editId", "") === (row.modelData.id || "")

    Layout.fillWidth: true
    Layout.preferredHeight: asRowCol.implicitHeight + 12
    radius: row.colProp("chipR", 8)
    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
    border.width: 1
    border.color: row.editing ? row.colProp("accent", "#fff")
                  : (row.enabledNow ? row.colProp("onGreen", "#2ee59a")
                                    : row.colProp("dividerStrong", "#333"))
    opacity: row.enabledNow ? 1.0 : 0.78

    ColumnLayout {
        id: asRowCol
        x: 6
        y: 6
        width: Math.max(1, parent.width - 12)
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            spacing: 6

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 26
                radius: 4
                color: asToggleMa.containsMouse
                       ? (row.enabledNow ? Qt.rgba(0.29, 0.87, 0.50, 0.18) : Qt.rgba(0.97, 0.44, 0.44, 0.18))
                       : "transparent"
                border.width: 1
                border.color: row.enabledNow ? row.colProp("onGreen", "#2ee59a") : row.colProp("offRed", "#FF3D8A")
                Text {
                    anchors.centerIn: parent
                    text: row.enabledNow ? "✓" : "✕"
                    color: row.enabledNow ? row.colProp("onGreen", "#2ee59a") : row.colProp("offRed", "#FF3D8A")
                    font.pixelSize: 14
                    font.bold: true
                }
                MouseArea {
                    id: asToggleMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const fn = row.colProp("toggleEntry", null)
                        if (typeof fn === "function")
                            fn(row.modelData.id, !row.enabledNow)
                    }
                    ToolTip.visible: containsMouse
                    ToolTip.delay: row.colProp("tooltipDelay", 0)
                    ToolTip.text: row.enabledNow ? "Disable at login" : "Enable at login"
                }
            }

            Image {
                visible: (row.modelData.icon || "").length > 0
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                source: row.modelData.icon ? ("file://" + row.modelData.icon) : ""
                fillMode: Image.PreserveAspectFit
                smooth: true
            }
            Text {
                visible: !(row.modelData.icon || "").length
                Layout.preferredWidth: 22
                horizontalAlignment: Text.AlignHCenter
                text: "󰣆"
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
                    text: row.modelData.name || row.modelData.id
                    color: row.colProp("textColor", "#fff")
                    font.pixelSize: 12
                    font.family: row.colProp("fontFamily", "")
                }
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: row.modelData.exec || row.modelData.id
                    color: row.colProp("subtext", "#aaa")
                    font.pixelSize: 10
                    font.family: row.colProp("fontMono", "")
                }
            }

            Rectangle {
                Layout.preferredWidth: asEditLbl.implicitWidth + 12
                Layout.preferredHeight: 26
                radius: 4
                color: asEditMa.containsMouse ? row.colProp("glassHover", "transparent") : row.colProp("buttonFill", "transparent")
                border.width: 1
                border.color: row.editing || asEditMa.containsMouse ? row.colProp("accent", "#fff") : row.colProp("pillBorder", "transparent")
                Text {
                    id: asEditLbl
                    anchors.centerIn: parent
                    text: row.editing ? "Close" : "Edit"
                    color: row.editing || asEditMa.containsMouse ? row.colProp("accent", "#fff") : row.colProp("subtext", "#aaa")
                    font.pixelSize: 11
                    font.family: row.colProp("fontFamily", "")
                }
                MouseArea {
                    id: asEditMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (row.editing) {
                            const cancel = row.colProp("cancelEdit", null)
                            if (typeof cancel === "function")
                                cancel()
                            return
                        }
                        const begin = row.colProp("beginEdit", null)
                        if (typeof begin === "function")
                            begin(row.modelData)
                        Qt.callLater(function() {
                            if (asEditField)
                                asEditField.forceActiveFocus()
                        })
                    }
                    ToolTip.visible: containsMouse
                    ToolTip.delay: row.colProp("tooltipDelay", 0)
                    ToolTip.text: "Edit the command"
                }
            }

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 26
                radius: 4
                color: runOneMa.containsMouse ? row.colProp("glassHover", "transparent") : row.colProp("buttonFill", "transparent")
                border.width: 1
                border.color: row.colProp("pillBorder", "transparent")
                Text {
                    anchors.centerIn: parent
                    text: "▶"
                    color: row.colProp("subtext", "#aaa")
                    font.pixelSize: 11
                }
                MouseArea {
                    id: runOneMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const fn = row.colProp("runOne", null)
                        if (typeof fn === "function")
                            fn(row.modelData.id)
                    }
                    ToolTip.visible: containsMouse
                    ToolTip.delay: row.colProp("tooltipDelay", 0)
                    ToolTip.text: "Run now"
                }
            }

            Rectangle {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 26
                radius: 4
                color: rmAsMa.containsMouse ? Qt.rgba(0.97, 0.44, 0.44, 0.18) : "transparent"
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
                    id: rmAsMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const fn = row.colProp("removeOne", null)
                        if (typeof fn === "function")
                            fn(row.modelData.id)
                    }
                    ToolTip.visible: containsMouse
                    ToolTip.delay: row.colProp("tooltipDelay", 0)
                    ToolTip.text: "Remove from autostart"
                }
            }
        }

        RowLayout {
            visible: row.editing
            Layout.fillWidth: true
            spacing: 6
            TextField {
                topPadding: 1
                bottomPadding: 1
                verticalAlignment: Text.AlignVCenter
                id: asEditField
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                placeholderText: "Command (Exec=)"
                color: row.colProp("textColor", "#fff")
                placeholderTextColor: row.colProp("subtext", "#aaa")
                font.pixelSize: 14
                font.family: row.colProp("monoFont", "")
                text: row.colProp("editExec", "")
                selectByMouse: true
                onTextChanged: {
                    const fn = row.colProp("setEditExec", null)
                    if (typeof fn === "function")
                        fn(text)
                }
                onAccepted: {
                    const fn = row.colProp("saveEdit", null)
                    if (typeof fn === "function")
                        fn()
                }
                background: Rectangle {
                    radius: row.colProp("chipR", 8)
                    color: parent.activeFocus ? row.colProp("fieldBgFocus", "transparent") : row.colProp("fieldBg", "transparent")
                    border.width: 1
                    border.color: parent.activeFocus ? row.colProp("accent", "#fff") : row.colProp("pillBorder", "transparent")
                }
            }
            Rectangle {
                Layout.preferredHeight: 28
                Layout.preferredWidth: asExecSaveLbl.implicitWidth + 14
                radius: row.colProp("chipR", 8)
                opacity: String(row.colProp("editExec", "")).trim().length ? 1 : 0.5
                color: asExecSaveMa.containsMouse ? row.colProp("glassHover", "transparent") : row.colProp("buttonFill", "transparent")
                border.width: 1
                border.color: asExecSaveMa.containsMouse ? row.colProp("accent", "#fff") : row.colProp("pillBorder", "transparent")
                Text {
                    id: asExecSaveLbl
                    anchors.centerIn: parent
                    text: "Save"
                    color: asExecSaveMa.containsMouse ? row.colProp("accent", "#fff") : row.colProp("subtext", "#aaa")
                    font.pixelSize: 11
                    font.family: row.colProp("fontFamily", "")
                }
                MouseArea {
                    id: asExecSaveMa
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: String(row.colProp("editExec", "")).trim().length > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const fn = row.colProp("saveEdit", null)
                        if (typeof fn === "function")
                            fn()
                    }
                }
            }
            Rectangle {
                Layout.preferredHeight: 28
                Layout.preferredWidth: asExecCancelLbl.implicitWidth + 14
                radius: row.colProp("chipR", 8)
                color: asExecCancelMa.containsMouse ? row.colProp("glassHover", "transparent") : row.colProp("buttonFill", "transparent")
                border.width: 1
                border.color: row.colProp("pillBorder", "transparent")
                Text {
                    id: asExecCancelLbl
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: row.colProp("subtext", "#aaa")
                    font.pixelSize: 11
                    font.family: row.colProp("fontFamily", "")
                }
                MouseArea {
                    id: asExecCancelMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const fn = row.colProp("cancelEdit", null)
                        if (typeof fn === "function")
                            fn()
                    }
                }
            }
        }
    }
}
