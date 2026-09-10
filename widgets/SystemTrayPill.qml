import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

// =============================================================================
// SystemTrayPill.qml — System tray with styled menus
// =============================================================================
//
// Purpose:
//   System tray pill showing icons. Click opens a custom glassmorphic menu
//   (avoids native GTK/Qt menus that clash with the bar theme on Blueman etc.).
//
// Theme Properties Consumed:
//   - bar.pillRadius, bar.pillBg, bar.pillBorder, bar.accent
//   - bar.iconHoverBg, bar.workspaceRadius  (per-icon hover; Config.qml)
//   - bar.iconSizeTray, bar.controlBorderWidth
//   - bar.popupRadius, bar.glassPopupBg, bar.glassPopupBorder,
//     bar.glassPopupHighlight, bar.popupHeaderHighlightHeight,
//     bar.popupSpacing, bar.popupHintSize, bar.buttonRadius
//   - bar.menuBtnNone, bar.menuBtnCheck, bar.menuBtnRadio
//   - bar.text, bar.subtext, bar.overlay, bar.accent, bar.glassHover
//   - bar.dividerStrong
//
// Dependencies:
//   - required property var bar (from shell.qml)
//   - required property Item barBg (for popup positioning)
//   - Quickshell.Services.SystemTray
//   - Quickshell.Widgets (IconImage)
//
// Notes:
//   - All menu logic (menuStack, QsMenuOpener, submenus, check/radio/separator handling) is preserved exactly.
//   - Menu delegate styling has been aligned to theme tokens where safe.
// =============================================================================

