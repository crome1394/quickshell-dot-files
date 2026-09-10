import QtQuick
import "../components"
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

// =============================================================================
// PowerMenu.qml — Power / Session menu
// =============================================================================
//
// Purpose:
//   Power/session pill that opens a centered popup with Lock, Logout,
//   Reboot, Shutdown, and Enter BIOS options.
//
// Theme Properties Consumed:
//   - bar.pillRadius, bar.pillBg, bar.glassHover, bar.pillBorder, bar.accent
//   - bar.iconPower, bar.iconSizePillLarge, bar.fontFamily
//   - bar.popupRadiusLarge, bar.glassPopupBg, bar.glassPopupBorder,
//     bar.glassPopupHighlight, bar.popupHeaderHighlightHeight,
//     bar.popupSpacing, bar.popupTitleSize, bar.popupHintSize,
//     bar.controlBorderWidth, bar.buttonRadius,
//     bar.popupSectionSpacing, bar.dividerSubtle
//   - bar.popupPowerWidth, bar.popupPowerHeight
//   - bar.text, bar.subtext, bar.overlay
//
// Dependencies:
//   - required property var bar (from shell.qml)
//   - required property Item barBg (for popup positioning)
//
// Notes:
//   - Session commands and menu rows come from Config.qml (search POWER MENU).
//   - Button styling inside the popup has been aligned to theme tokens
//     (including new state colors where applicable).
//   - Action buttons inside the Repeater still contain some hardcoded
//     values (radius, sizes, spacing, font sizes) — noted for possible
//     future micro-pass.
// =============================================================================

