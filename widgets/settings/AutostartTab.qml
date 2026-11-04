import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io as Io

// Settings → Autostart. XDG login entries and the installed-app picker.
ColumnLayout {
    id: root

    required property var bar
    // Settings window. The list process reads controlPopup.visible.
    required property var controlPopup
    required property int menuTick
    required property int chipR
    required property color onGreen
    required property color offRed
    required property color optFieldBg
    required property color optFieldBgFocus
    required property int bodyScrollBarW
    required property int bodyScrollGutter
    required property string entryFont
    required property string entryMonoFont
    // Shared app catalog. The query and the 280 ms timer stay on SettingsPanel.
    required property string desktopAppsQuery
    required property var scheduleSearch
    required property var filteredApps
    required property var appsTruncated

    // Parent owns menuTick. Emitting keeps the same write the page used to do.
    signal menuBumped()
    // Parent runs scheduleReposition after the autostart list loads.
    signal repositionRequested()

    property var autostartEntries: []
    property bool autostartLoading: false
    property string autostartStatus: ""
    property string autostartSearch: ""
    property string autostartEditId: ""
    property string autostartEditExec: ""

    function armControlFocusGrab() {}

    function refresh() {
        root.refreshAutostart()
    }

    function resetInnerScroll() {
        try {
            if (autostartBodyFlick)
                autostartBodyFlick.contentY = 0
        } catch (e) {}
    }

    // Show the shared catalog query when this page is opened.
    onVisibleChanged: {
        if (root.visible && asSearchField.text !== root.desktopAppsQuery)
            asSearchField.text = root.desktopAppsQuery
    }

    function refreshAutostart() {
        if (autostartListProcess.running)
            return
        root.autostartLoading = true
        root.autostartStatus = "Loading…"
        const script = bar.autostartListScript || ""
        if (!script.length) {
            root.autostartLoading = false
            root.autostartStatus = "list script missing"
            return
        }
        autostartListProcess.exec([script])
    }

    function autostartRows() {
        void root.menuTick
        const list = root.autostartEntries || []
        const q = (root.autostartSearch || "").trim().toLowerCase()
        const out = []
        for (let i = 0; i < list.length; i++) {
            const e = list[i]
            if (q) {
                const blob = ((e.name || "") + " " + (e.id || "") + " " + (e.exec || "")).toLowerCase()
                if (blob.indexOf(q) < 0)
                    continue
            }
            out.push(e)
        }
        return out
    }

    function setAutostartEnabled(id, enabled) {
        const script = bar.autostartSetScript || ""
        if (!script.length || !id)
            return
        autostartSetProcess.exec([script, enabled ? "enable" : "disable", id])
    }

    function removeAutostart(id) {
        const script = bar.autostartSetScript || ""
        if (!script.length || !id)
            return
        if (root.autostartEditId === id)
            root.cancelAutostartEdit()
        autostartSetProcess.exec([script, "remove", id])
    }

    function beginAutostartEdit(entry) {
        if (!entry || !entry.id)
            return
        root.autostartEditId = String(entry.id)
        root.autostartEditExec = String(entry.execRaw || entry.exec || "")
    }

    function cancelAutostartEdit() {
        root.autostartEditId = ""
        root.autostartEditExec = ""
    }

    function saveAutostartExec() {
        const id = root.autostartEditId
        const exec = String(root.autostartEditExec || "").trim()
        const script = bar.autostartSetScript || ""
        if (!script.length || !id || !exec.length)
            return
        root.autostartStatus = "Saving command…"
        autostartSetProcess.exec([script, "exec", id, exec])
    }

    function runAutostartNow(id) {
        const script = bar.autostartRunScript || ""
        if (!script.length)
            return
        if (id)
            Quickshell.execDetached([script, id])
        else
            Quickshell.execDetached([script])
        root.autostartStatus = id ? ("Started " + id) : "Started enabled apps"
    }

    function addAutostartFromApp(app) {
        if (!app)
            return
        const script = bar.autostartAddScript || ""
        if (!script.length)
            return
        const args = [script]
        if (app.id) {
            args.push("--desktop-id", String(app.id))
        } else {
            args.push("--name", String(app.name || app.tooltip || "App"))
            const cmd = app.command
            let execStr = ""
            if (typeof cmd === "string")
                execStr = cmd
            else if (cmd && cmd.length !== undefined) {
                const parts = []
                for (let i = 0; i < cmd.length; i++)
                    parts.push(String(cmd[i]))
                execStr = parts.join(" ")
            }
            if (!execStr.length)
                return
            args.push("--exec", execStr)
            if (app.icon)
                args.push("--icon", String(app.icon))
        }
        root.autostartStatus = "Adding…"
        autostartAddProcess.exec(args)
    }

    function openAutostartDir() {
        Quickshell.execDetached(["xdg-open", (Quickshell.env("HOME") + "/.config/autostart")])
    }

    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: 6

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: "Autostart"
            color: root.bar.text
            font.pixelSize: root.bar.popupTitleSize
            font.bold: true
            font.family: root.bar.fontFamily
        }
    }
    Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "XDG apps in ~/.config/autostart (session login). Core Hyprland services stay in autostarts.lua."
        color: root.bar.subtext
        font.pixelSize: root.bar.popupHintSize
        font.family: root.bar.fontFamily
    }
    Text {
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: root.autostartStatus.length ? root.autostartStatus : "Toggle ✓/✕ · Edit changes the command · add from apps below"
        color: root.bar.subtext
        font.pixelSize: 11
        font.family: root.bar.fontFamily
    }

    Flickable {
        id: autostartBodyFlick
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        contentWidth: width
        // Stretch short content so the app picker can fill the viewport.
        contentHeight: Math.max(autostartBodyCol.implicitHeight, height)
        interactive: contentHeight > height + 4
        ScrollBar.vertical: ScrollBar {
            policy: autostartBodyFlick.contentHeight > autostartBodyFlick.height + 4
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
            id: autostartBodyCol
            width: Math.max(1, autostartBodyFlick.width - root.bodyScrollGutter)
            height: Math.max(implicitHeight, autostartBodyFlick.height)
            spacing: 6

            readonly property string editId: root.autostartEditId
            readonly property string editExec: root.autostartEditExec
            readonly property int chipR: root.chipR
            readonly property color onGreen: root.onGreen
            readonly property color offRed: root.offRed
            readonly property color accent: root.bar.accent
            readonly property color textColor: root.bar.text
            readonly property color subtext: root.bar.subtext
            readonly property color dividerStrong: root.bar.dividerStrong
            readonly property color glassHover: root.bar.glassHover
            readonly property color pillBorder: root.bar.pillBorder
            readonly property color buttonFill: root.bar.buttonBg !== undefined ? root.bar.buttonBg : root.bar.pillBg
            readonly property string fontFamily: root.bar.fontFamily
            readonly property string fontMono: root.bar.fontMono !== undefined ? root.bar.fontMono : root.bar.fontFamily
            readonly property int tooltipDelay: root.bar.tooltipDelay
            readonly property string monoFont: root.entryMonoFont
            readonly property color fieldBg: root.optFieldBg
            readonly property color fieldBgFocus: root.optFieldBgFocus
            function toggleEntry(id, enabled) { root.setAutostartEnabled(id, enabled) }
            function beginEdit(entry) { root.beginAutostartEdit(entry) }
            function cancelEdit() { root.cancelAutostartEdit() }
            function saveEdit() { root.saveAutostartExec() }
            function setEditExec(value) { root.autostartEditExec = value }
            function runOne(id) { root.runAutostartNow(id) }
            function removeOne(id) { root.removeAutostart(id) }


    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Rectangle {
            Layout.preferredHeight: 28
            Layout.preferredWidth: openAsLbl.implicitWidth + 12
            radius: root.chipR
            color: openAsMa.containsMouse ? root.bar.glassHover : (root.bar.buttonBg !== undefined ? root.bar.buttonBg : root.bar.pillBg)
            border.width: 1
            border.color: root.bar.pillBorder
            Text {
                id: openAsLbl
                anchors.centerIn: parent
                text: "Open folder"
                color: root.bar.subtext
                font.pixelSize: 11
                font.family: root.bar.fontFamily
            }
            MouseArea {
                id: openAsMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openAutostartDir()
            }
        }
        Rectangle {
            Layout.preferredHeight: 28
            Layout.preferredWidth: runAllLbl.implicitWidth + 12
            radius: root.chipR
            color: runAllMa.containsMouse ? root.bar.glassHover : (root.bar.buttonBg !== undefined ? root.bar.buttonBg : root.bar.pillBg)
            border.width: 1
            border.color: runAllMa.containsMouse ? root.bar.accent : root.bar.pillBorder
            Text {
                id: runAllLbl
                anchors.centerIn: parent
                text: "Run enabled now"
                color: runAllMa.containsMouse ? root.bar.accent : root.bar.subtext
                font.pixelSize: 11
                font.family: root.bar.fontFamily
            }
            MouseArea {
                id: runAllMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.runAutostartNow("")
            }
        }
    }

    // Current autostart entries
    Repeater {
        model: root.autostartRows()
        delegate: AutostartEntryRow {}
    }

    Text {
        visible: !root.autostartLoading && root.autostartRows().length === 0
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "No XDG autostart entries yet. Add one from installed apps below."
        color: root.bar.subtext
        font.pixelSize: 11
        font.family: root.bar.fontFamily
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 1
        color: root.bar.dividerStrong
    }
    Text {
        text: "Add installed app to autostart"
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
            id: asSearchField
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
                border.color: parent.activeFocus ? root.bar.accent : root.bar.pillBorder
            }
            onPressed: root.armControlFocusGrab()
            onActiveFocusChanged: if (activeFocus) root.armControlFocusGrab()
            onTextEdited: {
                root.autostartSearch = ""
                root.scheduleSearch(text)
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: root.filteredApps().length > 0
        wrapMode: Text.WordWrap
        text: root.appsTruncated()
              ? ("Showing " + root.filteredApps().length
                 + " · scroll for more · type to filter")
              : ("Scroll if the list is longer than the panel")
        color: root.bar.subtext
        font.pixelSize: 10
        font.family: root.bar.fontFamily
    }

    // Fills whatever space is left under the search field. Scrolls inside
    // when there are more apps than fit; stays at least two rows tall
    // when the entries above already fill the panel.
    Flickable {
        id: asAppFlick
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 72
        Layout.preferredHeight: 220
        contentWidth: width
        contentHeight: asAppCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height + 2

        ScrollBar.vertical: ScrollBar {
            policy: asAppFlick.contentHeight > asAppFlick.height + 2
                    ? ScrollBar.AsNeeded
                    : ScrollBar.AlwaysOff
            width: 6
        }

        Column {
            id: asAppCol
            width: Math.max(1, asAppFlick.width - 14)
            spacing: 2

            readonly property int chipR: root.chipR
            readonly property color onGreen: root.onGreen
            readonly property color textColor: root.bar.text
            readonly property color hoverBg: root.bar.popupButtonHoverBg
            readonly property color dividerStrong: root.bar.dividerStrong
            readonly property string fontFamily: root.bar.fontFamily
            readonly property int tooltipDelay: root.bar.tooltipDelay
            function addApp(app) { root.addAutostartFromApp(app) }


            Repeater {
                model: root.filteredApps()
                delegate: AutostartAppRow {}
            }
        }
    }

        } // autostartBodyCol
    } // autostartBodyFlick

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Item { Layout.fillWidth: true }
        Rectangle {
            Layout.preferredHeight: 24
            Layout.preferredWidth: refreshAsLbl.implicitWidth + 12
            radius: root.chipR
            color: refreshAsMa.containsMouse ? root.bar.glassHover : (root.bar.buttonBg !== undefined ? root.bar.buttonBg : root.bar.pillBg)
            border.width: 1
            border.color: root.bar.pillBorder
            Text {
                id: refreshAsLbl
                anchors.centerIn: parent
                text: root.autostartLoading ? "…" : "Refresh"
                color: root.bar.subtext
                font.pixelSize: 11
                font.family: root.bar.fontFamily
            }
            MouseArea {
                id: refreshAsMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refreshAutostart()
            }
        }
    }

    Io.Process {
        id: autostartListProcess
        running: false
        stdout: Io.StdioCollector {
            id: autostartListStdout
            onStreamFinished: {
                root.autostartLoading = false
                const text = (autostartListStdout.text || "").trim()
                if (!text.startsWith("{")) {
                    root.autostartEntries = []
                    root.autostartStatus = "No entries"
                    return
                }
                try {
                    const j = JSON.parse(text)
                    root.autostartEntries = j.entries || []
                    root.autostartStatus = (j.count || 0) + " entry(ies)"
                } catch (e) {
                    root.autostartEntries = []
                    root.autostartStatus = "Parse error"
                }
                root.menuBumped()
                if (root.controlPopup.visible)
                    root.repositionRequested()
            }
        }
        onExited: (code) => {
            root.autostartLoading = false
            if (code !== 0 && !(autostartListStdout.text || "").trim()) {
                root.autostartEntries = []
                root.autostartStatus = "Failed to list"
            }
        }
    }

    Io.Process {
        id: autostartSetProcess
        running: false
        stdout: Io.StdioCollector {
            id: autostartSetStdout
            onStreamFinished: {
                const line = (autostartSetStdout.text || "").trim()
                if (line.indexOf("ok exec") === 0)
                    root.cancelAutostartEdit()
                root.autostartStatus = line.length ? line : "Updated"
                root.refreshAutostart()
            }
        }
        onExited: (code) => {
            if (code !== 0)
                root.autostartStatus = "Update failed"
            root.refreshAutostart()
        }
    }

    Io.Process {
        id: autostartAddProcess
        running: false
        stdout: Io.StdioCollector {
            id: autostartAddStdout
            onStreamFinished: {
                const line = (autostartAddStdout.text || "").trim()
                root.autostartStatus = line.length ? line : "Added"
                root.refreshAutostart()
            }
        }
        onExited: (code) => {
            if (code !== 0)
                root.autostartStatus = "Add failed"
            root.refreshAutostart()
        }
    }
}
