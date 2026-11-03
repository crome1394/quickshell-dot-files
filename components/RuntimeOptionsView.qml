import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io as Io

// Live Hyprland runtime options via `hyprctl getoption`, grouped by category.
Item {
    id: root

    property string globalFilter: ""
    property color textColor: "#f0f4fc"
    property color subtextColor: "#a8b4c8"
    property color accentColor: "#00F0E0"
    property color surfaceColor: "#141a24"
    property color overlayColor: "#6e7a90"

    readonly property string stubPath: "/usr/share/hypr/stubs/hl.meta.lua"
    readonly property string configDir: (Quickshell.env("HOME") + "/.config/hypr/config")
    readonly property string hyprMainConfig: (Quickshell.env("HOME") + "/.config/hypr/hyprland.lua")

    property var categories: []
    property string selectedCategoryId: "general"
    property string categorySearch: ""
    property var options: []
    property int optionsVersion: 0
    property bool catalogLoaded: false
    property bool loading: false

    property bool _loadHandled: false

    signal copyRequested(string text)

    readonly property var categoryLabelMap: ({
        "general": "General",
        "decoration": "Decorations",
        "animations": "Animations",
        "input": "Input",
        "misc": "Misc",
        "monitor": "Monitor",
        "window": "Window",
        "workspace": "Workspace",
        "dwindle": "Dwindle",
        "master": "Master",
        "group": "Group",
        "binds": "Binds",
        "cursor": "Cursor",
        "gestures": "Gestures",
        "render": "Render",
        "debug": "Debug",
        "xwayland": "XWayland",
        "layer": "Layer",
        "layout": "Layout",
        "scrolling": "Scrolling",
        "ecosystem": "Ecosystem",
        "hyprland": "Hyprland",
        "opengl": "OpenGL",
        "quirks": "Quirks",
        "screenshare": "Screenshare",
        "experimental": "Experimental",
        "config": "Config",
        "keybinds": "Keybinds"
    })

    readonly property var categoryOrder: [
        "general", "decoration", "animations", "input", "misc", "monitor",
        "window", "workspace", "dwindle", "master", "group", "binds", "cursor",
        "gestures", "render", "debug", "xwayland", "layer", "layout", "scrolling",
        "ecosystem", "hyprland", "opengl", "quirks", "screenshare", "experimental",
        "config", "keybinds"
    ]

    readonly property var optionDescriptions: ({
        "general.border_size": "Border width in pixels",
        "general.gaps_in": "Inner gaps between tiled windows",
        "general.gaps_out": "Outer gaps around workspace edges",
        "general.no_focus_fallback": "Focus window when none focused",
        "decoration.rounding": "Corner rounding radius",
        "decoration.rounding_power": "Rounding curve (squircle strength)",
        "decoration.active_opacity": "Opacity of the active window",
        "decoration.inactive_opacity": "Opacity of inactive windows",
        "decoration.blur.enabled": "Enable background blur",
        "decoration.blur.size": "Blur kernel size",
        "decoration.shadow.enabled": "Enable drop shadows",
        "animations.enabled": "Master animation toggle",
        "input.follow_mouse": "Focus follows mouse (0=off, 1=on, 2=lock)",
        "input.sensitivity": "Mouse sensitivity multiplier",
        "input.natural_scroll": "Invert scroll direction",
        "misc.disable_hyprland_logo": "Hide the Hyprland logo on startup",
        "misc.force_default_wallpaper": "Force default wallpaper behavior"
    })

    function filterQuery() {
        return (globalFilter && globalFilter.trim()) ? globalFilter.toLowerCase().trim() : ""
    }

    function filteredCategories() {
        const q = categorySearch ? categorySearch.toLowerCase().trim() : ""
        if (!q) return categories
        return categories.filter(function(c) {
            return c.label.toLowerCase().indexOf(q) !== -1 || c.id.toLowerCase().indexOf(q) !== -1
        })
    }

    function currentCategory() {
        for (let i = 0; i < categories.length; i++) {
            if (categories[i].id === selectedCategoryId) return categories[i]
        }
        return categories.length ? categories[0] : null
    }

    function categoryWikiUrl(catId) {
        return "https://wiki.hypr.land/Configuring/Variables/#" + (catId || "general")
    }

    function configPathForCategory(catId) {
        const id = catId || selectedCategoryId || "general"
        const map = {
            "general": hyprMainConfig,
            "hyprland": hyprMainConfig,
            "config": hyprMainConfig,
            "decoration": configDir + "/look-and-feel.lua",
            "animations": configDir + "/look-and-feel.lua",
            "dwindle": configDir + "/look-and-feel.lua",
            "master": configDir + "/look-and-feel.lua",
            "group": configDir + "/look-and-feel.lua",
            "layout": configDir + "/look-and-feel.lua",
            "scrolling": configDir + "/look-and-feel.lua",
            "render": configDir + "/look-and-feel.lua",
            "input": configDir + "/input.lua",
            "gestures": configDir + "/input.lua",
            "cursor": configDir + "/input.lua",
            "binds": configDir + "/keybindings.lua",
            "keybinds": configDir + "/keybindings.lua",
            "misc": configDir + "/misc.lua",
            "debug": configDir + "/misc.lua",
            "opengl": configDir + "/misc.lua",
            "quirks": configDir + "/misc.lua",
            "screenshare": configDir + "/misc.lua",
            "experimental": configDir + "/misc.lua",
            "monitor": configDir + "/monitors.lua",
            "window": configDir + "/windows-and-workspaces.lua",
            "workspace": configDir + "/windows-and-workspaces.lua",
            "layer": configDir + "/windows-and-workspaces.lua",
            "ecosystem": configDir + "/permissions.lua",
            "xwayland": configDir + "/environment-variables.lua"
        }
        return map[id] || hyprMainConfig
    }

    function editCategoryConfig() {
        const cat = currentCategory()
        const path = configPathForCategory(cat ? cat.id : selectedCategoryId)
        if (!path) return
        Quickshell.execDetached(["kitty", "-e", "nano", path])
    }

    function optionWikiUrl(key) {
        const cat = key.split(".")[0]
        return categoryWikiUrl(cat)
    }

    function optionDescription(key) {
        if (optionDescriptions[key]) return optionDescriptions[key]
        const tail = key.split(".").pop() || key
        return tail.replace(/_/g, " ")
    }

    function hexToColor(hex) {
        let h = hex
        if (h.length === 6) h = "ff" + h
        const n = parseInt(h, 16) >>> 0
        const a = ((n >> 24) & 255) / 255
        const r = (n >> 16) & 255
        const g = (n >> 8) & 255
        const b = n & 255
        return Qt.rgba(r / 255, g / 255, b / 255, a < 0.05 ? 1 : a)
    }

    function argbIntToColor(value) {
        const n = parseInt(value, 10)
        if (isNaN(n)) return textColor
        const u = n >>> 0
        const a = ((u >> 24) & 255) / 255
        const r = (u >> 16) & 255
        const g = (u >> 8) & 255
        const b = u & 255
        return Qt.rgba(r / 255, g / 255, b / 255, a < 0.05 ? 1 : a)
    }

    function extractSwatches(type, value) {
        const swatches = []
        const lowerType = (type || "").toLowerCase()
        const val = value || ""

        if (lowerType.indexOf("gradient") !== -1) {
            const parts = val.split(/\s+/)
            for (let i = 0; i < parts.length; i++) {
                const p = parts[i]
                if (/^[0-9a-fA-F]{6,8}$/.test(p)) swatches.push(hexToColor(p))
            }
        } else if (lowerType === "int") {
            const n = parseInt(val, 10)
            if (!isNaN(n) && n > 0xffffff) swatches.push(argbIntToColor(val))
        } else if (/^rgba?\(/i.test(val) || /^#?[0-9a-fA-F]{6,8}$/.test(val)) {
            if (val[0] === "#") swatches.push(hexToColor(val.substring(1)))
        }
        return swatches
    }

    function parseGetoptionOutput(text) {
        const raw = (text || "").trim()
        if (!raw || raw === "no such option") return null

        let value = ""
        let type = ""
        let set = false
        const lines = raw.split("\n")
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim()
            if (line.indexOf("set:") === 0) {
                set = line.substring(4).trim() === "true"
            } else if (line.indexOf(":") > 0) {
                const idx = line.indexOf(":")
                type = line.substring(0, idx).trim()
                value = line.substring(idx + 1).trim()
            }
        }
        if (!type && !value) return null
        return {
            value: value,
            type: type,
            set: set,
            swatches: extractSwatches(type, value)
        }
    }

    function parseRuntimeCatalog(text) {
        const keys = []
        const lines = (text || "").split("\n")
        for (let i = 0; i < lines.length; i++) {
            const m = lines[i].match(/---\| \"([^\"]+)\"/)
            if (m) keys.push(m[1])
        }

        const grouped = {}
        for (let k = 0; k < keys.length; k++) {
            const key = keys[k]
            const cat = key.split(".")[0]
            if (!grouped[cat]) grouped[cat] = []
            grouped[cat].push(key)
        }

        const built = []
        const seen = {}
        for (let o = 0; o < categoryOrder.length; o++) {
            const id = categoryOrder[o]
            if (!grouped[id]) continue
            seen[id] = true
            built.push({
                id: id,
                label: categoryLabelMap[id] || (id.charAt(0).toUpperCase() + id.slice(1)),
                keys: grouped[id].sort(),
                wikiUrl: categoryWikiUrl(id)
            })
        }

        const remaining = Object.keys(grouped).filter(function(id) { return !seen[id] }).sort()
        for (let r = 0; r < remaining.length; r++) {
            const id = remaining[r]
            built.push({
                id: id,
                label: categoryLabelMap[id] || (id.charAt(0).toUpperCase() + id.slice(1)),
                keys: grouped[id].sort(),
                wikiUrl: categoryWikiUrl(id)
            })
        }

        categories = built
        if (!selectedCategoryId || !built.find(function(c) { return c.id === selectedCategoryId })) {
            selectedCategoryId = built.length ? built[0].id : ""
        }
        catalogLoaded = true
        Qt.callLater(syncComboIndex)
    }

    function syncComboIndex() {
        for (let i = 0; i < categories.length; i++) {
            if (categories[i].id === selectedCategoryId) {
                categoryCombo.currentIndex = i
                return
            }
        }
        if (categories.length > 0) categoryCombo.currentIndex = 0
    }

    function parseRuntimeBatchOutput(text) {
        const parsed = []
        const marker = "@@OPT:"
        let searchFrom = 0
        while (searchFrom < text.length) {
            const markerAt = text.indexOf(marker, searchFrom)
            if (markerAt === -1) break
            const idStart = markerAt + marker.length
            const idEnd = text.indexOf("@@", idStart)
            if (idEnd === -1) break
            const key = text.substring(idStart, idEnd)
            let bodyStart = idEnd + 2
            if (text[bodyStart] === "\n") bodyStart++
            const nextMarker = text.indexOf(marker, bodyStart)
            const bodyEnd = nextMarker === -1 ? text.length : nextMarker
            const body = text.substring(bodyStart, bodyEnd)
            const result = parseGetoptionOutput(body)
            if (result) {
                parsed.push({
                    key: key,
                    shortName: key.split(".").pop(),
                    value: result.value,
                    type: result.type,
                    set: result.set,
                    swatches: result.swatches || [],
                    description: optionDescription(key),
                    wikiUrl: optionWikiUrl(key)
                })
            }
            searchFrom = bodyEnd
        }
        parsed.sort(function(a, b) { return a.key.localeCompare(b.key) })
        options = parsed
        optionsVersion++
    }

    function finishRuntimeLoad() {
        if (!loading || _loadHandled) return
        _loadHandled = true
        loading = false
        if (runtimeStdout.text) parseRuntimeBatchOutput(runtimeStdout.text)
    }

    function loadCatalog() {
        catalogProcess.running = false
        catalogProcess.running = true
    }

    function refreshCategory() {
        const cat = currentCategory()
        if (!cat || !cat.keys || !cat.keys.length) {
            options = []
            optionsVersion++
            return
        }
        loading = true
        _loadHandled = false
        const parts = []
        for (let i = 0; i < cat.keys.length; i++) {
            const key = cat.keys[i]
            const path = key.replace(/\./g, ":")
            const escaped = path.replace(/'/g, "'\\''")
            parts.push("printf '@@OPT:" + key + "@@\\n'")
            parts.push("hyprctl getoption '" + escaped + "' 2>&1")
        }
        runtimeProcess.running = false
        runtimeProcess.command = ["sh", "-c", parts.join(" && ")]
        runtimeProcess.running = true
    }

    function ensureLoaded() {
        if (!catalogLoaded) {
            loadCatalog()
            return
        }
        refreshCategory()
    }

    function refresh() {
        if (!catalogLoaded) {
            loadCatalog()
            return
        }
        refreshCategory()
    }

    function selectCategoryId(catId) {
        if (!catId) return
        selectedCategoryId = catId
        categorySearch = ""
        syncComboIndex()
        resetScroll()
        refreshCategory()
    }

    onOptionsVersionChanged: Qt.callLater(resetScroll)
    onSelectedCategoryIdChanged: Qt.callLater(resetScroll)

    function currentCategoryIndex() {
        for (let i = 0; i < categories.length; i++) {
            if (categories[i].id === selectedCategoryId) return i
        }
        return -1
    }

    function prevCategory() {
        if (!categories.length) return
        const idx = currentCategoryIndex()
        const nextIdx = idx <= 0 ? categories.length - 1 : idx - 1
        selectCategoryId(categories[nextIdx].id)
    }

    function nextCategory() {
        if (!categories.length) return
        const idx = currentCategoryIndex()
        const nextIdx = idx < 0 || idx >= categories.length - 1 ? 0 : idx + 1
        selectCategoryId(categories[nextIdx].id)
    }

    function focusNav() {
        navFocus.forceActiveFocus()
    }

    function focusScroll() {
        runtimeFlickable.forceActiveFocus()
    }

    function handleNavKey(event) {
        if (categoryPopup.opened) return false
        if (event.key === Qt.Key_Left) {
            prevCategory()
            event.accepted = true
            return true
        }
        if (event.key === Qt.Key_Right) {
            nextCategory()
            event.accepted = true
            return true
        }
        if (handleScrollKey(event)) return true
        return false
    }

    function handleScrollKey(event) {
        if (event.key === Qt.Key_PageUp) {
            pageScroll(-1)
            event.accepted = true
            return true
        }
        if (event.key === Qt.Key_PageDown) {
            pageScroll(1)
            event.accepted = true
            return true
        }
        if (event.key === Qt.Key_Up) {
            lineScroll(-1)
            event.accepted = true
            return true
        }
        if (event.key === Qt.Key_Down) {
            lineScroll(1)
            event.accepted = true
            return true
        }
        return false
    }

    function filteredOptions() {
        const q = filterQuery()
        if (!q) return options
        return options.filter(function(o) {
            return o.key.toLowerCase().indexOf(q) !== -1 ||
                   o.shortName.toLowerCase().indexOf(q) !== -1 ||
                   (o.value && o.value.toLowerCase().indexOf(q) !== -1) ||
                   (o.description && o.description.toLowerCase().indexOf(q) !== -1) ||
                   (o.type && o.type.toLowerCase().indexOf(q) !== -1)
        })
    }

    function displayValue(entry) {
        if (!entry) return ""
        if (entry.type === "bool") return entry.value === "true" ? "true" : "false"
        return entry.value
    }

    function exportText() {
        const cat = currentCategory()
        const opts = filteredOptions()
        if (!opts.length) return ""
        const lines = []
        if (cat) lines.push("# " + cat.label)
        for (let i = 0; i < opts.length; i++) {
            const o = opts[i]
            lines.push(o.key + " = " + displayValue(o))
        }
        return lines.join("\n")
    }

    function valueTextColor(entry) {
        if (!entry) return textColor
        if (entry.type === "bool") {
            return entry.value === "true" ? "#2ee59a" : "#e8a06a"
        }
        if (entry.set) return accentColor
        return textColor
    }

    function scrollableMaxY() {
        return Math.max(0, runtimeFlickable.contentHeight - runtimeFlickable.height)
    }

    function pageScroll(direction) {
        const maxY = scrollableMaxY()
        if (maxY <= 0) return
        const page = Math.max(80, runtimeFlickable.height * 0.85)
        runtimeFlickable.contentY = Math.max(0, Math.min(maxY, runtimeFlickable.contentY + direction * page))
    }

    function lineScroll(direction) {
        const maxY = scrollableMaxY()
        if (maxY <= 0) return
        const step = 28
        runtimeFlickable.contentY = Math.max(0, Math.min(maxY, runtimeFlickable.contentY + direction * step))
    }

    function wheelScroll(deltaY) {
        const maxY = scrollableMaxY()
        if (maxY <= 0) return
        const step = 42
        const ticks = deltaY / 120
        runtimeFlickable.contentY = Math.max(0, Math.min(maxY, runtimeFlickable.contentY - ticks * step))
    }

    function resetScroll() {
        if (!runtimeFlickable) return
        runtimeFlickable.contentY = 0
    }

    function runtimeContentHeight() {
        const rows = filteredOptions().length
        if (!rows) return 1
        return Math.max(1, rows * 34)
    }

    readonly property int tableSideMargin: 10
    readonly property int tableColSpacing: 12

    function tableContentWidth(totalWidth) {
        return Math.max(0, totalWidth - tableSideMargin * 2)
    }

    function longestTypeLength() {
        const opts = filteredOptions()
        let maxLen = 4
        for (let i = 0; i < opts.length; i++) {
            const t = opts[i].type || ""
            if (t.length > maxLen) maxLen = t.length
        }
        return maxLen
    }

    function typeColumnWidth(totalWidth) {
        const maxLen = longestTypeLength()
        const contentW = Math.ceil(maxLen * 7.5) + 20
        const minW = 56
        const maxW = Math.min(148, Math.round(tableContentWidth(totalWidth) * 0.20))
        return Math.max(minW, Math.min(maxW, contentW))
    }

    function optionColumnWidth(totalWidth) {
        const usable = tableContentWidth(totalWidth) - tableColSpacing * 2
        const target = Math.round(usable * 0.26)
        return Math.max(150, Math.min(target, 240))
    }

    function valueColumnWidth(totalWidth) {
        const usable = tableContentWidth(totalWidth) - tableColSpacing * 2
        const remaining = usable - optionColumnWidth(totalWidth) - typeColumnWidth(totalWidth)
        return Math.max(180, remaining)
    }

    Io.Process {
        id: catalogProcess
        command: ["cat", root.stubPath]
        running: false
        stdout: Io.StdioCollector {
            id: catalogStdout
            onStreamFinished: {
                root.parseRuntimeCatalog(catalogStdout.text || "")
                root.refreshCategory()
            }
        }
        onExited: {
            if (!root.catalogLoaded) {
                root.parseRuntimeCatalog(catalogStdout.text || "")
                root.refreshCategory()
            }
        }
    }

    Io.Process {
        id: runtimeProcess
        running: false
        stdout: Io.StdioCollector {
            id: runtimeStdout
            onStreamFinished: root.finishRuntimeLoad()
        }
        onExited: root.finishRuntimeLoad()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Item {
            id: navFocus
            Layout.fillWidth: true
            Layout.preferredHeight: 28

            Keys.onPressed: function(event) {
                root.handleNavKey(event)
            }

            onVisibleChanged: {
                if (visible) Qt.callLater(function() { root.focusScroll() })
            }

            RowLayout {
                anchors.fill: parent
                spacing: 8

            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 28
                radius: 6
                color: prevCatMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                opacity: root.categories.length > 0 ? 1 : 0.4

                Text {
                    anchors.centerIn: parent
                    text: "◀"
                    color: root.accentColor
                    font.pixelSize: 12
                }

                MouseArea {
                    id: prevCatMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.categories.length > 0
                    onClicked: root.prevCategory()
                }
            }

            ComboBox {
                id: categoryCombo
                Layout.preferredWidth: 220
                Layout.fillWidth: true
                model: root.categories
                textRole: "label"

                onActivated: function(index) {
                    const item = root.categories[index]
                    if (item) root.selectCategoryId(item.id)
                }

                contentItem: Text {
                    leftPadding: 8
                    rightPadding: categoryCombo.indicator.width + categoryCombo.spacing
                    text: categoryCombo.displayText
                    font.pixelSize: 13
                    color: root.textColor
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                indicator: Canvas {
                    x: categoryCombo.width - width - categoryCombo.rightPadding
                    y: categoryCombo.topPadding + (categoryCombo.availableHeight - height) / 2
                    width: 10
                    height: 6
                    contextType: "2d"
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = root.subtextColor
                        ctx.lineWidth = 1.5
                        ctx.beginPath()
                        ctx.moveTo(0, 1)
                        ctx.lineTo(5, 5)
                        ctx.lineTo(10, 1)
                        ctx.stroke()
                    }
                    onWidthChanged: requestPaint()
                }

                background: Rectangle {
                    radius: 6
                    color: root.surfaceColor
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                }

                popup: Popup {
                    id: categoryPopup
                    y: categoryCombo.height
                    width: Math.max(categoryCombo.width, 240)
                    implicitHeight: Math.min(categoryPopupContent.implicitHeight + 2, 360)
                    padding: 1
                    modal: true
                    focus: true
                    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                    onClosed: Qt.callLater(function() { root.focusScroll() })

                    onOpened: {
                        categoryFilterField.text = ""
                        root.categorySearch = ""
                        Qt.callLater(function() { categoryFilterField.forceActiveFocus() })
                    }

                    background: Rectangle {
                        radius: 6
                        color: root.surfaceColor
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.12)
                    }

                    contentItem: Column {
                        id: categoryPopupContent
                        spacing: 0
                        width: categoryPopup.width

                        Rectangle {
                            width: parent.width
                            height: 34
                            color: root.surfaceColor

                            TextField {
                                id: categoryFilterField
                                anchors.fill: parent
                                anchors.margins: 4
                                placeholderText: "Filter categories..."
                                placeholderTextColor: root.overlayColor
                                color: root.textColor
                                font.pixelSize: 13
                                selectionColor: Qt.rgba(0.55, 0.70, 0.96, 0.35)
                                selectedTextColor: root.textColor
                                onTextChanged: root.categorySearch = text
                                background: Rectangle {
                                    radius: 4
                                    color: Qt.rgba(1, 1, 1, 0.04)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.08)
                                }
                            }
                        }

                        ListView {
                            id: categoryList
                            width: parent.width
                            height: Math.min(contentHeight, 300)
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: root.filteredCategories()
                            property string _filterBind: root.categorySearch

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle {
                                    implicitWidth: 6
                                    radius: 3
                                    color: parent.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                                }
                            }

                            delegate: ItemDelegate {
                                width: categoryList.width
                                height: 30
                                readonly property bool isSelected: modelData.id === root.selectedCategoryId

                                contentItem: Text {
                                    text: modelData.label
                                    color: parent.isSelected ? root.accentColor : root.textColor
                                    font.pixelSize: 13
                                    font.bold: parent.isSelected
                                    leftPadding: 10
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                }

                                background: Rectangle {
                                    color: parent.hovered ? Qt.rgba(1, 1, 1, 0.05)
                                        : (parent.isSelected ? Qt.rgba(0.55, 0.70, 0.96, 0.12) : "transparent")
                                }

                                onClicked: {
                                    root.selectCategoryId(modelData.id)
                                    categoryPopup.close()
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 28
                radius: 6
                color: nextCatMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                opacity: root.categories.length > 0 ? 1 : 0.4

                Text {
                    anchors.centerIn: parent
                    text: "▶"
                    color: root.accentColor
                    font.pixelSize: 12
                }

                MouseArea {
                    id: nextCatMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.categories.length > 0
                    onClicked: root.nextCategory()
                }
            }

            Rectangle {
                width: 68
                height: 28
                radius: 6
                color: refreshCatMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                Text {
                    anchors.centerIn: parent
                    text: root.loading ? "Loading…" : "Refresh"
                    color: root.accentColor
                    font.pixelSize: 12
                }
                MouseArea {
                    id: refreshCatMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.refreshCategory()
                }
            }

            Rectangle {
                width: 40
                height: 28
                radius: 6
                color: editCatMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                Text {
                    anchors.centerIn: parent
                    text: "Edit"
                    color: root.accentColor
                    font.pixelSize: 12
                }
                MouseArea {
                    id: editCatMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.editCategoryConfig()
                }
            }

            Text {
                text: "Wiki"
                color: root.accentColor
                font.pixelSize: 12
                font.underline: wikiMa.containsMouse
                MouseArea {
                    id: wikiMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const cat = root.currentCategory()
                        if (cat) Quickshell.execDetached(["xdg-open", cat.wikiUrl])
                    }
                }
            }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 28
            radius: 4
            color: Qt.rgba(1, 1, 1, 0.03)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: root.tableSideMargin
                anchors.rightMargin: root.tableSideMargin
                spacing: root.tableColSpacing

                Text {
                    Layout.preferredWidth: root.optionColumnWidth(parent.width)
                    Layout.minimumWidth: root.optionColumnWidth(parent.width)
                    Layout.maximumWidth: root.optionColumnWidth(parent.width)
                    text: "Option"
                    color: root.accentColor
                    font.pixelSize: 12
                    font.bold: true
                    font.family: "monospace"
                }
                Text {
                    property int _typeW: root.optionsVersion
                    property string _filterW: root.globalFilter
                    Layout.preferredWidth: root.valueColumnWidth(parent.width)
                    Layout.minimumWidth: root.valueColumnWidth(parent.width)
                    Layout.maximumWidth: root.valueColumnWidth(parent.width)
                    text: "Value"
                    color: root.accentColor
                    font.pixelSize: 12
                    font.bold: true
                    font.family: "monospace"
                    horizontalAlignment: Text.AlignRight
                }
                Item {
                    property int _typeW: root.optionsVersion
                    property string _filterW: root.globalFilter
                    Layout.preferredWidth: root.typeColumnWidth(parent.width)
                    Layout.minimumWidth: root.typeColumnWidth(parent.width)
                    Layout.maximumWidth: root.typeColumnWidth(parent.width)
                    height: parent.height

                    Text {
                        anchors.fill: parent
                        text: "Type"
                        color: root.accentColor
                        font.pixelSize: 12
                        font.bold: true
                        font.family: "monospace"
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }
        }

        Flickable {
            id: runtimeFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: true
            focus: true
            activeFocusOnTab: true
            Keys.enabled: true
            contentWidth: width
            property int _opts: root.optionsVersion
            property string _filter: root.globalFilter
            contentHeight: Math.max(runtimeTable.implicitHeight, root.runtimeContentHeight())

            Keys.onPressed: function(event) {
                if (root.handleScrollKey(event)) return
                if (event.key === Qt.Key_Left) {
                    root.prevCategory()
                    event.accepted = true
                } else if (event.key === Qt.Key_Right) {
                    root.nextCategory()
                    event.accepted = true
                }
            }

            WheelHandler {
                onWheel: function(event) {
                    const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                    if (delta === 0) return
                    root.wheelScroll(delta)
                    event.accepted = true
                }
            }

            ScrollBar.vertical: ScrollBar {
                id: runtimeScrollBar
                policy: runtimeFlickable.contentHeight > runtimeFlickable.height + 1
                    ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                contentItem: Rectangle {
                    implicitWidth: 6
                    radius: 3
                    color: runtimeScrollBar.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                }
            }

            Column {
                id: runtimeTable
                width: parent.width
                spacing: 2
                property int _opts: root.optionsVersion
                property string _filter: root.globalFilter

                Repeater {
                    model: root.filteredOptions()
                    delegate: Rectangle {
                        width: runtimeTable.width
                        height: Math.max(28, descText.visible ? 40 : 28)
                        radius: 4
                        color: keyMa.containsMouse || valueMa.containsMouse
                            ? Qt.rgba(1, 1, 1, 0.03) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: root.tableSideMargin
                            anchors.rightMargin: root.tableSideMargin
                            spacing: root.tableColSpacing

                            ColumnLayout {
                                Layout.preferredWidth: root.optionColumnWidth(runtimeTable.width)
                                Layout.minimumWidth: root.optionColumnWidth(runtimeTable.width)
                                Layout.maximumWidth: root.optionColumnWidth(runtimeTable.width)
                                spacing: 0

                                RowLayout {
                                    spacing: 6
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.key
                                        color: modelData.set ? root.accentColor : root.textColor
                                        font.pixelSize: 13
                                        font.family: "monospace"
                                        font.bold: modelData.set
                                        elide: Text.ElideRight

                                        MouseArea {
                                            id: keyMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.copyRequested(modelData.key)
                                        }
                                    }
                                    Rectangle {
                                        visible: modelData.set
                                        width: setPill.implicitWidth + 10
                                        height: 16
                                        radius: 4
                                        color: Qt.rgba(0.55, 0.70, 0.96, 0.15)
                                        border.width: 1
                                        border.color: Qt.rgba(0.55, 0.70, 0.96, 0.35)
                                        Text {
                                            id: setPill
                                            anchors.centerIn: parent
                                            text: "set"
                                            color: root.accentColor
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                    }
                                }

                                Text {
                                    id: descText
                                    visible: modelData.description && modelData.description.length > 0
                                    text: modelData.description
                                    color: root.overlayColor
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }

                            Item {
                                id: valueCell
                                property int _typeW: root.optionsVersion
                                property string _filterW: root.globalFilter
                                Layout.preferredWidth: root.valueColumnWidth(runtimeTable.width)
                                Layout.minimumWidth: root.valueColumnWidth(runtimeTable.width)
                                Layout.maximumWidth: root.valueColumnWidth(runtimeTable.width)
                                Layout.preferredHeight: descText.visible ? 40 : 28
                                clip: true

                                readonly property int swatchCount: modelData.swatches ? modelData.swatches.length : 0
                                readonly property real swatchSpace: swatchCount > 0 ? (swatchCount * 14 + Math.max(0, swatchCount - 1) * 6) : 0
                                readonly property real textMaxWidth: Math.max(48, width - swatchSpace)

                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 6
                                    width: Math.min(implicitWidth, parent.width)

                                    Repeater {
                                        model: modelData.swatches || []
                                        delegate: Rectangle {
                                            width: 14
                                            height: 14
                                            radius: 3
                                            color: modelData
                                            border.width: 1
                                            border.color: Qt.rgba(1, 1, 1, 0.15)
                                        }
                                    }

                                    Text {
                                        width: Math.min(implicitWidth, valueCell.textMaxWidth)
                                        text: root.displayValue(modelData)
                                        color: root.valueTextColor(modelData)
                                        font.pixelSize: 13
                                        font.family: "monospace"
                                        horizontalAlignment: Text.AlignRight
                                        elide: Text.ElideLeft
                                    }
                                }

                                MouseArea {
                                    id: valueMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.copyRequested(root.displayValue(modelData))
                                }
                            }

                            Item {
                                property int _typeW: root.optionsVersion
                                property string _filterW: root.globalFilter
                                Layout.preferredWidth: root.typeColumnWidth(runtimeTable.width)
                                Layout.minimumWidth: root.typeColumnWidth(runtimeTable.width)
                                Layout.maximumWidth: root.typeColumnWidth(runtimeTable.width)
                                Layout.preferredHeight: descText.visible ? 40 : 28

                                Text {
                                    anchors.fill: parent
                                    visible: modelData.type
                                    text: modelData.type
                                    color: root.subtextColor
                                    font.pixelSize: 12
                                    font.family: "monospace"
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}