Rectangle {
    id: root

    required property var bar
    required property Item barBg

    // === Layout (for RowLayout participation in the bar) ===
    readonly property real _ws: (bar.widgetScale ? bar.widgetScale("power") : 1.0)
    Layout.preferredWidth: Math.round(42 * _ws)
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter

    // === Appearance via Theme ===
    radius: bar.pillRadius
    color: powerMouse.containsMouse ? bar.glassHover : bar.pillBg
    border.width: bar.controlBorderWidth
    border.color: powerMouse.containsMouse ? bar.accent : bar.pillBorder

    Text {
        id: powerIcon
        anchors.centerIn: parent
        text: bar.iconPower
        font.pixelSize: Math.max(10, Math.round(bar.iconSizePillLarge * _ws))
        font.family: bar.fontFamily
        color: powerMouse.containsMouse ? bar.accent : (bar.iconColor !== undefined ? bar.iconColor : bar.subtext)
    }

    MouseArea {
        id: powerMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        BarToolTip {
            bar: root.bar
            visible: powerMouse.containsMouse
            text: "Left: power menu · Right: quick menu"
            anchorItem: powerMouse
        }

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                showPowerContextMenu()
            } else {
                hidePowerContextMenu()
                if (powerPopup.visible) {
                    hidePowerMenu()
                } else {
                    showPowerMenu()
                }
            }
        }
    }

    // ===== Power / Session Menu Helpers =====
    function hidePowerContextMenu() {
        powerContextPopup.visible = false
    }

    function showPowerContextMenu() {
        if (powerContextPopup.visible) {
            hidePowerContextMenu()
            return
        }
        hidePowerMenu()

        var popupW = powerContextPopup.implicitWidth
        if (typeof bar.placePopup === "function") {
            bar.placePopup(powerContextPopup, root, popupW, powerContextPopup.implicitHeight, 2, root.width / 2)
        } else {
            var pos = root.mapToItem(barBg, root.width / 2, 0)
            var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920
            var targetX = bar.sideMargin + pos.x - (popupW / 2)
            var minX = 12
            var maxX = screenW - popupW - 12
            powerContextPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX))
            powerContextPopup.anchor.rect.y = bar.popupAnchorY(powerContextPopup.implicitHeight, 2)
        }
        powerContextPopup.visible = true
    }

    function showPowerMenu() {
        if (powerPopup.visible) {
            hidePowerMenu();
            return;
        }
        hidePowerContextMenu()

        var popupW = powerPopup.implicitWidth;
        if (typeof bar.placePopup === "function") {
            bar.placePopup(powerPopup, root, popupW, powerPopup.implicitHeight, undefined, root.width / 2, 60);
        } else {
            var pos = root.mapToItem(barBg, root.width / 2, root.height);
            var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920;
            var targetX = bar.sideMargin + pos.x - (popupW / 2) + 60;
            var minX = 12;
            var maxX = screenW - popupW - 12;
            powerPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX));
            powerPopup.anchor.rect.y = bar.popupAnchorY(powerPopup.implicitHeight);
        }

        powerPopup.visible = true;
    }

    function hidePowerMenu() {
        powerPopup.visible = false;
    }

    function hideAllPowerPopups() {
        hidePowerMenu()
        hidePowerContextMenu()
    }

    function runPowerAction(action) {
        bar.execPowerCommand(action)
        hideAllPowerPopups()
    }

    // ===== POWER QUICK MENU (right-click) =====
    PopupWindow {
        id: powerContextPopup
        anchor.window: bar
        implicitWidth: bar.popupContextMenuWidth
        implicitHeight: powerContextColumn.implicitHeight + bar.popupSpacingTight * 2
        visible: false
        grabFocus: true
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: bar.popupRadius
            color: bar.glassPopupBg
            border.width: bar.controlBorderWidth
            border.color: bar.glassPopupBorder

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                id: powerContextColumn
                anchors.fill: parent
                anchors.margins: bar.popupSpacingTight
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    text: "Power"
                    color: bar.text
                    font.pixelSize: bar.popupTitleSize
                    font.bold: true
                    font.family: bar.fontFamily
                }

                Repeater {
                    model: bar.powerMenuItems()
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: bar.popupContextMenuRowHeight
                        radius: bar.buttonRadius
                        color: ctxMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.6)
                        border.width: bar.controlBorderWidth
                        border.color: bar.dividerStrong

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: modelData.icon
                                font.pixelSize: 15
                                font.family: bar.fontFamily
                                color: ctxMa.containsMouse ? bar.accent : bar.subtext
                            }

                            Text {
                                Layout.fillWidth: true
                                text: modelData.label
                                color: bar.text
                                font.pixelSize: 12
                                font.family: bar.fontFamily
                            }
                        }

                        MouseArea {
                            id: ctxMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: runPowerAction(modelData.action)
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: "click outside to close"
                    color: bar.subtext
                    font.pixelSize: bar.popupHintSize
                    font.family: bar.fontFamily
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: hidePowerContextMenu()
        }
    }

    // ===== POWER MENU POPUP =====
    PopupWindow {
        id: powerPopup
        anchor.window: bar
        implicitWidth: bar.popupPowerWidth
        implicitHeight: bar.popupPowerHeight
        visible: false
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: bar.popupRadiusLarge
            color: bar.glassPopupBg
            border.width: bar.controlBorderWidth
            border.color: bar.glassPopupBorder

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: bar.popupSpacing
                spacing: bar.popupSectionSpacing

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "Power Menu"
                        color: bar.text
                        font.pixelSize: bar.popupTitleSize
                        font.bold: true
                        font.family: bar.fontFamily
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "ESC to close"
                        color: bar.subtext
                        font.pixelSize: bar.popupHintSize
                        font.family: bar.fontFamily
                    }

                    Rectangle {
                        width: 26
                        height: 26
                        radius: bar.buttonRadius
                        color: powerCloseMa.containsMouse ? bar.glassHover : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: bar.subtext
                            font.pixelSize: 13
                        }

                        MouseArea {
                            id: powerCloseMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: hidePowerMenu()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: bar.popupSectionSpacing
                    spacing: 10   // deliberate visual gap between large action cards

                    Repeater {
                        model: bar.powerMenuItems()
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 92
                            radius: 10
                            color: btnMa.containsMouse ? bar.popupButtonHoverBg : bar.popupButtonHoverBg
                            border.width: bar.controlBorderWidth
                            border.color: btnMa.containsMouse ? bar.accent : bar.dividerSubtle

                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.icon
                                    font.pixelSize: 32
                                    font.family: bar.fontFamily
                                    color: btnMa.containsMouse ? bar.accent : bar.text
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.label
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: btnMa.containsMouse ? bar.text : bar.subtext
                                }
                            }

                            MouseArea {
                                id: btnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: runPowerAction(modelData.action)
                            }
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: hidePowerMenu()
        }

        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: hidePowerMenu()
        }
    }
}
