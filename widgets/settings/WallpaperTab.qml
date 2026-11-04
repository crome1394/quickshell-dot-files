import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io as Io
import "../../components"

// Settings → Wallpaper. Folder, tile grid, and wallpaper scripts.
ColumnLayout {
    id: root

    required property var bar
    // Ancestor panel. Right-click maps the tile into this item, then clamps.
    required property var panel
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
    // Computed on SettingsPanel. measurePanelContent already voids it.
    required property int wallpaperTilePref
    required property color activeLabel

    // Parent owns menuTick. Emitting keeps the same write the page used to do.
    signal menuBumped()
    // Parent runs scheduleReposition after the wallpaper list loads.
    signal repositionRequested()

    property var wallpaperImages: []
    property string wallpaperDirDisplay: ""
    property bool wallpaperLoading: false
    property string wallpaperBusyPath: ""
    property string wallpaperStatus: ""
    property string wallpaperMenuPath: ""
    property string wallpaperMenuName: ""
    property real wallpaperMenuX: 0
    property real wallpaperMenuY: 0
    property string wallpaperDialog: ""      // "" | "rename" | "delete"
    property string wallpaperDialogPath: ""
    property string wallpaperDialogName: ""
    property string wallpaperRenameDraft: ""

    function resetInnerScroll() {
        try {
            if (wpBodyFlick)
                wpBodyFlick.contentY = 0
        } catch (e) {}
    }

    function armControlFocusGrab() {}

    function refresh() {
        root.refreshWallpapers()
    }

    function wallpaperDir() {
        void root.menuTick
        if (bar.wallpaperDir && String(bar.wallpaperDir).length)
            return String(bar.wallpaperDir)
        return (Quickshell.env("HOME") + "/Pictures/wallpapers")
    }

    function wallpaperCurrent() {
        void root.menuTick
        return (bar.wallpaperCurrent && String(bar.wallpaperCurrent).length)
            ? String(bar.wallpaperCurrent)
            : ""
    }

    function refreshWallpapers() {
        if (wallpaperListProcess.running)
            return
        root.wallpaperLoading = true
        root.wallpaperStatus = "Loading…"
        const script = bar.wallpaperListScript || ""
        if (!script.length) {
            root.wallpaperLoading = false
            root.wallpaperStatus = "list script missing"
            return
        }
        wallpaperListProcess.exec([script, root.wallpaperDir()])
    }

    function applyWallpaper(path) {
        if (!path || !String(path).length)
            return
        root.wallpaperBusyPath = String(path)
        root.wallpaperStatus = "Applying…"
        if (typeof bar.applyWallpaper === "function")
            bar.applyWallpaper(path)
        else {
            const script = bar.wallpaperApplyScript || ""
            const mon = bar.wallpaperMonitor || ""
            if (script.length)
                Quickshell.execDetached([script, path, mon])
        }
        wallpaperApplySettle.restart()
        root.menuBumped()
    }

    function pickWallpaperDir() {
        const script = bar.wallpaperPickDirScript || ""
        if (!script.length || wallpaperPickDirProcess.running)
            return
        root.wallpaperStatus = "Pick a folder…"
        wallpaperPickDirProcess.exec([script, root.wallpaperDir()])
    }

    function addWallpapers() {
        const script = bar.wallpaperAddScript || ""
        if (!script.length || wallpaperAddProcess.running)
            return
        root.wallpaperStatus = "Choose images to add…"
        wallpaperAddProcess.exec([script, root.wallpaperDir()])
    }

    function closeWallpaperUi() {
        root.wallpaperMenuPath = ""
        root.wallpaperMenuName = ""
        root.wallpaperDialog = ""
        root.wallpaperDialogPath = ""
        root.wallpaperDialogName = ""
        root.wallpaperRenameDraft = ""
    }

    function fileUrlToPath(url) {
        let s = String(url || "")
        if (!s.length)
            return ""
        if (s.startsWith("file://")) {
            s = s.slice(7)
            if (s.startsWith("localhost/"))
                s = s.slice(9)
            else if (s.startsWith("//")) {
                const slash = s.indexOf("/", 2)
                s = slash >= 0 ? s.slice(slash) : s
            }
            try {
                s = decodeURIComponent(s)
            } catch (e) {}
        }
        return s
    }

    function addDroppedWallpapers(urls) {
        const files = []
        const list = urls || []
        for (let i = 0; i < list.length; i++) {
            const p = root.fileUrlToPath(list[i])
            if (p.length)
                files.push(p)
        }
        if (!files.length) {
            root.wallpaperStatus = "No files in drop"
            return
        }
        const script = bar.wallpaperAddScript || ""
        if (!script.length || wallpaperAddProcess.running)
            return
        root.wallpaperStatus = "Adding " + files.length + " item(s)…"
        wallpaperAddProcess.exec([script, root.wallpaperDir()].concat(files))
    }

    function openWallpaperItemMenu(path, name, x, y) {
        root.wallpaperDialog = ""
        root.wallpaperMenuPath = String(path || "")
        root.wallpaperMenuName = String(name || "")
        const mw = 156
        const mh = 118
        let px = Number(x) || 0
        let py = Number(y) || 0
        try {
            if (root.panel) {
                px = Math.max(6, Math.min(px, root.panel.width - mw - 6))
                py = Math.max(6, Math.min(py, root.panel.height - mh - 6))
            }
        } catch (e) {}
        root.wallpaperMenuX = px
        root.wallpaperMenuY = py
    }

    function beginRenameWallpaper(path, name) {
        root.wallpaperMenuPath = ""
        root.wallpaperMenuName = ""
        root.wallpaperDialog = "rename"
        root.wallpaperDialogPath = String(path || "")
        root.wallpaperDialogName = String(name || "")
        root.wallpaperRenameDraft = String(name || "")
        root.armControlFocusGrab()
    }

    function beginDeleteWallpaper(path, name) {
        root.wallpaperMenuPath = ""
        root.wallpaperMenuName = ""
        root.wallpaperDialog = "delete"
        root.wallpaperDialogPath = String(path || "")
        root.wallpaperDialogName = String(name || "")
    }

    function confirmRenameWallpaper() {
        const draft = String(root.wallpaperRenameDraft || "").trim()
        if (!draft.length || !root.wallpaperDialogPath.length)
            return
        if (draft === root.wallpaperDialogName) {
            root.closeWallpaperUi()
            root.wallpaperStatus = "Name unchanged"
            return
        }
        const script = bar.wallpaperRenameScript || ""
        if (!script.length || wallpaperRenameProcess.running) {
            root.wallpaperStatus = script.length ? "Busy…" : "rename script missing"
            return
        }
        root.wallpaperStatus = "Renaming…"
        wallpaperRenameProcess.exec([script, root.wallpaperDir(), root.wallpaperDialogName, draft])
    }

    function confirmDeleteWallpaper() {
        if (!root.wallpaperDialogName.length)
            return
        const script = bar.wallpaperDeleteScript || ""
        if (!script.length || wallpaperDeleteProcess.running) {
            root.wallpaperStatus = script.length ? "Busy…" : "delete script missing"
            return
        }
        root.wallpaperStatus = "Deleting…"
        wallpaperDeleteProcess.exec([script, root.wallpaperDir(), root.wallpaperDialogName])
    }

    function setWallpaperTilePref(n) {
        if (bar && typeof bar.setWallpaperTileSize === "function")
            bar.setWallpaperTileSize(n)
    }

    function openWallpaperDir() {
        const d = root.wallpaperDir()
        if (d.length)
            Quickshell.execDetached(["xdg-open", d])
    }

    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: 8

    RowLayout {
        Layout.fillWidth: true
        Text {
            Layout.fillWidth: true
            text: "Wallpaper"
            color: root.bar.text
            font.pixelSize: root.bar.popupTitleSize
            font.bold: true
            font.family: root.bar.fontFamily
        }
    }

    Text {
        Layout.fillWidth: true
        wrapMode: Text.WrapAnywhere
        text: root.wallpaperDirDisplay || root.wallpaperDir()
        color: root.bar.subtext
        font.pixelSize: root.bar.popupHintSize
        font.family: root.bar.fontMono !== undefined ? root.bar.fontMono : root.bar.fontFamily
    }
    Text {
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: root.wallpaperStatus.length
              ? root.wallpaperStatus
              : "Click to apply · Right-click to rename or delete · Drop images to add"
        color: root.bar.subtext
        font.pixelSize: 11
        font.family: root.bar.fontFamily
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Rectangle {
            Layout.preferredHeight: 30
            Layout.preferredWidth: changeDirLbl.implicitWidth + 14
            radius: root.chipR
            color: changeDirMa.containsMouse ? root.bar.glassHover : (root.bar.buttonBg !== undefined ? root.bar.buttonBg : root.bar.pillBg)
            border.width: 1
            border.color: changeDirMa.containsMouse ? root.bar.accent : root.bar.pillBorder
            Text {
                id: changeDirLbl
                anchors.centerIn: parent
                text: "Change folder…"
                color: changeDirMa.containsMouse ? root.activeLabel : root.bar.subtext
                font.pixelSize: 11
                font.family: root.bar.fontFamily
            }
            MouseArea {
                id: changeDirMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pickWallpaperDir()
            }
        }
        Rectangle {
            Layout.preferredHeight: 30
            Layout.preferredWidth: addWpLbl.implicitWidth + 14
            radius: root.chipR
            color: addWpMa.containsMouse ? root.bar.glassHover : (root.bar.buttonBg !== undefined ? root.bar.buttonBg : root.bar.pillBg)
            border.width: 1
            border.color: addWpMa.containsMouse ? root.bar.accent : root.bar.pillBorder
            Text {
                id: addWpLbl
                anchors.centerIn: parent
                text: "Add wallpapers…"
                color: addWpMa.containsMouse ? root.activeLabel : root.bar.subtext
                font.pixelSize: 11
                font.family: root.bar.fontFamily
            }
            MouseArea {
                id: addWpMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.addWallpapers()
            }
        }
        Rectangle {
            Layout.preferredHeight: 30
            Layout.preferredWidth: openWpLbl.implicitWidth + 14
            radius: root.chipR
            color: openWpMa.containsMouse ? root.bar.glassHover : (root.bar.buttonBg !== undefined ? root.bar.buttonBg : root.bar.pillBg)
            border.width: 1
            border.color: root.bar.pillBorder
            Text {
                id: openWpLbl
                anchors.centerIn: parent
                text: "Open folder"
                color: root.bar.subtext
                font.pixelSize: 11
                font.family: root.bar.fontFamily
            }
            MouseArea {
                id: openWpMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openWallpaperDir()
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Text {
            text: "Tile size"
            color: root.bar.subtext
            font.pixelSize: 11
            font.family: root.bar.fontFamily
        }
        OptValueSlider {
            bar: root.bar
            fieldBg: root.optFieldBg
            fieldBgFocus: root.optFieldBgFocus
            from: 100
            to: 260
            stepSize: 10
            suffix: "px"
            value: root.wallpaperTilePref
            onValueEdited: (v) => root.setWallpaperTilePref(Math.round(v))
            onValueCommitted: (v) => root.setWallpaperTilePref(Math.round(v))
        }
        Text {
            Layout.preferredWidth: 44
            horizontalAlignment: Text.AlignRight
            text: root.wallpaperTilePref + "px"
            color: root.bar.subtext
            font.pixelSize: 11
            font.family: root.bar.fontMono !== undefined ? root.bar.fontMono : root.bar.fontFamily
        }
    }

    Flickable {
        id: wpBodyFlick
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        contentWidth: width
        contentHeight: wpGridCol.implicitHeight
        interactive: contentHeight > height + 4
        ScrollBar.vertical: ScrollBar {
            policy: wpBodyFlick.contentHeight > wpBodyFlick.height + 4
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
        id: wpGridCol
        width: Math.max(1, wpBodyFlick.width - root.bodyScrollGutter)
        spacing: 8

    Item {
        id: wpGridHost
        Layout.fillWidth: true
        implicitHeight: wpFlow.implicitHeight
        height: implicitHeight

        Flow {
            id: wpFlow
            width: parent.width
            spacing: 8
            readonly property int tileW: {
                const spacing = 8
                const pref = Math.max(80, root.wallpaperTilePref)
                const w = Math.max(pref, wpFlow.width)
                const cols = Math.max(1, Math.floor((w + spacing) / (pref + spacing)))
                return Math.max(80, Math.floor((w - (cols - 1) * spacing) / cols))
            }
            readonly property int tileH: Math.round(wpFlow.tileW * 9 / 16) + 22

            readonly property int chipR: root.chipR
            readonly property color onGreen: root.onGreen
            readonly property color offRed: root.offRed
            readonly property color accent: root.bar.accent
            readonly property color textColor: root.bar.text
            readonly property color subtext: root.bar.subtext
            readonly property color dividerStrong: root.bar.dividerStrong
            readonly property color pillBorder: root.bar.pillBorder
            readonly property color glassHover: root.bar.glassHover
            readonly property string fontFamily: root.bar.fontFamily
            readonly property int tooltipDelay: root.bar.tooltipDelay
            readonly property int tilePref: root.wallpaperTilePref
            readonly property string currentPath: root.wallpaperCurrent()
            readonly property string busyPath: root.wallpaperBusyPath

            function applyPath(path) {
                root.closeWallpaperUi()
                root.applyWallpaper(path)
            }
            function openMenu(path, name, item, mx, my) {
                let px = mx
                let py = my
                if (item && root.panel) {
                    const p = item.mapToItem(root.panel, mx, my)
                    px = p.x
                    py = p.y
                }
                root.openWallpaperItemMenu(path, name, px, py)
            }
            function beginRename(path, name) {
                root.beginRenameWallpaper(path, name)
            }
            function beginDelete(path, name) {
                root.beginDeleteWallpaper(path, name)
            }

            Repeater {
                model: root.wallpaperImages
                delegate: WallpaperThumb {}
            }
        }

        WheelHandler {
            acceptedModifiers: Qt.ControlModifier
            onWheel: (event) => {
                const d = event.angleDelta.y > 0 ? 10 : -10
                root.setWallpaperTilePref(root.wallpaperTilePref + d)
                event.accepted = true
            }
        }
    }

    Text {
        visible: !root.wallpaperLoading && root.wallpaperImages.length === 0
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "No images in this folder. Use “Add wallpapers…”, change folder, or drop image files here."
        color: root.bar.subtext
        font.pixelSize: 11
        font.family: root.bar.fontFamily
    }
    } // wpGridCol
    } // wpBodyFlick

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        Item { Layout.fillWidth: true }
        Rectangle {
            Layout.preferredHeight: 26
            Layout.preferredWidth: refreshWpLbl.implicitWidth + 12
            radius: root.chipR
            color: refreshWpMa.containsMouse ? root.bar.glassHover : (root.bar.buttonBg !== undefined ? root.bar.buttonBg : root.bar.pillBg)
            border.width: 1
            border.color: root.bar.pillBorder
            Text {
                id: refreshWpLbl
                anchors.centerIn: parent
                text: root.wallpaperLoading ? "…" : "Refresh"
                color: root.bar.subtext
                font.pixelSize: 11
                font.family: root.bar.fontFamily
            }
            MouseArea {
                id: refreshWpMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refreshWallpapers()
            }
        }
    }

    Timer {
        id: wallpaperApplySettle
        interval: 400
        repeat: false
        onTriggered: {
            root.wallpaperBusyPath = ""
            root.wallpaperStatus = "Applied"
            root.menuBumped()
        }
    }

    Io.Process {
        id: wallpaperListProcess
        running: false
        stdout: Io.StdioCollector {
            id: wallpaperListStdout
            onStreamFinished: {
                root.wallpaperLoading = false
                const text = (wallpaperListStdout.text || "").trim()
                if (!text.startsWith("{")) {
                    root.wallpaperImages = []
                    root.wallpaperStatus = "No images found"
                    return
                }
                try {
                    const j = JSON.parse(text)
                    root.wallpaperDirDisplay = j.dir || root.wallpaperDir()
                    root.wallpaperImages = j.images || []
                    root.wallpaperStatus = (j.count || 0) + " image(s)"
                } catch (e) {
                    root.wallpaperImages = []
                    root.wallpaperStatus = "Parse error"
                }
                root.menuBumped()
                if (root.controlPopup.visible)
                    root.repositionRequested()
            }
        }
        onExited: (code) => {
            root.wallpaperLoading = false
            if (code !== 0 && !(wallpaperListStdout.text || "").trim()) {
                root.wallpaperImages = []
                root.wallpaperStatus = "Failed to list wallpapers"
            }
        }
    }

    Io.Process {
        id: wallpaperPickDirProcess
        running: false
        stdout: Io.StdioCollector {
            id: wallpaperPickDirStdout
            onStreamFinished: {
                const dir = (wallpaperPickDirStdout.text || "").trim()
                if (!dir.length) {
                    root.wallpaperStatus = "Directory unchanged"
                    return
                }
                if (typeof root.bar.setWallpaperDir === "function")
                    root.bar.setWallpaperDir(dir)
                root.wallpaperStatus = "Folder: " + dir
                root.menuBumped()
                root.refreshWallpapers()
            }
        }
    }

    Io.Process {
        id: wallpaperAddProcess
        running: false
        stdout: Io.StdioCollector {
            id: wallpaperAddStdout
            onStreamFinished: {
                const text = (wallpaperAddStdout.text || "").trim()
                let n = 0
                let skipped = 0
                try {
                    if (text.startsWith("{")) {
                        const j = JSON.parse(text)
                        n = j.count || 0
                        skipped = j.skipped || 0
                    }
                } catch (e) {}
                if (n > 0)
                    root.wallpaperStatus = "Added " + n + " file(s)" + (skipped ? (" · skipped " + skipped) : "")
                else
                    root.wallpaperStatus = skipped ? "No images in drop" : "No files added"
                root.refreshWallpapers()
            }
        }
    }

    Io.Process {
        id: wallpaperRenameProcess
        running: false
        stdout: Io.StdioCollector {
            id: wallpaperRenameStdout
            onStreamFinished: {
                const fromPath = root.wallpaperDialogPath
                const current = root.wallpaperCurrent()
                const text = (wallpaperRenameStdout.text || "").trim()
                root.closeWallpaperUi()
                try {
                    const j = JSON.parse(text)
                    if (j.ok) {
                        if (!j.unchanged && current && (current === j.from || current === fromPath))
                            root.applyWallpaper(j.path)
                        root.wallpaperStatus = j.unchanged ? "Name unchanged" : ("Renamed to " + j.name)
                        root.refreshWallpapers()
                    } else {
                        root.wallpaperStatus = j.error || "Rename failed"
                    }
                } catch (e) {
                    root.wallpaperStatus = "Rename failed"
                }
            }
        }
        onExited: (code) => {
            if (code !== 0 && !(wallpaperRenameStdout.text || "").trim())
                root.wallpaperStatus = "Rename failed"
        }
    }

    Io.Process {
        id: wallpaperDeleteProcess
        running: false
        stdout: Io.StdioCollector {
            id: wallpaperDeleteStdout
            onStreamFinished: {
                const deletedPath = root.wallpaperDialogPath
                const current = root.wallpaperCurrent()
                const text = (wallpaperDeleteStdout.text || "").trim()
                root.closeWallpaperUi()
                try {
                    const j = JSON.parse(text)
                    if (j.ok) {
                        if (current && (current === j.path || current === deletedPath)
                                && typeof root.bar.setWallpaperCurrent === "function")
                            root.bar.setWallpaperCurrent("")
                        root.wallpaperStatus = "Deleted " + j.name
                        root.refreshWallpapers()
                    } else {
                        root.wallpaperStatus = j.error || "Delete failed"
                    }
                } catch (e) {
                    root.wallpaperStatus = "Delete failed"
                }
            }
        }
        onExited: (code) => {
            if (code !== 0 && !(wallpaperDeleteStdout.text || "").trim())
                root.wallpaperStatus = "Delete failed"
        }
    }
}
