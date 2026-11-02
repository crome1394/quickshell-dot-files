import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io as Io

// =============================================================================
// HyprConfigInsp.qml — Hyprland Config Inspector
// =============================================================================
//
// Floating overlay for browsing and editing split Hyprland configuration.
//
// Architecture (data flow):
//   ┌─────────────────────────────────────────────────────────────────────┐
//   │ FloatingWindow (inspectorWindow)                                    │
//   │   ├─ Header: hyprctl version + os-release (headerProcess)           │
//   │   ├─ Tab bar: `tabs` model → activateTab() → one visible viewer     │
//   │   ├─ Global search: globalFilter → per-tab filter functions         │
//   │   └─ Footer: statusText() + contextual actions (Copy / Refresh / Edit)   │
//   └─────────────────────────────────────────────────────────────────────┘
//
// Data sources (by tab view id — see `tabs` array):
//   - binds/env/raw     → fileContents{} via Io.Process cat (batch or single)
//   - configfiles       → configFileEntries + BatSyntaxView
//   - runtime           → RuntimeOptionsView (hyprctl getoption)
//   - cpu/gpu/memory/network/…  → SysMonService (scripts/sysmon-poller.sh, autoPoll when inspectorActive)
//   - processes/audio/logs/services → dedicated *View components + shell pollers
//   - system            → fastfetch --logo cachyos (ANSI→HTML color; systemProcess, lazy until tab opened)
//
// Theming:
//   - Config { id: th } is the single visual source (see config.qml HYPR CONFIG INSPECTOR).
//   - Window fill: inspWindowBg (solid) or inspUseGradient + inspGradientTop/Bottom.
//   - Short aliases below (accent, inspTabRadius, …) keep QML bindings readable.
//   - `required property var bar` is passed from shell.qml for API consistency; visuals use `th`.
//
// How to extend:
//   1. Add a tab entry to `tabs` (label, id, file, view).
//   2. If file-backed, add to configFileEntries or give tab a `file` path.
//   3. Add a *View component under the content Rectangle (visible bound to view id).
//   4. Wire refresh/focus/scroll in: activateTab, refreshAll, refreshCurrentTab,
//      focusActiveTabContent, resetTabScroll, pageContentScroll, statusText.
//   5. Add theme tokens to config.qml if the new tab needs unique colors/sizes.
//
// Features:
//   - Parsed tabs: Key Bindings, Environment, Runtime Options, Config Files, sysmon tabs, Audio, Logs, Services, System Info
//   - Edit (kitty nano, Ctrl+E) per config file tab; Refresh All reloads everything
//   - Global search (Ctrl+F, Esc), edit file (Ctrl+E on tabs with Edit), Tab/Shift+Tab, PgUp/PgDown/arrow scroll
//   - Resizable FloatingWindow (title: "Hyprland Config Inspector")
// =============================================================================

import ".."
import "../components"