Rectangle {
    id: root

    required property var bar
    required property Item barBg

    visible: SystemTray.items.values.length > 0
    // Scale cell sizes once; outer width follows implicit content (no transform double-scale)
    readonly property real _ws: (bar.widgetScale ? bar.widgetScale("tray") : 1.0)
    readonly property int _icon: Math.max(12, Math.round(bar.iconSizeTray * _ws))
    readonly property int _gap: Math.max(2, Math.round(4 * _ws))
    Layout.preferredWidth: visible ? (trayContent.implicitWidth + Math.round(14 * _ws)) : 0
    Layout.preferredHeight: bar.pillHeight
    radius: bar.pillRadius
    // Outer chrome is stable; each tray icon highlights on its own.
    color: bar.pillBg
    border.width: bar.controlBorderWidth
    border.color: bar.pillBorder
    clip: true

    Item {
        id: trayContent
        anchors.centerIn: parent
        implicitWidth: trayIconsRow.implicitWidth
        implicitHeight: trayIconsRow.implicitHeight

        Row {
            id: trayIconsRow
            spacing: root._gap
            anchors.centerIn: parent

            Repeater {
                model: SystemTray.items.values
                // Per-icon hover (same idea as WorkspacesPill buttons)
                delegate: Rectangle {
                    id: trayIconItem
                    required property var modelData
                    width: root._icon + 8
                    height: root._icon + 8
                    radius: bar.workspaceRadius
                    color: trayIconMa.containsMouse ? bar.iconHoverBg : "transparent"
                    border.width: trayIconMa.containsMouse ? bar.controlBorderWidth : 0
                    border.color: trayIconMa.containsMouse ? bar.accent : "transparent"

                    Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }
                    Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

                    IconImage {
                        anchors.centerIn: parent
                        width: root._icon
                        height: root._icon
                        source: modelData ? modelData.icon : ""
                    }

                    MouseArea {
                        id: trayIconMa
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!modelData) return
                            // Always use our styled menu when available (native Blueman menus look wrong on Hyprland)
                            if (modelData.hasMenu) {
                                showTrayMenu(modelData, trayIconItem)
                            } else {
                                modelData.activate()
                            }
                        }
                    }
                }
            }
        }
    }

    // ===== TRAY MENU HELPERS =====
    function showTrayMenu(trayItem, sourceItem) {
        if (!trayItem || !trayItem.hasMenu) return;
        trayMenuPopup.currentItem = trayItem;
        trayMenuPopup.menuHandle = trayItem.menu;
        trayMenuPopup.menuStack = [];
        trayMenuPopup.itemTitle = trayItem.title || trayItem.id || "Menu";

        trayMenuPopup.anchorSourceItem = sourceItem;
        if (typeof bar.placePopup !== "function") {
            var p = sourceItem.mapToItem(barBg, sourceItem.width / 2, sourceItem.height);
            trayMenuPopup.anchorSourceX = bar.sideMargin + p.x;
        }
        trayMenuPopup.visible = true;
        trayMenuPopup.reposition();
        // Menu height is unknown until items load — reposition again after layout
        Qt.callLater(function() { trayMenuPopup.reposition(); });
    }

    function closeTrayMenu() {
        trayMenuPopup.visible = false;
        trayMenuPopup.menuStack = [];
        trayMenuPopup.menuHandle = null;
        trayMenuPopup.currentItem = null;
    }

    // ===== STYLED SYSTEM TRAY MENU POPUP =====
    PopupWindow {
        id: trayMenuPopup
        anchor.window: bar
        implicitWidth: Math.max(200, menuContent.implicitWidth + 24)
        implicitHeight: Math.min(520, Math.max(80, menuContent.implicitHeight + 28))
        visible: false
        color: "transparent"

        property var currentItem: null
        property var menuHandle: null
        property var menuStack: []
        property string itemTitle: ""
        property real anchorSourceX: 0
        property var anchorSourceItem: null

        function reposition() {
            var popupW = implicitWidth > 0 ? implicitWidth : 220
            var popupH = implicitHeight > 0 ? implicitHeight : 80
            if (typeof bar.placePopup === "function" && anchorSourceItem) {
                bar.placePopup(trayMenuPopup, anchorSourceItem, popupW, popupH, undefined,
                               anchorSourceItem.width / 2)
                return
            }
            var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920
            var targetX = anchorSourceX - (popupW / 2)
            var minX = 12
            var maxX = screenW - popupW - 12
            anchor.rect.x = Math.max(minX, Math.min(targetX, maxX))
            anchor.rect.y = bar.popupAnchorY(popupH)
        }

        onImplicitHeightChanged: if (visible) reposition()
        onImplicitWidthChanged: if (visible) reposition()
        onMenuHandleChanged: if (visible) Qt.callLater(reposition)

        QsMenuOpener {
            id: trayMenuOpener
            menu: trayMenuPopup.menuHandle
        }

        function pushSubMenu(handle) {
            if (!handle) return;
            trayMenuPopup.menuStack.push(trayMenuPopup.menuHandle);
            trayMenuPopup.menuHandle = handle;
        }

        function popSubMenu() {
            if (trayMenuPopup.menuStack.length > 0) {
                trayMenuPopup.menuHandle = trayMenuPopup.menuStack.pop();
            } else {
                closeTrayMenu();
            }
        }

        function activateEntry(entry) {
            if (!entry) return;
            if (entry.hasChildren) {
                pushSubMenu(entry);
            } else {
                entry.triggered();
                closeTrayMenu();
            }
        }

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
                id: menuContent
                anchors.fill: parent
                anchors.margins: bar.popupSpacing
                spacing: 2

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4

                    Text {
                        Layout.fillWidth: true
                        text: trayMenuPopup.itemTitle
                        color: bar.text
                        font.pixelSize: bar.popupHintSize
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        visible: trayMenuPopup.menuStack.length > 0
                        width: 22; height: 22; radius: bar.buttonRadius
                        color: backMa.containsMouse ? bar.surface : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "←"
                            color: bar.accent
                            font.pixelSize: 14
                            font.bold: true
                        }
                        MouseArea {
                            id: backMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: trayMenuPopup.popSubMenu()
                        }
                    }

                    Rectangle {
                        width: 22; height: 22; radius: bar.buttonRadius
                        color: closeMa.containsMouse ? bar.surface : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: bar.subtext
                            font.pixelSize: 11
                        }
                        MouseArea {
                            id: closeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: closeTrayMenu()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    height: 1
                    color: bar.dividerStrong
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 4
                    spacing: 1

                    Repeater {
                        model: trayMenuOpener.children
                        delegate: Rectangle {
                            id: entryRow
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: modelData && modelData.isSeparator ? 6 : 28
                            radius: bar.buttonRadius
                            color: {
                                if (!modelData || modelData.isSeparator) return "transparent"
                                if (entryMouse.containsMouse) return bar.glassHover
                                if (modelData.checkState === Qt.Checked) return bar.menuCheckedRow
                                return "transparent"
                            }
                            visible: modelData && modelData.enabled !== false

                            MouseArea {
                                id: entryMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: modelData && !modelData.isSeparator
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData) trayMenuPopup.activateEntry(modelData);
                                }
                            }

                            Rectangle {
                                visible: modelData && modelData.isSeparator
                                anchors.centerIn: parent
                                width: parent.width - 16
                                height: 1
                                color: bar.dividerStrong
                            }

                            RowLayout {
                                visible: modelData && !modelData.isSeparator
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8

                                Item {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: modelData && (
                                        modelData.buttonType === bar.menuBtnCheck
                                        || modelData.buttonType === bar.menuBtnRadio
                                        || modelData.checkState === Qt.Checked
                                        || modelData.checkState === Qt.PartiallyChecked
                                    )

                                    Text {
                                        anchors.centerIn: parent
                                        text: {
                                            if (!modelData) return ""
                                            if (modelData.buttonType === bar.menuBtnRadio) {
                                                return modelData.checkState === Qt.Checked ? "●" : "○"
                                            }
                                            if (modelData.buttonType === bar.menuBtnCheck) {
                                                if (modelData.checkState === Qt.Checked) return "✓"
                                                if (modelData.checkState === Qt.PartiallyChecked) return "◐"
                                                return ""
                                            }
                                            return modelData.checkState === Qt.Checked ? "✓" : ""
                                        }
                                        color: {
                                            if (!modelData) return bar.menuUncheckedMark
                                            if (modelData.checkState === Qt.Checked) return bar.menuCheckMark
                                            if (modelData.checkState === Qt.PartiallyChecked) return bar.subtext
                                            return bar.menuUncheckedMark
                                        }
                                        font.pixelSize: bar.popupHintSize
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                }

                                Image {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: modelData && modelData.icon && modelData.icon.length > 0
                                    source: modelData ? modelData.icon : ""
                                    sourceSize: Qt.size(16, 16)
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                }

                                Text {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    text: modelData ? (modelData.text || "") : ""
                                    color: {
                                        if (entryMouse.containsMouse) return bar.text
                                        if (modelData && modelData.checkState === Qt.Checked) return bar.text
                                        return bar.subtext
                                    }
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontFamily
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: modelData && modelData.hasChildren
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "▸"
                                    color: bar.accent
                                    font.pixelSize: bar.popupHintSize
                                }
                            }
                        }
                    }

                    Text {
                        visible: (!trayMenuOpener.children || trayMenuOpener.children.length === 0) && !trayMenuPopup.menuHandle
                        Layout.alignment: Qt.AlignHCenter
                        text: "(no menu)"
                        color: bar.subtext
                        font.pixelSize: bar.popupHintSize
                        font.italic: true
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: closeTrayMenu()
        }
    }
}
