import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io as Io

// Control-strip keybindings browser/editor.
// Lists keybindings.lua with --#Category# descriptions (Inspector parity).
// Edits only: key chord, category, description — never the dispatcher expression.
Item {
    id: root

    property bool active: false
    property string filterText: ""

    property color textColor: "#f0f4fc"
    property color subtextColor: "#a8b4c8"
    property color accentColor: "#00F0E0"
    property color surfaceColor: "#141a24"
    property color overlayColor: "#6e7a90"
    property color okColor: "#2ee59a"
    property color warnColor: "#f0d060"
    property color errorColor: "#FF3D8A"
    property color fieldBg: Qt.rgba(0.18, 0.19, 0.23, 0.92)
    property color fieldBgFocus: Qt.rgba(0.22, 0.24, 0.30, 0.95)
    property color pillBorder: Qt.rgba(1, 1, 1, 0.12)
    property string fontFamily: "sans-serif"
    property string fontMono: "monospace"

    // Resolve relative to this component so worktree and ~/.config/quickshell both work
    function scriptPath(name) {
        const u = Qt.resolvedUrl("../scripts/" + name).toString()
        return u.replace(/^file:\/\//, "")
    }
    readonly property string listScript: scriptPath("keybinds-list-json.sh")
    readonly property string setScript: scriptPath("keybinds-set.sh")

    property var binds: []
    property string filePath: ""
    property bool loading: false
    property bool saving: false
    property bool reloading: false
    property string lastError: ""
    property string lastStatus: ""
    property int dataVersion: 0

    // Edit form state
    property int editLine: -1
    property string editKey: ""
    property string editCategory: ""
    property string editDescription: ""
    property bool editOpen: false

    property bool _loadHandled: false
    property bool _saveHandled: false

    function filterQuery() {
        return (filterText && filterText.trim()) ? filterText.toLowerCase().trim() : ""
    }

    function matchesFilter(b) {
        const q = filterQuery()
        if (!q) return true
        const hay = [
            b.key || "", b.category || "", b.description || "", b.preview || ""
        ].join(" ").toLowerCase()
        return hay.indexOf(q) !== -1
    }

    function filteredBinds() {
        void dataVersion
        void filterText
        if (!binds || !binds.length) return []
        const out = []
        for (let i = 0; i < binds.length; i++) {
            if (matchesFilter(binds[i])) out.push(binds[i])
        }
        return out
    }

    function groupedBinds() {
        const list = filteredBinds()
        let hasCat = false
        for (let i = 0; i < list.length; i++) {
            if (list[i].category && list[i].category.length > 0) {
                hasCat = true
                break
            }
        }
        if (!hasCat)
            return [{ category: "", binds: list }]

        const groups = []
        const indexByCat = ({})
        for (let i = 0; i < list.length; i++) {
            const b = list[i]
            const cat = (b.category && b.category.length > 0) ? b.category : "Other"
            if (indexByCat[cat] === undefined) {
                indexByCat[cat] = groups.length
                groups.push({ category: cat, binds: [] })
            }
            groups[indexByCat[cat]].binds.push(b)
        }
        return groups
    }

    function categoryList() {
        void dataVersion
        const seen = ({})
        const out = []
        for (let i = 0; i < binds.length; i++) {
            const c = binds[i].category || ""
            if (c && !seen[c]) {
                seen[c] = true
                out.push(c)
            }
        }
        return out
    }

    function keyPillColor(part) {
        const p = (part || "").toUpperCase()
        if (p === "SUPER" || p === "SUPER_L" || p === "SUPER_R")
            return Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.28)
        if (p === "SHIFT" || p === "CTRL" || p === "CONTROL" || p === "ALT" || p === "META")
            return Qt.rgba(0.55, 0.55, 0.65, 0.35)
        return Qt.rgba(1, 1, 1, 0.10)
    }

    function refresh() {
        if (listProcess.running) return
        loading = true
        lastError = ""
        // Keep lastStatus only if it is not a transient reload message
        if (lastStatus.indexOf("Reload") === 0 || lastStatus.indexOf("Reloading") === 0)
            lastStatus = ""
        _loadHandled = false
        listProcess.command = [root.listScript]
        listProcess.running = false
        listProcess.running = true
    }

    function finishLoad(exitCode) {
        if (_loadHandled) return
        _loadHandled = true
        loading = false
        const code = (exitCode === undefined || exitCode === null) ? 0 : exitCode
        const raw = (listStdout.text || "").trim()
        const errOut = (listStderr.text || "").trim()
        if (code !== 0 && !raw) {
            lastError = errOut.length
                ? errOut
                : ("Failed to list keybinds (exit " + code + "). Script: " + root.listScript)
            binds = []
            dataVersion++
            return
        }
        if (!raw) {
            lastError = "Empty response from keybinds list. Script: " + root.listScript
            binds = []
            dataVersion++
            return
        }
        try {
            const parsed = JSON.parse(raw)
            if (parsed.error) {
                lastError = parsed.error
                binds = []
            } else {
                binds = parsed.binds || []
                filePath = parsed.path || ""
                lastError = ""
            }
            dataVersion++
            // Refresh edit fields if still open
            if (editOpen && editLine > 0) {
                let found = null
                for (let i = 0; i < binds.length; i++) {
                    if (binds[i].line === editLine) {
                        found = binds[i]
                        break
                    }
                }
                if (found) {
                    editKey = found.key || ""
                    editCategory = found.category || ""
                    editDescription = found.description || ""
                }
            }
        } catch (e) {
            lastError = "Failed to parse keybinds JSON"
            binds = []
            dataVersion++
        }
    }

    function startEdit(bind) {
        if (!bind) return
        if (!bind.editable) {
            lastError = bind.reason || "This bind is not safely editable"
            lastStatus = ""
            return
        }
        editLine = bind.line
        editKey = bind.key || ""
        editCategory = bind.category || ""
        editDescription = bind.description || ""
        editOpen = true
        lastError = ""
        lastStatus = ""
    }

    function cancelEdit() {
        editOpen = false
        editLine = -1
        lastError = ""
    }

    function saveEdit() {
        if (editLine < 1 || saving || setProcess.running) return
        const key = (editKey || "").trim()
        if (!key.length) {
            lastError = "Key chord is required"
            return
        }
        saving = true
        lastError = ""
        lastStatus = ""
        _saveHandled = false
        setProcess.running = false
        setProcess.command = [
            root.setScript,
            String(editLine),
            "--key", key,
            "--category", editCategory || "",
            "--description", editDescription || ""
        ]
        setProcess.running = true
    }

    function reloadHypr() {
        if (reloadProcess.running) return
        reloading = true
        lastStatus = "Reloading Hyprland…"
        lastError = ""
        // Call hyprctl directly — does not depend on keybinds-set.sh being installed
        reloadProcess.command = ["hyprctl", "reload"]
        reloadProcess.running = false
        reloadProcess.running = true
    }

    function finishSave(code) {
        if (_saveHandled) return
        _saveHandled = true
        saving = false
        if (code !== 0) {
            const err = (setStderr.text || setStdout.text || "").trim()
            try {
                const j = JSON.parse(err)
                lastError = j.error || err || ("Save failed (exit " + code + "). Script: " + root.setScript)
            } catch (e) {
                lastError = err.length ? err : ("Save failed (exit " + code + "). Script: " + root.setScript)
            }
            return
        }
        lastStatus = "Saved (backup created). Use Reload Hypr to apply."
        editOpen = false
        editLine = -1
        Qt.callLater(function() { root.refresh() })
    }

    function finishReload(code) {
        reloading = false
        if (code === 0) {
            lastError = ""
            lastStatus = "Hyprland reloaded"
        } else {
            lastStatus = ""
            const err = (reloadStderr.text || reloadStdout.text || "").trim()
            lastError = err.length ? err : ("hyprctl reload failed (exit " + code + ")")
        }
    }

    onActiveChanged: {
        if (active) {
            // Always refresh when opening so list is current
            refresh()
        } else {
            if (listProcess.running)
                listProcess.running = false
            loading = false
            reloading = false
            if (lastStatus.indexOf("Reloading") === 0)
                lastStatus = ""
            cancelEdit()
        }
    }

    Io.Process {
        id: listProcess
        command: [root.listScript]
        running: false
        stdout: Io.StdioCollector { id: listStdout }
        stderr: Io.StdioCollector { id: listStderr }
        onExited: (code) => root.finishLoad(code)
    }

    Io.Process {
        id: setProcess
        running: false
        stdout: Io.StdioCollector { id: setStdout }
        stderr: Io.StdioCollector { id: setStderr }
        onExited: (code) => root.finishSave(code)
    }

    Io.Process {
        id: reloadProcess
        command: ["hyprctl", "reload"]
        running: false
        stdout: Io.StdioCollector { id: reloadStdout }
        stderr: Io.StdioCollector { id: reloadStderr }
        onExited: (code) => root.finishReload(code)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: root.reloading
                       ? "Reloading Hyprland…"
                       : (root.loading
                          ? "Loading…"
                          : (root.filteredBinds().length + " binds"))
                color: root.subtextColor
                font.pixelSize: 11
                font.family: root.fontFamily
                elide: Text.ElideRight
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.lastError.length > 0
            text: root.lastError
            color: root.errorColor
            font.pixelSize: 11
            font.family: root.fontFamily
            wrapMode: Text.WordWrap
        }
        Text {
            Layout.fillWidth: true
            visible: (root.reloading || root.lastStatus.length > 0) && root.lastError.length === 0
            text: root.reloading ? "Reloading Hyprland…" : root.lastStatus
            color: root.okColor
            font.pixelSize: 11
            font.family: root.fontFamily
            wrapMode: Text.WordWrap
        }

        // Edit form
        Rectangle {
            visible: root.editOpen
            Layout.fillWidth: true
            Layout.preferredHeight: editCol.implicitHeight + 16
            radius: 8
            color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.08)
            border.width: 1
            border.color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.28)

            ColumnLayout {
                id: editCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 8
                spacing: 6

                Text {
                    text: "Edit bind (line " + root.editLine + ") — action dispatcher stays unchanged"
                    color: root.accentColor
                    font.pixelSize: 11
                    font.bold: true
                    font.family: root.fontFamily
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: "Key"
                        color: root.subtextColor
                        font.pixelSize: 11
                        font.family: root.fontFamily
                        Layout.preferredWidth: 72
                    }
                    TextField {
                        id: keyField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        text: root.editKey
                        placeholderText: "SUPER + T"
                        color: root.textColor
                        placeholderTextColor: root.overlayColor
                        font.pixelSize: 12
                        font.family: root.fontMono
                        background: Rectangle {
                            radius: 6
                            color: parent.activeFocus ? root.fieldBgFocus : root.fieldBg
                            border.width: 1
                            border.color: keyField.activeFocus ? root.accentColor : root.pillBorder
                        }
                        onTextChanged: root.editKey = text
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: "Category"
                        color: root.subtextColor
                        font.pixelSize: 11
                        font.family: root.fontFamily
                        Layout.preferredWidth: 72
                    }
                    TextField {
                        id: catField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        text: root.editCategory
                        placeholderText: "Apps, Windows, Tools…"
                        color: root.textColor
                        placeholderTextColor: root.overlayColor
                        font.pixelSize: 12
                        font.family: root.fontFamily
                        background: Rectangle {
                            radius: 6
                            color: parent.activeFocus ? root.fieldBgFocus : root.fieldBg
                            border.width: 1
                            border.color: catField.activeFocus ? root.accentColor : root.pillBorder
                        }
                        onTextChanged: root.editCategory = text
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: "Description"
                        color: root.subtextColor
                        font.pixelSize: 11
                        font.family: root.fontFamily
                        Layout.preferredWidth: 72
                    }
                    TextField {
                        id: descField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        text: root.editDescription
                        placeholderText: "What this bind does"
                        color: root.textColor
                        placeholderTextColor: root.overlayColor
                        font.pixelSize: 12
                        font.family: root.fontFamily
                        background: Rectangle {
                            radius: 6
                            color: parent.activeFocus ? root.fieldBgFocus : root.fieldBg
                            border.width: 1
                            border.color: descField.activeFocus ? root.accentColor : root.pillBorder
                        }
                        onTextChanged: root.editDescription = text
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        Layout.preferredHeight: 28
                        Layout.preferredWidth: cancelLbl.implicitWidth + 16
                        radius: 6
                        color: cancelMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.12)
                        Text {
                            id: cancelLbl
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: root.subtextColor
                            font.pixelSize: 11
                        }
                        MouseArea {
                            id: cancelMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cancelEdit()
                        }
                    }
                    Rectangle {
                        Layout.preferredHeight: 28
                        Layout.preferredWidth: saveLbl.implicitWidth + 16
                        radius: 6
                        color: saveMa.containsMouse
                               ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.28)
                               : Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.16)
                        border.width: 1
                        border.color: root.accentColor
                        opacity: root.saving ? 0.55 : 1
                        Text {
                            id: saveLbl
                            anchors.centerIn: parent
                            text: root.saving ? "Saving…" : "Save"
                            color: root.accentColor
                            font.pixelSize: 11
                            font.bold: true
                        }
                        MouseArea {
                            id: saveMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: !root.saving
                            onClicked: root.saveEdit()
                        }
                    }
                }
            }
        }

        // Bind list
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 8
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            clip: true

            Flickable {
                id: listFlick
                anchors.fill: parent
                anchors.margins: 8
                // Leave a gutter so Edit buttons sit clear of the vertical scrollbar
                readonly property int scrollGutter: 14
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: Math.max(listCol.implicitHeight, height)

                property int _tick: root.dataVersion
                property string _filter: root.filterText

                WheelHandler {
                    onWheel: function(event) {
                        const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                        if (delta === 0) return
                        const maxY = Math.max(0, listFlick.contentHeight - listFlick.height)
                        if (maxY > 0) {
                            const ticks = delta / 120
                            listFlick.contentY = Math.max(0, Math.min(maxY, listFlick.contentY - ticks * 28))
                        }
                        event.accepted = true
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: listFlick.contentHeight > listFlick.height + 1
                            ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    padding: 1
                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: parent.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                    }
                }

                Column {
                    id: listCol
                    width: Math.max(0, listFlick.width - listFlick.scrollGutter)
                    spacing: 8

                    property int _t: listFlick._tick
                    property string _f: listFlick._filter
                    readonly property var groups: {
                        const _a = _t
                        const _b = _f
                        return root.groupedBinds()
                    }

                    Text {
                        width: parent.width
                        visible: root.loading && root.binds.length === 0
                        text: "Loading keybindings…"
                        color: root.overlayColor
                        font.pixelSize: 11
                        font.family: root.fontMono
                    }
                    Text {
                        width: parent.width
                        visible: !root.loading && listCol.groups.length === 0
                        text: "(no matching keybindings)"
                        color: root.overlayColor
                        font.pixelSize: 11
                        font.family: root.fontMono
                    }

                    Repeater {
                        model: listCol.groups
                        delegate: Column {
                            width: listCol.width
                            spacing: 3

                            // Category header
                            Rectangle {
                                visible: modelData.category && modelData.category.length > 0
                                width: parent.width
                                height: visible ? 26 : 0
                                radius: 6
                                color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.10)

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 4
                                    width: 3
                                    radius: 1.5
                                    color: root.accentColor
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 8
                                    spacing: 8
                                    Text {
                                        text: modelData.category
                                        color: root.accentColor
                                        font.pixelSize: 11
                                        font.bold: true
                                        font.letterSpacing: 0.5
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                    Rectangle {
                                        visible: modelData.binds && modelData.binds.length > 0
                                        Layout.preferredHeight: 16
                                        Layout.preferredWidth: cntLbl.implicitWidth + 8
                                        radius: 8
                                        color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18)
                                        Text {
                                            id: cntLbl
                                            anchors.centerIn: parent
                                            text: modelData.binds ? modelData.binds.length : 0
                                            color: root.accentColor
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                    }
                                }
                            }

                            Repeater {
                                model: modelData.binds
                                delegate: Rectangle {
                                    width: listCol.width
                                    height: 32
                                    radius: 4
                                    color: rowMa.containsMouse
                                           ? Qt.rgba(1, 1, 1, 0.05)
                                           : (root.editLine === modelData.line
                                              ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.12)
                                              : "transparent")
                                    opacity: modelData.editable ? 1 : 0.72

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 4
                                        anchors.rightMargin: 6
                                        spacing: 8

                                        // Key pills
                                        Row {
                                            spacing: 3
                                            Layout.preferredWidth: 160
                                            Repeater {
                                                model: (modelData.key || "").split(/\s*\+\s*/).filter(function(s) {
                                                    return s && s.length > 0
                                                })
                                                delegate: Rectangle {
                                                    height: 20
                                                    width: kTxt.implicitWidth + 10
                                                    radius: 4
                                                    color: root.keyPillColor(modelData)
                                                    Text {
                                                        id: kTxt
                                                        anchors.centerIn: parent
                                                        text: modelData
                                                        color: root.textColor
                                                        font.pixelSize: 10
                                                        font.family: root.fontMono
                                                        font.bold: true
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.description || "—"
                                            color: root.textColor
                                            font.pixelSize: 12
                                            font.family: root.fontFamily
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            visible: !modelData.editable
                                            text: "ro"
                                            color: root.warnColor
                                            font.pixelSize: 10
                                            font.family: root.fontMono
                                            ToolTip.visible: roMa.containsMouse
                                            ToolTip.text: modelData.reason || "Read-only (dynamic key)"
                                            MouseArea {
                                                id: roMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                            }
                                        }

                                        Rectangle {
                                            Layout.preferredHeight: 22
                                            Layout.preferredWidth: editBtnLbl.implicitWidth + 12
                                            radius: 5
                                            color: editBtnMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                                            border.width: 1
                                            border.color: Qt.rgba(1, 1, 1, 0.12)
                                            opacity: modelData.editable ? 1 : 0.35
                                            Text {
                                                id: editBtnLbl
                                                anchors.centerIn: parent
                                                text: "Edit"
                                                color: root.accentColor
                                                font.pixelSize: 10
                                            }
                                            MouseArea {
                                                id: editBtnMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: modelData.editable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                enabled: modelData.editable && !root.saving
                                                onClicked: root.startEdit(modelData)
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: rowMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.NoButton
                                        z: -1
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.filePath.length > 0
            text: root.filePath
            color: root.overlayColor
            font.pixelSize: 9
            font.family: root.fontMono
            elide: Text.ElideMiddle
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Item { Layout.fillWidth: true }
            Rectangle {
                Layout.preferredHeight: 26
                Layout.preferredWidth: refreshLbl.implicitWidth + 14
                radius: 6
                color: refreshMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)
                opacity: root.loading ? 0.5 : 1
                Text {
                    id: refreshLbl
                    anchors.centerIn: parent
                    text: root.loading ? "…" : "Refresh"
                    color: root.accentColor
                    font.pixelSize: 11
                    font.family: root.fontFamily
                }
                MouseArea {
                    id: refreshMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !root.loading && !root.saving
                    onClicked: root.refresh()
                }
            }
            Rectangle {
                Layout.preferredHeight: 26
                Layout.preferredWidth: reloadLbl.implicitWidth + 14
                radius: 6
                color: reloadMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.12)
                Text {
                    id: reloadLbl
                    anchors.centerIn: parent
                    text: "Reload Hypr"
                    color: root.accentColor
                    font.pixelSize: 11
                    font.family: root.fontFamily
                }
                MouseArea {
                    id: reloadMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.reloadHypr()
                }
            }
        }
    }
}