Item {
    id: root

    // === Required API (shell passes bar; visuals come from local Config instance) ===
    required property var bar

    Config { id: th }

    SysMonService {
        id: sysMonService
        autoPoll: root.inspectorActive   // poll only while overlay is shown (not minimized)
    }

    // === Config aliases — short names for bindings (all values from config.qml) ===
    // Inspector window background (inspWindow* — independent of other bar popups)
    readonly property color inspWindowBg: th.inspWindowBg
    readonly property color inspWindowBorder: th.inspWindowBorder
    readonly property color inspWindowHighlight: th.inspWindowHighlight
    readonly property bool inspUseGradient: th.inspUseGradient
    readonly property color inspGradientTop: th.inspGradientTop
    readonly property color inspGradientBottom: th.inspGradientBottom

    // Base palette
    readonly property color text: th.text
    readonly property color subtext: th.subtext
    readonly property color overlay: th.overlay
    readonly property color accent: th.accent
    readonly property color surface: th.surface
    readonly property color divider: th.divider
    readonly property string fontMono: th.fontMono

    // Window geometry
    readonly property int popupRadiusLarge: th.popupRadiusLarge
    readonly property int popupHelpWidth: th.popupHelpWidth
    readonly property int popupHelpHeight: th.popupHelpHeight
    readonly property int inspMinWidth: th.inspMinWidth
    readonly property int inspMinHeight: th.inspMinHeight
    readonly property int inspContentPadding: th.inspContentPadding
    readonly property int inspSectionSpacing: th.inspSectionSpacing

    // Tab bar + search
    readonly property int tabBarMaxHeight: th.inspTabBarMaxHeight
    readonly property int inspTabHeight: th.inspTabHeight
    readonly property int inspTabRadius: th.inspTabRadius
    readonly property int inspTabHPadding: th.inspTabHPadding
    readonly property int inspTabSpacing: th.inspTabSpacing
    readonly property int inspTabFontSize: th.inspTabFontSize
    readonly property color inspTabActiveBg: th.inspTabActiveBg
    readonly property color inspTabActiveBorder: th.inspTabActiveBorder
    readonly property color inspTabHoverBg: th.inspTabHoverBg
    readonly property int inspSearchWidth: th.inspSearchWidth
    readonly property int inspSearchHeight: th.inspSearchHeight
    readonly property int inspSearchRadius: th.inspSearchRadius
    readonly property color inspSearchSelectionBg: th.inspSearchSelectionBg

    // Header / footer / scrollbars / rows
    readonly property int inspTitleFontSize: th.inspTitleFontSize
    readonly property int inspSubtitleFontSize: th.inspSubtitleFontSize
    readonly property int inspStatusFontSize: th.inspStatusFontSize
    readonly property color inspRowHoverBg: th.inspRowHoverBg
    readonly property color inspRowHoverBgStrong: th.inspRowHoverBgStrong
    readonly property int inspScrollBarWidth: th.inspScrollBarWidth
    readonly property int inspScrollBarRadius: th.inspScrollBarRadius
    readonly property color inspScrollBarIdle: th.inspScrollBarIdle

    // Env table layout (width helpers use these)
    readonly property int envTableSideMargin: th.inspEnvTableSideMargin
    readonly property int envTableColSpacing: th.inspEnvTableColSpacing

    // === Static paths (edit here if your Hypr config lives elsewhere) ===
    readonly property string configDir: "/home/crome/.config/hypr/config"
    readonly property string hyprDir: "/home/crome/.config/hypr"

    readonly property var configFileEntries: [
        { id: "monitors", label: "Monitors", file: "monitors.lua" },
        { id: "my-programs", label: "My Programs", file: "my-programs.lua" },
        { id: "autostarts", label: "Autostarts", file: "autostarts.lua" },
        { id: "permissions", label: "Permissions", file: "permissions.lua" },
        { id: "look-and-feel", label: "Look & Feel", file: "look-and-feel.lua" },
        { id: "misc", label: "Misc", file: "misc.lua" },
        { id: "input", label: "Input", file: "input.lua" },
        { id: "windows-and-workspaces", label: "Window & Layer Rules", file: "windows-and-workspaces.lua" },
        { id: "hyprland", label: "Main Config", file: "hyprland.lua", dir: hyprDir },
        { id: "keybindings", label: "Key Bindings", file: "keybindings.lua" },
        { id: "environment", label: "Environment", file: "environment-variables.lua" },
        { id: "hypridle", label: "Hypridle", file: "hypridle.conf", dir: hyprDir, batLanguage: "INI" },
        { id: "hyprlock", label: "Hyprlock", file: "hyprlock.conf", dir: hyprDir, batLanguage: "Java Properties" },
        { id: "hyprpaper", label: "Hyprpaper", file: "hyprpaper.conf", dir: hyprDir, batLanguage: "INI" }
    ]

    // === Tab registry (order = tab bar order; `view` selects which content panel is visible) ===
    readonly property var tabs: [
        { label: "Key Bindings", id: "keybindings", file: "keybindings.lua", view: "binds" },
        { label: "Environment", id: "environment", file: "environment-variables.lua", view: "env" },
        { label: "Runtime Options", id: "runtime-options", file: "", view: "runtime" },
        { label: "Config Files", id: "config-files", file: "", view: "configfiles" },
        { label: "CPU", id: "cpu", file: "", view: "cpu" },
        { label: "GPU", id: "gpu", file: "", view: "gpu" },
        { label: "Memory", id: "memory", file: "", view: "memory" },
        { label: "Temperature", id: "temperature", file: "", view: "temperature" },
        { label: "Network", id: "network", file: "", view: "network" },
        { label: "Processes", id: "processes", file: "", view: "processes" },
        { label: "Audio", id: "audio", file: "", view: "audio" },
        { label: "Logs", id: "logs", file: "", view: "logs" },
        { label: "Services", id: "services", file: "", view: "services" },
        { label: "System Info", id: "system", file: "", view: "system" }
    ]

    // === View routing helpers (single place for "which tabs share behavior?") ===
    // Used by refresh/scroll/focus handlers — add new view ids here when extending.
    readonly property var _fileOnlyViews: ["binds", "env", "raw"]
    readonly property var _sysmonMetricViews: ["cpu", "gpu", "memory", "temperature", "network"]
    readonly property var _footerRefreshViews: ["system", "runtime", "processes", "audio", "logs", "services"]
    readonly property var _noFileTabViews: ["system", "runtime", "configfiles", "cpu", "gpu", "memory", "temperature", "network", "processes", "audio", "logs", "services"]

    function tabView() {
        const tab = currentTabInfo
        return tab ? tab.view : ""
    }

    function isSysmonMetricView(view) {
        return _sysmonMetricViews.indexOf(view || "") !== -1
    }

    function isLiveDataView(view) {
        const v = view || tabView()
        return isSysmonMetricView(v) || v === "processes"
    }

    readonly property var currentTabInfo: (currentTab >= 0 && currentTab < tabs.length) ? tabs[currentTab] : tabs[0]
    readonly property bool hasConfigFile: {
        const tab = currentTabInfo
        if (tab.view === "configfiles") return true
        return tab.file && tab.file.length > 0
    }
    // === Per-tab file viewer state (bat / raw source for config tabs) ===
    property string rawSource: ""
    property string batFilePath: ""
    property string batLanguage: ""

    function fileEntryById(id) {
        if (!id) return null
        for (let i = 0; i < configFileEntries.length; i++) {
            if (configFileEntries[i].id === id) return configFileEntries[i]
        }
        return null
    }

    function syncRawSource() {
        let id = currentTabInfo.id
        if (currentTabInfo.view === "configfiles") {
            const entry = configFilesViewer.currentEntry()
            id = entry ? entry.id : ""
        }
        rawSource = (id && fileContents[id]) ? fileContents[id] : ""
    }

    // === Window size (user-resizable; defaults from Theme popupHelp*) ===
    property int inspectorWidth: popupHelpWidth
    property int inspectorHeight: popupHelpHeight

    // === Public API (toggle from shell IPC: qs ipc call hyprConfigInsp toggle) ===
    // True when the window is open and not minimized — gates all live polling/timers.
    readonly property bool inspectorActive: inspectorWindow.visible && inspectorWindow.backingWindowVisible
    property bool open: inspectorWindow.visible
    signal opened()
    signal closed()

    property bool _initialLoadDone: false

    function toggle() {
        if (inspectorWindow.visible) hide()
        else show()
    }

    function stopBackgroundWork() {
        sysMonService.stopPolling()
        if (fileCat.running) fileCat.running = false
        if (statProcess.running) statProcess.running = false
        if (headerProcess.running) headerProcess.running = false
        if (systemProcess.running) systemProcess.running = false
        _loading = false
        _loadHandled = true
        _pendingMtimeId = ""
    }

    function handleWindowClosed() {
        hide()
    }

    onInspectorActiveChanged: {
        if (!inspectorActive)
            stopBackgroundWork()
    }

    // === Navigation + search ===
    property int currentTab: 0
    onCurrentTabChanged: syncRawSource()
    property string globalFilter: ""

    // === File cache (immutable-style updates via setFileContent/setFileMtime) ===
    property var fileContents: ({})
    property int fileContentsVersion: 0
    property var fileMtimes: ({})
    property int fileMtimesVersion: 0
    property string _pendingMtimeId: ""
    property var _parsedBinds: []
    property var _parsedEnv: []

    // === System Info tab (fastfetch --logo cachyos; lazy-loaded via systemDirty flag) ===
    property string systemOutput: ""
    property string systemHtml: ""
    property int systemDisplayVersion: 0
    property real systemContentWidth: 320
    property bool systemDirty: true
    property var systemEntries: []
    property string copiedValue: ""

    // === Header label (Hyprland version + distro from headerProcess) ===
    property string wmDistroLabel: ""

    // === Internal file-load coordination (do not bind from UI) ===
    property bool _loading: false
    property bool _loadHandled: false
    property bool _singleLoadPending: false
    property string _pendingFileId: ""
    property string _pendingFileView: ""

    function tabPath(tab) {
        if (!tab || !tab.file) return ""
        const base = tab.dir || configDir
        return base + "/" + tab.file
    }

    function setFileContent(id, text) {
        const copy = Object.assign({}, fileContents)
        copy[id] = text
        fileContents = copy
        fileContentsVersion++
    }

    function setFileMtime(id, epoch) {
        const copy = Object.assign({}, fileMtimes)
        copy[id] = epoch
        fileMtimes = copy
        fileMtimesVersion++
    }

    function formatFileMtime(id) {
        const epoch = fileMtimes[id]
        if (!epoch) return ""
        const seconds = parseInt(epoch, 10)
        if (!seconds || isNaN(seconds)) return ""
        const d = new Date(seconds * 1000)
        if (isNaN(d.getTime())) return ""
        const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        const pad = function(n) { return n < 10 ? "0" + n : "" + n }
        return "modified " + months[d.getMonth()] + " " + d.getDate() + ", " + d.getFullYear()
            + " " + pad(d.getHours()) + ":" + pad(d.getMinutes())
    }

    function mtimeSuffix(entry) {
        if (!entry || !entry.id) return ""
        const formatted = formatFileMtime(entry.id)
        return formatted ? "  ·  " + formatted : ""
    }

    function fileBackedEntries() {
        const entries = []
        for (let i = 0; i < tabs.length; i++) {
            const tab = tabs[i]
            if (_noFileTabViews.indexOf(tab.view) !== -1) continue
            if (tab.file) entries.push(tab)
        }
        for (let j = 0; j < configFileEntries.length; j++) {
            entries.push(configFileEntries[j])
        }
        return entries
    }

    function refreshFileMtime(tab) {
        if (!tab || !tab.file) return
        _pendingMtimeId = tab.id
        statProcess.running = false
        statProcess.command = ["stat", "-c", "%Y", tabPath(tab)]
        statProcess.running = true
    }

    function applyLoadedFile(id, view, text) {
        const body = text || ""
        setFileContent(id, body)
        if (view === "binds") _parsedBinds = parseKeybinds(body)
        else if (view === "env") _parsedEnv = parseEnvVars(body)
        if (currentTabInfo.id === id || (currentTabInfo.view === "configfiles" && configFilesViewer.selectedFileId === id)) {
            syncRawSource()
        }
    }

    function parseAllFileOutput(text) {
        if (!text) return
        let searchFrom = 0
        while (searchFrom < text.length) {
            const fileAt = text.indexOf("@@FILE:", searchFrom)
            const mtimeAt = text.indexOf("@@MTIME:", searchFrom)
            if (fileAt === -1 && mtimeAt === -1) break

            let marker = "@@FILE:"
            let markerAt = fileAt
            if (mtimeAt !== -1 && (fileAt === -1 || mtimeAt < fileAt)) {
                marker = "@@MTIME:"
                markerAt = mtimeAt
            }

            const idStart = markerAt + marker.length
            const idEnd = text.indexOf("@@", idStart)
            if (idEnd === -1) break
            const id = text.substring(idStart, idEnd)
            let bodyStart = idEnd + 2
            if (text[bodyStart] === "\n") bodyStart++

            const nextFile = text.indexOf("@@FILE:", bodyStart)
            const nextMtime = text.indexOf("@@MTIME:", bodyStart)
            let bodyEnd = text.length
            if (nextFile !== -1) bodyEnd = Math.min(bodyEnd, nextFile)
            if (nextMtime !== -1) bodyEnd = Math.min(bodyEnd, nextMtime)

            const body = text.substring(bodyStart, bodyEnd)
            if (marker === "@@MTIME:") {
                setFileMtime(id, body.trim())
            } else {
                const tab = tabs.find(function(t) { return t.id === id }) ||
                    fileEntryById(id)
                if (tab) applyLoadedFile(id, tab.view || "raw", body)
            }
            searchFrom = bodyEnd
        }
    }

    function finishFileLoad() {
        if (!_loading || _loadHandled) return
        _loadHandled = true
        const body = fileStdout.text || ""
        if (_singleLoadPending && _pendingFileId) {
            applyLoadedFile(_pendingFileId, _pendingFileView, body)
        } else {
            parseAllFileOutput(body)
        }
        _loading = false
        _singleLoadPending = false
        _pendingFileId = ""
        _pendingFileView = ""
        syncRawSource()
    }

    function startFileLoad(command, single, fileId, fileView) {
        _loading = true
        _loadHandled = false
        _singleLoadPending = single
        _pendingFileId = fileId || ""
        _pendingFileView = fileView || ""
        fileCat.running = false
        fileCat.command = command
        fileCat.running = true
    }

    function refreshAllFiles() {
        const parts = []
        const entries = fileBackedEntries()
        for (let i = 0; i < entries.length; i++) {
            const tab = entries[i]
            const path = tabPath(tab)
            const escaped = path.replace(/'/g, "'\\''")
            parts.push("printf '@@MTIME:" + tab.id + "@@\\n'")
            parts.push("stat -c '%Y' '" + escaped + "' 2>/dev/null || echo 0")
            parts.push("printf '@@FILE:" + tab.id + "@@\\n'")
            parts.push("cat '" + escaped + "'")
        }
        if (!parts.length) return
        startFileLoad(["sh", "-c", parts.join(" && ")], false, "", "")
    }

    function refreshConfigFileEntry(entry) {
        if (!entry || !entry.file) return
        refreshFileMtime(entry)
        configFilesViewer.refreshBat()
        startFileLoad(["cat", tabPath(entry)], true, entry.id, "raw")
    }

    function parseHeaderInfo(text) {
        if (!text) return ""
        const marker = "---OS---"
        const splitAt = text.indexOf(marker)
        const hyprLine = (splitAt === -1 ? text : text.substring(0, splitAt)).trim().split("\n")[0] || ""
        const osBlock = splitAt === -1 ? "" : text.substring(splitAt + marker.length)

        let wm = "Hyprland"
        const wmMatch = hyprLine.match(/Hyprland\s+([\d.]+)/i)
        if (wmMatch) wm = "Hyprland " + wmMatch[1]

        let distro = ""
        const prettyMatch = osBlock.match(/PRETTY_NAME="?([^"\n]+)"?/)
        if (prettyMatch) distro = prettyMatch[1]
        else {
            const nameMatch = osBlock.match(/NAME="?([^"\n]+)"?/)
            if (nameMatch) distro = nameMatch[1].replace(/ Linux$/i, "")
        }

        if (wm && distro) return wm + " \u2022 " + distro
        return wm || distro || ""
    }

    function refreshHeaderInfo() {
        headerProcess.running = false
        headerProcess.running = true
    }

    function refreshAll() {
        if (!inspectorActive) return
        refreshHeaderInfo()
        refreshAllFiles()
        const tab = currentTabInfo
        if (tab && tab.view === "raw" && tab.file) {
            batViewer.refresh()
        }
        if (tab && tab.view === "configfiles") {
            configFilesViewer.refreshBat()
        }
        if (tab && tab.view === "system") {
            refreshSystemInfo()
        } else {
            systemDirty = true
        }
        if (tab && tab.view === "runtime") {
            runtimeViewer.refresh()
        }
        if (tab && isSysmonMetricView(tab.view)) {
            sysMonService.refresh()
            if (tab.view === "network") networkViewer.refreshDetail()
        }
        processesViewer.refresh()
        if (tab && tab.view === "audio") {
            audioViewer.refresh()
        }
        if (tab && tab.view === "logs") {
            logsViewer.refresh(true)
        }
        if (tab && tab.view === "services") {
            servicesViewer.refresh()
        }
    }

    function refreshCurrentTab() {
        const tab = currentTabInfo
        if (!tab) return
        if (tab.view === "system") {
            refreshSystemInfo()
            return
        }
        if (tab.view === "runtime") {
            runtimeViewer.refresh()
            return
        }
        if (isSysmonMetricView(tab.view)) {
            sysMonService.refresh()
            if (tab.view === "network") networkViewer.refreshDetail()
            return
        }
        if (tab.view === "processes") {
            processesViewer.refresh()
            return
        }
        if (tab.view === "audio") {
            audioViewer.refresh()
            return
        }
        if (tab.view === "logs") {
            logsViewer.refresh(true)
            return
        }
        if (tab.view === "services") {
            servicesViewer.refresh()
            return
        }
        if (tab.view === "configfiles") {
            const entry = configFilesViewer.currentEntry()
            if (entry) refreshConfigFileEntry(entry)
            return
        }
        refreshFileMtime(tab)
        if (tab.view === "raw") {
            batViewer.refresh()
            startFileLoad(["cat", tabPath(tab)], true, tab.id, tab.view)
            return
        }
        startFileLoad(["cat", tabPath(tab)], true, tab.id, tab.view)
    }

    function editCurrentConfigFile() {
        const tab = currentTabInfo
        if (!tab) return
        if (tab.view === "configfiles") {
            const entry = configFilesViewer.currentEntry()
            if (!entry) return
            Quickshell.execDetached(["foot", "-e", "nano", tabPath(entry)])
            hide()
            return
        }
        if (!tab.file) return
        Quickshell.execDetached(["foot", "-e", "nano", tabPath(tab)])
        hide()
    }

    function statusText() {
        if (copiedValue) return "Copied to clipboard"
        const tab = currentTabInfo
        if (!tab) return ""
        const filterNote = (globalFilter && globalFilter.trim()) ? "  ·  filtered" : ""
        if (tab.view === "binds") return filteredBinds().length + " bindings  ·  " + tab.file + mtimeSuffix(tab) + filterNote
        if (tab.view === "env") return filteredEnv().length + " environment variables  ·  " + tab.file + mtimeSuffix(tab) + filterNote
        if (tab.view === "configfiles") {
            const entry = configFilesViewer.currentEntry()
            const file = entry ? entry.file : ""
            const id = entry ? entry.id : ""
            const body = rawSource || (id && fileContents[id]) || ""
            const lines = body.length ? body.split("\n").length : 0
            const chars = body.length
            return lines + " lines (" + chars + " chars)  ·  " + file + "  ·  bat" + mtimeSuffix(entry) + filterNote
        }
        if (tab.view === "raw") {
            const body = rawSource || fileContents[tab.id] || ""
            const lines = body.length ? body.split("\n").length : 0
            const chars = body.length
            return lines + " lines (" + chars + " chars)  ·  " + tab.file + "  ·  bat" + mtimeSuffix(tab) + filterNote
        }
        if (tab.view === "system") {
            const plain = stripAnsi(filteredSystemAnsi())
            const lines = plain ? plain.split("\n").filter(function(l) { return l.trim().length > 0 }).length : 0
            return lines + " lines  ·  fastfetch" + filterNote
        }
        if (tab.view === "cpu") {
            const util = sysMonService.data.cpu ? (sysMonService.data.cpu.util || 0).toFixed(0) : "0"
            const cores = sysMonService.data.cpu_info && sysMonService.data.cpu_info.cores ? sysMonService.data.cpu_info.cores : "?"
            return util + "% CPU  ·  " + cores + " cores  ·  live (" + (sysMonService.pollInterval / 1000).toFixed(1) + "s)" + filterNote
        }
        if (tab.view === "gpu") {
            const util = sysMonService.data.gpu ? (sysMonService.data.gpu.util || 0).toFixed(0) : "0"
            const vramUsed = sysMonService.data.gpu ? Math.round((sysMonService.data.gpu.vram_used || 0) / 1024) : 0
            const vramTotal = sysMonService.data.gpu ? Math.round((sysMonService.data.gpu.vram_total || 0) / 1024) : 0
            const name = sysMonService.data.gpu_info && sysMonService.data.gpu_info.name ? sysMonService.data.gpu_info.name : "GPU"
            return util + "% GPU  ·  " + vramUsed + "/" + vramTotal + " GB VRAM  ·  " + name + filterNote
        }
        if (tab.view === "memory") {
            const mem = sysMonService.data.memory
            const pct = mem ? (mem.ram_pct || 0).toFixed(0) : "0"
            const usedGiB = mem ? (mem.ram_used / 1024).toFixed(1) : "0"
            const totalGiB = mem ? (mem.ram_total / 1024).toFixed(1) : "0"
            return pct + "% Memory  ·  " + usedGiB + "/" + totalGiB + " GiB  ·  live (" + (sysMonService.pollInterval / 1000).toFixed(1) + "s)" + filterNote
        }
        if (tab.view === "temperature") {
            const cpuT = sysMonService.data.cpu ? (sysMonService.data.cpu.temp || 0).toFixed(0) : "0"
            const gpuT = sysMonService.data.gpu ? (sysMonService.data.gpu.temp || 0).toFixed(0) : "0"
            return "CPU " + cpuT + "°C  ·  GPU " + gpuT + "°C  ·  live (" + (sysMonService.pollInterval / 1000).toFixed(1) + "s)" + filterNote
        }
        if (tab.view === "network") {
            const net = sysMonService.data.network || {}
            const rx = formatNetRate(net.rx_rate)
            const tx = formatNetRate(net.tx_rate)
            const iface = net.iface || "—"
            const stats = net.conn_stats || {}
            const tcp = stats.tcp_established || 0
            const pub = networkViewer.detailData.public_ip || ""
            const pubNote = pub ? ("  ·  " + pub) : ""
            return "↓" + rx + "  ↑" + tx + "  ·  " + iface + "  ·  " + tcp + " TCP est" + pubNote
                + "  ·  live (" + (sysMonService.pollInterval / 1000).toFixed(1) + "s)" + filterNote
        }
        if (tab.view === "processes") {
            const stats = sysMonService.data.process_stats || {}
            const load = sysMonService.data.load || []
            const running = stats.running || 0
            const total = stats.total || 0
            const loadStr = load.length ? Number(load[0] || 0).toFixed(2) : "--"
            const rows = processesViewer.filteredProcesses().length
            const selNote = processesViewer.hasSelection ? ("  ·  " + processesViewer.selectionLabel()) : ""
            return rows + " shown  ·  " + total + " total  ·  " + running + " running  ·  load " + loadStr + selNote
                + "  ·  live (" + (sysMonService.pollInterval / 1000).toFixed(1) + "s)" + filterNote
        }
        if (tab.view === "audio") {
            const out = audioViewer.defaultSinkDevice()
            const inp = audioViewer.defaultSourceDevice()
            const outLabel = out ? (out.description || out.name) : "--"
            const inpLabel = inp ? (inp.description || inp.name) : "--"
            const sinks = audioViewer.filteredSinks().length
            const sources = audioViewer.filteredSources().length
            return outLabel + "  ·  " + inpLabel + "  ·  " + sinks + " sinks / " + sources + " sources" + filterNote
        }
        if (tab.view === "logs") {
            const lines = logsViewer.filteredLines().length
            const live = logsViewer.liveTail ? "live 3s" : "manual"
            return lines + " lines  ·  " + logsViewer.currentSourceLabel() + "  ·  last " + logsViewer.lineCount + "  ·  " + live + filterNote
        }
        if (tab.view === "services") {
            const rows = servicesViewer.filteredServices().length
            const running = servicesViewer.services.filter(function(s) {
                return (s.active_state || "").toLowerCase() === "active"
            }).length
            const failed = servicesViewer.services.filter(function(s) {
                const a = (s.active_state || "").toLowerCase()
                const sub = (s.sub_state || "").toLowerCase()
                return a === "failed" || sub.indexOf("fail") !== -1
            }).length
            const sel = servicesViewer.selectedService()
            const selNote = sel ? "  ·  " + servicesViewer.shortName(sel.id) : ""
            return rows + " shown  ·  " + running + " running  ·  " + failed + " failed" + selNote + filterNote
        }
        if (tab.view === "runtime") {
            const cat = runtimeViewer.currentCategory()
            const name = cat ? cat.label : "category"
            return runtimeViewer.filteredOptions().length + " options  ·  " + name + "  ·  live" + filterNote
        }
        return ""
    }

    function scrollTabIntoView() {
        if (!tabFlickable || !tabFlow || currentTab < 0 || currentTab >= tabs.length) return
        if (currentTab >= tabFlow.children.length) return
        const chip = tabFlow.children[currentTab]
        if (!chip || chip.y === undefined) return
        const top = chip.y
        const bottom = top + chip.height
        if (top < tabFlickable.contentY) {
            tabFlickable.contentY = top
        } else if (bottom > tabFlickable.contentY + tabFlickable.height) {
            tabFlickable.contentY = Math.max(0, bottom - tabFlickable.height)
        }
    }

    function focusActiveTabContent() {
        const tab = currentTabInfo
        if (tab.view === "runtime") runtimeViewer.focusScroll()
        else if (tab.view === "configfiles") configFilesViewer.focusScroll()
        else if (tab.view === "audio") audioViewer.focusScroll()
        else if (tab.view === "logs") logsViewer.focusScroll()
        else if (tab.view === "services") servicesViewer.focusScroll()
        else if (tab.view === "processes") processesViewer.focusScroll()
        else contentPanel.forceActiveFocus()
    }

    function focusGlobalSearch() {
        globalFilterField.forceActiveFocus()
        globalFilterField.selectAll()
    }

    function clearGlobalSearch() {
        globalFilterField.text = ""
        globalFilter = ""
    }

    function handleEscapeKey() {
        if (globalFilterField.activeFocus || (globalFilter && globalFilter.trim().length > 0)) {
            clearGlobalSearch()
            if (globalFilterField.activeFocus)
                globalFilterField.forceActiveFocus()
            else
                focusActiveTabContent()
            return
        }
        hide()
    }

    function resetTabScroll(tab) {
        if (!tab) return
        if (tab.view === "binds") bindsFlickable.contentY = 0
        else if (tab.view === "env") envFlickable.contentY = 0
        else if (tab.view === "system") systemFlickable.contentY = 0
        else if (tab.view === "cpu") cpuViewer.resetScroll()
        else if (tab.view === "gpu") gpuViewer.resetScroll()
        else if (tab.view === "memory") memoryViewer.resetScroll()
        else if (tab.view === "temperature") tempViewer.resetScroll()
        else if (tab.view === "network") networkViewer.resetScroll()
        else if (tab.view === "processes") processesViewer.resetScroll()
        else if (tab.view === "audio") audioViewer.resetScroll()
        else if (tab.view === "logs") logsViewer.resetScroll()
        else if (tab.view === "services") servicesViewer.resetScroll()
        else if (tab.view === "runtime") runtimeViewer.resetScroll()
        else if (tab.view === "configfiles") configFilesViewer.resetScroll()
        else if (tab.view === "raw") batViewer.resetScroll()
    }

    function activateTab(index) {
        if (index < 0 || index >= tabs.length) return
        currentTab = index
        const tab = tabs[index]
        batLanguage = (tab.view === "raw" && tab.batLanguage) ? tab.batLanguage : ""
        batFilePath = (tab.view === "raw" && tab.file) ? tabPath(tab) : ""
        syncRawSource()
        if (tab.view === "system" && systemDirty) {
            refreshSystemInfo()
        } else if (tab.view === "runtime") {
            runtimeViewer.ensureLoaded()
        } else if (isSysmonMetricView(tab.view)) {
            sysMonService.refresh()
            if (tab.view === "network") networkViewer.refreshDetail()
        } else if (tab.view === "processes") {
            processesViewer.refresh()
        } else if (tab.view === "audio") {
            audioViewer.refresh()
        } else if (tab.view === "logs") {
            logsViewer.refresh(false)
        } else if (tab.view === "services") {
            servicesViewer.refresh()
        } else if (tab.view === "configfiles") {
            const entry = configFilesViewer.currentEntry()
            if (entry && !fileContents[entry.id]) refreshConfigFileEntry(entry)
            else configFilesViewer.refreshBat()
        } else if (tab.file && !fileContents[tab.id]) {
            refreshCurrentTab()
        }
        scrollTabIntoView()
        Qt.callLater(function() {
            root.focusActiveTabContent()
            root.resetTabScroll(tab)
        })
    }

    function nextTab() {
        activateTab((currentTab + 1) % tabs.length)
    }

    function prevTab() {
        activateTab((currentTab - 1 + tabs.length) % tabs.length)
    }

    function show() {
        inspectorWindow.visible = true
        if (!_initialLoadDone) {
            _initialLoadDone = true
            refreshHeaderInfo()
            refreshAllFiles()
        }
        opened()
        const tab = currentTabInfo
        batLanguage = (tab.view === "raw" && tab.batLanguage) ? tab.batLanguage : ""
        batFilePath = (tab.view === "raw" && tab.file) ? tabPath(tab) : ""
        if (!wmDistroLabel) refreshHeaderInfo()
        if (tab.view === "system" && systemDirty) refreshSystemInfo()
        else if (tab.view === "runtime") runtimeViewer.ensureLoaded()
        else if (isSysmonMetricView(tab.view)) {
            sysMonService.refresh()
            if (tab.view === "network") networkViewer.refreshDetail()
        }
        else if (tab.view === "processes") processesViewer.refresh()
        else if (tab.view === "audio") audioViewer.refresh()
        else if (tab.view === "logs") logsViewer.refresh(false)
        else if (tab.view === "services") servicesViewer.refresh()
        else if (tab.view === "configfiles") {
            const entry = configFilesViewer.currentEntry()
            if (entry && !fileContents[entry.id]) refreshConfigFileEntry(entry)
            else configFilesViewer.refreshBat()
        }
        Qt.callLater(function() {
            scrollTabIntoView()
            root.focusActiveTabContent()
            root.resetTabScroll(tab)
        })
    }

    function hide() {
        const wasVisible = inspectorWindow.visible
        inspectorWindow.visible = false
        stopBackgroundWork()
        if (wasVisible)
            closed()
    }

    // === Background I/O: batch/single config file reads (@@FILE:/@@MTIME: protocol) ===
    Io.Process {
        id: fileCat
        running: false
        stdout: Io.StdioCollector {
            id: fileStdout
            onStreamFinished: finishFileLoad()
        }
        onExited: finishFileLoad()
    }

    // === Background I/O: per-file mtime for status line ("modified …" suffix) ===
    Io.Process {
        id: statProcess
        running: false
        stdout: Io.StdioCollector {
            id: statStdout
            onStreamFinished: {
                if (root._pendingMtimeId) {
                    root.setFileMtime(root._pendingMtimeId, (statStdout.text || "").trim())
                    root._pendingMtimeId = ""
                }
            }
        }
        onExited: {
            if (root._pendingMtimeId) {
                root.setFileMtime(root._pendingMtimeId, (statStdout.text || "").trim())
                root._pendingMtimeId = ""
            }
        }
    }

    Component.onCompleted: {
        syncRawSource()
    }

    // === Background I/O: header subtitle (Hyprland version + distro pretty name) ===
    Io.Process {
        id: headerProcess
        command: ["sh", "-c", "hyprctl version 2>/dev/null | head -1; printf '\\n---OS---\\n'; rg '^PRETTY_NAME=' /etc/os-release 2>/dev/null || grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null || true"]
        running: false
        stdout: Io.StdioCollector {
            id: headerStdout
            onStreamFinished: {
                const label = root.parseHeaderInfo(headerStdout.text || "")
                if (label) root.wmDistroLabel = label
            }
        }
        onExited: {
            const label = root.parseHeaderInfo(headerStdout.text || "")
            if (label) root.wmDistroLabel = label
        }
    }

    // Parses hl.bind() lines annotated with trailing help comments:
    //   --# description                 (uncategorized; legacy)
    //   --#Category# description        (grouped under Category)
    // Only active (non-commented) binds with a --# annotation are shown.
    function parseKeybinds(text) {
        if (!text) return []
        const lines = text.split("\n")
        const out = []
        for (let i = 0; i < lines.length; i++) {
            const originalLine = lines[i]
            let line = originalLine.trim()
            if (!line.includes("hl.bind(")) continue
            if (line.startsWith("--hl.bind") || line.startsWith("----hl.bind")) continue
            if (!originalLine.includes("--#")) continue

            const bindIdx = line.indexOf("hl.bind(")
            if (bindIdx === -1) continue
            const afterOpen = line.substring(bindIdx + 8)
            let depth = 0
            let keyEnd = -1
            for (let j = 0; j < afterOpen.length; j++) {
                const ch = afterOpen[j]
                if (ch === '(' || ch === '{' || ch === '[') depth++
                else if (ch === ')' || ch === '}' || ch === ']') depth--
                else if (ch === ',' && depth === 0) {
                    keyEnd = j
                    break
                }
            }
            if (keyEnd === -1) continue
            let keyExpr = afterOpen.substring(0, keyEnd).trim()
            keyExpr = keyExpr.replace(/mainMod\s*\.\.\s*/g, "SUPER + ")
            keyExpr = keyExpr.replace(/["']/g, "")
            keyExpr = keyExpr.replace(/\s*\+\s*/g, " + ")
            keyExpr = keyExpr.replace(/\+\s*\+\s*/g, "+ ")
            keyExpr = keyExpr.replace(/\s+/g, " ").trim()

            let description = ""
            let category = ""
            // Category form: --#Category# description  (category may contain spaces)
            const catMatch = originalLine.match(/--#([^#\n]+)#\s*(.*)$/)
            if (catMatch) {
                category = catMatch[1].trim()
                description = (catMatch[2] || "").trim()
            } else {
                const descMatch = originalLine.match(/--#\s*(.+)$/)
                if (descMatch) description = descMatch[1].trim()
            }

            out.push({ key: keyExpr, action: description, comment: "", category: category })
        }
        return out
    }

    function parseEnvVars(text) {
        if (!text) return []
        const lines = text.split("\n")
        const out = []
        for (let i = 0; i < lines.length; i++) {
            const originalLine = lines[i]
            let line = originalLine.trim()
            if (!line.includes("hl.env(")) continue
            if (line.startsWith("--hl.env") || line.startsWith("----hl.env")) continue
            const m = line.match(/^hl\.env\(\s*["']([^"']+)["']\s*,\s*(.+?)\s*\)/)
            if (!m) continue
            let value = m[2].trim()
            const quoted = value.match(/^["']([^"']*)["']$/)
            if (quoted) value = quoted[1]
            let comment = ""
            const hashMatch = originalLine.match(/--#\s*(.+)$/)
            if (hashMatch) comment = hashMatch[1].trim()
            else {
                const oldMatch = originalLine.match(/--\s*(.+)$/)
                if (oldMatch) comment = oldMatch[1].trim()
            }
            out.push({ key: m[1], value: value, comment: comment })
        }
        return out
    }

    // ANSI helpers for System Info (same approach as BatSyntaxView; scoped here to avoid coupling)
    function stripAnsi(text) {
        if (!text) return ""
        return text.replace(/\x1b\[[0-9;]*m/g, "")
    }

    function escapeHtml(text) {
        return String(text)
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
    }

    function colorToHex(color) {
        if (typeof color === "string") return color
        function hex(channel) {
            const value = Math.round(channel * 255).toString(16)
            return value.length === 1 ? "0" + value : value
        }
        return "#" + hex(color.r) + hex(color.g) + hex(color.b)
    }

    function rgbHex(r, g, b) {
        function hex(n) {
            const s = Math.round(n).toString(16)
            return s.length === 1 ? "0" + s : s
        }
        return "#" + hex(r) + hex(g) + hex(b)
    }

    function ansi16(code) {
        const palette = {
            30: "#141a24", 31: "#FF3D8A", 32: "#2ee59a", 33: "#f0d060",
            34: "#00F0E0", 35: "#c084fc", 36: "#00D4C8", 37: "#f0f4fc",
            90: "#6e7a90", 91: "#FF3D8A", 92: "#2ee59a", 93: "#f0d060",
            94: "#00F0E0", 95: "#c084fc", 96: "#00D4C8", 97: "#ffffff"
        }
        return palette[code] || null
    }

    function ansi256(code) {
        if (code < 16) return ansi16(code < 8 ? 30 + code : 90 + (code - 8))
        if (code >= 232) {
            const gray = (code - 232) * 10 + 8
            return rgbHex(gray, gray, gray)
        }
        const cc = code - 16
        const r = Math.floor(cc / 36)
        const g = Math.floor(cc / 6) % 6
        const b = cc % 6
        const levels = [0, 95, 135, 175, 215, 255]
        return rgbHex(levels[r], levels[g], levels[b])
    }

    function applyAnsiCode(parts, state) {
        const next = {
            fg: state.fg,
            bg: state.bg,
            bold: state.bold
        }
        for (let i = 0; i < parts.length; i++) {
            const p = parts[i]
            if (p === 0 || p === "") {
                next.fg = colorToHex(text)
                next.bg = null
                next.bold = false
            } else if (p === 1) {
                next.bold = true
            } else if (p === 22) {
                next.bold = false
            } else if (p === 39) {
                next.fg = colorToHex(text)
            } else if (p === 49) {
                next.bg = null
            } else if (p >= 30 && p <= 37) {
                next.fg = ansi16(p)
            } else if (p >= 90 && p <= 97) {
                next.fg = ansi16(p)
            } else if (p >= 40 && p <= 47) {
                next.bg = ansi16(p - 10)
            } else if (p >= 100 && p <= 107) {
                next.bg = ansi16(p - 10)
            } else if (p === 38 && parts[i + 1] === 2 && i + 4 < parts.length) {
                next.fg = rgbHex(parts[i + 2], parts[i + 3], parts[i + 4])
                i += 4
            } else if (p === 38 && parts[i + 1] === 5 && i + 2 < parts.length) {
                next.fg = ansi256(parts[i + 2])
                i += 2
            } else if (p === 48 && parts[i + 1] === 2 && i + 4 < parts.length) {
                next.bg = rgbHex(parts[i + 2], parts[i + 3], parts[i + 4])
                i += 4
            } else if (p === 48 && parts[i + 1] === 5 && i + 2 < parts.length) {
                next.bg = ansi256(parts[i + 2])
                i += 2
            }
        }
        return next
    }

    function ansiToHtml(raw) {
        if (!raw) return ""
        const defaultHex = colorToHex(text)
        const fontFamily = fontMono || "monospace"
        const fontSize = 13
        const lines = raw.split("\n")
        const htmlLines = []

        for (let li = 0; li < lines.length; li++) {
            const line = lines[li]
            let state = { fg: defaultHex, bg: null, bold: false }
            let html = ""
            let i = 0

            while (i < line.length) {
                if (line.charCodeAt(i) === 27 && line[i + 1] === "[") {
                    let j = i + 2
                    while (j < line.length && line[j] !== "m") j++
                    const codes = line.substring(i + 2, j).split(";").map(function(v) {
                        const n = parseInt(v, 10)
                        return isNaN(n) ? v : n
                    })
                    state = applyAnsiCode(codes, state)
                    i = j + 1
                    continue
                }

                let j = i
                while (j < line.length) {
                    if (line.charCodeAt(j) === 27 && line[j + 1] === "[") break
                    j++
                }

                if (j > i) {
                    const chunk = escapeHtml(line.substring(i, j)).replace(/ /g, "&nbsp;")
                    const weight = state.bold ? "font-weight:700;" : ""
                    const bg = state.bg ? ("background-color:" + state.bg + ";") : ""
                    html += '<span style="color:' + state.fg + ";" + weight + bg + '">' + chunk + "</span>"
                }
                i = j
            }

            htmlLines.push(html.length ? html : "&nbsp;")
        }

        return '<pre style="margin:0;font-family:' + fontFamily + ";font-size:" + fontSize
            + "px;color:" + defaultHex + '">' + htmlLines.join("<br/>") + "</pre>"
    }

    function filteredSystemAnsi() {
        if (!systemOutput) return ""
        const q = filterQuery()
        if (!q) return systemOutput
        return systemOutput.split("\n").filter(function(line) {
            return stripAnsi(line).toLowerCase().indexOf(q) !== -1
        }).join("\n")
    }

    function rebuildSystemDisplay() {
        const src = filteredSystemAnsi()
        const plain = stripAnsi(src)
        let maxLen = 40
        if (plain) {
            const lines = plain.split("\n")
            for (let i = 0; i < lines.length; i++) {
                if (lines[i].length > maxLen) maxLen = lines[i].length
            }
        }
        systemContentWidth = Math.max(320, Math.ceil(maxLen * 13 * 0.62) + 24)
        systemHtml = ansiToHtml(src)
        systemDisplayVersion++
    }

    function parseFastfetchOutput(raw) {
        if (!raw) return []
        // Strip ANSI so key:value parsing works when logo/colors are present
        const lines = stripAnsi(raw).split("\n")
        const entries = []
        for (let line of lines) {
            line = line.trim()
            if (!line) continue
            if (line.includes("@") && !line.includes(":")) continue
            if (line.match(/^[-=]+$/)) continue
            const idx = line.indexOf(":")
            if (idx > 0) {
                const label = line.substring(0, idx).trim()
                // Skip logo ASCII art (punctuation / decoration segments)
                if (!/^[A-Za-z0-9]/.test(label)) continue
                if (/[-*+=]{2,}/.test(label)) continue
                let value = line.substring(idx + 1).trim()
                const lower = label.toLowerCase()
                if (lower === "terminal" || lower.includes("font")) continue
                if (value) entries.push({ label: label, value: value })
            }
        }
        return entries
    }

    // Key/env semantic colors — delegated to config helpers (edit colors in config.qml)
    function keyPillColor(key) { return th.inspKeyPillColor(key) }
    function keyPillTextColor(key) { return th.inspKeyPillTextColor(key) }
    function envKeyIsHighlight(key) { return th.inspEnvKeyIsHighlight(key) }
    function envKeyColor(key) { return th.inspEnvKeyColor(key) }
    function envValueColor(key, value) { return th.inspEnvValueColor(key, value) }

    // Environment table column widths (ratios from Theme.inspEnv*)
    function envTableContentWidth(totalWidth) {
        return Math.max(0, totalWidth - envTableSideMargin * 2)
    }

    function envUsableInnerWidth(totalWidth) {
        return Math.max(0, envTableContentWidth(totalWidth) - envTableColSpacing * 2)
    }

    function envVariableColumnWidth(totalWidth) {
        const usable = envUsableInnerWidth(totalWidth)
        const target = Math.round(usable * th.inspEnvVarColRatio)
        return Math.max(th.inspEnvVarColMinWidth, Math.min(target, th.inspEnvVarColMaxWidth))
    }

    function envValueColumnWidth(totalWidth) {
        const usable = envUsableInnerWidth(totalWidth)
        const target = Math.round(usable * th.inspEnvValueColRatio)
        return Math.max(th.inspEnvValueColMinWidth, Math.min(target, th.inspEnvValueColMaxWidth))
    }

    function envDescriptionColumnWidth(totalWidth) {
        const usable = envUsableInnerWidth(totalWidth)
        return Math.max(th.inspEnvDescColMinWidth,
            usable - envVariableColumnWidth(totalWidth) - envValueColumnWidth(totalWidth))
    }

    function envTableWidth(viewportWidth) {
        return envTableSideMargin * 2
            + envVariableColumnWidth(viewportWidth)
            + envValueColumnWidth(viewportWidth)
            + envDescriptionColumnWidth(viewportWidth)
            + envTableColSpacing * 2
    }

    function refreshSystemInfo() {
        systemProcess.running = false
        systemProcess.running = true
        systemDirty = false
        copiedValue = ""
    }

    function copyToClipboard(text) {
        Quickshell.execDetached([
            "sh", "-c",
            'printf "%s" "$1" | wl-copy',
            "wl-copy",
            text
        ])
        copiedValue = text
        Qt.callLater(function() {
            if (copiedValue === text) copiedValue = ""
        }, 1200)
    }

    function openDocumentationUrl(url) {
        if (!url) return
        Quickshell.execDetached(["xdg-open", url])
    }

    readonly property var systemDocLinks: [
        {
            label: "Hardware specifications",
            url: "https://system76.com/tech-docs/models/thelio-mira-r4-n3/specs/",
            note: "Thelio Mira R4 — CPU, GPU, storage, and port details"
        },
        {
            label: "Repairs & maintenance",
            url: "https://system76.com/tech-docs/models/thelio-mira-r4-n3/repairs/",
            note: "Service manual and repair guides"
        },
        {
            label: "Thelio Io board",
            url: "https://github.com/system76/thelio-io",
            note: "Daughterboard hardware documentation"
        },
        {
            label: "Thelio Io firmware",
            url: "https://github.com/system76/thelio-io-firmware",
            note: "Open-source firmware source"
        },
        {
            label: "System76 support",
            url: "https://system76.com/support",
            note: "Warranty, drivers, and customer support"
        }
    ]

    readonly property bool canCopyTab: {
        const view = currentTabInfo.view
        return view === "raw" || view === "runtime" || view === "configfiles" || view === "logs"
    }

    function copyCurrentTabContent() {
        const tab = currentTabInfo
        if (!tab) return
        if (tab.view === "raw") {
            const text = batViewer.plainText()
            if (text) copyToClipboard(text)
            return
        }
        if (tab.view === "configfiles") {
            const text = configFilesViewer.plainText()
            if (text) copyToClipboard(text)
            return
        }
        if (tab.view === "runtime") {
            const text = runtimeViewer.exportText()
            if (text) copyToClipboard(text)
            return
        }
        if (tab.view === "logs") {
            const text = logsViewer.plainText()
            if (text) copyToClipboard(text)
        }
    }

    // === Background I/O: System Info tab (fastfetch + cachyos logo; only when tab activated) ===
    // --pipe false forces ANSI colors even when stdout is not a TTY (Quickshell Process).
    Io.Process {
        id: systemProcess
        command: ["fastfetch", "--logo", "cachyos", "--pipe", "false"]
        running: false
        stdout: Io.SplitParser {
            splitMarker: "\n"
            onRead: (line) => { systemOutput += line + "\n" }
        }
        onStarted: {
            systemOutput = ""
            systemHtml = ""
        }
        onExited: (code) => {
            if (code !== 0 && systemOutput.trim() === "") {
                systemOutput = "Failed to collect system information (exit code " + code + ")"
                systemEntries = []
            } else {
                systemEntries = parseFastfetchOutput(systemOutput)
            }
            rebuildSystemDisplay()
        }
    }

    function filterQuery() {
        return (globalFilter && globalFilter.trim()) ? globalFilter.toLowerCase().trim() : ""
    }

    function formatNetRate(bytesPerSec) {
        const b = Number(bytesPerSec) || 0
        const kb = b / 1024
        if (kb >= 1024) return (kb / 1024).toFixed(1) + " MB/s"
        return kb.toFixed(1) + " KB/s"
    }

    function filteredBinds() {
        const q = filterQuery()
        if (!q) return _parsedBinds
        return _parsedBinds.filter(function(b) {
            return (b.key && b.key.toLowerCase().indexOf(q) !== -1) ||
                   (b.action && b.action.toLowerCase().indexOf(q) !== -1) ||
                   (b.comment && b.comment.toLowerCase().indexOf(q) !== -1) ||
                   (b.category && b.category.toLowerCase().indexOf(q) !== -1)
        })
    }

    // Groups filtered binds by category for the Key Bindings tab.
    // Order follows first appearance in keybindings.lua. When no bind has a
    // category, returns a single header-less group so the UI stays flat.
    // Uncategorized binds mixed with categorized ones land under "Other".
    function groupedFilteredBinds() {
        const binds = filteredBinds()
        let hasCategory = false
        for (let i = 0; i < binds.length; i++) {
            if (binds[i].category && binds[i].category.length > 0) {
                hasCategory = true
                break
            }
        }
        if (!hasCategory)
            return [{ category: "", binds: binds }]

        const groups = []
        const indexByCat = ({})
        for (let i = 0; i < binds.length; i++) {
            const b = binds[i]
            const cat = (b.category && b.category.length > 0) ? b.category : "Other"
            if (indexByCat[cat] === undefined) {
                indexByCat[cat] = groups.length
                groups.push({ category: cat, binds: [] })
            }
            groups[indexByCat[cat]].binds.push(b)
        }
        return groups
    }

    function filteredEnv() {
        const q = filterQuery()
        if (!q) return _parsedEnv
        return _parsedEnv.filter(function(e) {
            return (e.key && e.key.toLowerCase().indexOf(q) !== -1) ||
                   (e.value && e.value.toLowerCase().indexOf(q) !== -1) ||
                   (e.comment && e.comment.toLowerCase().indexOf(q) !== -1)
        })
    }

    function filteredSystemEntries() {
        const q = filterQuery()
        if (!q) return systemEntries
        return systemEntries.filter(function(e) {
            return (e.label && e.label.toLowerCase().indexOf(q) !== -1) ||
                   (e.value && e.value.toLowerCase().indexOf(q) !== -1)
        })
    }

    function flickableMaxY(flickable) {
        if (!flickable) return 0
        return Math.max(0, flickable.contentHeight - flickable.height)
    }

    function scrollFlickablePage(flickable, direction) {
        const maxY = flickableMaxY(flickable)
        if (maxY <= 0) return
        const page = Math.max(80, flickable.height * 0.85)
        flickable.contentY = Math.max(0, Math.min(maxY, flickable.contentY + direction * page))
    }

    function scrollFlickableLine(flickable, direction, step) {
        const maxY = flickableMaxY(flickable)
        if (maxY <= 0) return
        const lineStep = step || 28
        flickable.contentY = Math.max(0, Math.min(maxY, flickable.contentY + direction * lineStep))
    }

    function flickableWheelScroll(flickable, deltaY, step) {
        const maxY = flickableMaxY(flickable)
        if (maxY <= 0) return
        const lineStep = step || 42
        const ticks = deltaY / 120
        flickable.contentY = Math.max(0, Math.min(maxY, flickable.contentY - ticks * lineStep))
    }

    function pageContentScroll(direction) {
        const tab = currentTabInfo
        if (!tab) return
        if (tab.view === "binds") scrollFlickablePage(bindsFlickable, direction)
        else if (tab.view === "env") scrollFlickablePage(envFlickable, direction)
        else if (tab.view === "raw") batViewer.pageScroll(direction)
        else if (tab.view === "configfiles") configFilesViewer.pageScroll(direction)
        else if (tab.view === "runtime") runtimeViewer.pageScroll(direction)
        else if (tab.view === "cpu") cpuViewer.pageScroll(direction)
        else if (tab.view === "gpu") gpuViewer.pageScroll(direction)
        else if (tab.view === "memory") memoryViewer.pageScroll(direction)
        else if (tab.view === "temperature") tempViewer.pageScroll(direction)
        else if (tab.view === "network") networkViewer.pageScroll(direction)
        else if (tab.view === "processes") processesViewer.pageScroll(direction)
        else if (tab.view === "audio") audioViewer.pageScroll(direction)
        else if (tab.view === "logs") logsViewer.pageScroll(direction)
        else if (tab.view === "services") servicesViewer.pageScroll(direction)
        else if (tab.view === "system") scrollFlickablePage(systemFlickable, direction)
    }

    function lineContentScroll(direction) {
        const tab = currentTabInfo
        if (!tab) return
        if (tab.view === "binds") scrollFlickableLine(bindsFlickable, direction)
        else if (tab.view === "env") scrollFlickableLine(envFlickable, direction)
        else if (tab.view === "raw") batViewer.lineScroll(direction)
        else if (tab.view === "configfiles") configFilesViewer.lineScroll(direction)
        else if (tab.view === "runtime") runtimeViewer.lineScroll(direction)
        else if (tab.view === "cpu") cpuViewer.lineScroll(direction)
        else if (tab.view === "gpu") gpuViewer.lineScroll(direction)
        else if (tab.view === "memory") memoryViewer.lineScroll(direction)
        else if (tab.view === "temperature") tempViewer.lineScroll(direction)
        else if (tab.view === "network") networkViewer.lineScroll(direction)
        else if (tab.view === "processes") processesViewer.lineScroll(direction)
        else if (tab.view === "audio") audioViewer.lineScroll(direction)
        else if (tab.view === "logs") logsViewer.lineScroll(direction)
        else if (tab.view === "services") servicesViewer.lineScroll(direction)
        else if (tab.view === "system") scrollFlickableLine(systemFlickable, direction)
    }

    FloatingWindow {
        id: inspectorWindow
        visible: false
        title: "Hyprland Config Inspector"
        color: "transparent"
        implicitWidth: root.inspectorWidth
        implicitHeight: root.inspectorHeight
        minimumSize: Qt.size(root.inspMinWidth, root.inspMinHeight)

        onClosed: root.handleWindowClosed()

        Shortcut {
            sequence: "Escape"
            enabled: inspectorWindow.visible
            onActivated: root.handleEscapeKey()
        }

        Shortcut {
            sequence: "Ctrl+F"
            enabled: inspectorWindow.visible
            onActivated: root.focusGlobalSearch()
        }

        Shortcut {
            sequence: "Ctrl+R"
            enabled: inspectorWindow.visible
            onActivated: root.refreshAll()
        }

        Shortcut {
            sequence: "Ctrl+E"
            enabled: inspectorWindow.visible && root.hasConfigFile
            onActivated: root.editCurrentConfigFile()
        }

        Shortcut {
            sequence: "Tab"
            enabled: inspectorWindow.visible && !globalFilterField.activeFocus
            onActivated: root.nextTab()
        }

        Shortcut {
            sequence: "Shift+Tab"
            enabled: inspectorWindow.visible && !globalFilterField.activeFocus
            onActivated: root.prevTab()
        }

        Shortcut {
            sequence: "PgUp"
            enabled: inspectorWindow.visible && !globalFilterField.activeFocus
            onActivated: root.pageContentScroll(-1)
        }

        Shortcut {
            sequence: "PgDown"
            enabled: inspectorWindow.visible && !globalFilterField.activeFocus
            onActivated: root.pageContentScroll(1)
        }

        Shortcut {
            sequence: "Up"
            enabled: inspectorWindow.visible && !globalFilterField.activeFocus
            onActivated: root.lineContentScroll(-1)
        }

        Shortcut {
            sequence: "Down"
            enabled: inspectorWindow.visible && !globalFilterField.activeFocus
            onActivated: root.lineContentScroll(1)
        }

        Rectangle {
            id: contentPanel
            anchors.fill: parent
            radius: root.popupRadiusLarge
            color: root.inspUseGradient ? "transparent" : root.inspWindowBg
            border.width: 1
            border.color: root.inspWindowBorder
            focus: inspectorWindow.visible

            // Vertical gradient fill (Theme: inspUseGradient + inspGradientTop/Bottom)
            gradient: root.inspUseGradient ? contentPanelGradient : null

            Gradient {
                id: contentPanelGradient
                GradientStop { position: 0.0; color: root.inspGradientTop }
                GradientStop { position: 1.0; color: root.inspGradientBottom }
            }

            Keys.onPressed: (event) => {
                if (globalFilterField.activeFocus) return
                const tab = root.currentTabInfo
                if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                    if (tab.view === "runtime" && runtimeViewer.handleNavKey(event)) {
                        runtimeViewer.focusScroll()
                        return
                    }
                    if (tab.view === "configfiles" && configFilesViewer.handleNavKey(event)) {
                        configFilesViewer.focusScroll()
                        return
                    }
                    if (tab.view === "logs" && logsViewer.handleNavKey(event)) {
                        logsViewer.focusScroll()
                        return
                    }
                }
                if (event.key === Qt.Key_PageUp) {
                    root.pageContentScroll(-1)
                    event.accepted = true
                } else if (event.key === Qt.Key_PageDown) {
                    root.pageContentScroll(1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                    root.lineContentScroll(-1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                    root.lineContentScroll(1)
                    event.accepted = true
                } else if (tab.view === "runtime" && runtimeViewer.handleNavKey(event)) {
                    runtimeViewer.focusScroll()
                } else if (tab.view === "configfiles" && configFilesViewer.handleNavKey(event)) {
                    configFilesViewer.focusScroll()
                } else if (tab.view === "logs" && logsViewer.handleNavKey(event)) {
                    logsViewer.focusScroll()
                }
            }

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1.5
                color: root.inspWindowHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.inspContentPadding
                spacing: root.inspSectionSpacing

                Item {
                    id: titleBar
                    Layout.fillWidth: true
                    Layout.preferredHeight: titleColumn.implicitHeight

                    ColumnLayout {
                        id: titleColumn
                        anchors.fill: parent
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text { text: "Hyprland Config Inspector"; color: root.text; font.pixelSize: root.inspTitleFontSize; font.bold: true }
                            Item { Layout.fillWidth: true }

                            Rectangle {
                                width: th.inspRefreshButtonWidth
                                height: th.inspHeaderButtonHeight
                                radius: th.buttonRadius
                                color: refreshAllMa.containsMouse ? root.surface : "transparent"
                                border.width: 1
                                border.color: th.pillBorder
                                Text { anchors.centerIn: parent; text: "Refresh All"; color: root.accent; font.pixelSize: root.inspStatusFontSize }
                                MouseArea {
                                    id: refreshAllMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.refreshAll()
                                }
                            }

                            Rectangle {
                                width: th.inspCloseButtonSize
                                height: th.inspCloseButtonSize
                                radius: th.buttonRadius
                                color: closeMa.containsMouse ? root.surface : "transparent"
                                Text { anchors.centerIn: parent; text: "✕"; color: root.text; font.pixelSize: 14 }
                                MouseArea {
                                    id: closeMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.hide()
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            Text {
                                text: root.wmDistroLabel || "Hyprland"
                                color: root.accent
                                font.pixelSize: root.inspSubtitleFontSize
                                font.bold: true
                            }

                            Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 14; color: th.inspHeaderDivider }

                            Text {
                                text: "SUPER + ?  ·  Tab / Shift+Tab  ·  Ctrl+E (edit)  ·  PgUp / PgDown / ↑ / ↓"
                                color: root.overlay
                                font.pixelSize: root.inspSubtitleFontSize
                            }

                            Item { Layout.fillWidth: true }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        z: -1
                        cursorShape: Qt.SizeAllCursor
                        onPressed: inspectorWindow.startSystemMove()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Flickable {
                        id: tabFlickable
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(Math.max(34, tabFlow.implicitHeight), root.tabBarMaxHeight)
                        contentWidth: width
                        contentHeight: tabFlow.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.VerticalFlick

                        ScrollBar.vertical: ScrollBar {
                            id: tabBarScrollBar
                            policy: tabFlickable.contentHeight > tabFlickable.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                            contentItem: Rectangle {
                                implicitWidth: root.inspScrollBarWidth
                                radius: root.inspScrollBarRadius
                                color: tabBarScrollBar.pressed ? root.accent : root.inspScrollBarIdle
                            }
                        }

                        Flow {
                            id: tabFlow
                            width: parent.width
                            spacing: root.inspTabSpacing

                            Repeater {
                                model: root.tabs
                                delegate: Rectangle {
                                    required property int index
                                    required property var modelData

                                    height: root.inspTabHeight
                                    width: tabLabel.implicitWidth + root.inspTabHPadding
                                    radius: root.inspTabRadius
                                    color: (root.currentTab === index) ? root.inspTabActiveBg
                                        : (tma.containsMouse ? root.inspTabHoverBg : "transparent")
                                    border.width: (root.currentTab === index) ? 1 : 0
                                    border.color: root.inspTabActiveBorder

                                    Text {
                                        id: tabLabel
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        color: (root.currentTab === index) ? root.accent : root.text
                                        font.pixelSize: root.inspTabFontSize
                                        font.bold: (root.currentTab === index)
                                    }

                                    MouseArea {
                                        id: tma
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.activateTab(index)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: root.inspSearchWidth
                        Layout.preferredHeight: root.inspSearchHeight
                        radius: root.inspSearchRadius
                        color: root.surface
                        border.width: 1
                        border.color: th.pillBorder

                        TextField {
                            id: globalFilterField
                            anchors.fill: parent
                            anchors.margins: th.inspSearchPadding
                            z: 2
                            focusPolicy: Qt.StrongFocus
                            activeFocusOnPress: true
                            selectByMouse: true
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.text
                            font.pixelSize: th.inspSearchFontSize
                            selectionColor: root.inspSearchSelectionBg
                            selectedTextColor: root.text
                            placeholderText: "Search all tabs..."
                            placeholderTextColor: root.overlay
                            onTextChanged: root.globalFilter = text
                            Keys.onPressed: (event) => {
                                if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
                                    selectAll()
                                    event.accepted = true
                                } else if (event.key === Qt.Key_Escape) {
                                    root.clearGlobalSearch()
                                    event.accepted = true
                                    root.focusActiveTabContent()
                                }
                            }
                            Keys.onTabPressed: (event) => {
                                event.accepted = true
                                root.nextTab()
                            }
                            Keys.onBacktabPressed: (event) => {
                                event.accepted = true
                                root.prevTab()
                            }
                            background: Rectangle {
                                color: "transparent"
                                border.width: 0
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "transparent"

                    // Key Bindings (optional categories via --#Category# description)
                    Flickable {
                        id: bindsFlickable
                        visible: root.currentTabInfo.view === "binds"
                        anchors.fill: parent
                        property int _bindsTick: root.fileContentsVersion
                        property string _filterTick: root.globalFilter
                        contentHeight: Math.max(bindsColumn.implicitHeight + 20, 1)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: true

                        WheelHandler {
                            onWheel: function(event) {
                                const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                                if (delta === 0) return
                                root.flickableWheelScroll(bindsFlickable, delta)
                                event.accepted = true
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            id: bindsScrollBar
                            policy: bindsFlickable.contentHeight > bindsFlickable.height + 1
                                ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                            contentItem: Rectangle {
                                implicitWidth: root.inspScrollBarWidth
                                radius: root.inspScrollBarRadius
                                color: bindsScrollBar.pressed ? root.accent : root.inspScrollBarIdle
                            }
                        }

                        Column {
                            id: bindsColumn
                            width: parent.width
                            spacing: 10

                            // Depend on cache/filter so the grouped model rebinds reliably
                            property int _tick: bindsFlickable._bindsTick
                            property string _filter: bindsFlickable._filterTick
                            readonly property var groups: {
                                // Touch deps so QML tracks file reload + search
                                const _a = _tick
                                const _b = _filter
                                return root.groupedFilteredBinds()
                            }

                            Repeater {
                                model: bindsColumn.groups

                                delegate: Column {
                                    width: bindsColumn.width
                                    spacing: 4

                                    // Category header (hidden when all binds are uncategorized)
                                    Rectangle {
                                        visible: modelData.category && modelData.category.length > 0
                                        width: parent.width
                                        height: visible ? 28 : 0
                                        radius: th.inspRowRadius
                                        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10)

                                        // Left accent bar
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            anchors.margins: 4
                                            width: 3
                                            radius: 1.5
                                            color: root.accent
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 14
                                            anchors.rightMargin: 10
                                            spacing: 8

                                            Text {
                                                text: modelData.category
                                                color: root.accent
                                                font.pixelSize: 12
                                                font.bold: true
                                                font.letterSpacing: 0.6
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            // Bind count chip for this category
                                            Rectangle {
                                                visible: modelData.binds && modelData.binds.length > 0
                                                Layout.preferredHeight: 18
                                                Layout.preferredWidth: catCountText.implicitWidth + 10
                                                radius: 9
                                                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)

                                                Text {
                                                    id: catCountText
                                                    anchors.centerIn: parent
                                                    text: modelData.binds ? modelData.binds.length : 0
                                                    color: root.accent
                                                    font.pixelSize: 10
                                                    font.bold: true
                                                    font.family: root.fontMono
                                                }
                                            }
                                        }
                                    }

                                    GridLayout {
                                        width: parent.width
                                        columns: 2
                                        columnSpacing: 16
                                        rowSpacing: 2

                                        Repeater {
                                            model: modelData.binds
                                            delegate: Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: th.inspBindRowHeight
                                                radius: th.inspRowRadius
                                                color: bindRowMa.containsMouse ? root.inspRowHoverBg : "transparent"

                                                MouseArea { id: bindRowMa; anchors.fill: parent; hoverEnabled: true }

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 8
                                                    spacing: 8

                                                    Row {
                                                        spacing: 4
                                                        Repeater {
                                                            model: modelData.key.split(/\s*\+\s*/)
                                                            delegate: Rectangle {
                                                                height: th.inspKeyPillHeight
                                                                width: keyText.implicitWidth + th.inspKeyPillHPadding
                                                                radius: th.inspKeyPillRadius
                                                                color: keyPillColor(modelData)

                                                                Text {
                                                                    id: keyText
                                                                    anchors.centerIn: parent
                                                                    text: modelData
                                                                    color: keyPillTextColor(modelData)
                                                                    font.pixelSize: th.inspKeyPillFontSize
                                                                    font.family: root.fontMono
                                                                    font.bold: true
                                                                }
                                                            }
                                                        }
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.action
                                                        color: root.text
                                                        font.pixelSize: 13
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RuntimeOptionsView {
                        id: runtimeViewer
                        visible: root.currentTabInfo.view === "runtime"
                        anchors.fill: parent
                        globalFilter: root.globalFilter
                        textColor: root.text
                        subtextColor: root.subtext
                        accentColor: root.accent
                        surfaceColor: root.surface
                        overlayColor: root.overlay
                        onCopyRequested: (text) => root.copyToClipboard(text)
                    }

                    ConfigFilesView {
                        id: configFilesViewer
                        visible: root.currentTabInfo.view === "configfiles"
                        anchors.fill: parent
                        anchors.margins: 10
                        files: root.configFileEntries
                        configDir: root.configDir
                        globalFilter: root.globalFilter
                        textColor: root.text
                        subtextColor: root.subtext
                        accentColor: root.accent
                        surfaceColor: root.surface
                        overlayColor: root.overlay
                        onSelectedFileIdChanged: {
                            root.syncRawSource()
                            const entry = configFilesViewer.currentEntry()
                            if (entry && !root.fileContents[entry.id]) {
                                root.refreshConfigFileEntry(entry)
                            } else {
                                configFilesViewer.refreshBat()
                            }
                        }
                    }

                    // Environment
                    Flickable {
                        id: envFlickable
                        visible: root.currentTabInfo.view === "env"
                        anchors.fill: parent
                        anchors.margins: 10
                        property int _envTick: root.fileContentsVersion
                        property string _filterTick: root.globalFilter
                        flickableDirection: Flickable.VerticalFlick | Flickable.HorizontalFlick
                        contentWidth: root.envTableWidth(width)
                        contentHeight: Math.max(envCol.implicitHeight, 1)
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: true

                        WheelHandler {
                            onWheel: function(event) {
                                const deltaY = event.angleDelta.y
                                const deltaX = event.angleDelta.x
                                if (deltaY !== 0) {
                                    root.flickableWheelScroll(envFlickable, deltaY)
                                } else if (deltaX !== 0) {
                                    const maxX = Math.max(0, envFlickable.contentWidth - envFlickable.width)
                                    if (maxX > 0) {
                                        const ticks = deltaX / 120
                                        envFlickable.contentX = Math.max(0, Math.min(maxX,
                                            envFlickable.contentX - ticks * 42))
                                    }
                                }
                                event.accepted = true
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            id: envScrollBar
                            policy: envFlickable.contentHeight > envFlickable.height + 1
                                ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                            contentItem: Rectangle {
                                implicitWidth: root.inspScrollBarWidth
                                radius: root.inspScrollBarRadius
                                color: envScrollBar.pressed ? root.accent : root.inspScrollBarIdle
                            }
                        }

                        ScrollBar.horizontal: ScrollBar {
                            id: envHScrollBar
                            policy: envFlickable.contentWidth > envFlickable.width + 1
                                ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                            contentItem: Rectangle {
                                implicitHeight: root.inspScrollBarWidth
                                radius: root.inspScrollBarRadius
                                color: envHScrollBar.pressed ? root.accent : root.inspScrollBarIdle
                            }
                        }

                        Column {
                            id: envCol
                            width: root.envTableWidth(envFlickable.width)
                            spacing: 8

                            Rectangle {
                                width: parent.width
                                height: th.inspEnvHeaderHeight
                                radius: th.inspRowRadius
                                color: root.inspRowHoverBg

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: root.envTableSideMargin
                                    anchors.rightMargin: root.envTableSideMargin
                                    spacing: root.envTableColSpacing

                                    Text {
                                        Layout.preferredWidth: root.envVariableColumnWidth(envFlickable.width)
                                        Layout.minimumWidth: root.envVariableColumnWidth(envFlickable.width)
                                        Layout.maximumWidth: root.envVariableColumnWidth(envFlickable.width)
                                        text: "Variable"
                                        color: root.accent
                                        font.pixelSize: 12
                                        font.bold: true
                                        font.family: root.fontMono
                                    }
                                    Text {
                                        Layout.preferredWidth: root.envValueColumnWidth(envFlickable.width)
                                        Layout.minimumWidth: root.envValueColumnWidth(envFlickable.width)
                                        Layout.maximumWidth: root.envValueColumnWidth(envFlickable.width)
                                        text: "Value"
                                        color: root.accent
                                        font.pixelSize: 12
                                        font.bold: true
                                        font.family: root.fontMono
                                        horizontalAlignment: Text.AlignRight
                                    }
                                    Text {
                                        Layout.preferredWidth: root.envDescriptionColumnWidth(envFlickable.width)
                                        Layout.minimumWidth: root.envDescriptionColumnWidth(envFlickable.width)
                                        text: "Description"
                                        color: root.accent
                                        font.pixelSize: 12
                                        font.bold: true
                                        font.family: root.fontMono
                                    }
                                }
                            }

                            Column {
                                width: parent.width
                                spacing: 2

                                Repeater {
                                    model: root.filteredEnv()
                                    delegate: Rectangle {
                                        width: envCol.width
                                        implicitHeight: envRowLayout.implicitHeight + 8
                                        height: implicitHeight
                                        radius: th.inspRowRadius
                                        color: keyMa.containsMouse || valueMa.containsMouse
                                                || (commentMa.containsMouse && envComment.text.length > 0)
                                            ? root.inspRowHoverBg : "transparent"

                                        RowLayout {
                                            id: envRowLayout
                                            anchors.fill: parent
                                            anchors.topMargin: 4
                                            anchors.bottomMargin: 4
                                            anchors.leftMargin: root.envTableSideMargin
                                            anchors.rightMargin: root.envTableSideMargin
                                            spacing: root.envTableColSpacing

                                            Text {
                                                Layout.preferredWidth: root.envVariableColumnWidth(envFlickable.width)
                                                Layout.minimumWidth: root.envVariableColumnWidth(envFlickable.width)
                                                Layout.maximumWidth: root.envVariableColumnWidth(envFlickable.width)
                                                Layout.alignment: Qt.AlignTop
                                                text: modelData.key
                                                color: root.envKeyColor(modelData.key)
                                                font.pixelSize: 13
                                                font.family: root.fontMono
                                                font.bold: root.envKeyIsHighlight(modelData.key)
                                                wrapMode: Text.Wrap

                                                MouseArea {
                                                    id: keyMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.copyToClipboard(modelData.key)
                                                }
                                            }

                                            Text {
                                                Layout.preferredWidth: root.envValueColumnWidth(envFlickable.width)
                                                Layout.minimumWidth: root.envValueColumnWidth(envFlickable.width)
                                                Layout.maximumWidth: root.envValueColumnWidth(envFlickable.width)
                                                Layout.alignment: Qt.AlignTop
                                                text: modelData.value
                                                color: root.envValueColor(modelData.key, modelData.value)
                                                font.pixelSize: 13
                                                font.family: root.fontMono
                                                horizontalAlignment: Text.AlignRight
                                                wrapMode: Text.Wrap

                                                MouseArea {
                                                    id: valueMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.copyToClipboard(modelData.value)
                                                }
                                            }

                                            Text {
                                                id: envComment
                                                Layout.preferredWidth: root.envDescriptionColumnWidth(envFlickable.width)
                                                Layout.minimumWidth: root.envDescriptionColumnWidth(envFlickable.width)
                                                Layout.alignment: Qt.AlignTop
                                                text: modelData.comment || ""
                                                color: root.overlay
                                                font.pixelSize: 11
                                                font.family: root.fontMono
                                                wrapMode: Text.Wrap

                                                MouseArea {
                                                    id: commentMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: envComment.text.length > 0
                                                        ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: {
                                                        if (modelData.comment && modelData.comment.length > 0)
                                                            root.copyToClipboard(modelData.comment)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Raw config file viewer — syntax highlighting via `bat`
                    BatSyntaxView {
                        id: batViewer
                        visible: root.currentTabInfo.view === "raw"
                        anchors.fill: parent
                        filePath: root.batFilePath
                        language: root.batLanguage
                        filterText: root.globalFilter
                        defaultColor: root.text
                        accentColor: root.accent
                    }

                    CpuMonitorView {
                        id: cpuViewer
                        visible: root.currentTabInfo.view === "cpu"
                        anchors.fill: parent
                        anchors.margins: 10
                        service: sysMonService
                        textColor: root.text
                        subtextColor: root.subtext
                        accentColor: root.accent
                        surfaceColor: root.surface
                        overlayColor: root.overlay
                    }

                    GpuMonitorView {
                        id: gpuViewer
                        visible: root.currentTabInfo.view === "gpu"
                        anchors.fill: parent
                        anchors.margins: 10
                        service: sysMonService
                        textColor: root.text
                        subtextColor: root.subtext
                        accentColor: root.accent
                        surfaceColor: root.surface
                        overlayColor: root.overlay
                        gaugeLowColor: th.gaugeLow
                        gaugeMidColor: th.gaugeMid
                        gaugeHighColor: th.gaugeHigh
                    }

                    MemoryMonitorView {
                        id: memoryViewer
                        visible: root.currentTabInfo.view === "memory"
                        anchors.fill: parent
                        anchors.margins: 10
                        service: sysMonService
                        textColor: root.text
                        subtextColor: root.subtext
                        accentColor: root.accent
                        surfaceColor: root.surface
                        overlayColor: root.overlay
                        gaugeLowColor: th.gaugeLow
                        gaugeMidColor: th.gaugeMid
                        gaugeHighColor: th.gaugeHigh
                    }

                    TemperatureMonitorView {
                        id: tempViewer
                        visible: root.currentTabInfo.view === "temperature"
                        anchors.fill: parent
                        anchors.margins: 10
                        service: sysMonService
                        textColor: root.text
                        subtextColor: root.subtext
                        accentColor: root.accent
                        surfaceColor: root.surface
                        overlayColor: root.overlay
                        gaugeLowColor: th.gaugeLow
                        gaugeMidColor: th.gaugeMid
                        gaugeHighColor: th.gaugeHigh
                    }

                    NetworkMonitorView {
                        id: networkViewer
                        visible: root.currentTabInfo.view === "network"
                        anchors.fill: parent
                        anchors.margins: 8
                        active: root.inspectorActive && root.currentTabInfo.view === "network"
                        service: sysMonService
                        globalFilter: root.globalFilter
                        textColor: root.text
                        subtextColor: root.subtext
                        accentColor: root.accent
                        surfaceColor: root.surface
                        overlayColor: root.overlay
                        okColor: th.gaugeLow
                        warnColor: th.gaugeMid
                        errorColor: th.gaugeHigh
                    }

                    ProcessMonitorView {
                        id: processesViewer
                        visible: root.currentTabInfo.view === "processes"
                        anchors.fill: parent
                        anchors.margins: 10
                        active: root.inspectorActive && root.currentTabInfo.view === "processes"
                        globalFilter: root.globalFilter
                        service: sysMonService
                        textColor: root.text
                        subtextColor: root.subtext
                        accentColor: root.accent
                        surfaceColor: root.surface
                        overlayColor: root.overlay
                        okColor: th.gaugeLow
                        warnColor: th.gaugeMid
                        errorColor: th.gaugeHigh
                    }

                    AudioMonitorView {
                        id: audioViewer
                        visible: root.currentTabInfo.view === "audio"
                        anchors.fill: parent
                        anchors.margins: 10
                        active: root.inspectorActive && root.currentTabInfo.view === "audio"
                        globalFilter: root.globalFilter
                        textColor: root.text
                        subtextColor: root.subtext
                        accentColor: root.accent
                        surfaceColor: root.surface
                        overlayColor: root.overlay
                        okColor: th.gaugeLow
                        warnColor: th.gaugeMid
                        errorColor: th.gaugeHigh
                    }

                    LogsView {
                        id: logsViewer
                        visible: root.currentTabInfo.view === "logs"
                        anchors.fill: parent
                        anchors.margins: 10
                        active: root.inspectorActive && root.currentTabInfo.view === "logs"
                        globalFilter: root.globalFilter
                        textColor: root.text
                        subtextColor: root.subtext
                        accentColor: root.accent
                        surfaceColor: root.surface
                        overlayColor: root.overlay
                    }

                    ServicesView {
                        id: servicesViewer
                        visible: root.currentTabInfo.view === "services"
                        anchors.fill: parent
                        anchors.margins: 10
                        active: root.inspectorActive && root.currentTabInfo.view === "services"
                        globalFilter: root.globalFilter
                        textColor: root.text
                        subtextColor: root.subtext
                        accentColor: root.accent
                        surfaceColor: root.surface
                        overlayColor: root.overlay
                        okColor: th.gaugeLow
                        warnColor: th.gaugeMid
                        errorColor: th.gaugeHigh
                    }

                    // System Info — colored fastfetch --logo cachyos; Service Documentation kept at bottom
                    Item {
                        visible: root.currentTabInfo.view === "system"
                        anchors.fill: parent
                        anchors.margins: 10

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 10

                            Flickable {
                                id: systemFlickable
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 0
                                clip: true
                                property int _sysTick: root.systemDisplayVersion
                                property string _filterTick: root.globalFilter
                                on_FilterTickChanged: root.rebuildSystemDisplay()
                                contentWidth: Math.max(width, root.systemContentWidth)
                                contentHeight: Math.max(systemText.implicitHeight + 12, 1)
                                boundsBehavior: Flickable.StopAtBounds
                                interactive: true
                                flickableDirection: Flickable.HorizontalAndVerticalFlick

                                WheelHandler {
                                    onWheel: function(event) {
                                        const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                                        if (delta === 0) return
                                        root.flickableWheelScroll(systemFlickable, delta)
                                        event.accepted = true
                                    }
                                }

                                ScrollBar.vertical: ScrollBar {
                                    id: systemScrollBar
                                    policy: systemFlickable.contentHeight > systemFlickable.height + 1
                                        ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                    contentItem: Rectangle {
                                        implicitWidth: root.inspScrollBarWidth
                                        radius: root.inspScrollBarRadius
                                        color: systemScrollBar.pressed ? root.accent : root.inspScrollBarIdle
                                    }
                                }

                                ScrollBar.horizontal: ScrollBar {
                                    id: systemHScrollBar
                                    policy: systemFlickable.contentWidth > systemFlickable.width + 1
                                        ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                    contentItem: Rectangle {
                                        implicitHeight: 6
                                        radius: 3
                                        color: systemHScrollBar.pressed ? root.accent : root.inspScrollBarIdle
                                    }
                                }

                                Text {
                                    id: systemText
                                    width: Math.max(systemFlickable.width - 8, root.systemContentWidth)
                                    text: root.systemHtml
                                    textFormat: Text.RichText
                                    color: root.text
                                    font.pixelSize: 13
                                    font.family: root.fontMono
                                    wrapMode: Text.NoWrap
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: root.inspWindowBorder
                                opacity: 0.5
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: serviceDocInner.implicitHeight + 14
                                Layout.maximumHeight: parent.height * 0.45
                                radius: 6
                                color: root.surface
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.08)

                                ColumnLayout {
                                    id: serviceDocInner
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 4

                                    Text {
                                        text: "SERVICE DOCUMENTATION"
                                        color: root.accent
                                        font.pixelSize: 10
                                        font.bold: true
                                        font.family: root.fontMono
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "System76 Thelio Mira R4 reference docs for this desktop."
                                        color: root.subtext
                                        font.pixelSize: 11
                                        font.family: root.fontMono
                                        wrapMode: Text.Wrap
                                    }

                                    Repeater {
                                        model: root.systemDocLinks
                                        delegate: Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 22
                                            radius: 4
                                            color: docLinkMa.containsMouse ? root.inspRowHoverBg : "transparent"

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 4
                                                anchors.rightMargin: 6
                                                spacing: 10

                                                Text {
                                                    Layout.preferredWidth: 168
                                                    text: modelData.label
                                                    color: docLinkMa.containsMouse ? root.accent : root.text
                                                    font.pixelSize: 12
                                                    font.family: root.fontMono
                                                    font.underline: docLinkMa.containsMouse
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.note || modelData.url
                                                    color: root.overlay
                                                    font.pixelSize: 11
                                                    font.family: root.fontMono
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            MouseArea {
                                                id: docLinkMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.openDocumentationUrl(modelData.url)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: root.statusText()
                        color: root.overlay
                        font.pixelSize: root.inspStatusFontSize
                        property int _mtimeTick: root.fileMtimesVersion
                        property string _filterTick: root.globalFilter
                        property int _fileTick: root.fileContentsVersion
                        property int _runtimeTick: runtimeViewer.optionsVersion
                        property string _configFileTick: configFilesViewer.selectedFileId
                        property int _cpuTick: sysMonService.cpuHistory.length
                        property int _gpuTick: sysMonService.gpuHistory.length
                        property int _ramTick: sysMonService.ramHistory.length
                        property int _cpuTempTick: sysMonService.cpuTempHistory.length
                        property int _gpuTempTick: sysMonService.gpuTempHistory.length
                        property int _netRxTick: sysMonService.netRxHistory.length
                        property int _netTxTick: sysMonService.netTxHistory.length
                        property var _cpuData: sysMonService.data
                        property int _procTick: processesViewer.dataVersion
                        property int _procSel: processesViewer.selectionVersion
                        property int _logsTick: logsViewer.contentVersion
                        property string _logsSource: logsViewer.selectedSourceId
                        property bool _logsLive: logsViewer.liveTail
                        property int _audioTick: audioViewer.dataVersion
                        property int _svcTick: servicesViewer.dataVersion
                        property string _svcFilter: servicesViewer.filterMode
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        visible: root.canCopyTab
                        width: 44
                        height: th.inspFooterButtonHeight
                        radius: th.inspFooterButtonRadius
                        color: copyTabMa.containsMouse ? root.surface : "transparent"
                        border.width: 1
                        border.color: th.pillBorder
                        Text { anchors.centerIn: parent; text: "Copy"; color: root.accent; font.pixelSize: root.inspStatusFontSize }
                        MouseArea {
                            id: copyTabMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.copyCurrentTabContent()
                        }
                    }

                    Rectangle {
                        visible: root.currentTabInfo.view === "processes"
                        width: 58
                        height: th.inspFooterButtonHeight
                        radius: th.inspFooterButtonRadius
                        color: copyAllProcMa.containsMouse ? root.surface : "transparent"
                        border.width: 1
                        border.color: th.pillBorder
                        opacity: processesViewer.filteredProcesses().length > 0 ? 1 : 0.35
                        Text { anchors.centerIn: parent; text: "Copy All"; color: root.accent; font.pixelSize: root.inspStatusFontSize }
                        MouseArea {
                            id: copyAllProcMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: processesViewer.filteredProcesses().length > 0
                            onClicked: processesViewer.copyAll()
                        }
                    }

                    Rectangle {
                        visible: root._footerRefreshViews.indexOf(root.tabView()) !== -1 || isSysmonMetricView(root.tabView())
                        width: 68
                        height: th.inspFooterButtonHeight
                        radius: th.inspFooterButtonRadius
                        color: refSysMa.containsMouse ? root.surface : "transparent"
                        border.width: 1
                        border.color: th.pillBorder
                        Text { anchors.centerIn: parent; text: "Refresh"; color: root.accent; font.pixelSize: root.inspStatusFontSize }
                        MouseArea {
                            id: refSysMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.currentTabInfo.view === "runtime") runtimeViewer.refreshCategory()
                                else if (isSysmonMetricView(root.currentTabInfo.view)) {
                                    sysMonService.refresh()
                                    if (root.currentTabInfo.view === "network") networkViewer.refreshDetail()
                                }
                                else if (root.currentTabInfo.view === "processes") processesViewer.refresh()
                                else if (root.currentTabInfo.view === "audio") audioViewer.refresh()
                                else if (root.currentTabInfo.view === "logs") logsViewer.refresh(true)
                                else if (root.currentTabInfo.view === "services") servicesViewer.refresh()
                                else root.refreshSystemInfo()
                            }
                        }
                    }

                    Rectangle {
                        visible: root.hasConfigFile
                        width: 40
                        height: th.inspFooterButtonHeight
                        radius: th.inspFooterButtonRadius
                        color: editLuaMa.containsMouse ? root.surface : "transparent"
                        border.width: 1
                        border.color: th.pillBorder
                        Text { anchors.centerIn: parent; text: "Edit"; color: root.accent; font.pixelSize: root.inspStatusFontSize }
                        MouseArea {
                            id: editLuaMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.editCurrentConfigFile()
                        }
                    }

                }
            }

            // Bottom-right resize grip — updates implicitWidth/Height directly
            Rectangle {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 4
                width: 22
                height: 22
                radius: 3
                z: 201
                color: resizeMa.containsMouse || resizeMa.pressed ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "◢"
                    color: root.overlay
                    font.pixelSize: 9
                }

                MouseArea {
                    id: resizeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.SizeFDiagCursor

                    property real startWidth: 0
                    property real startHeight: 0
                    property real pressSceneX: 0
                    property real pressSceneY: 0

                    onPressed: (mouse) => {
                        startWidth = root.inspectorWidth
                        startHeight = root.inspectorHeight
                        pressSceneX = mouse.scenePosition.x
                        pressSceneY = mouse.scenePosition.y
                    }

                    onPositionChanged: (mouse) => {
                        if (!pressed) return
                        const dx = mouse.scenePosition.x - pressSceneX
                        const dy = mouse.scenePosition.y - pressSceneY
                        root.inspectorWidth = Math.max(root.inspMinWidth, Math.round(startWidth + dx))
                        root.inspectorHeight = Math.max(root.inspMinHeight, Math.round(startHeight + dy))
                    }
                }
            }
        }
    }
}