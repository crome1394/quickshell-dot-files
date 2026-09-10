import QtQuick
import "../components"
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

// =============================================================================
// QuickLaunchPill.qml — Quick launch row
// =============================================================================
//
// Purpose:
//   Horizontal row of icon buttons inside a pill. Apps and icons are defined in
//   Config.qml defaults (search QUICK LAUNCH); runtime list is bar.quickLaunchApps
//   (editable from BarControlBar → Launch, persisted in bar-layout.json).
//
// Theme Properties Consumed:
//   - bar.pillRadius, bar.pillBg, bar.pillBorder, bar.accent
//   - bar.iconHoverBg, bar.workspaceRadius  (per-icon hover; Config.qml)
//   - bar.quickLaunchIcon, bar.quickLaunchSpacing, bar.quickLaunchPaddingH
//   - bar.quickLaunchApps, bar.fontFamily, bar.controlBorderWidth, bar.tooltipDelay
// =============================================================================

Rectangle {
    id: root

    required property var bar

    // Local copy so Repeater rebinds when shell replaces the array
    property var appsModel: bar.quickLaunchApps || []

    // Horizontal scale only. Cell sizes already include _ws — do NOT multiply the
    // total width by _ws again (that was shrinking the chrome under the icons).
    readonly property real _ws: (bar.widgetScale ? bar.widgetScale("quickLaunch") : 1.0)
    readonly property int _icon: Math.max(12, Math.round(bar.quickLaunchIcon * _ws))
    readonly property int _pad: Math.max(4, Math.round(bar.quickLaunchPaddingH * _ws))
    readonly property int _gap: Math.max(2, Math.round(bar.quickLaunchSpacing * _ws))
    Layout.preferredWidth: Math.max(_icon + _pad * 2, appsRow.implicitWidth + _pad * 2)
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter
    clip: true

    radius: bar.pillRadius
    // Outer chrome is stable; each app icon highlights on its own.
    color: bar.pillBg
    border.width: bar.controlBorderWidth
    border.color: bar.pillBorder

    Connections {
        target: bar
        function onQuickLaunchAppsChanged() {
            root.appsModel = bar.quickLaunchApps || []
        }
    }

    function launchEntry(entry) {
        if (!entry || entry.command === undefined || entry.command === null)
            return

        const cmd = entry.command
        // String form: "gtk-launch firefox" (runs through shell)
        if (typeof cmd === "string") {
            if (cmd.length > 0)
                Quickshell.execDetached(["sh", "-c", cmd])
            return
        }

        // List form from Config.qml — QML lists are not JS arrays (Array.isArray is false).
        const args = []
        const len = cmd.length
        if (len === undefined || len <= 0)
            return
        for (let i = 0; i < len; i++)
            args.push(cmd[i])
        if (args.length > 0)
            Quickshell.execDetached(args)
    }

    function entryUsesGlyph(entry) {
        return entry && (!entry.icon || entry.icon.length === 0) && entry.glyph && entry.glyph.length > 0
    }

    Row {
        id: appsRow
        anchors.centerIn: parent
        spacing: root._gap

        Repeater {
            model: root.appsModel

            // Per-icon hover (same idea as WorkspacesPill buttons)
            Rectangle {
                required property var modelData
                required property int index

                // Keep cells square so icons never squash into each other
                width: root._icon + 8
                height: root._icon + 8
                radius: bar.workspaceRadius
                color: launchClick.containsMouse ? bar.iconHoverBg : "transparent"
                border.width: launchClick.containsMouse ? bar.controlBorderWidth : 0
                border.color: launchClick.containsMouse ? bar.accent : "transparent"
                Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }
                clip: true

                Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

                Image {
                    visible: !root.entryUsesGlyph(modelData)
                    anchors.centerIn: parent
                    width: root._icon
                    height: root._icon
                    source: modelData.icon || ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    mipmap: true
                }

                Text {
                    visible: root.entryUsesGlyph(modelData)
                    anchors.centerIn: parent
                    text: modelData.glyph || ""
                    font.pixelSize: root._icon
                    font.family: bar.fontFamily
                    color: launchClick.containsMouse ? bar.accent : (bar.iconColor !== undefined ? bar.iconColor : bar.subtext)
                }

                MouseArea {
                    id: launchClick
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.launchEntry(modelData)

                    BarToolTip {
                        bar: root.bar
                        widgetId: "quickLaunch"
                        visible: launchClick.containsMouse && (modelData.tooltip || "").length > 0
                        text: modelData.tooltip || ""
                        anchorItem: launchClick
                    }
                }
            }
        }
    }
}
