import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Settings → App Launcher. Pins, installed apps, and custom commands.
ColumnLayout {
    id: root

    required property var bar
    required property int menuTick
    required property int chipR
    required property color onGreen
    required property color offRed
    required property color optFieldBg
    required property color optFieldBgFocus
    required property int bodyScrollBarW
    required property int bodyScrollGutter
    required property string entryFont
    // Shared app catalog. The query and the 280 ms timer stay on SettingsPanel.
    required property string desktopAppsQuery
    required property bool desktopAppsLoading
    required property var scheduleSearch
    required property var refreshApps
    required property var filteredApps

    // Parent owns menuTick. Emitting keeps the same write the page used to do.
    signal menuBumped()

    property string customName: ""
    property string customCommand: ""
    property string customIcon: ""

    function reposition() {
    }

    function armControlFocusGrab() {}

    function resetInnerScroll() {
        try {
            if (launchBodyFlick)
                launchBodyFlick.contentY = 0
        } catch (e) {}
    }

    // Show the shared catalog query when this page is opened.
    onVisibleChanged: {
        if (root.visible && appSearchField.text !== root.desktopAppsQuery)
            appSearchField.text = root.desktopAppsQuery
    }

    function quickLaunchEntries() {
        void root.menuTick
        const apps = bar.quickLaunchApps || []
        const out = []
        for (let i = 0; i < apps.length; i++) {
            const e = apps[i]
            out.push({
                index: i,
                icon: e.icon || "",
                glyph: e.glyph || "",
                tooltip: e.tooltip || "",
                command: e.command,
                commandText: root.commandToText(e.command)
            })
        }
        return out
    }

    function commandToText(cmd) {
        if (cmd === undefined || cmd === null)
            return ""
        if (typeof cmd === "string")
            return cmd
        const parts = []
        const len = cmd.length
        if (len === undefined)
            return String(cmd)
        for (let i = 0; i < len; i++)
            parts.push(String(cmd[i]))
        return parts.join(" ")
    }

    function addDesktopApp(app) {
        if (!app)
            return
        const entry = {
            icon: app.icon || "",
            glyph: "",
            command: app.command || ["gtk-launch", String(app.id || "").replace(/\.desktop$/, "")],
            tooltip: app.name || app.tooltip || ""
        }
        if (typeof bar.addQuickLaunchApp === "function")
            bar.addQuickLaunchApp(entry)
        root.menuBumped()
        Qt.callLater(reposition)
    }

    function addCustomApp() {
        const name = String(root.customName || "").trim()
        const cmd = String(root.customCommand || "").trim()
        const icon = String(root.customIcon || "").trim()
        if (!cmd.length)
            return
        const entry = {
            icon: icon,
            glyph: icon.length ? "" : "󰣆",
            command: cmd,
            tooltip: name || cmd
        }
        if (typeof bar.addQuickLaunchApp === "function")
            bar.addQuickLaunchApp(entry)
        root.customName = ""
        root.customCommand = ""
        root.customIcon = ""
        root.menuBumped()
        Qt.callLater(reposition)
    }

    function removeLaunchApp(index) {
        if (typeof bar.removeQuickLaunchApp === "function")
            bar.removeQuickLaunchApp(index)
        root.menuBumped()
        Qt.callLater(reposition)
    }

    function moveLaunchApp(index, delta) {
        if (typeof bar.moveQuickLaunchApp === "function")
            bar.moveQuickLaunchApp(index, delta)
        root.menuBumped()
        Qt.callLater(reposition)
    }

    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: 6


    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: "Application Launcher"
            color: root.bar.text
            font.pixelSize: root.bar.popupTitleSize
            font.bold: true
            font.family: root.bar.fontFamily
        }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "Pinned icons on the bar · ✕ remove · ↑↓ reorder · add from installed apps or custom"
        color: root.bar.subtext
        font.pixelSize: root.bar.popupHintSize
        font.family: root.bar.fontFamily
    }

    Flickable {
        id: launchBodyFlick
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        contentWidth: width
        contentHeight: launchBodyCol.implicitHeight
        interactive: contentHeight > height + 4
        ScrollBar.vertical: ScrollBar {
            policy: launchBodyFlick.contentHeight > launchBodyFlick.height + 4
                    ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            width: root.bodyScrollBarW
            padding: 2
            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: root.bar.accent
                opacity: 0.5
            }
            background: Rectangle {
                implicitWidth: root.bodyScrollBarW
                radius: 4
                color: Qt.rgba(1, 1, 1, 0.06)
            }
        }
        ColumnLayout {
            id: launchBodyCol
            width: Math.max(1, launchBodyFlick.width - root.bodyScrollGutter)
            spacing: 6

            readonly property int chipR: root.chipR
            readonly property color onGreen: root.onGreen
            readonly property color offRed: root.offRed
            readonly property int controlBorderWidth: root.bar.controlBorderWidth
            readonly property color textColor: root.bar.text
            readonly property color subtext: root.bar.subtext
            readonly property color dividerStrong: root.bar.dividerStrong
            readonly property color glassHover: root.bar.glassHover
            readonly property color pillBorder: root.bar.pillBorder
            readonly property color buttonFill: root.bar.buttonBg !== undefined ? root.bar.buttonBg : root.bar.pillBg
            readonly property color hoverBg: root.bar.popupButtonHoverBg
            readonly property string fontFamily: root.bar.fontFamily
            readonly property string fontMono: root.bar.fontMono !== undefined ? root.bar.fontMono : root.bar.fontFamily
            readonly property int tooltipDelay: root.bar.tooltipDelay
            function removeApp(index) { root.removeLaunchApp(index) }
            function moveApp(index, delta) { root.moveLaunchApp(index, delta) }
            function addApp(app) { root.addDesktopApp(app) }

    // Current pins
    Repeater {
        model: root.quickLaunchEntries()
        delegate: LaunchPinRow {}
    }

    // Add from installed apps
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: root.bar.dividerStrong
    }
    Text {
        text: "Add installed app"
        color: root.bar.text
        font.pixelSize: 12
        font.bold: true
        font.family: root.bar.fontFamily
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        TextField {
            topPadding: 1
            bottomPadding: 1
            verticalAlignment: Text.AlignVCenter
            id: appSearchField
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            placeholderText: "Search apps…"
            color: root.bar.text
            placeholderTextColor: root.bar.subtext
            font.pixelSize: 14
            font.family: root.entryFont
            background: Rectangle {
                radius: root.chipR
                color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                border.width: 1
                border.color: appSearchField.activeFocus ? root.bar.accent : root.bar.pillBorder
            }
            onPressed: root.armControlFocusGrab()
            onActiveFocusChanged: if (activeFocus) root.armControlFocusGrab()
            onTextEdited: root.scheduleSearch(text)
        }
        Rectangle {
            Layout.preferredHeight: 30
            Layout.preferredWidth: searchBtnLbl.implicitWidth + 14
            radius: root.chipR
            color: searchBtnMa.containsMouse ? root.bar.glassHover : (root.bar.buttonBg !== undefined ? root.bar.buttonBg : root.bar.pillBg)
            border.width: 1
            border.color: root.bar.pillBorder
            Text {
                id: searchBtnLbl
                anchors.centerIn: parent
                text: root.desktopAppsLoading ? "…" : "Search"
                color: root.bar.subtext
                font.pixelSize: 11
                font.family: root.bar.fontFamily
            }
            MouseArea {
                id: searchBtnMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refreshApps()
            }
        }
    }

    Repeater {
        model: root.filteredApps()
        delegate: LaunchAppRow {}
    }

    // Custom add
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: root.bar.dividerStrong
    }
    Text {
        text: "Add custom"
        color: root.bar.text
        font.pixelSize: 12
        font.bold: true
        font.family: root.bar.fontFamily
    }
    TextField {
        font.family: root.entryFont
        topPadding: 1
        bottomPadding: 1
        verticalAlignment: Text.AlignVCenter
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        placeholderText: "Name (tooltip)"
        color: root.bar.text
        placeholderTextColor: root.bar.subtext
        font.pixelSize: 14
        text: root.customName
        onTextChanged: root.customName = text
        background: Rectangle {
            radius: root.chipR
            color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
            border.width: 1
            border.color: root.bar.pillBorder
        }
    }
    TextField {
        font.family: root.entryFont
        topPadding: 1
        bottomPadding: 1
        verticalAlignment: Text.AlignVCenter
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        placeholderText: "Command (e.g. gtk-launch firefox or /usr/bin/app)"
        color: root.bar.text
        placeholderTextColor: root.bar.subtext
        font.pixelSize: 14
        text: root.customCommand
        onTextChanged: root.customCommand = text
        background: Rectangle {
            radius: root.chipR
            color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
            border.width: 1
            border.color: root.bar.pillBorder
        }
    }
    TextField {
        font.family: root.entryFont
        topPadding: 1
        bottomPadding: 1
        verticalAlignment: Text.AlignVCenter
        Layout.fillWidth: true
        Layout.preferredHeight: 28
        placeholderText: "Icon path (optional, e.g. /home/…/icons/app.svg)"
        color: root.bar.text
        placeholderTextColor: root.bar.subtext
        font.pixelSize: 14
        text: root.customIcon
        onTextChanged: root.customIcon = text
        background: Rectangle {
            radius: root.chipR
            color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
            border.width: 1
            border.color: root.bar.pillBorder
        }
    }
    Rectangle {
        Layout.preferredHeight: 32
        Layout.preferredWidth: addCustomLbl.implicitWidth + 18
        radius: root.chipR
        color: addCustomMa.containsMouse ? root.bar.glassHover : (root.bar.buttonBg !== undefined ? root.bar.buttonBg : root.bar.pillBg)
        border.width: 1
        border.color: addCustomMa.containsMouse ? root.bar.accent : root.bar.pillBorder
        opacity: root.customCommand.trim().length ? 1 : 0.5
        Text {
            id: addCustomLbl
            anchors.centerIn: parent
            text: "Add custom app"
            color: addCustomMa.containsMouse ? root.bar.accent : root.bar.subtext
            font.pixelSize: 12
            font.family: root.bar.fontFamily
        }
        MouseArea {
            id: addCustomMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: root.customCommand.trim().length > 0
            onClicked: root.addCustomApp()
        }
    }

        } // launchBodyCol
    } // launchBodyFlick

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Item { Layout.fillWidth: true }
        Rectangle {
            Layout.preferredHeight: 24
            Layout.preferredWidth: resetLaunchLbl.implicitWidth + 12
            radius: root.chipR
            color: resetLaunchMa.containsMouse ? root.bar.glassHover : (root.bar.buttonBg !== undefined ? root.bar.buttonBg : root.bar.pillBg)
            border.width: root.bar.controlBorderWidth
            border.color: root.bar.pillBorder
            Text {
                id: resetLaunchLbl
                anchors.centerIn: parent
                text: "Reset"
                color: root.bar.subtext
                font.pixelSize: 11
                font.family: root.bar.fontFamily
            }
            MouseArea {
                id: resetLaunchMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (typeof root.bar.resetQuickLaunchApps === "function")
                        root.bar.resetQuickLaunchApps()
                    root.menuBumped()
                    Qt.callLater(root.reposition)
                }
            }
        }
    }
}
