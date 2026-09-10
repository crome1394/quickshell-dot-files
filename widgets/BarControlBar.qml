// =============================================================================
// BarControlBar.qml — Temporary mini-bar opened from empty main-bar chrome
// =============================================================================
//
// Right-click blank area of the main bar (wired in shell.qml) toggles this
// strip. Horizontally centered; stacks just inward from the main bar.
//
// Single PopupWindow. Expandable panel on top; toolbar buttons
// along the bottom: Position · Display · Wallpaper · Widgets · Options ·
// Themes · Launch · Autostart · MIME · Services · Audio · Keybinds · Clock
// Widgets = layout; Options = behavior prefs; Themes = bar/widget theme;
// MIME = preferred applications / file-type defaults (MimeAppsView);
// Services = systemd; Audio = devices/ports/AEC (AudioMonitorView);
// Keybinds = chord/category/desc.
// Display = monitor resolution / refresh / bit depth (Apply to switch).
// Clock = Region & Clock tabs (timezone map + format presets / custom Qt format).
// Window height follows content; tall menus scroll only when needed.
//
// =============================================================================

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io as Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../components"

Item {
    id: root

    required property var bar

    width: 0
    height: 0

    property double _closedAtMs: 0
    readonly property int _reopenGuardMs: 220
    readonly property bool open: controlPopup.visible

    // "" | "position" | "display" | "wallpaper" | "widgets" | "options" |
    // "colors" | "launch" | "autostart" | "mime" | "services" | "audio" | "keybinds" | "clock"
    // ("sizes" accepted as alias of "widgets" for any leftover callers)
    property string activeMenu: ""
    property int menuTick: 0
    // Clock panel: draft Qt.formatDateTime string for the custom field
    property string clockFormatDraft: ""
    // Clock panel sub-tab: "region" | "clock" (default Region, like MIME's File types)
    property string clockTab: "region"
    // Options panel live reads (refreshed on open / toggle)
    property int optionsTick: 0
    // Themes panel state (activeMenu id remains "colors" for compatibility)
    property int colorsTick: 0
    property string colorsPickerKey: ""
    property string colorsExportName: ""
    property string colorsImportPath: ""
    property bool colorsShowImport: false
    // Themes sub-tabs: "theming" | "thresholds" | "fonts" | "presets"
    property string colorsTab: "theming"
    // Collapsible Theming sections (true = expanded)
    property bool themeSecColorsOpen: true
    property bool themeSecTextOpen: true
    property bool themeSecEffectsOpen: true
    // System font list for Fonts tab dropdowns (filled on first open)
    property var systemFontFamilies: []
    property bool systemFontsLoaded: false
    // Themes undo stack (snapshots of themeExport); max 40 entries
    property var themeUndoStack: []
    property bool _themeUndoGuard: false
    // Preferred height for the side color picker so the SV square uses free vertical space
    readonly property int colorsPickerPreferredH: {
        void root.menuTick
        void root.panelMaxH
        // Leave room for header + sticky tabs (~120–160px inside Themes body)
        return Math.max(260, Math.min(460, root.panelMaxH - 200))
    }
    // Themes panel fills the outer panel; body scrolls under sticky tabs
    readonly property int themesPanelBodyH: {
        void root.menuTick
        void root.panelMaxH
        // panelMaxH minus title/hint/tabs chrome inside the Themes column
        return Math.max(180, root.panelMaxH - 150)
    }
    // Inner-panel scrollbar lane (Wallpaper / Widgets / Options / Launch / Autostart)
    readonly property int bodyScrollBarW: 10
    readonly property int bodyScrollGutter: 22
    // Options panel: fixed right slot — toggles & fields share the same vertical center line
    readonly property int optControlColW: 40
    readonly property int optToggleW: 28
    readonly property int optToggleH: 26
    readonly property int optFieldW: 40
    // Slightly lifted blue-slate glass so TextFields read as editable (not flat chrome)
    readonly property color optFieldBg: Qt.rgba(0.10, 0.12, 0.18, 0.92)
    readonly property color optFieldBgFocus: Qt.rgba(0.14, 0.16, 0.24, 0.95)

    readonly property color onGreen: "#2ee59a"
    readonly property color offRed:  "#FF3D8A"

    // Desktop app picker (Launch panel)
    property var desktopApps: []
    property string desktopAppsQuery: ""
    property bool desktopAppsLoading: false
    property string customName: ""
    property string customCommand: ""
    property string customIcon: ""

    // Wallpaper panel
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
    readonly property int wallpaperTilePref: {
        void root.menuTick
        const n = (bar && bar.wallpaperTileSize !== undefined) ? Number(bar.wallpaperTileSize) : 148
        if (!(n > 0))
            return 148
        return Math.max(100, Math.min(260, Math.round(n)))
    }

    // Display panel (monitor resolution / refresh / bit depth)
    property bool displayLoading: false
    property bool displayApplying: false
    property string displayStatus: ""
    property string displayError: ""
    property var displayInfo: ({})
    property var displayResolutions: []     // full catalog from hyprctl
    property var displayFilteredList: []    // cached: res that support displaySelectedRate
    property int displayResIndex: 0         // index into displayFilteredList
    property real displaySelectedRate: 0    // selected refresh (Hz)
    property int displayBitdepth: 10
    property bool displayRateMenuOpen: false
    property bool displayBitdepthMenuOpen: false
    property bool displaySliderPressed: false
    property int displayTick: 0             // UI selection / catalog changes
    property int displayGpuTick: 0          // soft GPU/status poll only (cheap)
    // true while a full list+status load is in flight (not GPU-only poll)
    property bool displayFullFetch: false

    // Autostart panel (XDG ~/.config/autostart)
    property var autostartEntries: []
    property bool autostartLoading: false
    property string autostartStatus: ""
    property string autostartSearch: ""

    // Services panel (reuse components/ServicesView.qml)
    property string servicesFilter: ""

    // Audio panel (reuse components/AudioMonitorView.qml)
    property string audioFilter: ""

    // Keybinds panel (components/KeybindsView.qml)
    property string keybindsFilter: ""

    readonly property int pad: (bar.popupSpacingTight !== undefined) ? bar.popupSpacingTight : 6
    readonly property int chipH: Math.max(26, Math.round((bar.pillHeight || 36) * 0.78))
    readonly property int chipR: bar.buttonRadius !== undefined ? bar.buttonRadius : 8
    // Cap panel so the popup always fits above/below the bar; short menus shrink to content.
    readonly property int panelMaxH: {
        void root.menuTick
        let screenH = 1080
        try {
            if (bar.screen && bar.screen.height)
                screenH = bar.screen.height
            else if (bar.height > 200)
                screenH = bar.height
        } catch (e) {}
        const reserved = (bar.barHeight || 58) + 110
        return Math.max(240, Math.min(640, screenH - reserved))
    }

    // Height of the *visible* panel section only (ignore hidden menus — childrenRect does not).
    function measurePanelContent() {
        void root.menuTick
        void root.activeMenu
        void root.wallpaperTilePref
        if (typeof panelStack === "undefined" || !panelStack)
            return 0
        let h = 0
        const kids = panelStack.children
        for (let i = 0; i < kids.length; i++) {
            const c = kids[i]
            if (!c || c.visible === false)
                continue
            const ch = Math.max(
                c.implicitHeight || 0,
                (c.Layout && c.Layout.preferredHeight > 0) ? c.Layout.preferredHeight : 0,
                c.height || 0
            )
            if (ch > h)
                h = ch
        }
        // Fallback if layout has not assigned heights yet
        if (h < 8 && panelStack.implicitHeight > 0)
            h = panelStack.implicitHeight
        return h
    }

    // Menus that commonly overflow the screen and should scroll inside the panel
    readonly property bool panelScrollableMenu: {
        const m = root.activeMenu
        return m === "wallpaper" || m === "widgets" || m === "options"
               || m === "colors" || m === "autostart" || m === "launch" || m === "display"
               || m === "clock"
    }

    // These panels pin a header/footer and scroll their body (like Themes / Audio).
    readonly property bool panelUsesInnerScroll: {
        const m = root.activeMenu
        return m === "colors" || m === "audio" || m === "mime" || m === "services"
               || m === "keybinds" || m === "wallpaper" || m === "widgets"
               || m === "options" || m === "launch" || m === "autostart" || m === "display"
               || m === "clock"
    }

    function themeRows() {
        if (bar && bar.themeUiRows)
            return bar.themeUiRows
        return []
    }

    function _themeSection(row) {
        if (!row)
            return "colors"
        if (row.section && ("" + row.section).length)
            return row.section
        // Legacy rows without section field
        if (root._themeIsTextKey(row.key))
            return "text"
        if (row.key === "glassHover" || row.key === "glassHighlight"
                || row.key === "iconHoverBg" || row.key === "glassPopupHighlight")
            return "effects"
        return "colors"
    }

    function _themeIsTextKey(key) {
        return key === "text" || key === "subtext" || key === "barText"
               || key === "overlay" || key === "clock"
               || key === "buttonText" || key === "buttonTextActive"
               || key === "wsActiveText" || key === "wsInactiveText"
    }

    function themeRowsInSection(section) {
        const rows = root.themeRows()
        const out = []
        for (let i = 0; i < rows.length; i++) {
            if (rows[i] && root._themeSection(rows[i]) === section)
                out.push(rows[i])
        }
        return out
    }

    // Solid color swatches (Theming → Colors)
    function themeColorRows() {
        return root.themeRowsInSection("colors")
    }

    // Opacity sliders (all keys with opacity: true)
    function themeOpacityRows() {
        const rows = root.themeRows()
        const out = []
        for (let i = 0; i < rows.length; i++) {
            if (rows[i] && rows[i].opacity)
                out.push(rows[i])
        }
        return out
    }

    // Text color swatches
    function themeTextRows() {
        return root.themeRowsInSection("text")
    }

    // Special / Effects swatches (hover glow, top edge shine, …)
    function themeEffectsRows() {
        return root.themeRowsInSection("effects")
    }

    // Theming: always open the picker on the right so bottom chrome fits the panel height
    // (left column stays the lists). Thresholds also use the right column.
    function themePickerOpenOnRight() {
        return root.colorsPickerKey.length > 0
               && !root.isThresholdThemeKey(root.colorsPickerKey)
    }

    function themePickerOpenOnLeft() {
        // Reserved — Theming no longer parks the picker on the left (avoids truncation)
        return false
    }

    function thresholdsPickerOpen() {
        return root.colorsTab === "thresholds"
               && root.colorsPickerKey.length > 0
               && root.isThresholdThemeKey(root.colorsPickerKey)
    }

    function themeLabelForKey(key) {
        const rows = root.themeRows()
        for (let i = 0; i < rows.length; i++) {
            if (rows[i].key === key)
                return rows[i].label
        }
        const extra = root.volumeTierRows().concat(root.micVolumeTierRows())
            .concat(root.statUtilTierRows()).concat(root.statTempRows())
        for (let j = 0; j < extra.length; j++) {
            if (extra[j].key === key)
                return extra[j].label
        }
        return "Pick a color"
    }

    function themeKeyHasOpacity(key) {
        const rows = root.themeRows()
        for (let i = 0; i < rows.length; i++) {
            if (rows[i].key === key)
                return !!rows[i].opacity
        }
        return false
    }

    function themeColorFor(key) {
        if (bar && typeof bar.getThemeColor === "function")
            return bar.getThemeColor(key)
        return Qt.rgba(0.5, 0.5, 0.5, 1)
    }

    function themeHexFor(key) {
        const c = root.themeColorFor(key)
        if (bar && typeof bar.colorToHex === "function")
            return bar.colorToHex(c)
        return "#888888"
    }

    function themeAlphaPct(key) {
        const c = root.themeColorFor(key)
        return Math.round((c && c.a !== undefined ? c.a : 1) * 100)
    }

    function openColorPicker(key) {
        root.colorsPickerKey = key || ""
        root._pickerUndoPushed = false
        // Route threshold-tier swatches to the Thresholds tab; everything else to Theming
        if (root.isThresholdThemeKey(root.colorsPickerKey))
            root.colorsTab = "thresholds"
        else
            root.colorsTab = "theming"
        root.colorsTick++
        // Keep picker fully on-screen and avoid Flickable fighting the drag
        if (typeof panelFlick !== "undefined" && panelFlick) {
            panelFlick.contentY = 0
            if (panelFlick.returnToBounds)
                panelFlick.returnToBounds()
        }
        if (typeof themesBodyFlick !== "undefined" && themesBodyFlick)
            themesBodyFlick.contentY = 0
        const inner = [wpBodyFlick, widgetsBodyFlick, launchBodyFlick, autostartBodyFlick, optionsBodyFlick, displayBodyFlick]
        for (let i = 0; i < inner.length; i++) {
            try {
                if (inner[i])
                    inner[i].contentY = 0
            } catch (e) {}
        }
    }

    function closeColorPicker() {
        root.colorsPickerKey = ""
        root._pickerUndoPushed = false
        root.colorsTick++
    }

    function applyPickedColor(c) {
        if (!root.colorsPickerKey || !bar || typeof bar.setThemeColor !== "function")
            return
        // One undo step per continuous drag session: push only on first edit after open/key change
        if (!root._pickerUndoPushed) {
            root.pushThemeUndo()
            root._pickerUndoPushed = true
        }
        bar.setThemeColor(root.colorsPickerKey, c)
        // Bump tick so swatches / opacity labels refresh; picker keeps its own HSV state.
        root.colorsTick++
    }

    property bool _pickerUndoPushed: false

    property string _alphaUndoKey: ""
    function setThemeAlphaPct(key, pct) {
        if (!bar || typeof bar.setThemeAlpha !== "function")
            return
        // One undo step per opacity control until a different key is moved
        if (root._alphaUndoKey !== key) {
            root.pushThemeUndo()
            root._alphaUndoKey = key
        }
        bar.setThemeAlpha(key, Math.max(0, Math.min(100, pct)) / 100)
        root.colorsTick++
    }

    function colorsPresetModel() {
        const out = []
        if (bar && typeof bar.themeBuiltinList === "function") {
            const b = bar.themeBuiltinList()
            for (let i = 0; i < b.length; i++)
                out.push(b[i])
        }
        const saved = (bar && bar.themeSavedList) ? bar.themeSavedList : []
        for (let j = 0; j < saved.length; j++) {
            out.push({
                id: saved[j].path || saved[j].id,
                name: saved[j].name || saved[j].id,
                builtin: false,
                path: saved[j].path || ""
            })
        }
        return out
    }

    readonly property bool panelNeedsScroll: {
        void root.menuTick
        void root.activeMenu
        void root.wallpaperTilePref
        if (!root.panelScrollableMenu)
            return false
        const content = root.measurePanelContent()
        return content + 18 > root.panelMaxH
    }

    function hide() {
        // A file-manager drag starts as an outside press; do not tear down the
        // surface while a drop is in flight or the wallpaper panel is holding
        // itself open for that drop.
        if (typeof wpDropArea !== "undefined" && wpDropArea && wpDropArea.containsDrag)
            return
        root.closeWallpaperUi()
        root.activeMenu = ""
        if (!controlPopup.visible)
            return
        if (typeof controlFocusGrab !== "undefined" && controlFocusGrab)
            controlFocusGrab.active = false
        controlPopup.visible = false
        root._closedAtMs = Date.now()
    }

    function show() {
        root.menuTick++
        controlPopup.visible = true
        root.scheduleReposition()
        Qt.callLater(root.armControlFocusGrab)
    }

    function toggle() {
        if (controlPopup.visible) {
            hide()
            return
        }
        if (Date.now() - root._closedAtMs < root._reopenGuardMs)
            return
        show()
    }

    function reposition() {
        // Prefer chrome's laid-out size; popup implicit* can lag one frame and
        // park a tall panel mid-screen (especially with bar on bottom).
        var popupW = Math.max(
            controlChrome.implicitWidth || 0,
            controlPopup.implicitWidth || 0,
            mainCol.implicitWidth + pad * 2,
            320
        )
        var popupH = Math.max(
            controlChrome.implicitHeight || 0,
            controlPopup.implicitHeight || 0,
            mainCol.implicitHeight + pad * 2,
            48
        )
        var screenW = 1920
        var screenH = 1080
        try {
            if (bar.screen && bar.screen.width)
                screenW = bar.screen.width
            else if (bar.width > 0)
                screenW = bar.width
            if (bar.screen && bar.screen.height)
                screenH = bar.screen.height
        } catch (e) {}

        var gap = (bar.popupBarGap !== undefined) ? bar.popupBarGap : 4
        var minX = 12
        var maxX = Math.max(minX, screenW - popupW - 12)
        // Center on the bar / screen
        var targetX = Math.round((screenW - popupW) / 2)

        // Always anchor to `bar`. The control PopupWindow lives in that window;
        // pointing it at the dual bottom bar made the strip unclickable (✕ / Esc / gear).
        controlPopup.anchor.window = bar
        controlPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX))
        var y = (typeof bar.controlPopupAnchorY === "function")
                ? bar.controlPopupAnchorY(popupH, gap)
                : bar.popupAnchorY(popupH, gap)
        var edge = (typeof bar.controlPopupEdge === "function") ? bar.controlPopupEdge() : bar.barPosition
        // Clamp so a huge panel never starts above the top of the monitor
        if (edge === "bottom") {
            if (bar.barLayoutMode === "dual") {
                if (y < 8)
                    y = 8
            } else {
                var minY = -(screenH - (bar.barHeight || 58) - 8)
                if (y < minY)
                    y = minY
            }
        }
        controlPopup.anchor.rect.y = y
        controlPopup.anchor.rect.width = 1
        controlPopup.anchor.rect.height = 1
    }

    function scheduleReposition() {
        Qt.callLater(function() {
            root.reposition()
            // Second pass after ColumnLayout/Flickable settle
            settleRepositionTimer.restart()
        })
    }

    function resetPanelScroll() {
        // Switching menus must not keep Widgets' scroll offset (Clock etc. look empty)
        if (typeof panelFlick !== "undefined" && panelFlick) {
            panelFlick.contentY = 0
            if (panelFlick.returnToBounds)
                panelFlick.returnToBounds()
        }
        const inner = [wpBodyFlick, widgetsBodyFlick, launchBodyFlick, autostartBodyFlick, optionsBodyFlick, displayBodyFlick, themesBodyFlick, clockBodyFlick]
        for (let i = 0; i < inner.length; i++) {
            try {
                if (inner[i])
                    inner[i].contentY = 0
            } catch (e) {}
        }
    }

    function toggleMenu(name) {
        // Sizes was merged into Widgets
        if (name === "sizes")
            name = "widgets"
        root.closeWallpaperUi()
        if (root.activeMenu === name)
            root.activeMenu = ""
        else
            root.activeMenu = name
        root.armControlFocusGrab()
        if (root.activeMenu === "options")
            root.refreshOptions()
        if (root.activeMenu === "clock") {
            root.clockTab = "region"
            root.clockFormatDraft = root.currentClockFormat()
        }
        if (root.activeMenu === "colors") {
            root.colorsPickerKey = ""
            root.colorsShowImport = false
            root.colorsTab = "theming"
            root.colorsTick++
            if (bar && typeof bar.refreshThemeSavedList === "function")
                bar.refreshThemeSavedList()
        }
        root.menuTick++
        root.resetPanelScroll()
        // After layout height settles (tall Widgets → short Clock): remeasure + scroll top
        Qt.callLater(function () {
            root.resetPanelScroll()
            root.menuTick++
            root.scheduleReposition()
        })
        root.scheduleReposition()
    }

    function refreshOptions() {
        if (typeof bar.refreshOptionsState === "function")
            bar.refreshOptionsState()
        root.refreshFreshRssSecrets()
        root.optionsTick++
        root.menuTick++
    }

    function optBool(getter, fallback) {
        void root.optionsTick
        void root.menuTick
        try {
            if (typeof getter === "function")
                return !!getter()
        } catch (e) {}
        return !!fallback
    }

    function optEchoCancel() {
        void root.optionsTick
        if (typeof bar.getEchoCancelEnabled === "function")
            return !!bar.getEchoCancelEnabled()
        return false
    }

    function optNetApplet() {
        void root.optionsTick
        if (typeof bar.getNetworkAppletAutostart === "function")
            return !!bar.getNetworkAppletAutostart()
        return true
    }

    function optBtApplet() {
        void root.optionsTick
        if (typeof bar.getBluetoothAppletAutostart === "function")
            return !!bar.getBluetoothAppletAutostart()
        return true
    }

    function optMetricsLive() {
        void root.optionsTick
        if (typeof bar.getMetricsLiveUpdates === "function")
            return !!bar.getMetricsLiveUpdates()
        return true
    }

    function optUiScaleManual() {
        void root.optionsTick
        void root.menuTick
        const m = Number(bar.uiScaleManual)
        return (m > 0) ? m : 0
    }

    function optUiScaleIsAuto() {
        return !(root.optUiScaleManual() > 0)
    }

    function optBarEdgeMargin() {
        void root.optionsTick
        void root.menuTick
        const n = (bar && bar.barEdgeMargin !== undefined) ? Number(bar.barEdgeMargin) : 0
        if (!(n >= 0))
            return 0
        return Math.max(0, Math.min(48, Math.round(n)))
    }

    function optBarSizePct() {
        void root.optionsTick
        void root.menuTick
        const s = (bar && bar.barSizeScale !== undefined) ? Number(bar.barSizeScale) : 1
        if (!(s > 0))
            return 100
        return Math.round(Math.max(0.8, Math.min(1.4, s)) * 100)
    }

    function optTooltipDelay() {
        void root.optionsTick
        void root.menuTick
        const n = (bar && bar.tooltipDelay !== undefined) ? Number(bar.tooltipDelay) : 1550
        if (!(n >= 0))
            return 1550
        return Math.max(0, Math.min(3000, Math.round(n)))
    }

    function tooltipAlignTargets() {
        return [
            { id: "launcher", label: "Launcher" },
            { id: "quickLaunch", label: "Quick Launch" },
            { id: "freshRss", label: "FreshRSS" },
            { id: "stats", label: "Sys Stats" },
            { id: "network", label: "Network" },
            { id: "bluetooth", label: "Bluetooth" },
            { id: "notifications", label: "Notifications" },
            { id: "killTarget", label: "Kill Target" },
            { id: "hyprInsp", label: "Hypr Inspector" },
            { id: "controlBar", label: "Config menu" },
            { id: "power", label: "Power" }
        ]
    }

    function optTooltipAlign(id) {
        void root.optionsTick
        if (bar && typeof bar.tooltipAlignFor === "function")
            return String(bar.tooltipAlignFor(id) || "auto")
        return "auto"
    }

    function setOptToggle(setterName, enabled) {
        const on = !!enabled
        switch (setterName) {
        case "setShowMagicWorkspacePill":
            if (typeof bar.setShowMagicWorkspacePill === "function")
                bar.setShowMagicWorkspacePill(on)
            break
        case "setWsShowOnlyActive":
            if (typeof bar.setWsShowOnlyActive === "function")
                bar.setWsShowOnlyActive(on)
            break
        case "setWsStartupCloseMagic":
            if (typeof bar.setWsStartupCloseMagic === "function")
                bar.setWsStartupCloseMagic(on)
            break
        case "setEchoCancel":
            if (typeof bar.setEchoCancel === "function")
                bar.setEchoCancel(on)
            break
        case "setNetworkAppletAutostart":
            if (typeof bar.setNetworkAppletAutostart === "function")
                bar.setNetworkAppletAutostart(on)
            break
        case "setBluetoothAppletAutostart":
            if (typeof bar.setBluetoothAppletAutostart === "function")
                bar.setBluetoothAppletAutostart(on)
            break
        case "setMetricsLiveUpdates":
            if (typeof bar.setMetricsLiveUpdates === "function")
                bar.setMetricsLiveUpdates(on)
            break
        case "setShowControlBarPill":
            if (typeof bar.setShowControlBarPill === "function")
                bar.setShowControlBarPill(on)
            else if (typeof bar.setWidgetVisible === "function")
                bar.setWidgetVisible("controlBar", on)
            break
        case "setShowColorPresets":
            if (typeof bar.setShowColorPresets === "function")
                bar.setShowColorPresets(on)
            break
        case "setShowStatCpu":
            if (typeof bar.setShowStatCpu === "function")
                bar.setShowStatCpu(on)
            break
        case "setShowStatMem":
            if (typeof bar.setShowStatMem === "function")
                bar.setShowStatMem(on)
            break
        case "setShowStatGpu":
            if (typeof bar.setShowStatGpu === "function")
                bar.setShowStatGpu(on)
            break
        case "setShowStatGauges":
            if (typeof bar.setShowStatGauges === "function")
                bar.setShowStatGauges(on)
            break
        case "setShowStatMenuGraphs":
            if (typeof bar.setShowStatMenuGraphs === "function")
                bar.setShowStatMenuGraphs(on)
            break
        case "setShowNetTrafficGraph":
            if (typeof bar.setShowNetTrafficGraph === "function")
                bar.setShowNetTrafficGraph(on)
            break
        case "setShowNetworkFullIp":
            if (typeof bar.setShowNetworkFullIp === "function")
                bar.setShowNetworkFullIp(on)
            break
        case "setShowNetworkLastOctet":
            if (typeof bar.setShowNetworkLastOctet === "function")
                bar.setShowNetworkLastOctet(on)
            break
        case "setShowNetworkDeviceName":
            if (typeof bar.setShowNetworkDeviceName === "function")
                bar.setShowNetworkDeviceName(on)
            break
        case "setFlushWindowsToBar":
            if (typeof bar.setFlushWindowsToBar === "function")
                bar.setFlushWindowsToBar(on)
            break
        case "setShowEchoCancelInMenu":
            if (typeof bar.setShowEchoCancelInMenu === "function")
                bar.setShowEchoCancelInMenu(on)
            break
        case "setShowAudioSummary":
            if (typeof bar.setShowAudioSummary === "function")
                bar.setShowAudioSummary(on)
            break
        case "setShowAudioDefaults":
            if (typeof bar.setShowAudioDefaults === "function")
                bar.setShowAudioDefaults(on)
            break
        case "setShowAudioLevelMeters":
            if (typeof bar.setShowAudioLevelMeters === "function")
                bar.setShowAudioLevelMeters(on)
            break
        case "setAudioSummaryExpanded":
            if (typeof bar.setAudioSummaryExpanded === "function")
                bar.setAudioSummaryExpanded(on)
            break
        case "setAudioDefaultsExpanded":
            if (typeof bar.setAudioDefaultsExpanded === "function")
                bar.setAudioDefaultsExpanded(on)
            break
        case "setFreshRssFiltersExpanded":
            if (typeof bar.setFreshRssFiltersExpanded === "function")
                bar.setFreshRssFiltersExpanded(on)
            break
        }
        Qt.callLater(root.refreshOptions)
    }

    // FreshRSS Options (server credentials — external env file)
    property string frScheme: "https"
    property string frHost: ""
    property string frUser: ""
    property string frPassword: ""
    property bool frHasPassword: false
    property string frStatus: ""
    property bool frLoading: false

    function refreshFreshRssSecrets() {
        const script = bar.freshRssSecretsReadScript || ""
        if (!script.length) {
            root.frStatus = "read script missing"
            return
        }
        if (frSecretsReadProcess.running)
            return
        root.frLoading = true
        frSecretsReadProcess.exec([script])
    }

    function frBuildCredArgs(script) {
        const host = (root.frHost || "").trim()
        if (!host.length)
            return null
        let scheme = (root.frScheme || "https").toLowerCase()
        if (scheme !== "http")
            scheme = "https"
        const args = [script, "--scheme", scheme, "--host", host, "--user", (root.frUser || "admin").trim()]
        if (root.frPassword.length)
            args.push("--password", root.frPassword)
        return args
    }

    function saveFreshRssSecrets() {
        const script = bar.freshRssSecretsWriteScript || ""
        if (!script.length) {
            root.frStatus = "write script missing"
            return
        }
        if (frSecretsWriteProcess.running)
            return
        const args = root.frBuildCredArgs(script)
        if (!args) {
            root.frStatus = "host required"
            return
        }
        root.frStatus = "Saving…"
        root.frLoading = true
        frSecretsWriteProcess.exec(args)
    }

    function testFreshRssConnection() {
        const script = bar.freshRssConnectionTestScript || ""
        if (!script.length) {
            root.frStatus = "test script missing"
            return
        }
        if (frConnectionTestProcess.running)
            return
        const args = root.frBuildCredArgs(script)
        if (!args) {
            root.frStatus = "host required"
            return
        }
        root.frStatus = "Testing…"
        root.frLoading = true
        frConnectionTestProcess.exec(args)
    }

    function setOptNumber(setterName, value) {
        const n = Number(value)
        if (!(n >= 0) && setterName !== "setWsStartupWorkspace")
            return
        switch (setterName) {
        case "setWsMinimumShown":
            if (typeof bar.setWsMinimumShown === "function")
                bar.setWsMinimumShown(n)
            break
        case "setWsStartupWorkspace":
            if (typeof bar.setWsStartupWorkspace === "function")
                bar.setWsStartupWorkspace(n)
            break
        }
        Qt.callLater(root.refreshOptions)
    }

    function chipBg(active, hovered) {
        if (active)
            return bar.controlActiveBg !== undefined ? bar.controlActiveBg : Qt.rgba(0.0, 0.77, 0.96, 0.22)
        if (hovered)
            return bar.glassHover
        // Isolated button fill (legend 1/6/11) — not glassPillBg/pillBg
        return bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg
    }

    function controlButtonBg(hovered) {
        if (hovered)
            return bar.glassHover
        return bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg
    }

    function volumeTierRows() {
        if (bar && bar.themeVolumeTierUiRows)
            return bar.themeVolumeTierUiRows
        return [
            { key: "audioSpeakerTier1", label: "Out low" },
            { key: "audioSpeakerTier2", label: "Out mid" },
            { key: "audioSpeakerTier3", label: "Out high" },
            { key: "audioSpeakerTier4", label: "Out peak" }
        ]
    }

    function micVolumeTierRows() {
        if (bar && bar.themeMicVolumeTierUiRows)
            return bar.themeMicVolumeTierUiRows
        return [
            { key: "audioMicTier1", label: "In low" },
            { key: "audioMicTier2", label: "In mid" },
            { key: "audioMicTier3", label: "In high" },
            { key: "audioMicTier4", label: "In peak" }
        ]
    }

    function pushThemeUndo() {
        if (root._themeUndoGuard)
            return
        if (!bar || typeof bar.getThemeSnapshot !== "function")
            return
        try {
            const snap = bar.getThemeSnapshot()
            if (!snap)
                return
            // Deep-ish copy via JSON so later mutations don't rewrite history
            const copy = JSON.parse(JSON.stringify(snap))
            let stack = root.themeUndoStack ? root.themeUndoStack.slice() : []
            stack.push(copy)
            if (stack.length > 40)
                stack = stack.slice(stack.length - 40)
            root.themeUndoStack = stack
            root.colorsTick++
        } catch (e) {}
    }

    function canThemeUndo() {
        void root.colorsTick
        return !!(root.themeUndoStack && root.themeUndoStack.length)
    }

    function undoThemeEdit() {
        if (!root.canThemeUndo())
            return
        if (!bar || typeof bar.applyThemeObject !== "function")
            return
        const stack = root.themeUndoStack.slice()
        const prev = stack.pop()
        root.themeUndoStack = stack
        root._themeUndoGuard = true
        try {
            bar.applyThemeObject(prev)
        } catch (e) {}
        root._themeUndoGuard = false
        root.colorsPickerKey = ""
        root.colorsTick++
    }

    function statUtilTierRows() {
        if (bar && bar.themeStatUtilTierUiRows)
            return bar.themeStatUtilTierUiRows
        return [
            { key: "statUtilTier1", label: "Load low" },
            { key: "statUtilTier2", label: "Load mid" },
            { key: "statUtilTier3", label: "Load high" },
            { key: "statUtilTier4", label: "Load peak" }
        ]
    }

    function statTempRows() {
        if (bar && bar.themeStatTempUiRows)
            return bar.themeStatTempUiRows
        return [
            { key: "statTempCool", label: "Temp cool" },
            { key: "statTempWarm", label: "Temp warm" },
            { key: "statTempHot", label: "Temp hot" }
        ]
    }

    function isThresholdThemeKey(key) {
        if (!key || !key.length)
            return false
        return key.indexOf("audioSpeakerTier") === 0
            || key.indexOf("audioMicTier") === 0
            || key.indexOf("audioUtilThreshold") === 0
            || key.indexOf("audioMicUtilThreshold") === 0
            || key.indexOf("statUtilTier") === 0
            || key.indexOf("statUtilThreshold") === 0
            || key.indexOf("statTemp") === 0
    }

    function themeNumberFor(key) {
        if (bar && typeof bar.getThemeNumber === "function") {
            const n = bar.getThemeNumber(key)
            if (n !== null && n !== undefined)
                return n
        }
        if (key === "audioUtilThreshold1") return bar && bar.audioUtilThreshold1 !== undefined ? bar.audioUtilThreshold1 : 25
        if (key === "audioUtilThreshold2") return bar && bar.audioUtilThreshold2 !== undefined ? bar.audioUtilThreshold2 : 50
        if (key === "audioUtilThreshold3") return bar && bar.audioUtilThreshold3 !== undefined ? bar.audioUtilThreshold3 : 75
        if (key === "audioMicUtilThreshold1") return bar && bar.audioMicUtilThreshold1 !== undefined ? bar.audioMicUtilThreshold1 : 25
        if (key === "audioMicUtilThreshold2") return bar && bar.audioMicUtilThreshold2 !== undefined ? bar.audioMicUtilThreshold2 : 50
        if (key === "audioMicUtilThreshold3") return bar && bar.audioMicUtilThreshold3 !== undefined ? bar.audioMicUtilThreshold3 : 75
        if (key === "statUtilThreshold1") return bar && bar.statUtilThreshold1 !== undefined ? bar.statUtilThreshold1 : 25
        if (key === "statUtilThreshold2") return bar && bar.statUtilThreshold2 !== undefined ? bar.statUtilThreshold2 : 50
        if (key === "statUtilThreshold3") return bar && bar.statUtilThreshold3 !== undefined ? bar.statUtilThreshold3 : 75
        if (key === "statTempWarmAt") return bar && bar.statTempWarmAt !== undefined ? bar.statTempWarmAt : 70
        if (key === "statTempHotAt") return bar && bar.statTempHotAt !== undefined ? bar.statTempHotAt : 85
        return 0
    }

    function setThemeNumberValue(key, n) {
        if (!bar || typeof bar.setThemeNumber !== "function")
            return
        root.pushThemeUndo()
        bar.setThemeNumber(key, n)
        root.colorsTick++
    }

    function setColorsTab(tab) {
        const t = tab || "theming"
        if (root.colorsTab === t) {
            if (t === "fonts")
                root.refreshSystemFonts()
            return
        }
        root.colorsTab = t
        // Picker lives on Theming / Thresholds — close when leaving its host
        if (root.colorsPickerKey.length) {
            if (root.isThresholdThemeKey(root.colorsPickerKey) && t !== "thresholds")
                root.closeColorPicker()
            else if (!root.isThresholdThemeKey(root.colorsPickerKey) && t !== "theming")
                root.closeColorPicker()
        }
        if (t === "fonts")
            root.refreshSystemFonts()
        root.colorsTick++
    }

    function toggleThemeSection(sec) {
        if (sec === "colors")
            root.themeSecColorsOpen = !root.themeSecColorsOpen
        else if (sec === "text")
            root.themeSecTextOpen = !root.themeSecTextOpen
        else if (sec === "effects")
            root.themeSecEffectsOpen = !root.themeSecEffectsOpen
        root.colorsTick++
    }

    function refreshSystemFonts() {
        if (root.systemFontsLoaded && root.systemFontFamilies && root.systemFontFamilies.length)
            return
        var list = []
        try {
            // Qt.fontFamilies() — all installed faces (Qt 5.15+ / Qt 6)
            list = Qt.fontFamilies()
        } catch (e) {
            list = []
        }
        if (!list || !list.length) {
            list = [
                "JetBrains Mono Nerd Font", "Symbols Nerd Font",
                "DejaVu Sans", "DejaVu Sans Mono", "Noto Sans", "Noto Sans Mono",
                "FreeSans", "FreeMono", "Monospace", "Sans Serif"
            ]
        }
        // Sort case-insensitive; drop empties
        var out = []
        for (var i = 0; i < list.length; i++) {
            var n = ("" + list[i]).trim()
            if (n.length)
                out.push(n)
        }
        out.sort(function(a, b) {
            var al = a.toLowerCase(), bl = b.toLowerCase()
            if (al < bl) return -1
            if (al > bl) return 1
            return 0
        })
        root.systemFontFamilies = out
        root.systemFontsLoaded = true
    }

    function currentUiFontName() {
        if (bar && typeof bar.primaryUiFontFamily === "function")
            return bar.primaryUiFontFamily()
        return ""
    }

    function currentMonoFontName() {
        if (bar && typeof bar.primaryFontFamily === "function")
            return bar.primaryFontFamily(bar.fontMono || "")
        return ""
    }

    function fontIndexFor(name) {
        var list = root.systemFontFamilies || []
        var want = ("" + (name || "")).trim().toLowerCase()
        if (!want.length)
            return -1
        for (var i = 0; i < list.length; i++) {
            if (("" + list[i]).trim().toLowerCase() === want)
                return i
        }
        return -1
    }

    function applyUiFontFromCombo(index) {
        var list = root.systemFontFamilies || []
        if (index < 0 || index >= list.length)
            return
        root.pushThemeUndo()
        if (bar && typeof bar.setUiFontFamily === "function")
            bar.setUiFontFamily(list[index])
        root.colorsTick++
    }

    function applyMonoFontFromCombo(index) {
        var list = root.systemFontFamilies || []
        if (index < 0 || index >= list.length)
            return
        root.pushThemeUndo()
        if (bar && typeof bar.setMonoFontFamily === "function")
            bar.setMonoFontFamily(list[index])
        root.colorsTick++
    }

    function applyFontScalePct(pct) {
        var p = Number(pct)
        if (!(p > 0))
            return
        // Undo is pushed once on slider press (see Fonts tab), not every tick
        if (bar && typeof bar.setThemeFontScale === "function")
            bar.setThemeFontScale(p / 100)
        root.colorsTick++
    }

    function currentFontScalePct() {
        void root.colorsTick
        var s = (bar && bar.fontScale !== undefined) ? Number(bar.fontScale) : 1
        if (!(s > 0))
            s = 1
        return Math.round(s * 100)
    }

    // role: "main" | "secondary" | "bar"
    function currentRoleFontName(role) {
        void root.colorsTick
        if (bar && typeof bar.primaryRoleFontFamily === "function")
            return bar.primaryRoleFontFamily(role)
        return root.currentUiFontName()
    }

    function applyRoleFontFromCombo(role, index) {
        var list = root.systemFontFamilies || []
        if (index < 0 || index >= list.length)
            return
        root.pushThemeUndo()
        if (bar && typeof bar.setRoleFontFamily === "function")
            bar.setRoleFontFamily(role, list[index])
        root.colorsTick++
    }

    function applyRoleFontScalePct(role, pct) {
        var p = Number(pct)
        if (!(p > 0))
            return
        if (bar && typeof bar.setThemeFontRoleScale === "function")
            bar.setThemeFontRoleScale(role, p / 100)
        root.colorsTick++
    }

    function currentRoleFontScalePct(role) {
        void root.colorsTick
        var s = 1
        if (role === "ui" || role === "scale")
            s = (bar && bar.fontScale !== undefined) ? Number(bar.fontScale) : 1
        else if (role === "mono" && bar && bar.fontMonoScale !== undefined)
            s = Number(bar.fontMonoScale)
        else if (role === "main" && bar && bar.fontMainScale !== undefined)
            s = Number(bar.fontMainScale)
        else if (role === "secondary" && bar && bar.fontSecondaryScale !== undefined)
            s = Number(bar.fontSecondaryScale)
        else if (role === "bar" && bar && bar.fontBarScale !== undefined)
            s = Number(bar.fontBarScale)
        if (!(s > 0))
            s = 1
        return Math.round(s * 100)
    }

    // Shared size slider chip (right column of font rows)
    function fontSizeChipWidth() { return 168 }

    // Helpers for Fonts tab / panels — safe fallbacks
    function menuTitleFont() {
        void root.colorsTick
        return (bar && bar.fontMainResolved) ? bar.fontMainResolved : bar.fontFamily
    }
    function menuBodyFont() {
        void root.colorsTick
        return (bar && bar.fontSecondaryResolved) ? bar.fontSecondaryResolved : bar.fontFamily
    }
    function barFaceFont() {
        void root.colorsTick
        return (bar && bar.fontBarResolved) ? bar.fontBarResolved : bar.fontFamily
    }

    // Active/hover chip chrome uses button tokens — not accent — so editing Accent
    // does not recolor toolbar labels or tab borders (use Active button / Active button text).
    function chipBorder(active, hovered) {
        if (active || hovered)
            return bar.buttonTextActive !== undefined ? bar.buttonTextActive : bar.pillBorder
        return bar.pillBorder
    }

    function chipText(active, hovered) {
        if (active || hovered)
            return bar.buttonTextActive !== undefined ? bar.buttonTextActive : bar.text
        return bar.buttonText !== undefined ? bar.buttonText : bar.subtext
    }

    // Active control labels inside Themes/Options panels (not accent)
    function activeLabelColor() {
        return bar.buttonTextActive !== undefined ? bar.buttonTextActive : bar.text
    }

    function isWidgetOn(id) {
        void root.menuTick
        if (typeof bar.getWidgetVisible === "function")
            return !!bar.getWidgetVisible(id)
        return false
    }

    function toggleWidget(id) {
        if (typeof bar.toggleWidgetVisible === "function")
            bar.toggleWidgetVisible(id)
        root.menuTick++
        // Keep panel open; only refresh list state
        Qt.callLater(reposition)
    }

    function currentClockFormat() {
        void root.menuTick
        return (bar.clockFormat && String(bar.clockFormat).length)
            ? String(bar.clockFormat)
            : "dddd, MM·dd·yyyy | HH:mm:ss"
    }

    function setClockFormat(fmt) {
        if (typeof bar.setClockFormat === "function")
            bar.setClockFormat(fmt)
        root.clockFormatDraft = String(fmt || "")
        root.menuTick++
        Qt.callLater(reposition)
    }

    function clockFormatIsPreset(fmt) {
        const want = String(fmt || "")
        const presets = root.clockPresets()
        for (let i = 0; i < presets.length; i++) {
            if (presets[i] && presets[i].format === want)
                return true
        }
        return false
    }

    function applyClockFormatDraft() {
        const fmt = String(root.clockFormatDraft || "").trim()
        if (!fmt.length)
            return
        root.setClockFormat(fmt)
    }

    // Widget list for the combined Widgets panel (layout + visibility + scale).
    function widgetEntries() {
        void root.menuTick
        void bar.widgetScales
        const layout = bar.widgetLayout
        const cat = bar.widgetCatalog || []
        const labels = {}
        for (let i = 0; i < cat.length; i++)
            labels[cat[i].id] = cat[i].label
        const out = []
        if (layout && layout.length) {
            for (let i = 0; i < layout.length; i++) {
                const e = layout[i]
                out.push({
                    id: e.id,
                    zone: e.zone,
                    label: labels[e.id] || e.id,
                    on: root.isWidgetOn(e.id)
                })
            }
        } else {
            for (let i = 0; i < cat.length; i++) {
                out.push({
                    id: cat[i].id,
                    zone: (bar.barLayoutMode === "dual") ? "bottom" : "right",
                    label: cat[i].label,
                    on: root.isWidgetOn(cat[i].id)
                })
            }
        }
        // Sort: classic L → C → R, dual T → B, then alphabetical by label
        out.sort(function (a, b) {
            const dual = bar.barLayoutMode === "dual"
            const zoneOrder = dual
                ? { top: 0, bottom: 1 }
                : { left: 0, center: 1, right: 2 }
            const za = zoneOrder[a.zone] !== undefined ? zoneOrder[a.zone] : 9
            const zb = zoneOrder[b.zone] !== undefined ? zoneOrder[b.zone] : 9
            if (za !== zb)
                return za - zb
            const la = String(a.label || a.id).toLowerCase()
            const lb = String(b.label || b.id).toLowerCase()
            if (la < lb)
                return -1
            if (la > lb)
                return 1
            return 0
        })
        return out
    }

    function zoneChoices() {
        void root.menuTick
        if (bar && bar.barLayoutMode === "dual")
            return [
                { id: "top", label: "T" },
                { id: "bottom", label: "B" }
            ]
        return [
            { id: "left", label: "L" },
            { id: "center", label: "C" },
            { id: "right", label: "R" }
        ]
    }

    function clockPresets() {
        return bar.clockFormatPresets || []
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

    function refreshDesktopApps() {
        if (desktopAppsProcess.running)
            return
        root.desktopAppsLoading = true
        const script = bar.desktopAppsJsonScript || ""
        if (!script.length) {
            root.desktopAppsLoading = false
            return
        }
        const args = [script]
        if (root.desktopAppsQuery && root.desktopAppsQuery.length)
            args.push(root.desktopAppsQuery)
        desktopAppsProcess.exec(args)
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
        root.menuTick++
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
        root.menuTick++
        Qt.callLater(reposition)
    }

    function removeLaunchApp(index) {
        if (typeof bar.removeQuickLaunchApp === "function")
            bar.removeQuickLaunchApp(index)
        root.menuTick++
        Qt.callLater(reposition)
    }

    function moveLaunchApp(index, delta) {
        if (typeof bar.moveQuickLaunchApp === "function")
            bar.moveQuickLaunchApp(index, delta)
        root.menuTick++
        Qt.callLater(reposition)
    }

    function filteredDesktopApps() {
        void root.menuTick
        // Script already token-filters + ranks; show more hits so office apps aren't cut off.
        // Autostart also stacks current entries above the picker — keep that list shorter so
        // the panel doesn't bury results below the fold (scroll still available).
        const list = root.desktopApps || []
        const out = []
        const q = root.desktopAppsQuery && root.desktopAppsQuery.length
        const isAs = root.activeMenu === "autostart"
        const max = q ? (isAs ? 50 : 80) : (isAs ? 24 : 60)
        for (let i = 0; i < list.length && out.length < max; i++)
            out.push(list[i])
        return out
    }

    function desktopAppsTruncated() {
        void root.menuTick
        const list = root.desktopApps || []
        const shown = root.filteredDesktopApps().length
        return list.length > shown
    }

    function wallpaperDir() {
        void root.menuTick
        if (bar.wallpaperDir && String(bar.wallpaperDir).length)
            return String(bar.wallpaperDir)
        return "/home/crome/Pictures/wallpapers"
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
            const mon = bar.wallpaperMonitor || "DP-1"
            if (script.length)
                Quickshell.execDetached([script, path, mon])
        }
        wallpaperApplySettle.restart()
        root.menuTick++
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

    // HyprlandFocusGrab is dismissed by any outside press — including the start
    // of a file-manager drag. Close is the panel ✕ / Esc / tab; keep the grab
    // armed so TextFields (search) receive keys. Skip re-arm during a wallpaper drop.
    // Pulse the grab after the popup maps: setting active=true before the surface
    // exists leaves hover dead until the user clicks the panel.
    property bool _armingGrab: false

    function armControlFocusGrab() {
        if (!controlPopup.visible)
            return
        if (typeof controlFocusGrab === "undefined" || !controlFocusGrab)
            return
        if (typeof wpDropArea !== "undefined" && wpDropArea && wpDropArea.containsDrag)
            return
        if (root._armingGrab) {
            controlFocusGrab.active = true
            return
        }
        root._armingGrab = true
        if (controlFocusGrab.active)
            controlFocusGrab.active = false
        Qt.callLater(function() {
            root._armingGrab = false
            if (!controlPopup.visible)
                return
            if (typeof wpDropArea !== "undefined" && wpDropArea && wpDropArea.containsDrag)
                return
            controlFocusGrab.active = true
            if (controlChrome) {
                controlChrome.focus = true
                controlChrome.forceActiveFocus()
            }
            grabRetryTimer.restart()
        })
    }

    function onControlGrabCleared() {
        if (root._armingGrab)
            return
        if (!controlPopup.visible)
            return
        if (root.activeMenu === "wallpaper")
            return
        Qt.callLater(root.armControlFocusGrab)
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
            if (typeof panelBox !== "undefined" && panelBox) {
                px = Math.max(6, Math.min(px, panelBox.width - mw - 6))
                py = Math.max(6, Math.min(py, panelBox.height - mh - 6))
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

    // ── Display (monitor modes via scripts/monitor-mode.sh) ──────────────
    function monitorModeScriptPath() {
        // Resolve relative to this widget so worktrees and ~/.config/quickshell both work.
        try {
            const local = Qt.resolvedUrl("../scripts/monitor-mode.sh").toString().replace("file://", "")
            if (local && local.length)
                return local
        } catch (e) {}
        if (bar.monitorModeScript && String(bar.monitorModeScript).length)
            return String(bar.monitorModeScript)
        return "/home/crome/.config/quickshell/scripts/monitor-mode.sh"
    }

    // Exact match (for applied-vs-pending and EDID labels)
    function displayRateNear(a, b) {
        return Math.abs(Number(a) - Number(b)) < 0.05
    }

    // Family match — EDID reports 239.76 / 239.90 / 239.97 as different values;
    // a 0.05Hz epsilon left only *one* res at "240Hz", which disabled the slider.
    function displayRateBucket(r) {
        const n = Number(r) || 0
        if (n <= 0)
            return 0
        if (n >= 200)
            return 240
        if (n >= 140)
            return 144
        if (n >= 100)
            return 120
        if (n >= 70)
            return 75
        if (n >= 55)
            return 60
        return Math.round(n)
    }

    function displayRateSameFamily(a, b) {
        const ba = root.displayRateBucket(a)
        const bb = root.displayRateBucket(b)
        return ba > 0 && ba === bb
    }

    function displayEntryHasRate(e, rate) {
        if (!e || !e.rates || !(rate > 0))
            return false
        for (let i = 0; i < e.rates.length; i++) {
            if (root.displayRateSameFamily(e.rates[i], rate))
                return true
        }
        return false
    }

    // Rebuild cached filtered list once when catalog or selected rate changes.
    function displayRebuildFilter() {
        const all = root.displayResolutions || []
        const rate = Number(root.displaySelectedRate) || 0
        let out = all
        if (all.length && rate > 0) {
            const filtered = []
            for (let i = 0; i < all.length; i++) {
                if (root.displayEntryHasRate(all[i], rate))
                    filtered.push(all[i])
            }
            if (filtered.length)
                out = filtered
        }
        root.displayFilteredList = out
        if (root.displayResIndex >= out.length)
            root.displayResIndex = Math.max(0, out.length - 1)
        return out
    }

    function displayResEntry() {
        void root.displayTick
        const list = root.displayFilteredList || []
        if (!list.length)
            return null
        const i = Math.max(0, Math.min(root.displayResIndex, list.length - 1))
        return list[i] || null
    }

    // Exact rates for the selected resolution only (from hyprctl).
    function displayPendingRates() {
        void root.displayTick
        const e = root.displayResEntry()
        if (!e || !e.rates)
            return []
        return e.rates
    }

    function displayPendingRes() {
        void root.displayTick
        const e = root.displayResEntry()
        return e && e.res ? String(e.res) : ""
    }

    function displayPendingRate() {
        void root.displayTick
        const r = Number(root.displaySelectedRate) || 0
        if (r > 0)
            return r
        const rates = root.displayPendingRates()
        return rates.length ? Number(rates[0]) : 0
    }

    // Prefer exact EDID mode for this entry in the same rate family as `rate`.
    function displayModeForEntryRate(e, rate) {
        if (!e)
            return ""
        if (e.modes && e.rates) {
            let bestIdx = -1
            let bestDiff = 1e9
            for (let i = 0; i < e.rates.length; i++) {
                if (!root.displayRateSameFamily(e.rates[i], rate))
                    continue
                const d = Math.abs(Number(e.rates[i]) - Number(rate))
                if (d < bestDiff) {
                    bestDiff = d
                    bestIdx = i
                }
            }
            if (bestIdx >= 0 && e.modes[bestIdx])
                return String(e.modes[bestIdx])
            // Fallback: any mode on this entry
            if (e.modes[0])
                return String(e.modes[0])
        }
        if (e.res && rate > 0)
            return String(e.res) + "@" + rate
        return ""
    }

    function displayPendingMode() {
        void root.displayTick
        return root.displayModeForEntryRate(root.displayResEntry(), root.displayPendingRate())
    }

    function displayFormatRate(r) {
        const all = root.displayResolutions || []
        for (let i = 0; i < all.length; i++) {
            const e = all[i]
            if (!e || !e.rateLabels || !e.rates)
                continue
            for (let j = 0; j < e.rates.length; j++) {
                if (root.displayRateNear(e.rates[j], r) && e.rateLabels[j])
                    return String(e.rateLabels[j])
            }
        }
        const n = Number(r)
        if (!(n > 0))
            return "—"
        if (Math.abs(n - Math.round(n)) < 0.005)
            return String(Math.round(n))
        return n.toFixed(2)
    }

    function displayCloseMenus() {
        root.displayRateMenuOpen = false
        root.displayBitdepthMenuOpen = false
    }

    function openNvidiaPanel() {
        Quickshell.execDetached(["nvidia-settings"])
    }

    function displayNotifyUi() {
        // Selection-only refresh — do NOT bump menuTick (avoids layout thrash / slider cancel)
        root.displayTick++
    }

    function displayCurrentLabel() {
        void root.displayTick
        void root.displayGpuTick
        void root.displayInfo
        const info = root.displayInfo || {}
        const w = info.width || 0
        const h = info.height || 0
        const rate = info.refreshRate || 0
        const bd = info.bitdepth || 0
        if (!(w > 0 && h > 0))
            return root.displayLoading ? "Loading…" : "No monitor data"
        return w + "×" + h + " @ " + root.displayFormatRate(rate) + " Hz · " + bd + "-bit"
    }

    function displayIdentityLabel() {
        void root.displayTick
        void root.displayInfo
        const info = root.displayInfo || {}
        const parts = []
        if (info.make)
            parts.push(String(info.make))
        if (info.model)
            parts.push(String(info.model))
        if (info.serial)
            parts.push(String(info.serial))
        return parts.length ? parts.join(" · ") : (info.description || "—")
    }

    function displayConnectorLabel() {
        void root.displayTick
        void root.displayInfo
        const info = root.displayInfo || {}
        const name = info.name || ""
        const fmt = info.format || ""
        const scale = info.scale !== undefined ? Number(info.scale) : 0
        const parts = []
        if (name)
            parts.push(String(name))
        if (fmt)
            parts.push(String(fmt))
        if (scale > 0)
            parts.push("scale " + scale.toFixed(2))
        if (info.vrr)
            parts.push("VRR on")
        return parts.join(" · ")
    }

    function displayMetaLabel() {
        void root.displayTick
        void root.displayInfo
        const info = root.displayInfo || {}
        const parts = []
        const pw = Number(info.physicalWidth) || 0
        const ph = Number(info.physicalHeight) || 0
        if (pw > 0 && ph > 0) {
            const inch = Math.sqrt(pw * pw + ph * ph) / 25.4
            parts.push(pw + "×" + ph + " mm · ~" + inch.toFixed(1) + "\"")
        }
        if (info.x !== undefined && info.y !== undefined)
            parts.push("pos " + info.x + "," + info.y)
        if (info.colorManagementPreset)
            parts.push(String(info.colorManagementPreset))
        if (info.dpmsStatus === false)
            parts.push("DPMS off")
        return parts.join(" · ")
    }

    function displayAdapterLabel() {
        void root.displayGpuTick
        void root.displayInfo
        const info = root.displayInfo || {}
        const a = info.adapter || {}
        const g = info.gpu || {}
        const gpuName = (g && g.name) ? String(g.name)
                        : (a && a.pciName) ? String(a.pciName) : ""
        const driver = (g && g.driver) ? ("driver " + g.driver)
                       : (a && a.driver) ? ("drm " + a.driver) : ""
        const conn = (a && a.connector) ? String(a.connector) : ""
        const pci = (a && a.pci) ? String(a.pci) : ((g && g.pciBus) ? String(g.pciBus) : "")
        const parts = []
        if (gpuName)
            parts.push(gpuName)
        if (driver)
            parts.push(driver)
        if (conn)
            parts.push(conn)
        if (pci)
            parts.push(pci)
        return parts.length ? parts.join(" · ") : "Adapter unknown"
    }

    function displayGpuStatsLine1() {
        void root.displayGpuTick
        void root.displayInfo
        const g = (root.displayInfo && root.displayInfo.gpu) ? root.displayInfo.gpu : null
        if (!g || !g.available)
            return "GPU stats unavailable (nvidia-smi)"
        const util = (g.utilGpu !== undefined) ? Math.round(Number(g.utilGpu)) : 0
        const temp = (g.tempC !== undefined) ? Math.round(Number(g.tempC)) : 0
        const pstate = g.pstate || "—"
        const power = (g.powerW !== undefined) ? Number(g.powerW).toFixed(0) : "—"
        const plim = (g.powerLimitW !== undefined) ? Number(g.powerLimitW).toFixed(0) : "—"
        return "GPU " + util + "% · " + temp + "°C · " + pstate
               + " · " + power + "/" + plim + " W"
    }

    function displayGpuStatsLine2() {
        void root.displayGpuTick
        void root.displayInfo
        const g = (root.displayInfo && root.displayInfo.gpu) ? root.displayInfo.gpu : null
        if (!g || !g.available)
            return ""
        const used = (g.memUsedMiB !== undefined) ? Math.round(Number(g.memUsedMiB)) : 0
        const total = (g.memTotalMiB !== undefined) ? Math.round(Number(g.memTotalMiB)) : 0
        const memUtil = (g.utilMem !== undefined) ? Math.round(Number(g.utilMem)) : 0
        const gfx = (g.clockGfxMHz !== undefined) ? Math.round(Number(g.clockGfxMHz)) : 0
        const memClk = (g.clockMemMHz !== undefined) ? Math.round(Number(g.clockMemMHz)) : 0
        const usedGi = (used / 1024).toFixed(1)
        const totalGi = (total / 1024).toFixed(1)
        return "VRAM " + usedGi + "/" + totalGi + " GiB (" + memUtil + "%)"
               + " · " + gfx + " / " + memClk + " MHz"
    }

    function displayGpuMemFrac() {
        void root.displayGpuTick
        void root.displayInfo
        const g = (root.displayInfo && root.displayInfo.gpu) ? root.displayInfo.gpu : null
        if (!g || !g.available)
            return 0
        const used = Number(g.memUsedMiB) || 0
        const total = Number(g.memTotalMiB) || 0
        if (total <= 0)
            return 0
        return Math.max(0, Math.min(1, used / total))
    }

    function displayGpuUtilFrac() {
        void root.displayGpuTick
        void root.displayInfo
        const g = (root.displayInfo && root.displayInfo.gpu) ? root.displayInfo.gpu : null
        if (!g || !g.available)
            return 0
        return Math.max(0, Math.min(1, (Number(g.utilGpu) || 0) / 100))
    }

    function displayHasPendingChange() {
        void root.displayTick
        const info = root.displayInfo || {}
        const pendRes = root.displayPendingRes()
        const pendRate = root.displayPendingRate()
        const pendBd = root.displayBitdepth
        if (!pendRes.length || !(pendRate > 0))
            return false
        const curRes = (info.width && info.height) ? (info.width + "x" + info.height) : ""
        const curRate = Number(info.refreshRate) || 0
        const curBd = Number(info.bitdepth) || 0
        const rateMatch = root.displayRateNear(curRate, pendRate)
        return pendRes !== curRes || !rateMatch || pendBd !== curBd
    }

    function displayFindResIndex(list, res) {
        if (!list || !res)
            return 0
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].res === res)
                return i
        }
        return 0
    }

    // Closest catalog rate on entry in the same family as preferred (else highest).
    function displayPickRateOnEntry(e, preferred) {
        if (!e || !e.rates || !e.rates.length)
            return 0
        if (preferred > 0) {
            let best = -1
            let bestDiff = 1e9
            for (let i = 0; i < e.rates.length; i++) {
                if (!root.displayRateSameFamily(e.rates[i], preferred))
                    continue
                const d = Math.abs(Number(e.rates[i]) - Number(preferred))
                if (d < bestDiff) {
                    bestDiff = d
                    best = i
                }
            }
            if (best >= 0)
                return Number(e.rates[best])
        }
        return Number(e.rates[0]) || 0
    }

    function displaySyncPendingFromInfo() {
        const info = root.displayInfo || {}
        const all = root.displayResolutions || []
        if (!all.length)
            return
        const curRes = (info.width && info.height) ? (String(info.width) + "x" + String(info.height)) : ""
        const curRate = Number(info.refreshRate) || 0
        const curBd = Number(info.bitdepth) || 10

        let matchedRate = curRate
        for (let i = 0; i < all.length; i++) {
            if (all[i] && all[i].res === curRes && all[i].rates) {
                matchedRate = root.displayPickRateOnEntry(all[i], curRate)
                break
            }
        }
        root.displaySelectedRate = matchedRate
        root.displayBitdepth = (curBd === 8) ? 8 : 10
        root.displayRebuildFilter()
        root.displayResIndex = root.displayFindResIndex(root.displayFilteredList, curRes)
        root.displayCloseMenus()
        root.displayNotifyUi()
    }

    // Slider step within rate-family-filtered list. Snap selected rate to this
    // entry's exact EDID value in the same family (no refilter — list stays stable).
    function displayOnResIndexChanged(newIndex) {
        const list = root.displayFilteredList || []
        if (!list.length)
            return
        const i = Math.max(0, Math.min(Math.round(newIndex), list.length - 1))
        const e = list[i]
        if (!e)
            return
        if (i === root.displayResIndex) {
            // Still snap rate if needed (exact EDID for Apply)
            const snapped = root.displayPickRateOnEntry(e, root.displaySelectedRate)
            if (snapped > 0 && !root.displayRateNear(snapped, root.displaySelectedRate)) {
                root.displaySelectedRate = snapped
                root.displayNotifyUi()
            }
            return
        }
        root.displayResIndex = i
        // Keep family; use this panel's exact Hz so Apply gets a real mode string
        const snapped = root.displayPickRateOnEntry(e, root.displaySelectedRate)
        if (snapped > 0)
            root.displaySelectedRate = snapped
        root.displayNotifyUi()
    }

    // Rate chosen: refilter resolutions to the same Hz *family* (e.g. all ~240).
    function displaySelectRate(rate) {
        const r = Number(rate) || 0
        if (!(r > 0))
            return
        if (root.displayRateNear(r, root.displaySelectedRate)) {
            root.displayCloseMenus()
            return
        }
        const prevRes = root.displayPendingRes()
        root.displaySelectedRate = r
        root.displayRebuildFilter()
        root.displayResIndex = root.displayFindResIndex(root.displayFilteredList, prevRes)
        // Snap to exact rate on the chosen res in this family
        const e = root.displayResEntry()
        if (e) {
            const snapped = root.displayPickRateOnEntry(e, r)
            if (snapped > 0)
                root.displaySelectedRate = snapped
        }
        root.displayCloseMenus()
        root.displayNotifyUi()
    }

    function displaySelectBitdepth(bd) {
        const v = (Number(bd) === 8) ? 8 : 10
        if (v === root.displayBitdepth) {
            root.displayCloseMenus()
            return
        }
        root.displayBitdepth = v
        root.displayCloseMenus()
        root.displayNotifyUi()
    }

    function refreshDisplay() {
        if (displayStatusProcess.running || displayListProcess.running)
            return
        root.displayFullFetch = true
        root.displayLoading = true
        root.displayError = ""
        root.displayStatus = "Loading…"
        root.displayCloseMenus()
        const script = root.monitorModeScriptPath()
        if (!script.length) {
            root.displayLoading = false
            root.displayFullFetch = false
            root.displayError = "monitor-mode script missing"
            root.displayStatus = ""
            return
        }
        displayStatusProcess.exec([script, "status-json"])
        displayListProcess.exec([script, "list-json"])
    }

    // Soft GPU/monitor status — Display panel only; never while dragging the slider
    function refreshDisplayStatusOnly() {
        if (!controlPopup.visible || root.activeMenu !== "display")
            return
        if (root.displaySliderPressed || root.displayApplying || root.displayLoading)
            return
        if (displayStatusProcess.running || displayListProcess.running)
            return
        const script = root.monitorModeScriptPath()
        if (!script.length)
            return
        root.displayFullFetch = false
        displayStatusProcess.exec([script, "status-json"])
    }

    function applyDisplayMode() {
        if (root.displayApplying || displayApplyProcess.running)
            return
        const mode = root.displayPendingMode()
        if (!mode.length) {
            root.displayError = "Select a resolution and refresh rate"
            return
        }
        const script = root.monitorModeScriptPath()
        if (!script.length) {
            root.displayError = "monitor-mode script missing"
            return
        }
        root.displayApplying = true
        root.displayError = ""
        root.displayStatus = "Applying " + mode + " · " + root.displayBitdepth + "-bit…"
        root.displayCloseMenus()
        displayApplyProcess.exec([script, "apply", mode, String(root.displayBitdepth)])
        root.displayTick++
        root.menuTick++
    }

    function openWallpaperDir() {
        const d = root.wallpaperDir()
        if (d.length)
            Quickshell.execDetached(["xdg-open", d])
    }

    function scalePercentOf(id) {
        // Depend on widgetScales so bindings refresh without menuTick thrash
        void bar.widgetScales
        if (typeof bar.widgetScale === "function")
            return Math.round(bar.widgetScale(id) * 100)
        return 100
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
        autostartSetProcess.exec([script, "remove", id])
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
        Quickshell.execDetached(["xdg-open", "/home/crome/.config/autostart"])
    }

    function setScalePercent(id, percent) {
        let p = Number(percent)
        if (!(p > 0))
            return
        if (p < 80)
            p = 80
        if (p > 180)
            p = 180
        if (typeof bar.setWidgetScale === "function")
            bar.setWidgetScale(id, p / 100)
        // Do not bump menuTick / full panel rebuild while dragging — bar.widgetScales notifies
        sizeRepositionTimer.restart()
    }

    Connections {
        target: bar
        function onBarPositionChanged() {
            if (controlPopup.visible)
                root.scheduleReposition()
        }
        function onClockFormatChanged() {
            root.menuTick++
        }
    }

    Timer {
        id: desktopSearchDebounce
        interval: 280
        repeat: false
        onTriggered: root.refreshDesktopApps()
    }

    Timer {
        id: settleRepositionTimer
        interval: 48
        repeat: false
        onTriggered: {
            root.reposition()
            if (controlPopup.visible)
                root.armControlFocusGrab()
        }
    }

    Timer {
        id: grabRetryTimer
        interval: 90
        repeat: false
        onTriggered: {
            if (!controlPopup.visible)
                return
            if (controlFocusGrab && controlFocusGrab.active)
                return
            root.armControlFocusGrab()
        }
    }

    // Light debounce when sizes change (avoid reposition every slider step)
    Timer {
        id: sizeRepositionTimer
        interval: 80
        repeat: false
        onTriggered: root.reposition()
    }

    Timer {
        id: wallpaperApplySettle
        interval: 400
        repeat: false
        onTriggered: {
            root.wallpaperBusyPath = ""
            root.wallpaperStatus = "Applied"
            root.menuTick++
        }
    }

    function _displayMaybeFinishFetch() {
        if (displayStatusProcess.running || displayListProcess.running)
            return
        const full = root.displayFullFetch
        root.displayLoading = false
        if (full) {
            root.displayFullFetch = false
            if (!root.displayError.length && !root.displayApplying)
                root.displayStatus = root.displayResolutions.length
                    ? (root.displayResolutions.length + " resolution(s)")
                    : "No modes"
            if ((root.displayResolutions || []).length)
                root.displaySyncPendingFromInfo()
            root.displayGpuTick++
            root.menuTick++
            if (controlPopup.visible)
                root.scheduleReposition()
        } else {
            // Soft poll: update GPU/indicator bindings only — never touch selection or layout
            root.displayGpuTick++
        }
    }

    // Live GPU stats — ONLY while Display is open; paused during slider drag / apply / load
    Timer {
        id: displayStatsTimer
        interval: 3000
        repeat: true
        running: controlPopup.visible
                 && root.activeMenu === "display"
                 && !root.displayApplying
                 && !root.displayLoading
                 && !root.displaySliderPressed
        onTriggered: root.refreshDisplayStatusOnly()
    }

    Io.Process {
        id: displayStatusProcess
        running: false
        stdout: Io.StdioCollector {
            id: displayStatusStdout
            onStreamFinished: {
                const text = (displayStatusStdout.text || "").trim()
                if (text.startsWith("{")) {
                    try {
                        root.displayInfo = JSON.parse(text)
                    } catch (e) {
                        if (root.displayFullFetch)
                            root.displayError = "Status parse error"
                    }
                } else if (root.displayFullFetch && !root.displayError.length) {
                    root.displayError = "Failed to read monitor status"
                }
            }
        }
        onExited: (code) => {
            if (root.displayFullFetch && code !== 0 && !(displayStatusStdout.text || "").trim())
                root.displayError = "status-json failed (" + code + ")"
            // Always re-check; list process may still be running
            root._displayMaybeFinishFetch()
        }
    }

    Io.Process {
        id: displayListProcess
        running: false
        stdout: Io.StdioCollector {
            id: displayListStdout
            onStreamFinished: {
                const text = (displayListStdout.text || "").trim()
                if (text.startsWith("{")) {
                    try {
                        const j = JSON.parse(text)
                        root.displayResolutions = j.resolutions || []
                        root.displayRebuildFilter()
                    } catch (e) {
                        root.displayResolutions = []
                        root.displayFilteredList = []
                        root.displayError = "List parse error"
                    }
                } else {
                    root.displayResolutions = []
                    root.displayFilteredList = []
                    if (!root.displayError.length)
                        root.displayError = "Failed to list modes"
                }
            }
        }
        onExited: (code) => {
            if (code !== 0 && !(displayListStdout.text || "").trim()) {
                root.displayResolutions = []
                root.displayFilteredList = []
                root.displayError = "list-json failed (" + code + ")"
            }
            root._displayMaybeFinishFetch()
        }
    }

    Io.Process {
        id: displayApplyProcess
        running: false
        stdout: Io.StdioCollector {
            id: displayApplyStdout
            onStreamFinished: {
                const text = (displayApplyStdout.text || "").trim()
                if (text.startsWith("{")) {
                    try {
                        root.displayInfo = JSON.parse(text)
                        root.displayError = ""
                        root.displayStatus = "Applied · " + root.displayCurrentLabel()
                        root.displaySyncPendingFromInfo()
                        root.displayGpuTick++
                    } catch (e) {
                        root.displayError = "Apply parse error"
                    }
                }
                root.displayApplying = false
            }
        }
        onExited: (code) => {
            root.displayApplying = false
            if (code !== 0) {
                const t = (displayApplyStdout.text || "").trim()
                root.displayError = t.length
                    ? t.replace(/^error:\s*/i, "").slice(0, 160)
                    : ("Apply failed (" + code + ")")
                root.displayStatus = ""
                root.displayNotifyUi()
            } else if (root.activeMenu === "display") {
                // One catalog refresh after successful apply (not a poll loop)
                Qt.callLater(function () { root.refreshDisplay() })
            }
        }
    }

    Io.Process {
        id: desktopAppsProcess
        running: false
        stdout: Io.StdioCollector {
            id: desktopAppsStdout
            onStreamFinished: {
                root.desktopAppsLoading = false
                const text = (desktopAppsStdout.text || "").trim()
                if (!text.startsWith("[")) {
                    root.desktopApps = []
                    return
                }
                try {
                    root.desktopApps = JSON.parse(text)
                } catch (e) {
                    root.desktopApps = []
                }
                root.menuTick++
                if (controlPopup.visible)
                    root.scheduleReposition()
            }
        }
        onExited: (code) => {
            root.desktopAppsLoading = false
            if (code !== 0 && !(desktopAppsStdout.text || "").trim())
                root.desktopApps = []
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
                root.menuTick++
                if (controlPopup.visible)
                    root.scheduleReposition()
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
                if (typeof bar.setWallpaperDir === "function")
                    bar.setWallpaperDir(dir)
                root.wallpaperStatus = "Folder: " + dir
                root.menuTick++
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
                                && typeof bar.setWallpaperCurrent === "function")
                            bar.setWallpaperCurrent("")
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
                root.menuTick++
                if (controlPopup.visible)
                    root.scheduleReposition()
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

    Io.Process {
        id: frSecretsReadProcess
        running: false
        stdout: Io.StdioCollector {
            id: frSecretsReadStdout
            onStreamFinished: {
                root.frLoading = false
                const text = (frSecretsReadStdout.text || "").trim()
                if (!text.startsWith("{")) {
                    root.frStatus = "No secrets file yet"
                    return
                }
                try {
                    const j = JSON.parse(text)
                    root.frScheme = j.scheme === "http" ? "http" : "https"
                    root.frHost = j.host || ""
                    root.frUser = j.user || ""
                    root.frHasPassword = !!j.hasPassword
                    root.frPassword = ""
                    root.frStatus = j.exists
                        ? ("Loaded · " + (j.hasPassword ? "API password set" : "no API password"))
                        : "No secrets file — fill and Save"
                } catch (e) {
                    root.frStatus = "Parse error"
                }
                root.optionsTick++
            }
        }
        onExited: (code) => {
            root.frLoading = false
            if (code !== 0)
                root.frStatus = "Read failed"
        }
    }

    Io.Process {
        id: frSecretsWriteProcess
        running: false
        stdout: Io.StdioCollector {
            id: frSecretsWriteStdout
            onStreamFinished: {
                root.frLoading = false
                const text = (frSecretsWriteStdout.text || "").trim()
                if (text.startsWith("{")) {
                    try {
                        const j = JSON.parse(text)
                        root.frStatus = j.ok ? ("Saved · " + (j.baseUrl || "")) : "Save failed"
                        root.frPassword = ""
                        root.frHasPassword = !!j.hasPassword
                    } catch (e) {
                        root.frStatus = "Saved"
                        root.frPassword = ""
                    }
                } else {
                    root.frStatus = text.length ? text : "Saved"
                    root.frPassword = ""
                }
                root.refreshFreshRssSecrets()
            }
        }
        onExited: (code) => {
            root.frLoading = false
            if (code !== 0)
                root.frStatus = "Save failed"
        }
    }

    Io.Process {
        id: frConnectionTestProcess
        running: false
        stdout: Io.StdioCollector {
            id: frConnectionTestStdout
            onStreamFinished: {
                root.frLoading = false
                const text = (frConnectionTestStdout.text || "").trim()
                if (text.startsWith("{")) {
                    try {
                        const j = JSON.parse(text)
                        if (j.ok)
                            root.frStatus = j.message || ("OK · " + (j.mode || "connected"))
                        else
                            root.frStatus = j.message || ("Failed · " + (j.error || "connection failed"))
                    } catch (e) {
                        root.frStatus = "Test parse error"
                    }
                } else {
                    root.frStatus = text.length ? text : "Test failed"
                }
                root.optionsTick++
            }
        }
        onExited: (code) => {
            root.frLoading = false
            if (code !== 0 && !(frConnectionTestStdout.text || "").trim())
                root.frStatus = "Test failed"
        }
    }

    // -------------------------------------------------------------------------
    // One popup: toolbar row + optional expandable panel
    // grabFocus (Qt::Popup) dismisses on any outside press, which also fires
    // when a file-manager drag starts — so Wallpaper DnD would close the panel.
    // HyprlandFocusGrab restores click-outside-to-close for every other tab.
    // -------------------------------------------------------------------------
    HyprlandFocusGrab {
        id: controlFocusGrab
        windows: {
            void bar.layoutEpoch
            void bar.barLayoutMode
            void controlPopup.visible
            void controlPopup.implicitWidth
            void controlPopup.implicitHeight
            const list = [controlPopup, bar]
            if (bar && bar.barLayoutMode === "dual" && bar.bottomBarWindow)
                list.push(bar.bottomBarWindow)
            return list
        }
        onCleared: root.onControlGrabCleared()
    }

    PopupWindow {
        id: controlPopup
        anchor.window: bar
        implicitWidth: controlChrome.implicitWidth
        implicitHeight: controlChrome.implicitHeight
        visible: false
        grabFocus: false
        color: "transparent"

        Shortcut {
            sequences: ["Escape"]
            enabled: controlPopup.visible
            context: Qt.ApplicationShortcut
            onActivated: root.hide()
        }

        onVisibleChanged: {
            if (visible) {
                root.armControlFocusGrab()
                return
            }
            if (root.activeMenu === "wallpaper"
                    && typeof wpDropArea !== "undefined" && wpDropArea
                    && wpDropArea.containsDrag) {
                Qt.callLater(function() {
                    controlPopup.visible = true
                    root.activeMenu = "wallpaper"
                    root.scheduleReposition()
                })
                return
            }
            root._closedAtMs = Date.now()
            root.activeMenu = ""
        }

        onImplicitWidthChanged: if (visible) root.scheduleReposition()
        onImplicitHeightChanged: if (visible) root.scheduleReposition()

        Rectangle {
            id: controlChrome
            implicitWidth: Math.max(mainCol.implicitWidth + root.pad * 2,
                                    (root.activeMenu === "wallpaper"
                                     || root.activeMenu === "options"
                                     || root.activeMenu === "colors"
                                     || root.activeMenu === "widgets"
                                     || root.activeMenu === "display"
                                     || root.activeMenu === "clock"
                                     || root.activeMenu === "mime"
                                     || root.activeMenu === "services"
                                     || root.activeMenu === "audio"
                                     || root.activeMenu === "keybinds")
                                        ? ((root.activeMenu === "mime"
                                            || root.activeMenu === "services"
                                            || root.activeMenu === "audio"
                                            || root.activeMenu === "keybinds") ? 620
                                           : (root.activeMenu === "colors" ? 560 : 520))
                                        : 420)
            implicitHeight: mainCol.implicitHeight + root.pad * 2
            radius: bar.popupRadius !== undefined ? bar.popupRadius : bar.barRadius
            color: bar.glassPopupBg
            border.width: bar.controlBorderWidth
            border.color: bar.glassPopupBorder

            // Keep clicks on empty chrome from falling through / dismissing oddly
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: (mouse) => { mouse.accepted = true }
                // Let children receive events — z below content
                z: -1
            }

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassPopupHighlight
                radius: parent.radius
                z: 2
            }

            ColumnLayout {
                id: mainCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: root.pad
                spacing: 8

                // ── Expandable panel (same window so clicks stay in this popup) ──
                Rectangle {
                    id: panelBox
                    visible: root.activeMenu.length > 0
                    Layout.fillWidth: true
                    // Margins (8×2) + slack; height tracks active menu content up to panelMaxH
                    readonly property int panelPad: 18
                    readonly property int contentH: {
                        void root.menuTick
                        void root.activeMenu
                        void root.wallpaperTilePref
                        return root.measurePanelContent()
                    }
                    Layout.preferredHeight: {
                        void root.menuTick
                        void root.activeMenu
                        void root.wallpaperTilePref
                        if (!visible)
                            return 0
                        // Fit content; screen-cap (and scroll) only for tall menus
                        const need = panelBox.contentH + panelPad
                        if (need <= 0)
                            return 72
                        if (root.panelScrollableMenu)
                            return Math.min(root.panelMaxH, Math.max(48, need))
                        // Position / Clock etc.: hug content (still never exceed screen)
                        return Math.min(root.panelMaxH, Math.max(48, need))
                    }
                    Layout.minimumHeight: visible ? 48 : 0
                    Layout.maximumHeight: root.panelMaxH
                    radius: root.chipR
                    color: Qt.rgba(0.05, 0.05, 0.07, 0.85)
                    border.width: bar.controlBorderWidth
                    border.color: bar.dividerStrong
                    clip: true

                    DropArea {
                        id: wpDropArea
                        anchors.fill: parent
                        // Never bind Item.enabled here — that disables this whole
                        // tree (Flickable + every panel), which killed wheel-scroll
                        // on Widgets / Options / Themes / Launch / Audio / Keybinds.
                        // Wallpaper drops are filtered in onEntered / onDropped.

                        onEntered: (drag) => {
                            if (root.activeMenu === "wallpaper")
                                drag.accept(Qt.CopyAction)
                        }
                        onExited: root.armControlFocusGrab()
                        onDropped: (drop) => {
                            if (root.activeMenu !== "wallpaper")
                                return
                            if (drop.hasUrls)
                                root.addDroppedWallpapers(drop.urls)
                            drop.accept(Qt.CopyAction)
                            root.armControlFocusGrab()
                        }

                        Flickable {
                            id: panelFlick
                            anchors.fill: parent
                            anchors.margins: 8
                            anchors.rightMargin: 38
                        contentWidth: width
                        // Only the visible section — never the sum of hidden menus
                        contentHeight: {
                            void root.menuTick
                            void root.activeMenu
                            void root.wallpaperTilePref
                            return Math.max(root.measurePanelContent(), 1)
                        }
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.VerticalFlick
                        // Scroll only when content exceeds the panel (Wallpaper/Widgets/Autostart/Launch)
                        // Disable scrolling while the color picker is open — Flickable
                        // otherwise steals vertical drag from the SV square / hue strip.
                        // Themes panel scrolls internally (sticky tabs) — never use outer flick
                        interactive: root.panelNeedsScroll
                                     && (contentHeight > height + 4)
                                     && !root.panelUsesInnerScroll

                        onContentHeightChanged: {
                            if (contentHeight <= height + 4)
                                contentY = 0
                            else if (contentY > contentHeight - height)
                                contentY = Math.max(0, contentHeight - height)
                        }
                        onHeightChanged: {
                            if (contentHeight <= height + 4)
                                contentY = 0
                            else if (contentY > contentHeight - height)
                                contentY = Math.max(0, contentHeight - height)
                        }

                        ScrollBar.vertical: ScrollBar {
                            id: panelScrollBar
                            policy: (root.panelNeedsScroll && panelFlick.contentHeight > panelFlick.height + 4)
                                    ? ScrollBar.AsNeeded
                                    : ScrollBar.AlwaysOff
                            width: 8
                            padding: 1
                            contentItem: Rectangle {
                                implicitWidth: 6
                                radius: 3
                                color: bar.accent
                                opacity: 0.55
                            }
                            background: Rectangle {
                                implicitWidth: 8
                                radius: 4
                                color: Qt.rgba(1, 1, 1, 0.06)
                            }
                        }

                        ColumnLayout {
                            id: panelStack
                            width: panelFlick.width - ((root.panelNeedsScroll && panelFlick.contentHeight > panelFlick.height + 4) ? 10 : 0)
                            spacing: 6

                            // ===== POSITION =====
                            ColumnLayout {
                                visible: root.activeMenu === "position"
                                Layout.fillWidth: true
                                spacing: 10

                                Text {
                                    text: "Bar position"
                                    color: bar.text
                                    font.pixelSize: bar.popupTitleSize
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Text {
                                    text: (bar.barLayoutMode === "dual")
                                          ? "Dual layout uses a centered bar on both edges. Switch to Classic for a single bar."
                                          : "Pin the status bar to the top or bottom edge"
                                    color: bar.subtext
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontFamily
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: "Layout"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 52
                                    Layout.minimumHeight: 52
                                    spacing: 8

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Layout.preferredHeight: 52
                                        Layout.minimumHeight: 52
                                        radius: root.chipR
                                        color: (bar.barLayoutMode !== "dual")
                                               ? (bar.controlActiveBg || Qt.rgba(0, 0.77, 0.96, 0.22))
                                               : (modeClassicMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg))
                                        border.width: bar.controlBorderWidth
                                        border.color: (bar.barLayoutMode !== "dual") ? root.activeLabelColor() : bar.pillBorder
                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            anchors.topMargin: 8
                                            anchors.bottomMargin: 8
                                            spacing: 0
                                            Text {
                                                text: "Classic"
                                                font.pixelSize: 13
                                                font.bold: bar.barLayoutMode !== "dual"
                                                font.family: bar.fontFamily
                                                color: bar.barLayoutMode !== "dual" ? root.activeLabelColor() : bar.text
                                            }
                                            Text {
                                                text: "One bar · L / C / R"
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                color: bar.subtext
                                            }
                                        }
                                        MouseArea {
                                            id: modeClassicMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (typeof bar.setBarLayoutMode === "function")
                                                    bar.setBarLayoutMode("classic")
                                                root.menuTick++
                                                Qt.callLater(root.reposition)
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Layout.preferredHeight: 52
                                        Layout.minimumHeight: 52
                                        radius: root.chipR
                                        color: (bar.barLayoutMode === "dual")
                                               ? (bar.controlActiveBg || Qt.rgba(0, 0.77, 0.96, 0.22))
                                               : (modeDualMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg))
                                        border.width: bar.controlBorderWidth
                                        border.color: (bar.barLayoutMode === "dual") ? root.activeLabelColor() : bar.pillBorder
                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            anchors.topMargin: 8
                                            anchors.bottomMargin: 8
                                            spacing: 0
                                            Text {
                                                text: "Dual"
                                                font.pixelSize: 13
                                                font.bold: bar.barLayoutMode === "dual"
                                                font.family: bar.fontFamily
                                                color: bar.barLayoutMode === "dual" ? root.activeLabelColor() : bar.text
                                            }
                                            Text {
                                                text: "Top + bottom · centered"
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                color: bar.subtext
                                            }
                                        }
                                        MouseArea {
                                            id: modeDualMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (typeof bar.setBarLayoutMode === "function")
                                                    bar.setBarLayoutMode("dual")
                                                root.menuTick++
                                                Qt.callLater(root.reposition)
                                            }
                                        }
                                    }
                                }

                                Text {
                                    visible: bar.barLayoutMode !== "dual"
                                    text: "Edge"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }

                                RowLayout {
                                    visible: bar.barLayoutMode !== "dual"
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 52
                                    Layout.minimumHeight: 52
                                    spacing: 8

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Layout.preferredHeight: 52
                                        Layout.minimumHeight: 52
                                        radius: root.chipR
                                        color: (bar.barPosition === "top")
                                               ? (bar.controlActiveBg || Qt.rgba(0, 0.77, 0.96, 0.22))
                                               : (posTopMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg))
                                        border.width: bar.controlBorderWidth
                                        border.color: (bar.barPosition === "top") ? root.activeLabelColor() : bar.pillBorder
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            anchors.topMargin: 10
                                            anchors.bottomMargin: 10
                                            spacing: 8
                                            Text {
                                                Layout.alignment: Qt.AlignVCenter
                                                text: bar.barPositionIconTop
                                                font.pixelSize: bar.iconSizePill
                                                font.family: bar.fontFamily
                                                color: bar.barPosition === "top" ? root.activeLabelColor() : bar.subtext
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignVCenter
                                                text: "Top"
                                                font.pixelSize: 13
                                                font.bold: bar.barPosition === "top"
                                                font.family: bar.fontFamily
                                                color: bar.barPosition === "top" ? root.activeLabelColor() : bar.text
                                            }
                                            Item { Layout.fillWidth: true }
                                        }
                                        MouseArea {
                                            id: posTopMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (typeof bar.setBarPosition === "function")
                                                    bar.setBarPosition("top")
                                                Qt.callLater(root.reposition)
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Layout.preferredHeight: 52
                                        Layout.minimumHeight: 52
                                        radius: root.chipR
                                        color: (bar.barPosition === "bottom")
                                               ? (bar.controlActiveBg || Qt.rgba(0, 0.77, 0.96, 0.22))
                                               : (posBotMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg))
                                        border.width: bar.controlBorderWidth
                                        border.color: (bar.barPosition === "bottom") ? root.activeLabelColor() : bar.pillBorder
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            anchors.topMargin: 10
                                            anchors.bottomMargin: 10
                                            spacing: 8
                                            Text {
                                                Layout.alignment: Qt.AlignVCenter
                                                text: bar.barPositionIconBottom
                                                font.pixelSize: bar.iconSizePill
                                                font.family: bar.fontFamily
                                                color: bar.barPosition === "bottom" ? root.activeLabelColor() : bar.subtext
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignVCenter
                                                text: "Bottom"
                                                font.pixelSize: 13
                                                font.bold: bar.barPosition === "bottom"
                                                font.family: bar.fontFamily
                                                color: bar.barPosition === "bottom" ? root.activeLabelColor() : bar.text
                                            }
                                            Item { Layout.fillWidth: true }
                                        }
                                        MouseArea {
                                            id: posBotMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (typeof bar.setBarPosition === "function")
                                                    bar.setBarPosition("bottom")
                                                Qt.callLater(root.reposition)
                                            }
                                        }
                                    }
                                }

                                Text {
                                    text: "Inset & size"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 48
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        anchors.topMargin: 6
                                        anchors.bottomMargin: 6
                                        spacing: 2
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: "Gap from edge"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: root.optBarEdgeMargin() + " px"
                                                color: bar.subtext
                                                font.pixelSize: 11
                                                font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                Layout.preferredWidth: root.optControlColW
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                        }
                                        Slider {
                                            id: posEdgeSlider
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 16
                                            from: 0
                                            to: 48
                                            stepSize: 2
                                            value: root.optBarEdgeMargin()
                                            onMoved: {
                                                if (typeof bar.setBarEdgeMargin === "function")
                                                    bar.setBarEdgeMargin(Math.round(value))
                                                root.menuTick++
                                                Qt.callLater(root.reposition)
                                            }
                                            background: Rectangle {
                                                x: posEdgeSlider.leftPadding
                                                y: posEdgeSlider.topPadding + posEdgeSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 160
                                                implicitHeight: 5
                                                width: posEdgeSlider.availableWidth
                                                height: 5
                                                radius: 3
                                                color: Qt.rgba(1, 1, 1, 0.12)
                                                Rectangle {
                                                    width: posEdgeSlider.visualPosition * parent.width
                                                    height: parent.height
                                                    radius: 3
                                                    color: bar.accent
                                                }
                                            }
                                            handle: Rectangle {
                                                x: posEdgeSlider.leftPadding + posEdgeSlider.visualPosition * (posEdgeSlider.availableWidth - width)
                                                y: posEdgeSlider.topPadding + posEdgeSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 12
                                                implicitHeight: 12
                                                radius: 3
                                                color: posEdgeSlider.pressed ? bar.accent : bar.text
                                                border.width: 1
                                                border.color: bar.accent
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Flush windows to bar"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Close the gap between tiled windows and the bar"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.flushWindowsToBar === true) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.flushWindowsToBar === true) ? "✓" : "✕"
                                                    color: (bar.flushWindowsToBar === true) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.setOptToggle("setFlushWindowsToBar", !(bar.flushWindowsToBar === true))
                                                        Qt.callLater(root.reposition)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 48
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        anchors.topMargin: 6
                                        anchors.bottomMargin: 6
                                        spacing: 2
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: "Bar size"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: root.optBarSizePct() + "%"
                                                color: bar.subtext
                                                font.pixelSize: 11
                                                font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                Layout.preferredWidth: root.optControlColW
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                        }
                                        Slider {
                                            id: posBarSizeSlider
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 16
                                            from: 80
                                            to: 140
                                            stepSize: 5
                                            value: root.optBarSizePct()
                                            onMoved: {
                                                if (typeof bar.setBarSizeScale === "function")
                                                    bar.setBarSizeScale(Math.round(value) / 100)
                                                root.menuTick++
                                                Qt.callLater(root.reposition)
                                            }
                                            background: Rectangle {
                                                x: posBarSizeSlider.leftPadding
                                                y: posBarSizeSlider.topPadding + posBarSizeSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 160
                                                implicitHeight: 5
                                                width: posBarSizeSlider.availableWidth
                                                height: 5
                                                radius: 3
                                                color: Qt.rgba(1, 1, 1, 0.12)
                                                Rectangle {
                                                    width: posBarSizeSlider.visualPosition * parent.width
                                                    height: parent.height
                                                    radius: 3
                                                    color: bar.accent
                                                }
                                            }
                                            handle: Rectangle {
                                                x: posBarSizeSlider.leftPadding + posBarSizeSlider.visualPosition * (posBarSizeSlider.availableWidth - width)
                                                y: posBarSizeSlider.topPadding + posBarSizeSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 12
                                                implicitHeight: 12
                                                radius: 3
                                                color: posBarSizeSlider.pressed ? bar.accent : bar.text
                                                border.width: 1
                                                border.color: bar.accent
                                            }
                                        }
                                    }
                                }
                            }

                            // ===== DISPLAY (resolution / refresh / bit depth / GPU) =====
                            ColumnLayout {
                                visible: root.activeMenu === "display"
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(280, root.panelMaxH - 12)
                                spacing: 12

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Display"
                                        color: bar.text
                                        font.pixelSize: bar.popupTitleSize
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                }

                                Flickable {
                                    id: displayBodyFlick
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    flickableDirection: Flickable.VerticalFlick
                                    contentWidth: width
                                    contentHeight: displayBodyCol.implicitHeight
                                    interactive: contentHeight > height + 4
                                    ScrollBar.vertical: ScrollBar {
                                        policy: displayBodyFlick.contentHeight > displayBodyFlick.height + 4
                                                ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                        width: 8
                                        contentItem: Rectangle {
                                            implicitWidth: 6
                                            radius: 3
                                            color: bar.accent
                                            opacity: 0.5
                                        }
                                    }
                                    ColumnLayout {
                                        id: displayBodyCol
                                        width: displayBodyFlick.width
                                        spacing: 12

                                // Current monitor indicator
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: dispInfoCol.implicitHeight + 16
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.65)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    ColumnLayout {
                                        id: dispInfoCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 2
                                        Text {
                                            Layout.fillWidth: true
                                            text: root.displayCurrentLabel()
                                            color: bar.text
                                            font.pixelSize: 13
                                            font.bold: true
                                            font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: root.displayIdentityLabel()
                                            color: bar.text
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                            elide: Text.ElideRight
                                            wrapMode: Text.WordWrap
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: root.displayConnectorLabel().length > 0
                                            text: root.displayConnectorLabel()
                                            color: bar.subtext
                                            font.pixelSize: 10
                                            font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: root.displayMetaLabel().length > 0
                                            text: root.displayMetaLabel()
                                            color: bar.subtext
                                            font.pixelSize: 10
                                            font.family: bar.fontFamily
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                // GPU / display adapter
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: dispGpuCol.implicitHeight + 16
                                    radius: root.chipR
                                    color: Qt.rgba(0.05, 0.07, 0.12, 0.70)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    ColumnLayout {
                                        id: dispGpuCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 4
                                        Text {
                                            Layout.fillWidth: true
                                            text: "Adapter"
                                            color: bar.subtext
                                            font.pixelSize: 10
                                            font.bold: true
                                            font.family: bar.fontFamily
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: root.displayAdapterLabel()
                                            color: bar.text
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                            wrapMode: Text.WordWrap
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: root.displayGpuStatsLine1()
                                            color: bar.subtext
                                            font.pixelSize: 10
                                            font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: root.displayGpuStatsLine2().length > 0
                                            text: root.displayGpuStatsLine2()
                                            color: bar.subtext
                                            font.pixelSize: 10
                                            font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                            elide: Text.ElideRight
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.topMargin: 2
                                            spacing: 8
                                            visible: {
                                                void root.displayGpuTick
                                                void root.displayInfo
                                                const g = root.displayInfo && root.displayInfo.gpu
                                                return !!(g && g.available)
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text {
                                                    text: "GPU"
                                                    color: bar.subtext
                                                    font.pixelSize: 9
                                                    font.family: bar.fontFamily
                                                }
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 5
                                                    radius: 2
                                                    color: Qt.rgba(1, 1, 1, 0.10)
                                                    Rectangle {
                                                        width: parent.width * root.displayGpuUtilFrac()
                                                        height: parent.height
                                                        radius: 2
                                                        color: bar.accent
                                                    }
                                                }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text {
                                                    text: "VRAM"
                                                    color: bar.subtext
                                                    font.pixelSize: 9
                                                    font.family: bar.fontFamily
                                                }
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 5
                                                    radius: 2
                                                    color: Qt.rgba(1, 1, 1, 0.10)
                                                    Rectangle {
                                                        width: parent.width * root.displayGpuMemFrac()
                                                        height: parent.height
                                                        radius: 2
                                                        color: root.onGreen
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Resolution | Refresh rate | Bit depth  (spaced, single row)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 18

                                    // Resolution slider
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 140
                                        spacing: 6
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: "Resolution"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: root.displayPendingRes().length
                                                      ? root.displayPendingRes().replace("x", "×")
                                                      : "—"
                                                color: bar.subtext
                                                font.pixelSize: 12
                                                font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                            }
                                        }
                                        Slider {
                                            id: displayResSlider
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 28
                                            readonly property int resCount: (root.displayFilteredList || []).length
                                            from: 0
                                            to: Math.max(0, resCount - 1)
                                            stepSize: 1
                                            snapMode: Slider.SnapAlways
                                            live: true
                                            enabled: resCount > 1 && !root.displayApplying && !root.displayLoading
                                            // External value only when not dragging — avoids binding fight
                                            Binding on value {
                                                when: !displayResSlider.pressed
                                                value: root.displayResIndex
                                            }
                                            // Integer steps only — skip redundant work between snaps
                                            property int _lastStep: -1
                                            onMoved: {
                                                const step = Math.round(value)
                                                if (step === _lastStep)
                                                    return
                                                _lastStep = step
                                                root.displayOnResIndexChanged(step)
                                            }
                                            onPressedChanged: {
                                                root.displaySliderPressed = pressed
                                                if (typeof panelFlick !== "undefined" && panelFlick) {
                                                    if (pressed) {
                                                        _lastStep = Math.round(value)
                                                        panelFlick.interactive = false
                                                    } else {
                                                        panelFlick.interactive = root.panelNeedsScroll
                                                                && (panelFlick.contentHeight > panelFlick.height + 4)
                                                        root.displayOnResIndexChanged(Math.round(value))
                                                        _lastStep = -1
                                                    }
                                                } else if (!pressed) {
                                                    root.displayOnResIndexChanged(Math.round(value))
                                                    _lastStep = -1
                                                }
                                            }
                                            background: Rectangle {
                                                x: displayResSlider.leftPadding
                                                y: displayResSlider.topPadding + displayResSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 120
                                                implicitHeight: 6
                                                width: displayResSlider.availableWidth
                                                height: 6
                                                radius: 2
                                                color: Qt.rgba(1, 1, 1, 0.12)
                                                Rectangle {
                                                    width: displayResSlider.visualPosition * parent.width
                                                    height: parent.height
                                                    radius: 2
                                                    color: bar.accent
                                                }
                                            }
                                            handle: Rectangle {
                                                x: displayResSlider.leftPadding + displayResSlider.visualPosition * (displayResSlider.availableWidth - width)
                                                y: displayResSlider.topPadding + displayResSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 16
                                                implicitHeight: 16
                                                radius: 3
                                                color: displayResSlider.pressed ? bar.accent : bar.text
                                                border.width: 1
                                                border.color: bar.accent
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: {
                                                void root.displayTick
                                                const n = (root.displayFilteredList || []).length
                                                const all = (root.displayResolutions || []).length
                                                const fam = root.displayRateBucket(root.displaySelectedRate)
                                                if (!all)
                                                    return root.displayLoading ? "Loading…" : "No modes"
                                                if (n <= 1)
                                                    return "1 res near " + fam + " Hz (pick another Refresh)"
                                                return (root.displayResIndex + 1) + "/" + n
                                                       + " res near " + fam + " Hz"
                                            }
                                            color: bar.subtext
                                            font.pixelSize: 10
                                            font.family: bar.fontFamily
                                        }
                                    }

                                    // Refresh rate dropdown
                                    ColumnLayout {
                                        Layout.preferredWidth: 118
                                        Layout.maximumWidth: 130
                                        Layout.alignment: Qt.AlignTop
                                        spacing: 6
                                        Text {
                                            text: "Refresh"
                                            color: bar.text
                                            font.pixelSize: 12
                                            font.family: bar.fontFamily
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 34
                                            radius: root.chipR
                                            color: displayRateMa.containsMouse ? root.optFieldBgFocus : root.optFieldBg
                                            border.width: 1
                                            border.color: root.displayRateMenuOpen ? bar.accent : bar.pillBorder
                                            opacity: root.displayPendingRates().length ? 1 : 0.55
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 4
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: {
                                                        void root.displayTick
                                                        const r = root.displayPendingRate()
                                                        return r > 0 ? (root.displayFormatRate(r) + " Hz") : "—"
                                                    }
                                                    color: bar.text
                                                    font.pixelSize: 11
                                                    font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    text: root.displayRateMenuOpen ? "▴" : "▾"
                                                    color: bar.subtext
                                                    font.pixelSize: 11
                                                }
                                            }
                                            MouseArea {
                                                id: displayRateMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                enabled: root.displayPendingRates().length > 0 && !root.displayApplying
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.displayBitdepthMenuOpen = false
                                                    root.displayRateMenuOpen = !root.displayRateMenuOpen
                                                }
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3
                                            visible: root.displayRateMenuOpen
                                            Repeater {
                                                model: root.displayPendingRates()
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    required property int index
                                                    readonly property bool active: root.displayRateNear(modelData, root.displaySelectedRate)
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 28
                                                    radius: root.chipR
                                                    color: active
                                                           ? (bar.controlActiveBg || Qt.rgba(0, 0.77, 0.96, 0.22))
                                                           : (rateRowMa.containsMouse ? bar.glassHover : Qt.rgba(0.10, 0.10, 0.12, 0.55))
                                                    border.width: 1
                                                    border.color: active ? root.activeLabelColor() : bar.dividerStrong
                                                    Text {
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 8
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: root.displayFormatRate(modelData) + " Hz"
                                                        color: active ? root.activeLabelColor() : bar.text
                                                        font.pixelSize: 11
                                                        font.family: bar.fontFamily
                                                        font.bold: active
                                                    }
                                                    MouseArea {
                                                        id: rateRowMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.displaySelectRate(modelData)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Bit depth dropdown
                                    ColumnLayout {
                                        Layout.preferredWidth: 96
                                        Layout.maximumWidth: 104
                                        Layout.alignment: Qt.AlignTop
                                        spacing: 6
                                        Text {
                                            text: "Bit depth"
                                            color: bar.text
                                            font.pixelSize: 12
                                            font.family: bar.fontFamily
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 34
                                            radius: root.chipR
                                            color: displayBdMa.containsMouse ? root.optFieldBgFocus : root.optFieldBg
                                            border.width: 1
                                            border.color: root.displayBitdepthMenuOpen ? bar.accent : bar.pillBorder
                                            opacity: root.displayApplying ? 0.6 : 1
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 4
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: root.displayBitdepth + "-bit"
                                                    color: bar.text
                                                    font.pixelSize: 11
                                                    font.family: bar.fontFamily
                                                }
                                                Text {
                                                    text: root.displayBitdepthMenuOpen ? "▴" : "▾"
                                                    color: bar.subtext
                                                    font.pixelSize: 11
                                                }
                                            }
                                            MouseArea {
                                                id: displayBdMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                enabled: !root.displayApplying
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.displayRateMenuOpen = false
                                                    root.displayBitdepthMenuOpen = !root.displayBitdepthMenuOpen
                                                }
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3
                                            visible: root.displayBitdepthMenuOpen
                                            Repeater {
                                                model: [8, 10]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    readonly property bool active: root.displayBitdepth === modelData
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 28
                                                    radius: root.chipR
                                                    color: active
                                                           ? (bar.controlActiveBg || Qt.rgba(0, 0.77, 0.96, 0.22))
                                                           : (bdRowMa.containsMouse ? bar.glassHover : Qt.rgba(0.10, 0.10, 0.12, 0.55))
                                                    border.width: 1
                                                    border.color: active ? root.activeLabelColor() : bar.dividerStrong
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: modelData + "-bit"
                                                        color: active ? root.activeLabelColor() : bar.text
                                                        font.pixelSize: 11
                                                        font.bold: active
                                                        font.family: bar.fontFamily
                                                    }
                                                    MouseArea {
                                                        id: bdRowMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.displaySelectBitdepth(modelData)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Apply + status
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 36
                                        radius: root.chipR
                                        readonly property bool canApply: root.displayHasPendingChange()
                                                                         && !root.displayApplying
                                                                         && root.displayPendingMode().length > 0
                                        color: canApply
                                               ? (applyDispMa.containsMouse
                                                  ? (bar.controlActiveBg || Qt.rgba(0, 0.77, 0.96, 0.28))
                                                  : Qt.rgba(0, 0.77, 0.96, 0.18))
                                               : Qt.rgba(0.12, 0.12, 0.14, 0.55)
                                        border.width: 1
                                        border.color: canApply ? root.activeLabelColor() : bar.dividerStrong
                                        Text {
                                            anchors.centerIn: parent
                                            text: root.displayApplying
                                                  ? "Applying…"
                                                  : (parent.canApply
                                                     ? ("Apply  " + root.displayPendingMode()
                                                        + "  ·  " + root.displayBitdepth + "-bit")
                                                     : "No changes")
                                            color: parent.canApply ? root.activeLabelColor() : bar.overlay
                                            font.pixelSize: 12
                                            font.bold: parent.canApply
                                            font.family: bar.fontFamily
                                            elide: Text.ElideRight
                                            width: parent.width - 16
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        MouseArea {
                                            id: applyDispMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: parent.canApply
                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: root.applyDisplayMode()
                                        }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: root.displayError.length > 0
                                    text: root.displayError
                                    color: root.offRed
                                    font.pixelSize: 11
                                    font.family: bar.fontFamily
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: root.displayStatus.length > 0 && root.displayError.length === 0
                                    text: root.displayStatus
                                    color: root.onGreen
                                    font.pixelSize: 11
                                    font.family: bar.fontFamily
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "Res ↔ rate linked (hyprctl). GPU stats poll every 3s only while this panel is open (paused while dragging). Apply uses scale 1.0."
                                    color: bar.subtext
                                    font.pixelSize: 10
                                    font.family: bar.fontFamily
                                }

                                    } // displayBodyCol
                                } // displayBodyFlick

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Rectangle {
                                        Layout.preferredHeight: 26
                                        Layout.preferredWidth: Math.max(72, nvidiaPanelRow.implicitWidth + 14)
                                        radius: root.chipR
                                        color: nvidiaPanelMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                        border.width: 1
                                        border.color: nvidiaPanelMa.containsMouse
                                                      ? "#76b900"
                                                      : bar.pillBorder
                                        Row {
                                            id: nvidiaPanelRow
                                            anchors.centerIn: parent
                                            spacing: 5
                                            Text {
                                                text: "\uF135D"
                                                color: nvidiaPanelMa.containsMouse ? "#76b900" : bar.subtext
                                                font.pixelSize: 14
                                                font.family: bar.fontFamily
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            Text {
                                                text: "NVIDIA"
                                                color: nvidiaPanelMa.containsMouse ? "#76b900" : bar.subtext
                                                font.pixelSize: 11
                                                font.bold: true
                                                font.family: bar.fontFamily
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                        }
                                        MouseArea {
                                            id: nvidiaPanelMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.openNvidiaPanel()
                                        }
                                        ToolTip.visible: nvidiaPanelMa.containsMouse
                                        ToolTip.delay: bar.tooltipDelay !== undefined ? bar.tooltipDelay : 400
                                        ToolTip.text: "Open NVIDIA Settings"
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 26
                                        Layout.preferredWidth: Math.max(56, refreshDispTxt.implicitWidth + 16)
                                        radius: root.chipR
                                        color: refreshDispMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: refreshDispTxt
                                            anchors.centerIn: parent
                                            text: root.displayLoading ? "…" : "Refresh"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: refreshDispMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.refreshDisplay()
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                            }

                            // ===== WALLPAPER =====
                            ColumnLayout {
                                id: wallpaperPanel
                                visible: root.activeMenu === "wallpaper"
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(280, root.panelMaxH - 12)
                                spacing: 8

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            Layout.fillWidth: true
                                            text: "Wallpaper"
                                            color: bar.text
                                            font.pixelSize: bar.popupTitleSize
                                            font.bold: true
                                            font.family: bar.fontFamily
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WrapAnywhere
                                        text: root.wallpaperDirDisplay || root.wallpaperDir()
                                        color: bar.subtext
                                        font.pixelSize: bar.popupHintSize
                                        font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: root.wallpaperStatus.length
                                              ? root.wallpaperStatus
                                              : "Click to apply · Right-click to rename or delete · Drop images to add"
                                        color: bar.subtext
                                        font.pixelSize: 11
                                        font.family: bar.fontFamily
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Rectangle {
                                            Layout.preferredHeight: 30
                                            Layout.preferredWidth: changeDirLbl.implicitWidth + 14
                                            radius: root.chipR
                                            color: changeDirMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                            border.width: 1
                                            border.color: changeDirMa.containsMouse ? bar.accent : bar.pillBorder
                                            Text {
                                                id: changeDirLbl
                                                anchors.centerIn: parent
                                                text: "Change folder…"
                                                color: changeDirMa.containsMouse ? root.activeLabelColor() : bar.subtext
                                                font.pixelSize: 11
                                                font.family: bar.fontFamily
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
                                            color: addWpMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                            border.width: 1
                                            border.color: addWpMa.containsMouse ? bar.accent : bar.pillBorder
                                            Text {
                                                id: addWpLbl
                                                anchors.centerIn: parent
                                                text: "Add wallpapers…"
                                                color: addWpMa.containsMouse ? root.activeLabelColor() : bar.subtext
                                                font.pixelSize: 11
                                                font.family: bar.fontFamily
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
                                            color: openWpMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                            border.width: 1
                                            border.color: bar.pillBorder
                                            Text {
                                                id: openWpLbl
                                                anchors.centerIn: parent
                                                text: "Open folder"
                                                color: bar.subtext
                                                font.pixelSize: 11
                                                font.family: bar.fontFamily
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
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        Slider {
                                            id: wpTileSizeSlider
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 16
                                            from: 100
                                            to: 260
                                            stepSize: 10
                                            snapMode: Slider.SnapAlways
                                            value: root.wallpaperTilePref
                                            onMoved: root.setWallpaperTilePref(Math.round(value))
                                            onPressedChanged: {
                                                if (!pressed)
                                                    root.setWallpaperTilePref(Math.round(value))
                                            }
                                            background: Rectangle {
                                                x: wpTileSizeSlider.leftPadding
                                                y: wpTileSizeSlider.topPadding + wpTileSizeSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 160
                                                implicitHeight: 5
                                                width: wpTileSizeSlider.availableWidth
                                                height: 5
                                                radius: 3
                                                color: Qt.rgba(1, 1, 1, 0.12)
                                                Rectangle {
                                                    width: wpTileSizeSlider.visualPosition * parent.width
                                                    height: parent.height
                                                    radius: 3
                                                    color: bar.accent
                                                }
                                            }
                                            handle: Rectangle {
                                                x: wpTileSizeSlider.leftPadding + wpTileSizeSlider.visualPosition * (wpTileSizeSlider.availableWidth - width)
                                                y: wpTileSizeSlider.topPadding + wpTileSizeSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 12
                                                implicitHeight: 12
                                                radius: 3
                                                color: wpTileSizeSlider.pressed ? bar.accent : bar.text
                                                border.width: 1
                                                border.color: bar.accent
                                            }
                                        }
                                        Text {
                                            Layout.preferredWidth: 44
                                            horizontalAlignment: Text.AlignRight
                                            text: root.wallpaperTilePref + "px"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
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
                                                color: bar.accent
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
                                                const w = Math.max(pref, width)
                                                const cols = Math.max(1, Math.floor((w + spacing) / (pref + spacing)))
                                                return Math.max(80, Math.floor((w - (cols - 1) * spacing) / cols))
                                            }
                                            readonly property int tileH: Math.round(tileW * 9 / 16) + 22

                                            Repeater {
                                                model: root.wallpaperImages
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    readonly property bool isCurrent: root.wallpaperCurrent() === modelData.path
                                                    readonly property bool isBusy: root.wallpaperBusyPath === modelData.path
                                                    readonly property bool showActions: thumbMa.containsMouse || wpRenameBtnMa.containsMouse || wpDeleteBtnMa.containsMouse
                                                    width: wpFlow.tileW
                                                    height: wpFlow.tileH
                                                    radius: root.chipR
                                                    color: Qt.rgba(0.05, 0.07, 0.12, 0.88)
                                                    border.width: isCurrent || thumbMa.containsMouse ? 2 : 1
                                                    border.color: isCurrent ? root.onGreen
                                                                  : (thumbMa.containsMouse ? bar.accent : bar.dividerStrong)
                                                    clip: true

                                                    Image {
                                                        id: thumb
                                                        anchors.fill: parent
                                                        anchors.margins: 2
                                                        anchors.bottomMargin: 22
                                                        source: modelData.url || ("file://" + modelData.path)
                                                        fillMode: Image.PreserveAspectCrop
                                                        asynchronous: true
                                                        cache: true
                                                        sourceSize.width: Math.max(296, root.wallpaperTilePref * 2)
                                                        sourceSize.height: Math.max(168, Math.round(root.wallpaperTilePref * 2 * 9 / 16))
                                                        smooth: true
                                                        mipmap: true
                                                    }

                                                    Rectangle {
                                                        anchors.fill: thumb
                                                        visible: isBusy
                                                        color: Qt.rgba(0, 0, 0, 0.45)
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "…"
                                                            color: bar.accent
                                                            font.pixelSize: 18
                                                        }
                                                    }

                                                    Rectangle {
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.bottom: parent.bottom
                                                        height: 22
                                                        color: Qt.rgba(0, 0, 0, 0.72)
                                                        Text {
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 6
                                                            anchors.rightMargin: 6
                                                            verticalAlignment: Text.AlignVCenter
                                                            elide: Text.ElideRight
                                                            text: {
                                                                const dims = (modelData.width > 0 && modelData.height > 0)
                                                                    ? (modelData.width + "×" + modelData.height)
                                                                    : "?"
                                                                return modelData.name + "  ·  " + dims
                                                            }
                                                            color: isCurrent ? root.onGreen : bar.subtext
                                                            font.pixelSize: 10
                                                            font.family: bar.fontFamily
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: thumbMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: (mouse) => {
                                                            if (mouse.button === Qt.RightButton) {
                                                                const p = mapToItem(panelBox, mouse.x, mouse.y)
                                                                root.openWallpaperItemMenu(modelData.path, modelData.name, p.x, p.y)
                                                            } else {
                                                                root.closeWallpaperUi()
                                                                root.applyWallpaper(modelData.path)
                                                            }
                                                        }
                                                        ToolTip.visible: containsMouse && !wpRenameBtnMa.containsMouse && !wpDeleteBtnMa.containsMouse
                                                        ToolTip.delay: bar.tooltipDelay
                                                        ToolTip.text: {
                                                            const dims = (modelData.width > 0 && modelData.height > 0)
                                                                ? (modelData.width + " × " + modelData.height)
                                                                : "dimensions unknown"
                                                            return modelData.name + "\n" + dims + "\nClick to apply · Right-click for more"
                                                        }
                                                    }

                                                    Row {
                                                        z: 2
                                                        visible: showActions
                                                        anchors.top: parent.top
                                                        anchors.right: parent.right
                                                        anchors.margins: 4
                                                        spacing: 4

                                                        Rectangle {
                                                            width: 22
                                                            height: 22
                                                            radius: 4
                                                            color: wpRenameBtnMa.containsMouse ? bar.glassHover : Qt.rgba(0, 0, 0, 0.62)
                                                            border.width: 1
                                                            border.color: wpRenameBtnMa.containsMouse ? bar.accent : bar.pillBorder
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: "✎"
                                                                color: bar.text
                                                                font.pixelSize: 11
                                                            }
                                                            MouseArea {
                                                                id: wpRenameBtnMa
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: root.beginRenameWallpaper(modelData.path, modelData.name)
                                                            }
                                                        }
                                                        Rectangle {
                                                            width: 22
                                                            height: 22
                                                            radius: 4
                                                            color: wpDeleteBtnMa.containsMouse ? Qt.rgba(1, 0.24, 0.54, 0.28) : Qt.rgba(0, 0, 0, 0.62)
                                                            border.width: 1
                                                            border.color: wpDeleteBtnMa.containsMouse ? root.offRed : bar.pillBorder
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: "✕"
                                                                color: wpDeleteBtnMa.containsMouse ? root.offRed : bar.text
                                                                font.pixelSize: 11
                                                            }
                                                            MouseArea {
                                                                id: wpDeleteBtnMa
                                                                anchors.fill: parent
                                                                hoverEnabled: true
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: root.beginDeleteWallpaper(modelData.path, modelData.name)
                                                            }
                                                        }
                                                    }
                                                }
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
                                        color: bar.subtext
                                        font.pixelSize: 11
                                        font.family: bar.fontFamily
                                    }
                                    } // wpGridCol
                                    } // wpBodyFlick

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Rectangle {
                                            Layout.preferredHeight: 26
                                            Layout.preferredWidth: refreshWpLbl.implicitWidth + 12
                                            radius: root.chipR
                                            color: refreshWpMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                            border.width: 1
                                            border.color: bar.pillBorder
                                            Text {
                                                id: refreshWpLbl
                                                anchors.centerIn: parent
                                                text: root.wallpaperLoading ? "…" : "Refresh"
                                                color: bar.subtext
                                                font.pixelSize: 11
                                                font.family: bar.fontFamily
                                            }
                                            MouseArea {
                                                id: refreshWpMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.refreshWallpapers()
                                            }
                                        }
                                        Item { Layout.fillWidth: true }
                                    }
                            }

                            // ===== WIDGETS (visibility + zone + order + width scale) =====
                            ColumnLayout {
                                visible: root.activeMenu === "widgets" || root.activeMenu === "sizes"
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(280, root.panelMaxH - 12)
                                spacing: 7

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Widgets"
                                        color: bar.text
                                        font.pixelSize: bar.popupTitleSize
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: (bar.barLayoutMode === "dual")
                                          ? "T→B then A–Z · ✓/✕ · name · T/B · ↑↓ · width % (80–180)"
                                          : "L→C→R then A–Z · ✓/✕ · name · L/C/R · ↑↓ · width % (80–180)"
                                    color: bar.subtext
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontFamily
                                }

                                Flickable {
                                    id: widgetsBodyFlick
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    flickableDirection: Flickable.VerticalFlick
                                    contentWidth: width
                                    contentHeight: widgetsBodyCol.implicitHeight
                                    interactive: contentHeight > height + 4
                                    ScrollBar.vertical: ScrollBar {
                                        policy: widgetsBodyFlick.contentHeight > widgetsBodyFlick.height + 4
                                                ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                        width: root.bodyScrollBarW
                                        padding: 2
                                        contentItem: Rectangle {
                                            implicitWidth: 6
                                            radius: 3
                                            color: bar.accent
                                            opacity: 0.5
                                        }
                                        background: Rectangle {
                                            implicitWidth: root.bodyScrollBarW
                                            radius: 4
                                            color: Qt.rgba(1, 1, 1, 0.06)
                                        }
                                    }
                                    ColumnLayout {
                                        id: widgetsBodyCol
                                        width: Math.max(1, widgetsBodyFlick.width - root.bodyScrollGutter)
                                        spacing: 7

                                Repeater {
                                    model: root.widgetEntries()
                                    delegate: Rectangle {
                                        id: widgetRow
                                        required property var modelData
                                        readonly property string widgetId: modelData.id
                                        readonly property string widgetZone: modelData.zone
                                        readonly property string widgetLabel: modelData.label
                                        readonly property bool widgetOn: modelData.on
                                        readonly property int livePct: root.scalePercentOf(widgetId)
                                        property int localPct: livePct
                                        property bool editing: false

                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 58
                                        radius: root.chipR
                                        color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                        border.width: bar.controlBorderWidth
                                        border.color: bar.dividerStrong
                                        opacity: widgetRow.widgetOn ? 1.0 : 0.78

                                        onLivePctChanged: {
                                            if (!widgetRow.editing && !sizeSlider.pressed)
                                                widgetRow.localPct = livePct
                                        }

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 6
                                            anchors.topMargin: 5
                                            anchors.bottomMargin: 5
                                            spacing: 4

                                            // Row 1 — three columns: [✓ name] | [L C R] | [↑ ↓]
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 10

                                                // Column 1: toggle + full name
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 120
                                                    spacing: 6

                                                    Rectangle {
                                                        Layout.preferredWidth: 28
                                                        Layout.preferredHeight: 24
                                                        Layout.alignment: Qt.AlignVCenter
                                                        radius: 4
                                                        color: visMa.containsMouse
                                                               ? (widgetRow.widgetOn
                                                                  ? Qt.rgba(0.29, 0.87, 0.50, 0.18)
                                                                  : Qt.rgba(0.97, 0.44, 0.44, 0.18))
                                                               : "transparent"
                                                        border.width: 1
                                                        border.color: widgetRow.widgetOn ? root.onGreen : root.offRed
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: widgetRow.widgetOn ? "✓" : "✕"
                                                            color: widgetRow.widgetOn ? root.onGreen : root.offRed
                                                            font.pixelSize: 14
                                                            font.bold: true
                                                            font.family: bar.fontFamily
                                                        }
                                                        MouseArea {
                                                            id: visMa
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: root.toggleWidget(widgetRow.widgetId)
                                                            ToolTip.visible: containsMouse
                                                            ToolTip.delay: bar.tooltipDelay
                                                            ToolTip.text: widgetRow.widgetOn ? "Hide from bar" : "Show on bar"
                                                        }
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        Layout.minimumWidth: 72
                                                        // Prefer full labels; elide only if panel is extremely narrow
                                                        elide: Text.ElideRight
                                                        text: widgetRow.widgetLabel
                                                        color: bar.text
                                                        font.pixelSize: 12
                                                        font.family: bar.fontFamily
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                }

                                                // Column 2: zone L C R (classic) or T B (dual)
                                                RowLayout {
                                                    readonly property int zoneBtnCount: root.zoneChoices().length
                                                    Layout.preferredWidth: zoneBtnCount * 22 + (zoneBtnCount - 1) * 4
                                                    Layout.maximumWidth: zoneBtnCount * 22 + (zoneBtnCount - 1) * 4
                                                    Layout.minimumWidth: zoneBtnCount * 22 + (zoneBtnCount - 1) * 4
                                                    Layout.alignment: Qt.AlignVCenter
                                                    spacing: 4

                                                    Repeater {
                                                        model: root.zoneChoices()
                                                        delegate: Rectangle {
                                                            required property var modelData
                                                            readonly property bool zoneOn: widgetRow.widgetZone === modelData.id
                                                            Layout.preferredWidth: 22
                                                            Layout.preferredHeight: 22
                                                            radius: 4
                                                            color: zoneOn ? bar.controlActiveBg : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                                            border.width: 1
                                                            border.color: zoneOn ? root.activeLabelColor() : bar.pillBorder
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: modelData.label
                                                                font.pixelSize: 10
                                                                font.family: bar.fontFamily
                                                                color: zoneOn ? root.activeLabelColor() : bar.subtext
                                                            }
                                                            MouseArea {
                                                                anchors.fill: parent
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    if (typeof bar.setWidgetZone === "function")
                                                                        bar.setWidgetZone(widgetRow.widgetId, modelData.id)
                                                                    root.menuTick++
                                                                    Qt.callLater(root.reposition)
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                // Column 3: reorder ↑ ↓
                                                RowLayout {
                                                    Layout.preferredWidth: 52
                                                    Layout.maximumWidth: 52
                                                    Layout.minimumWidth: 52
                                                    Layout.alignment: Qt.AlignVCenter
                                                    spacing: 4

                                                    Rectangle {
                                                        Layout.preferredWidth: 24
                                                        Layout.preferredHeight: 24
                                                        radius: 4
                                                        color: upMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                                        border.width: 1
                                                        border.color: bar.pillBorder
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "↑"
                                                            color: bar.subtext
                                                            font.pixelSize: 12
                                                        }
                                                        MouseArea {
                                                            id: upMa
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (typeof bar.moveWidget === "function")
                                                                    bar.moveWidget(widgetRow.widgetId, -1)
                                                                root.menuTick++
                                                                Qt.callLater(root.reposition)
                                                            }
                                                        }
                                                    }
                                                    Rectangle {
                                                        Layout.preferredWidth: 24
                                                        Layout.preferredHeight: 24
                                                        radius: 4
                                                        color: dnMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                                        border.width: 1
                                                        border.color: bar.pillBorder
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "↓"
                                                            color: bar.subtext
                                                            font.pixelSize: 12
                                                        }
                                                        MouseArea {
                                                            id: dnMa
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (typeof bar.moveWidget === "function")
                                                                    bar.moveWidget(widgetRow.widgetId, 1)
                                                                root.menuTick++
                                                                Qt.callLater(root.reposition)
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            // Row 2: horizontal width scale
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                Slider {
                                                    id: sizeSlider
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 16
                                                    from: 80
                                                    to: 180
                                                    stepSize: 5
                                                    value: widgetRow.localPct
                                                    onMoved: {
                                                        widgetRow.localPct = Math.round(value)
                                                        root.setScalePercent(widgetRow.widgetId, widgetRow.localPct)
                                                    }
                                                    onPressedChanged: {
                                                        if (!pressed)
                                                            root.setScalePercent(widgetRow.widgetId, widgetRow.localPct)
                                                    }

                                                    background: Rectangle {
                                                        x: sizeSlider.leftPadding
                                                        y: sizeSlider.topPadding + sizeSlider.availableHeight / 2 - height / 2
                                                        implicitWidth: 160
                                                        implicitHeight: 5
                                                        width: sizeSlider.availableWidth
                                                        height: 5
                                                        radius: 3
                                                        color: Qt.rgba(1, 1, 1, 0.12)
                                                        Rectangle {
                                                            width: sizeSlider.visualPosition * parent.width
                                                            height: parent.height
                                                            radius: 3
                                                            color: bar.accent
                                                        }
                                                    }
                                                    handle: Rectangle {
                                                        x: sizeSlider.leftPadding + sizeSlider.visualPosition * (sizeSlider.availableWidth - width)
                                                        y: sizeSlider.topPadding + sizeSlider.availableHeight / 2 - height / 2
                                                        implicitWidth: 12
                                                        implicitHeight: 12
                                                        radius: 3
                                                        color: sizeSlider.pressed ? bar.accent : bar.text
                                                        border.width: 1
                                                        border.color: bar.accent
                                                    }
                                                }

                                                TextField {
                                                    id: pctField
                                                    Layout.preferredWidth: 44
                                                    Layout.preferredHeight: 22
                                                    horizontalAlignment: Text.AlignHCenter
                                                    color: bar.text
                                                    font.pixelSize: 11
                                                    font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                    text: String(widgetRow.localPct)
                                                    validator: IntValidator { bottom: 80; top: 180 }
                                                    background: Rectangle {
                                                        radius: 4
                                                        color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                                        border.width: 1
                                                        border.color: pctField.activeFocus ? bar.accent : bar.pillBorder
                                                    }
                                                    onActiveFocusChanged: widgetRow.editing = activeFocus
                                                    onTextChanged: {
                                                        const n = parseInt(text, 10)
                                                        if (!isNaN(n))
                                                            widgetRow.localPct = n
                                                    }
                                                    onAccepted: root.setScalePercent(widgetRow.widgetId, widgetRow.localPct)
                                                    onEditingFinished: root.setScalePercent(widgetRow.widgetId, widgetRow.localPct)
                                                }
                                                Text {
                                                    text: "%"
                                                    color: bar.subtext
                                                    font.pixelSize: 10
                                                    font.family: bar.fontFamily
                                                }
                                            }
                                        }
                                    }
                                }

                                    } // widgetsBodyCol
                                } // widgetsBodyFlick

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Rectangle {
                                        Layout.preferredHeight: 24
                                        Layout.preferredWidth: resetLbl.implicitWidth + 12
                                        radius: root.chipR
                                        color: resetMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                        border.width: bar.controlBorderWidth
                                        border.color: bar.pillBorder
                                        Text {
                                            id: resetLbl
                                            anchors.centerIn: parent
                                            text: "Reset layout"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: resetMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (typeof bar.resetWidgetLayout === "function")
                                                    bar.resetWidgetLayout()
                                                root.menuTick++
                                                Qt.callLater(root.reposition)
                                            }
                                        }
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 24
                                        Layout.preferredWidth: resetSizesLbl.implicitWidth + 12
                                        radius: root.chipR
                                        color: resetSizesMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: resetSizesLbl
                                            anchors.centerIn: parent
                                            text: "Reset sizes"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: resetSizesMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (typeof bar.resetWidgetScales === "function")
                                                    bar.resetWidgetScales()
                                                root.menuTick++
                                                Qt.callLater(root.reposition)
                                            }
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                            }

                            // ===== QUICK LAUNCH =====
                            ColumnLayout {
                                visible: root.activeMenu === "launch"
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(280, root.panelMaxH - 12)
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Quick Launch"
                                        color: bar.text
                                        font.pixelSize: bar.popupTitleSize
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "Pinned icons on the bar · ✕ remove · ↑↓ reorder · add from installed apps or custom"
                                    color: bar.subtext
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontFamily
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
                                            color: bar.accent
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

                                // Current pins
                                Repeater {
                                    model: root.quickLaunchEntries()
                                    delegate: Rectangle {
                                        id: launchRow
                                        required property var modelData
                                        readonly property int appIndex: modelData.index
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        radius: root.chipR
                                        color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                        border.width: bar.controlBorderWidth
                                        border.color: bar.dividerStrong

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 6
                                            spacing: 6

                                            // Remove
                                            Rectangle {
                                                Layout.preferredWidth: 28
                                                Layout.preferredHeight: 26
                                                radius: 4
                                                color: rmMa.containsMouse ? Qt.rgba(0.97, 0.44, 0.44, 0.18) : "transparent"
                                                border.width: 1
                                                border.color: root.offRed
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "✕"
                                                    color: root.offRed
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    id: rmMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.removeLaunchApp(launchRow.appIndex)
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.delay: bar.tooltipDelay
                                                    ToolTip.text: "Remove"
                                                }
                                            }

                                            Image {
                                                visible: (modelData.icon || "").length > 0
                                                Layout.preferredWidth: 22
                                                Layout.preferredHeight: 22
                                                source: modelData.icon || ""
                                                fillMode: Image.PreserveAspectFit
                                                smooth: true
                                                mipmap: true
                                            }
                                            Text {
                                                visible: !(modelData.icon || "").length
                                                Layout.preferredWidth: 22
                                                horizontalAlignment: Text.AlignHCenter
                                                text: modelData.glyph || "󰣆"
                                                font.pixelSize: 16
                                                font.family: bar.fontFamily
                                                color: bar.subtext
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text {
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                    text: modelData.tooltip || "(unnamed)"
                                                    color: bar.text
                                                    font.pixelSize: 12
                                                    font.family: bar.fontFamily
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                    text: modelData.commandText
                                                    color: bar.subtext
                                                    font.pixelSize: 10
                                                    font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                }
                                            }

                                            Rectangle {
                                                Layout.preferredWidth: 24
                                                Layout.preferredHeight: 24
                                                radius: 4
                                                color: upLMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                                border.width: 1
                                                border.color: bar.pillBorder
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "↑"
                                                    color: bar.subtext
                                                    font.pixelSize: 12
                                                }
                                                MouseArea {
                                                    id: upLMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.moveLaunchApp(launchRow.appIndex, -1)
                                                }
                                            }
                                            Rectangle {
                                                Layout.preferredWidth: 24
                                                Layout.preferredHeight: 24
                                                radius: 4
                                                color: dnLMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                                border.width: 1
                                                border.color: bar.pillBorder
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "↓"
                                                    color: bar.subtext
                                                    font.pixelSize: 12
                                                }
                                                MouseArea {
                                                    id: dnLMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.moveLaunchApp(launchRow.appIndex, 1)
                                                }
                                            }
                                        }
                                    }
                                }

                                // Add from installed apps
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: bar.dividerStrong
                                }
                                Text {
                                    text: "Add installed app"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    TextField {
                                        id: appSearchField
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 30
                                        placeholderText: "Search apps…"
                                        color: bar.text
                                        placeholderTextColor: bar.subtext
                                        font.pixelSize: 12
                                        font.family: bar.fontFamily
                                        background: Rectangle {
                                            radius: root.chipR
                                            color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                            border.width: 1
                                            border.color: appSearchField.activeFocus ? bar.accent : bar.pillBorder
                                        }
                                        onPressed: root.armControlFocusGrab()
                                        onActiveFocusChanged: if (activeFocus) root.armControlFocusGrab()
                                        onTextChanged: {
                                            root.desktopAppsQuery = text
                                            desktopSearchDebounce.restart()
                                        }
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 30
                                        Layout.preferredWidth: searchBtnLbl.implicitWidth + 14
                                        radius: root.chipR
                                        color: searchBtnMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: searchBtnLbl
                                            anchors.centerIn: parent
                                            text: root.desktopAppsLoading ? "…" : "Search"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: searchBtnMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.refreshDesktopApps()
                                        }
                                    }
                                }

                                Repeater {
                                    model: root.filteredDesktopApps()
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 34
                                        radius: root.chipR
                                        color: addAppMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.45)
                                        border.width: 1
                                        border.color: bar.dividerStrong

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 8
                                            Image {
                                                visible: (modelData.icon || "").length > 0
                                                Layout.preferredWidth: 20
                                                Layout.preferredHeight: 20
                                                source: modelData.icon || ""
                                                fillMode: Image.PreserveAspectFit
                                                smooth: true
                                            }
                                            Text {
                                                visible: !(modelData.icon || "").length
                                                text: "󰣆"
                                                font.pixelSize: 14
                                                font.family: bar.fontFamily
                                                color: bar.subtext
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                                text: modelData.name || modelData.id
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                            }
                                            Text {
                                                text: "+"
                                                color: root.onGreen
                                                font.pixelSize: 16
                                                font.bold: true
                                            }
                                        }
                                        MouseArea {
                                            id: addAppMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.addDesktopApp(modelData)
                                            ToolTip.visible: containsMouse
                                            ToolTip.delay: bar.tooltipDelay
                                            ToolTip.text: "Add " + (modelData.name || "")
                                        }
                                    }
                                }

                                // Custom add
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: bar.dividerStrong
                                }
                                Text {
                                    text: "Add custom"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                TextField {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    placeholderText: "Name (tooltip)"
                                    color: bar.text
                                    placeholderTextColor: bar.subtext
                                    font.pixelSize: 12
                                    text: root.customName
                                    onTextChanged: root.customName = text
                                    background: Rectangle {
                                        radius: root.chipR
                                        color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                        border.width: 1
                                        border.color: bar.pillBorder
                                    }
                                }
                                TextField {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    placeholderText: "Command (e.g. gtk-launch firefox or /usr/bin/app)"
                                    color: bar.text
                                    placeholderTextColor: bar.subtext
                                    font.pixelSize: 12
                                    text: root.customCommand
                                    onTextChanged: root.customCommand = text
                                    background: Rectangle {
                                        radius: root.chipR
                                        color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                        border.width: 1
                                        border.color: bar.pillBorder
                                    }
                                }
                                TextField {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    placeholderText: "Icon path (optional, e.g. /home/…/icons/app.svg)"
                                    color: bar.text
                                    placeholderTextColor: bar.subtext
                                    font.pixelSize: 12
                                    text: root.customIcon
                                    onTextChanged: root.customIcon = text
                                    background: Rectangle {
                                        radius: root.chipR
                                        color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                        border.width: 1
                                        border.color: bar.pillBorder
                                    }
                                }
                                Rectangle {
                                    Layout.preferredHeight: 32
                                    Layout.preferredWidth: addCustomLbl.implicitWidth + 18
                                    radius: root.chipR
                                    color: addCustomMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                    border.width: 1
                                    border.color: addCustomMa.containsMouse ? bar.accent : bar.pillBorder
                                    opacity: root.customCommand.trim().length ? 1 : 0.5
                                    Text {
                                        id: addCustomLbl
                                        anchors.centerIn: parent
                                        text: "Add custom app"
                                        color: addCustomMa.containsMouse ? bar.accent : bar.subtext
                                        font.pixelSize: 12
                                        font.family: bar.fontFamily
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
                                    Rectangle {
                                        Layout.preferredHeight: 24
                                        Layout.preferredWidth: resetLaunchLbl.implicitWidth + 12
                                        radius: root.chipR
                                        color: resetLaunchMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                        border.width: bar.controlBorderWidth
                                        border.color: bar.pillBorder
                                        Text {
                                            id: resetLaunchLbl
                                            anchors.centerIn: parent
                                            text: "Reset"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: resetLaunchMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (typeof bar.resetQuickLaunchApps === "function")
                                                    bar.resetQuickLaunchApps()
                                                root.menuTick++
                                                Qt.callLater(root.reposition)
                                            }
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                            }

                            // ===== AUTOSTART (XDG) =====
                            ColumnLayout {
                                visible: root.activeMenu === "autostart"
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(280, root.panelMaxH - 12)
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Autostart"
                                        color: bar.text
                                        font.pixelSize: bar.popupTitleSize
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "XDG apps in ~/.config/autostart (session login). Core Hyprland services stay in autostarts.lua."
                                    color: bar.subtext
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontFamily
                                }
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: root.autostartStatus.length ? root.autostartStatus : "Toggle ✓/✕ · add from apps below"
                                    color: bar.subtext
                                    font.pixelSize: 11
                                    font.family: bar.fontFamily
                                }

                                Flickable {
                                    id: autostartBodyFlick
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    flickableDirection: Flickable.VerticalFlick
                                    contentWidth: width
                                    contentHeight: autostartBodyCol.implicitHeight
                                    interactive: contentHeight > height + 4
                                    ScrollBar.vertical: ScrollBar {
                                        policy: autostartBodyFlick.contentHeight > autostartBodyFlick.height + 4
                                                ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                        width: root.bodyScrollBarW
                                        padding: 2
                                        contentItem: Rectangle {
                                            implicitWidth: 6
                                            radius: 3
                                            color: bar.accent
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
                                        spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Rectangle {
                                        Layout.preferredHeight: 28
                                        Layout.preferredWidth: openAsLbl.implicitWidth + 12
                                        radius: root.chipR
                                        color: openAsMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: openAsLbl
                                            anchors.centerIn: parent
                                            text: "Open folder"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
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
                                        color: runAllMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                        border.width: 1
                                        border.color: runAllMa.containsMouse ? bar.accent : bar.pillBorder
                                        Text {
                                            id: runAllLbl
                                            anchors.centerIn: parent
                                            text: "Run enabled now"
                                            color: runAllMa.containsMouse ? bar.accent : bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
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
                                    delegate: Rectangle {
                                        id: asRow
                                        required property var modelData
                                        readonly property bool on: !!modelData.enabled
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        radius: root.chipR
                                        color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                        border.width: 1
                                        border.color: asRow.on ? root.onGreen : bar.dividerStrong
                                        opacity: asRow.on ? 1.0 : 0.78

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 6
                                            spacing: 6

                                            // Enable toggle
                                            Rectangle {
                                                Layout.preferredWidth: 28
                                                Layout.preferredHeight: 26
                                                radius: 4
                                                color: asToggleMa.containsMouse
                                                       ? (asRow.on ? Qt.rgba(0.29, 0.87, 0.50, 0.18) : Qt.rgba(0.97, 0.44, 0.44, 0.18))
                                                       : "transparent"
                                                border.width: 1
                                                border.color: asRow.on ? root.onGreen : root.offRed
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: asRow.on ? "✓" : "✕"
                                                    color: asRow.on ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    id: asToggleMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setAutostartEnabled(modelData.id, !asRow.on)
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.delay: bar.tooltipDelay
                                                    ToolTip.text: asRow.on ? "Disable at login" : "Enable at login"
                                                }
                                            }

                                            Image {
                                                visible: (modelData.icon || "").length > 0
                                                Layout.preferredWidth: 22
                                                Layout.preferredHeight: 22
                                                source: modelData.icon ? ("file://" + modelData.icon) : ""
                                                fillMode: Image.PreserveAspectFit
                                                smooth: true
                                            }
                                            Text {
                                                visible: !(modelData.icon || "").length
                                                Layout.preferredWidth: 22
                                                horizontalAlignment: Text.AlignHCenter
                                                text: "󰣆"
                                                font.pixelSize: 16
                                                font.family: bar.fontFamily
                                                color: bar.subtext
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text {
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                    text: modelData.name || modelData.id
                                                    color: bar.text
                                                    font.pixelSize: 12
                                                    font.family: bar.fontFamily
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                    text: modelData.exec || modelData.id
                                                    color: bar.subtext
                                                    font.pixelSize: 10
                                                    font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                }
                                            }

                                            // Run now
                                            Rectangle {
                                                Layout.preferredWidth: 28
                                                Layout.preferredHeight: 26
                                                radius: 4
                                                color: runOneMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                                border.width: 1
                                                border.color: bar.pillBorder
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "▶"
                                                    color: bar.subtext
                                                    font.pixelSize: 11
                                                }
                                                MouseArea {
                                                    id: runOneMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.runAutostartNow(modelData.id)
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.delay: bar.tooltipDelay
                                                    ToolTip.text: "Run now"
                                                }
                                            }

                                            // Remove
                                            Rectangle {
                                                Layout.preferredWidth: 28
                                                Layout.preferredHeight: 26
                                                radius: 4
                                                color: rmAsMa.containsMouse ? Qt.rgba(0.97, 0.44, 0.44, 0.18) : "transparent"
                                                border.width: 1
                                                border.color: root.offRed
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "✕"
                                                    color: root.offRed
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    id: rmAsMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.removeAutostart(modelData.id)
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.delay: bar.tooltipDelay
                                                    ToolTip.text: "Remove from autostart"
                                                }
                                            }
                                        }
                                    }
                                }

                                Text {
                                    visible: !root.autostartLoading && root.autostartRows().length === 0
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "No XDG autostart entries yet. Add one from installed apps below."
                                    color: bar.subtext
                                    font.pixelSize: 11
                                    font.family: bar.fontFamily
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: bar.dividerStrong
                                }
                                Text {
                                    text: "Add installed app to autostart"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    TextField {
                                        id: asSearchField
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 30
                                        placeholderText: "Search apps…"
                                        color: bar.text
                                        placeholderTextColor: bar.subtext
                                        font.pixelSize: 12
                                        font.family: bar.fontFamily
                                        background: Rectangle {
                                            radius: root.chipR
                                            color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                            border.width: 1
                                            border.color: parent.activeFocus ? bar.accent : bar.pillBorder
                                        }
                                        onPressed: root.armControlFocusGrab()
                                        onActiveFocusChanged: if (activeFocus) root.armControlFocusGrab()
                                        onTextChanged: {
                                            root.desktopAppsQuery = text
                                            root.autostartSearch = ""
                                            desktopSearchDebounce.restart()
                                        }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: root.filteredDesktopApps().length > 0
                                    wrapMode: Text.WordWrap
                                    text: root.desktopAppsTruncated()
                                          ? ("Showing " + root.filteredDesktopApps().length
                                             + " · scroll for more · type to filter")
                                          : ("Scroll if the list is longer than the panel")
                                    color: bar.subtext
                                    font.pixelSize: 10
                                    font.family: bar.fontFamily
                                }

                                // Bounded picker so entries above stay visible; scrolls inside.
                                Flickable {
                                    id: asAppFlick
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: {
                                        const n = root.filteredDesktopApps().length
                                        if (n <= 0)
                                            return 0
                                        const rowH = 36
                                        return Math.min(220, n * rowH)
                                    }
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

                                        Repeater {
                                            model: root.filteredDesktopApps()
                                            delegate: Rectangle {
                                                required property var modelData
                                                width: asAppCol.width
                                                height: 34
                                                radius: root.chipR
                                                color: addAsMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.45)
                                                border.width: 1
                                                border.color: bar.dividerStrong

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 8
                                                    spacing: 8
                                                    Image {
                                                        visible: (modelData.icon || "").length > 0
                                                        Layout.preferredWidth: 20
                                                        Layout.preferredHeight: 20
                                                        source: modelData.icon ? (String(modelData.icon).indexOf("file:") === 0 ? modelData.icon : ("file://" + modelData.icon)) : ""
                                                        fillMode: Image.PreserveAspectFit
                                                        smooth: true
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        elide: Text.ElideRight
                                                        text: modelData.name || modelData.id
                                                        color: bar.text
                                                        font.pixelSize: 12
                                                        font.family: bar.fontFamily
                                                    }
                                                    Text {
                                                        text: "+"
                                                        color: root.onGreen
                                                        font.pixelSize: 16
                                                        font.bold: true
                                                    }
                                                }
                                                MouseArea {
                                                    id: addAsMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    // Don't steal vertical drag from asAppFlick
                                                    preventStealing: false
                                                    onClicked: root.addAutostartFromApp(modelData)
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.delay: bar.tooltipDelay
                                                    ToolTip.text: "Add " + (modelData.name || "") + " to login autostart"
                                                }
                                            }
                                        }
                                    }
                                }

                                    } // autostartBodyCol
                                } // autostartBodyFlick

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Rectangle {
                                        Layout.preferredHeight: 24
                                        Layout.preferredWidth: refreshAsLbl.implicitWidth + 12
                                        radius: root.chipR
                                        color: refreshAsMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: refreshAsLbl
                                            anchors.centerIn: parent
                                            text: root.autostartLoading ? "…" : "Refresh"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: refreshAsMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.refreshAutostart()
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                            }

                            // ===== OPTIONS (behavior prefs — not layout) =====
                            ColumnLayout {
                                visible: root.activeMenu === "options"
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(280, root.panelMaxH - 12)
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Options"
                                        color: bar.text
                                        font.pixelSize: bar.popupTitleSize
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "Behavior prefs (saved where noted). Layout is under Widgets. Actions stay on keybinds / qs ipc."
                                    color: bar.subtext
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontFamily
                                }

                                Flickable {
                                    id: optionsBodyFlick
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    flickableDirection: Flickable.VerticalFlick
                                    contentWidth: width
                                    contentHeight: optionsBodyCol.implicitHeight
                                    interactive: contentHeight > height + 4
                                    ScrollBar.vertical: ScrollBar {
                                        policy: optionsBodyFlick.contentHeight > optionsBodyFlick.height + 4
                                                ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                        width: root.bodyScrollBarW
                                        padding: 2
                                        contentItem: Rectangle {
                                            implicitWidth: 6
                                            radius: 3
                                            color: bar.accent
                                            opacity: 0.5
                                        }
                                        background: Rectangle {
                                            implicitWidth: root.bodyScrollBarW
                                            radius: 4
                                            color: Qt.rgba(1, 1, 1, 0.06)
                                        }
                                    }
                                    ColumnLayout {
                                        id: optionsBodyCol
                                        width: Math.max(1, optionsBodyFlick.width - root.bodyScrollGutter)
                                        spacing: 8


                                Text {
                                    text: "Bar / UI"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "UI scale auto"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Scale with monitor width (recommended)"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (root.optUiScaleIsAuto()) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (root.optUiScaleIsAuto()) ? "✓" : "✕"
                                                    color: (root.optUiScaleIsAuto()) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                    if (root.optUiScaleIsAuto()) {
                                                        const cur = Number(bar.uiScale) || 1
                                                        if (typeof bar.setUiScale === "function")
                                                            bar.setUiScale(cur)
                                                    } else if (typeof bar.setUiScaleAuto === "function") {
                                                        bar.setUiScaleAuto()
                                                    }
                                                    root.refreshOptions()
                                                }
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    visible: !root.optUiScaleIsAuto()
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 48
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        anchors.topMargin: 6
                                        anchors.bottomMargin: 6
                                        spacing: 2
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: "Manual scale"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: Math.round(root.optUiScaleManual() * 100) + "%"
                                                color: bar.subtext
                                                font.pixelSize: 11
                                                font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                Layout.preferredWidth: root.optControlColW
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                        }
                                        Slider {
                                            id: uiScaleSlider
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 16
                                            from: 65
                                            to: 100
                                            stepSize: 5
                                            value: Math.round(root.optUiScaleManual() * 100)
                                            onMoved: {
                                                if (typeof bar.setUiScale === "function")
                                                    bar.setUiScale(Math.round(value) / 100)
                                            }
                                            onPressedChanged: {
                                                if (!pressed)
                                                    root.refreshOptions()
                                            }
                                            background: Rectangle {
                                                x: uiScaleSlider.leftPadding
                                                y: uiScaleSlider.topPadding + uiScaleSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 160
                                                implicitHeight: 5
                                                width: uiScaleSlider.availableWidth
                                                height: 5
                                                radius: 3
                                                color: Qt.rgba(1, 1, 1, 0.12)
                                                Rectangle {
                                                    width: uiScaleSlider.visualPosition * parent.width
                                                    height: parent.height
                                                    radius: 3
                                                    color: bar.accent
                                                }
                                            }
                                            handle: Rectangle {
                                                x: uiScaleSlider.leftPadding + uiScaleSlider.visualPosition * (uiScaleSlider.availableWidth - width)
                                                y: uiScaleSlider.topPadding + uiScaleSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 12
                                                implicitHeight: 12
                                                radius: 3
                                                color: uiScaleSlider.pressed ? bar.accent : bar.text
                                                border.width: 1
                                                border.color: bar.accent
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 48
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        anchors.topMargin: 6
                                        anchors.bottomMargin: 6
                                        spacing: 2
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: "Gap from edge"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: root.optBarEdgeMargin() + " px"
                                                color: bar.subtext
                                                font.pixelSize: 11
                                                font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                Layout.preferredWidth: root.optControlColW
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                        }
                                        Slider {
                                            id: optEdgeSlider
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 16
                                            from: 0
                                            to: 48
                                            stepSize: 2
                                            value: root.optBarEdgeMargin()
                                            onMoved: {
                                                if (typeof bar.setBarEdgeMargin === "function")
                                                    bar.setBarEdgeMargin(Math.round(value))
                                                root.optionsTick++
                                                root.menuTick++
                                                Qt.callLater(root.reposition)
                                            }
                                            background: Rectangle {
                                                x: optEdgeSlider.leftPadding
                                                y: optEdgeSlider.topPadding + optEdgeSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 160
                                                implicitHeight: 5
                                                width: optEdgeSlider.availableWidth
                                                height: 5
                                                radius: 3
                                                color: Qt.rgba(1, 1, 1, 0.12)
                                                Rectangle {
                                                    width: optEdgeSlider.visualPosition * parent.width
                                                    height: parent.height
                                                    radius: 3
                                                    color: bar.accent
                                                }
                                            }
                                            handle: Rectangle {
                                                x: optEdgeSlider.leftPadding + optEdgeSlider.visualPosition * (optEdgeSlider.availableWidth - width)
                                                y: optEdgeSlider.topPadding + optEdgeSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 12
                                                implicitHeight: 12
                                                radius: 3
                                                color: optEdgeSlider.pressed ? bar.accent : bar.text
                                                border.width: 1
                                                border.color: bar.accent
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Flush windows to bar"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Close the gap between tiled windows and the bar"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.flushWindowsToBar === true) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.flushWindowsToBar === true) ? "✓" : "✕"
                                                    color: (bar.flushWindowsToBar === true) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.setOptToggle("setFlushWindowsToBar", !(bar.flushWindowsToBar === true))
                                                        Qt.callLater(root.reposition)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 48
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        anchors.topMargin: 6
                                        anchors.bottomMargin: 6
                                        spacing: 2
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: "Bar size"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: root.optBarSizePct() + "%"
                                                color: bar.subtext
                                                font.pixelSize: 11
                                                font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                Layout.preferredWidth: root.optControlColW
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                        }
                                        Slider {
                                            id: optBarSizeSlider
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 16
                                            from: 80
                                            to: 140
                                            stepSize: 5
                                            value: root.optBarSizePct()
                                            onMoved: {
                                                if (typeof bar.setBarSizeScale === "function")
                                                    bar.setBarSizeScale(Math.round(value) / 100)
                                                root.optionsTick++
                                                root.menuTick++
                                                Qt.callLater(root.reposition)
                                            }
                                            background: Rectangle {
                                                x: optBarSizeSlider.leftPadding
                                                y: optBarSizeSlider.topPadding + optBarSizeSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 160
                                                implicitHeight: 5
                                                width: optBarSizeSlider.availableWidth
                                                height: 5
                                                radius: 3
                                                color: Qt.rgba(1, 1, 1, 0.12)
                                                Rectangle {
                                                    width: optBarSizeSlider.visualPosition * parent.width
                                                    height: parent.height
                                                    radius: 3
                                                    color: bar.accent
                                                }
                                            }
                                            handle: Rectangle {
                                                x: optBarSizeSlider.leftPadding + optBarSizeSlider.visualPosition * (optBarSizeSlider.availableWidth - width)
                                                y: optBarSizeSlider.topPadding + optBarSizeSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 12
                                                implicitHeight: 12
                                                radius: 3
                                                color: optBarSizeSlider.pressed ? bar.accent : bar.text
                                                border.width: 1
                                                border.color: bar.accent
                                            }
                                        }
                                    }
                                }
                                Text {
                                    text: "Tooltips"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 48
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        anchors.topMargin: 6
                                        anchors.bottomMargin: 6
                                        spacing: 2
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: "Delay"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: root.optTooltipDelay() + " ms"
                                                color: bar.subtext
                                                font.pixelSize: 11
                                                font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                Layout.preferredWidth: 56
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                        }
                                        Slider {
                                            id: optTipDelaySlider
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 16
                                            from: 0
                                            to: 3000
                                            stepSize: 50
                                            value: root.optTooltipDelay()
                                            onMoved: {
                                                if (typeof bar.setTooltipDelay === "function")
                                                    bar.setTooltipDelay(Math.round(value))
                                                root.optionsTick++
                                                root.menuTick++
                                            }
                                            background: Rectangle {
                                                x: optTipDelaySlider.leftPadding
                                                y: optTipDelaySlider.topPadding + optTipDelaySlider.availableHeight / 2 - height / 2
                                                implicitWidth: 160
                                                implicitHeight: 5
                                                width: optTipDelaySlider.availableWidth
                                                height: 5
                                                radius: 3
                                                color: Qt.rgba(1, 1, 1, 0.12)
                                                Rectangle {
                                                    width: optTipDelaySlider.visualPosition * parent.width
                                                    height: parent.height
                                                    radius: 3
                                                    color: bar.accent
                                                }
                                            }
                                            handle: Rectangle {
                                                x: optTipDelaySlider.leftPadding + optTipDelaySlider.visualPosition * (optTipDelaySlider.availableWidth - width)
                                                y: optTipDelaySlider.topPadding + optTipDelaySlider.availableHeight / 2 - height / 2
                                                implicitWidth: 12
                                                implicitHeight: 12
                                                radius: 3
                                                color: optTipDelaySlider.pressed ? bar.accent : bar.text
                                                border.width: 1
                                                border.color: bar.accent
                                            }
                                        }
                                    }
                                }
                                Text {
                                    text: "Per-widget side (auto follows the bar edge)"
                                    color: bar.subtext
                                    font.pixelSize: 10
                                    font.family: bar.fontFamily
                                }
                                Repeater {
                                    model: root.tooltipAlignTargets()
                                    delegate: Rectangle {
                                        id: tipAlignRow
                                        required property var modelData
                                        readonly property string widgetId: modelData.id
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 36
                                        radius: root.chipR
                                        color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                        border.width: 1
                                        border.color: bar.dividerStrong
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 8
                                            spacing: 6
                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.label
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                            }
                                            Repeater {
                                                model: [
                                                    { id: "auto", label: "A" },
                                                    { id: "above", label: "T" },
                                                    { id: "below", label: "B" },
                                                    { id: "left", label: "L" },
                                                    { id: "right", label: "R" }
                                                ]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    readonly property bool on: {
                                                        const cur = root.optTooltipAlign(tipAlignRow.widgetId)
                                                        if (modelData.id === "auto")
                                                            return cur === "auto" || cur === ""
                                                        return cur === modelData.id
                                                    }
                                                    width: 22
                                                    height: 22
                                                    radius: 4
                                                    color: on
                                                           ? Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.22)
                                                           : "transparent"
                                                    border.width: 1
                                                    border.color: on ? bar.accent : bar.pillBorder
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: modelData.label
                                                        color: on ? bar.accent : bar.subtext
                                                        font.pixelSize: 10
                                                        font.bold: on
                                                        font.family: bar.fontFamily
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (typeof bar.setTooltipAlign === "function")
                                                                bar.setTooltipAlign(tipAlignRow.widgetId, modelData.id)
                                                            root.optionsTick++
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Config menu icon on bar"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Gear pill opens this control strip"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showControlBarPill) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showControlBarPill) ? "✓" : "✕"
                                                    color: (bar.showControlBarPill) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowControlBarPill", !bar.showControlBarPill)
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Color presets section"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Show built-in / custom presets on the Colors panel"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showColorPresets !== false) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showColorPresets !== false) ? "✓" : "✕"
                                                    color: (bar.showColorPresets !== false) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowColorPresets", !(bar.showColorPresets !== false))
                                                }
                                            }
                                        }
                                    }
                                }
                                Text {
                                    text: "Workspaces"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "Saved to bar layout"
                                    color: bar.subtext
                                    font.pixelSize: 10
                                    font.family: bar.fontFamily
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 36
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Magic workspace pill"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showMagicWorkspacePill) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showMagicWorkspacePill) ? "✓" : "✕"
                                                    color: (bar.showMagicWorkspacePill) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowMagicWorkspacePill", !bar.showMagicWorkspacePill)
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Show only active workspace"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Hide empty numbered pills"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.wsShowOnlyActive) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.wsShowOnlyActive) ? "✓" : "✕"
                                                    color: (bar.wsShowOnlyActive) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setWsShowOnlyActive", !bar.wsShowOnlyActive)
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Minimum workspace pills"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Show 1…N when not “only active”"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            TextField {
                                                id: wsMinField
                                                anchors.centerIn: parent
                                                width: root.optFieldW
                                                height: root.optToggleH
                                                horizontalAlignment: Text.AlignHCenter
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                text: String(bar.wsMinimumShown)
                                                validator: IntValidator { bottom: 0; top: 10 }
                                                background: Rectangle {
                                                    radius: 4
                                                    color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                                    border.width: 1
                                                    border.color: wsMinField.activeFocus ? bar.accent : bar.pillBorder
                                                }
                                                onAccepted: root.setOptNumber("setWsMinimumShown", parseInt(text, 10))
                                                onEditingFinished: root.setOptNumber("setWsMinimumShown", parseInt(text, 10))
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Startup workspace"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "0 = leave focus alone (safe on qs reload)"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            TextField {
                                                id: wsStartField
                                                anchors.centerIn: parent
                                                width: root.optFieldW
                                                height: root.optToggleH
                                                horizontalAlignment: Text.AlignHCenter
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                text: String(bar.wsStartupWorkspace)
                                                validator: IntValidator { bottom: 0; top: 10 }
                                                background: Rectangle {
                                                    radius: 4
                                                    color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                                    border.width: 1
                                                    border.color: wsStartField.activeFocus ? bar.accent : bar.pillBorder
                                                }
                                                onAccepted: root.setOptNumber("setWsStartupWorkspace", parseInt(text, 10))
                                                onEditingFinished: root.setOptNumber("setWsStartupWorkspace", parseInt(text, 10))
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Close magic on startup"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Only if startup workspace > 0"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.wsStartupCloseMagic) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.wsStartupCloseMagic) ? "✓" : "✕"
                                                    color: (bar.wsStartupCloseMagic) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setWsStartupCloseMagic", !bar.wsStartupCloseMagic)
                                                }
                                            }
                                        }
                                    }
                                }
                                Text {
                                    text: "Audio"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Show echo cancel in audio menu"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Show AEC section on Audio pill + control-bar Audio (on/off stays in the panel)"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showEchoCancelInMenu) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showEchoCancelInMenu) ? "✓" : "✕"
                                                    color: (bar.showEchoCancelInMenu) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowEchoCancelInMenu", !bar.showEchoCancelInMenu)
                                                }
                                            }
                                        }
                                    }
                                }
                                // Control-bar Audio panel section visibility
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Show Audio Summary"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Control-bar Audio panel section"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showAudioSummary !== false) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showAudioSummary !== false) ? "✓" : "✕"
                                                    color: (bar.showAudioSummary !== false) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowAudioSummary", !(bar.showAudioSummary !== false))
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Show device profiles"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Profile dropdowns under Output / Input devices"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showAudioDefaults !== false) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showAudioDefaults !== false) ? "✓" : "✕"
                                                    color: (bar.showAudioDefaults !== false) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowAudioDefaults", !(bar.showAudioDefaults !== false))
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Show Level meters"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Playback / Recording VU meters below Active streams"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showAudioLevelMeters !== false) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showAudioLevelMeters !== false) ? "✓" : "✕"
                                                    color: (bar.showAudioLevelMeters !== false) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowAudioLevelMeters", !(bar.showAudioLevelMeters !== false))
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Keep Audio Summary expanded"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "When opening the control-bar Audio panel"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.audioSummaryExpanded !== false) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.audioSummaryExpanded !== false) ? "✓" : "✕"
                                                    color: (bar.audioSummaryExpanded !== false) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setAudioSummaryExpanded", !(bar.audioSummaryExpanded !== false))
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Keep Active streams expanded"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "When opening the control-bar Audio panel"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.audioDefaultsExpanded !== false) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.audioDefaultsExpanded !== false) ? "✓" : "✕"
                                                    color: (bar.audioDefaultsExpanded !== false) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setAudioDefaultsExpanded", !(bar.audioDefaultsExpanded !== false))
                                                }
                                            }
                                        }
                                    }
                                }
                                Text {
                                    text: "Network"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "nm-applet login autostart"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Sticky · survives reboot"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (root.optNetApplet()) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (root.optNetApplet()) ? "✓" : "✕"
                                                    color: (root.optNetApplet()) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setNetworkAppletAutostart", !root.optNetApplet())
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Traffic graph"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Sparkline in network details (adapters stay)"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showNetTrafficGraph !== false) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showNetTrafficGraph !== false) ? "✓" : "✕"
                                                    color: (bar.showNetTrafficGraph !== false) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowNetTrafficGraph", !(bar.showNetTrafficGraph !== false))
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Full IP on bar"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Show complete address instead of last octet"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showNetworkFullIp === true) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showNetworkFullIp === true) ? "✓" : "✕"
                                                    color: (bar.showNetworkFullIp === true) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowNetworkFullIp", !(bar.showNetworkFullIp === true))
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Last octet on bar"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Show the last IPv4 octet when full IP is off"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showNetworkLastOctet !== false) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showNetworkLastOctet !== false) ? "✓" : "✕"
                                                    color: (bar.showNetworkLastOctet !== false) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowNetworkLastOctet", !(bar.showNetworkLastOctet !== false))
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Device name on bar"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Show adapter name such as enp10s0 or wlan0"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showNetworkDeviceName === true) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showNetworkDeviceName === true) ? "✓" : "✕"
                                                    color: (bar.showNetworkDeviceName === true) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowNetworkDeviceName", !(bar.showNetworkDeviceName === true))
                                                }
                                            }
                                        }
                                    }
                                }
                                Text {
                                    text: "Bluetooth"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Blueman tray login autostart"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Sticky · survives reboot"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (root.optBtApplet()) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (root.optBtApplet()) ? "✓" : "✕"
                                                    color: (root.optBtApplet()) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setBluetoothAppletAutostart", !root.optBtApplet())
                                                }
                                            }
                                        }
                                    }
                                }
                                Text {
                                    text: "System stats"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "Which gauges appear on the Sys Stats pill (saved)"
                                    color: bar.subtext
                                    font.pixelSize: 10
                                    font.family: bar.fontFamily
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 36
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Show CPU"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Gauge + metrics popup on the pill"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showStatCpu) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showStatCpu) ? "✓" : "✕"
                                                    color: (bar.showStatCpu) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowStatCpu", !bar.showStatCpu)
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 36
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Show Memory"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Gauge + metrics popup on the pill"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showStatMem) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showStatMem) ? "✓" : "✕"
                                                    color: (bar.showStatMem) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowStatMem", !bar.showStatMem)
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 36
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Show GPU"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Gauge + metrics popup on the pill"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showStatGpu) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showStatGpu) ? "✓" : "✕"
                                                    color: (bar.showStatGpu) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowStatGpu", !bar.showStatGpu)
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Bar util graphs"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Mini bars on the Sys Stats pill face"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showStatGauges !== false) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showStatGauges !== false) ? "✓" : "✕"
                                                    color: (bar.showStatGauges !== false) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowStatGauges", !(bar.showStatGauges !== false))
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Menu util graphs"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Gauges + history in left-click metrics; processes stay"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showStatMenuGraphs !== false) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showStatMenuGraphs !== false) ? "✓" : "✕"
                                                    color: (bar.showStatMenuGraphs !== false) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowStatMenuGraphs", !(bar.showStatMenuGraphs !== false))
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Metrics live updates"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "CPU / Mem / GPU popups (session)"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (root.optMetricsLive()) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (root.optMetricsLive()) ? "✓" : "✕"
                                                    color: (root.optMetricsLive()) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setMetricsLiveUpdates", !root.optMetricsLive())
                                                }
                                            }
                                        }
                                    }
                                }

                                // --- FreshRSS ---
                                Text {
                                    text: "FreshRSS"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "Server + credentials write to ~/.config/freshrss-quickshell/freshrss.env (outside git). API password = Profile → API password."
                                    color: bar.subtext
                                    font.pixelSize: 10
                                    font.family: bar.fontFamily
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Filters expanded on open"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Search / max days / per feed section"
                                                color: bar.subtext
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.preferredHeight: root.optToggleH
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (!!bar.freshRssFiltersExpanded) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (!!bar.freshRssFiltersExpanded) ? "✓" : "✕"
                                                    color: (!!bar.freshRssFiltersExpanded) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setFreshRssFiltersExpanded", !bar.freshRssFiltersExpanded)
                                                }
                                            }
                                        }
                                    }
                                }
                                // Scheme (+ spacer so control column lines up with toggles above)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Text {
                                        text: "Scheme"
                                        color: bar.subtext
                                        font.pixelSize: 12
                                        font.family: bar.fontFamily
                                        Layout.preferredWidth: 56
                                    }
                                    Repeater {
                                        model: [
                                            { id: "https", label: "HTTPS" },
                                            { id: "http", label: "HTTP" }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.preferredHeight: 28
                                            Layout.preferredWidth: frSchemeLbl.implicitWidth + 16
                                            radius: root.chipR
                                            color: root.frScheme === modelData.id
                                                   ? (bar.controlActiveBg || Qt.rgba(0, 0.77, 0.96, 0.22))
                                                   : (frSchemeMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg))
                                            border.width: 1
                                            border.color: root.frScheme === modelData.id ? bar.accent : bar.pillBorder
                                            Text {
                                                id: frSchemeLbl
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                color: root.frScheme === modelData.id ? bar.accent : bar.subtext
                                                font.pixelSize: 11
                                                font.family: bar.fontFamily
                                            }
                                            MouseArea {
                                                id: frSchemeMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.frScheme = modelData.id
                                            }
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Item {
                                        Layout.preferredWidth: root.optControlColW
                                        Layout.maximumWidth: root.optControlColW
                                        Layout.minimumWidth: root.optControlColW
                                    }
                                }
                                // Host
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Text {
                                        text: "Host"
                                        color: bar.subtext
                                        font.pixelSize: 12
                                        Layout.preferredWidth: 56
                                    }
                                    TextField {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 30
                                        placeholderText: "freshrss.example or 10.74.10.8"
                                        color: bar.text
                                        placeholderTextColor: bar.subtext
                                        font.pixelSize: 12
                                        font.family: bar.fontFamily
                                        text: root.frHost
                                        onTextChanged: root.frHost = text
                                        background: Rectangle {
                                            radius: root.chipR
                                            color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                            border.width: 1
                                            border.color: parent.activeFocus ? bar.accent : bar.pillBorder
                                        }
                                    }
                                    Item {
                                        Layout.preferredWidth: root.optControlColW
                                        Layout.maximumWidth: root.optControlColW
                                        Layout.minimumWidth: root.optControlColW
                                    }
                                }
                                // User
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Text {
                                        text: "User"
                                        color: bar.subtext
                                        font.pixelSize: 12
                                        Layout.preferredWidth: 56
                                    }
                                    TextField {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 30
                                        placeholderText: "admin"
                                        color: bar.text
                                        placeholderTextColor: bar.subtext
                                        font.pixelSize: 12
                                        font.family: bar.fontFamily
                                        text: root.frUser
                                        onTextChanged: root.frUser = text
                                        background: Rectangle {
                                            radius: root.chipR
                                            color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                            border.width: 1
                                            border.color: parent.activeFocus ? bar.accent : bar.pillBorder
                                        }
                                    }
                                    Item {
                                        Layout.preferredWidth: root.optControlColW
                                        Layout.maximumWidth: root.optControlColW
                                        Layout.minimumWidth: root.optControlColW
                                    }
                                }
                                // API password (write-only)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Text {
                                        text: "API pw"
                                        color: bar.subtext
                                        font.pixelSize: 12
                                        Layout.preferredWidth: 56
                                    }
                                    TextField {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 30
                                        echoMode: TextInput.Password
                                        placeholderText: root.frHasPassword
                                                         ? "•••• set (type to replace)"
                                                         : "Profile → API password"
                                        color: bar.text
                                        placeholderTextColor: bar.subtext
                                        font.pixelSize: 12
                                        font.family: bar.fontFamily
                                        text: root.frPassword
                                        onTextChanged: root.frPassword = text
                                        background: Rectangle {
                                            radius: root.chipR
                                            color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                            border.width: 1
                                            border.color: parent.activeFocus ? bar.accent : bar.pillBorder
                                        }
                                    }
                                    Item {
                                        Layout.preferredWidth: root.optControlColW
                                        Layout.maximumWidth: root.optControlColW
                                        Layout.minimumWidth: root.optControlColW
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: root.frLoading
                                              ? "…"
                                              : (root.frStatus || "Test connection · Save writes external env")
                                        color: {
                                            const s = root.frStatus || ""
                                            if (s.indexOf("OK") === 0 || s.indexOf("Saved") === 0)
                                                return root.onGreen
                                            if (s.indexOf("Failed") === 0 || s.indexOf("failed") >= 0 || s.indexOf("error") >= 0)
                                                return root.offRed
                                            return bar.subtext
                                        }
                                        font.pixelSize: 11
                                        font.family: bar.fontFamily
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 28
                                        Layout.preferredWidth: frTestLbl.implicitWidth + 16
                                        radius: root.chipR
                                        color: frTestMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                        border.width: 1
                                        border.color: frTestMa.containsMouse ? bar.accent : bar.pillBorder
                                        opacity: root.frLoading ? 0.6 : 1.0
                                        Text {
                                            id: frTestLbl
                                            anchors.centerIn: parent
                                            text: "Test"
                                            color: frTestMa.containsMouse ? root.activeLabelColor() : bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: frTestMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: !root.frLoading
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.testFreshRssConnection()
                                            ToolTip.visible: containsMouse
                                            ToolTip.delay: bar.tooltipDelay
                                            ToolTip.text: "Probe server with form values (does not Save)"
                                        }
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 28
                                        Layout.preferredWidth: frSaveLbl.implicitWidth + 16
                                        radius: root.chipR
                                        color: frSaveMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                        border.width: 1
                                        border.color: frSaveMa.containsMouse ? bar.accent : bar.pillBorder
                                        opacity: root.frLoading ? 0.6 : 1.0
                                        Text {
                                            id: frSaveLbl
                                            anchors.centerIn: parent
                                            text: "Save server"
                                            color: frSaveMa.containsMouse ? root.activeLabelColor() : bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: frSaveMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: !root.frLoading
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.saveFreshRssSecrets()
                                            ToolTip.visible: containsMouse
                                            ToolTip.delay: bar.tooltipDelay
                                            ToolTip.text: "Write ~/.config/freshrss-quickshell/freshrss.env"
                                        }
                                    }
                                }

                                    } // optionsBodyCol
                                } // optionsBodyFlick

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Rectangle {
                                        Layout.preferredHeight: 24
                                        Layout.preferredWidth: refreshOptLbl.implicitWidth + 12
                                        radius: root.chipR
                                        color: refreshOptMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: refreshOptLbl
                                            anchors.centerIn: parent
                                            text: "Refresh"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: refreshOptMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.refreshOptions()
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                            }

                            // ===== MIME (preferred applications / file-type defaults) =====
                            ColumnLayout {
                                id: mimePanel
                                visible: root.activeMenu === "mime"
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(320, root.panelMaxH - 12)
                                spacing: 6

                                Text {
                                    text: "Preferred applications"
                                    color: bar.text
                                    font.pixelSize: bar.popupTitleSize
                                    font.bold: true
                                    font.family: root.menuTitleFont()
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "Choose a file type or app, then set which program opens it by default."
                                    color: bar.subtext
                                    font.pixelSize: bar.popupHintSize
                                    font.family: root.menuBodyFont()
                                }
                                MimeAppsView {
                                    id: controlMime
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumHeight: 200
                                    // Stretch to panel bottom (preferredHeight 0 + fillHeight)
                                    Layout.preferredHeight: 0
                                    showReloadButton: false
                                    keyboardGrab: function() { root.armControlFocusGrab() }
                                    active: mimePanel.visible && controlPopup.visible
                                    textColor: bar.text
                                    subtextColor: bar.subtext
                                    accentColor: bar.accent
                                    surfaceColor: Qt.rgba(0.05, 0.07, 0.12, 0.90)
                                    // Secondary text for muted body greys (not overlay)
                                    overlayColor: bar.subtext
                                    okColor: root.onGreen
                                    warnColor: "#f0d060"
                                    errorColor: root.offRed
                                    fieldBg: root.optFieldBg
                                    fieldBgFocus: root.optFieldBgFocus
                                    pillBorder: bar.pillBorder
                                    fontFamily: root.menuBodyFont()
                                    fontMono: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Rectangle {
                                        Layout.preferredHeight: 26
                                        Layout.preferredWidth: mimeReloadLbl.implicitWidth + 14
                                        radius: root.chipR
                                        color: mimeReloadMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        enabled: controlMime && !controlMime.loading && !controlMime.acting
                                        opacity: enabled ? 1 : 0.5
                                        Text {
                                            id: mimeReloadLbl
                                            anchors.centerIn: parent
                                            text: "Reload"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: mimeReloadMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (controlMime && typeof controlMime.refresh === "function")
                                                    controlMime.refresh()
                                            }
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                            }

                            // ===== SERVICES (systemd — same engine as Inspector) =====
                            ColumnLayout {
                                id: servicesPanel
                                visible: root.activeMenu === "services"
                                Layout.fillWidth: true
                                // Fixed tall panel; ServicesView scrolls internally (no outer double-scroll)
                                Layout.preferredHeight: Math.max(320, root.panelMaxH - 12)
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Services"
                                        color: bar.text
                                        font.pixelSize: bar.popupTitleSize
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                    Text {
                                        visible: controlServices.lastError.length > 0
                                        text: controlServices.lastError
                                        color: root.offRed
                                        font.pixelSize: 10
                                        font.family: bar.fontFamily
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: 220
                                    }
                                    Text {
                                        visible: controlServices.lastAction.length > 0
                                                 && controlServices.lastError.length === 0
                                        text: controlServices.lastAction
                                        color: root.onGreen
                                        font.pixelSize: 10
                                        font.family: bar.fontFamily
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "User and system units (same as Inspector Services). Select a row, then Start / Stop / Restart. System scope may prompt for polkit."
                                    color: bar.subtext
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontFamily
                                }
                                TextField {
                                    id: servicesFilterField
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 30
                                    placeholderText: "Filter services…"
                                    color: bar.text
                                    placeholderTextColor: bar.subtext
                                    font.pixelSize: 12
                                    font.family: bar.fontFamily
                                    text: root.servicesFilter
                                    background: Rectangle {
                                        radius: root.chipR
                                        color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                        border.width: 1
                                        border.color: servicesFilterField.activeFocus ? bar.accent : bar.pillBorder
                                    }
                                    onPressed: root.armControlFocusGrab()
                                    onActiveFocusChanged: if (activeFocus) root.armControlFocusGrab()
                                    onTextChanged: root.servicesFilter = text
                                }
                                ServicesView {
                                    id: controlServices
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumHeight: 200
                                    active: servicesPanel.visible && controlPopup.visible
                                    globalFilter: root.servicesFilter
                                    textColor: bar.text
                                    subtextColor: bar.subtext
                                    accentColor: bar.accent
                                    surfaceColor: Qt.rgba(0.05, 0.07, 0.12, 0.90)
                                    overlayColor: bar.overlay
                                    okColor: root.onGreen
                                    warnColor: "#f0d060"
                                    errorColor: root.offRed
                                }
                            }

                            // ===== AUDIO (devices / ports / AEC — same engine as Inspector) =====
                            ColumnLayout {
                                id: audioPanel
                                visible: root.activeMenu === "audio"
                                Layout.fillWidth: true
                                // Fixed tall panel; AudioMonitorView scrolls internally
                                Layout.preferredHeight: Math.max(320, root.panelMaxH - 12)
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Audio"
                                        color: bar.text
                                        font.pixelSize: bar.popupTitleSize
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                    Text {
                                        visible: controlAudio.lastError.length > 0
                                        text: controlAudio.lastError
                                        color: root.offRed
                                        font.pixelSize: 10
                                        font.family: bar.fontFamily
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: 220
                                    }
                                    Text {
                                        visible: controlAudio.toolsStatus.length > 0
                                                 && controlAudio.lastError.length === 0
                                        text: controlAudio.toolsStatus
                                        color: root.onGreen
                                        font.pixelSize: 10
                                        font.family: bar.fontFamily
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: 200
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "Sinks, sources, ports, and defaults (same as Inspector Audio). Tools: Refresh, pw-top, Restart audio, echo cancel. Pill stays the quick volume control."
                                    color: bar.subtext
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontFamily
                                }
                                TextField {
                                    id: audioFilterField
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 30
                                    placeholderText: "Filter devices / apps…"
                                    color: bar.text
                                    placeholderTextColor: bar.subtext
                                    font.pixelSize: 12
                                    font.family: bar.fontFamily
                                    text: root.audioFilter
                                    background: Rectangle {
                                        radius: root.chipR
                                        color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                        border.width: 1
                                        border.color: audioFilterField.activeFocus ? bar.accent : bar.pillBorder
                                    }
                                    onPressed: root.armControlFocusGrab()
                                    onActiveFocusChanged: if (activeFocus) root.armControlFocusGrab()
                                    onTextChanged: root.audioFilter = text
                                }
                                AudioMonitorView {
                                    id: controlAudio
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumHeight: 200
                                    active: audioPanel.visible && controlPopup.visible
                                    showTools: true
                                    showSummary: bar.showAudioSummary !== false
                                    showDefaults: bar.showAudioDefaults !== false
                                    showLevelMeters: bar.showAudioLevelMeters !== false
                                    showEchoCancel: bar.showEchoCancelInMenu !== false
                                    summaryExpandedPref: bar.audioSummaryExpanded !== false
                                    defaultsExpandedPref: bar.audioDefaultsExpanded !== false
                                    globalFilter: root.audioFilter
                                    textColor: bar.text
                                    subtextColor: bar.subtext
                                    accentColor: bar.accent
                                    surfaceColor: Qt.rgba(0.05, 0.07, 0.12, 0.90)
                                    overlayColor: bar.overlay
                                    okColor: root.onGreen
                                    warnColor: "#f0d060"
                                    errorColor: root.offRed
                                }
                            }

                            // ===== KEYBINDS (edit chord / category / description) =====
                            ColumnLayout {
                                id: keybindsPanel
                                visible: root.activeMenu === "keybinds"
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(320, root.panelMaxH - 12)
                                spacing: 6

                                Text {
                                    text: "Keybindings"
                                    color: bar.text
                                    font.pixelSize: bar.popupTitleSize
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "From keybindings.lua (same categories as Inspector). Edit key, category, or description — not the action. Loop/dynamic binds are read-only. Save writes the file; use Reload Hypr to apply."
                                    color: bar.subtext
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontFamily
                                }
                                TextField {
                                    id: keybindsFilterField
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 30
                                    placeholderText: "Filter keybindings…"
                                    color: bar.text
                                    placeholderTextColor: bar.subtext
                                    font.pixelSize: 12
                                    font.family: bar.fontFamily
                                    text: root.keybindsFilter
                                    background: Rectangle {
                                        radius: root.chipR
                                        color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                        border.width: 1
                                        border.color: keybindsFilterField.activeFocus ? bar.accent : bar.pillBorder
                                    }
                                    onPressed: root.armControlFocusGrab()
                                    onActiveFocusChanged: if (activeFocus) root.armControlFocusGrab()
                                    onTextChanged: root.keybindsFilter = text
                                }
                                KeybindsView {
                                    id: controlKeybinds
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumHeight: 200
                                    active: keybindsPanel.visible && controlPopup.visible
                                    filterText: root.keybindsFilter
                                    textColor: bar.text
                                    subtextColor: bar.subtext
                                    accentColor: bar.accent
                                    surfaceColor: Qt.rgba(0.05, 0.07, 0.12, 0.90)
                                    overlayColor: bar.overlay
                                    okColor: root.onGreen
                                    warnColor: "#f0d060"
                                    errorColor: root.offRed
                                    fieldBg: root.optFieldBg
                                    fieldBgFocus: root.optFieldBgFocus
                                    pillBorder: bar.pillBorder
                                    fontFamily: bar.fontFamily
                                    fontMono: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                }
                            }

                            // ===== THEMES (bar / widget theme) =====
                            ColumnLayout {
                                id: themesPanel
                                visible: root.activeMenu === "colors"
                                Layout.fillWidth: true
                                // Fill the panel height so title + tabs stay fixed; body scrolls inside
                                Layout.preferredHeight: root.panelMaxH - 24
                                Layout.minimumHeight: 280
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Themes"
                                        color: bar.text
                                        font.pixelSize: bar.popupTitleSize
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 24
                                        Layout.preferredWidth: undoThemeLbl.implicitWidth + 12
                                        radius: root.chipR
                                        opacity: root.canThemeUndo() ? 1 : 0.4
                                        color: undoThemeMa.containsMouse && root.canThemeUndo()
                                               ? bar.glassHover
                                               : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: undoThemeLbl
                                            anchors.centerIn: parent
                                            text: {
                                                void root.colorsTick
                                                const n = root.themeUndoStack ? root.themeUndoStack.length : 0
                                                return n > 0 ? ("Undo (" + n + ")") : "Undo"
                                            }
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: undoThemeMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: root.canThemeUndo()
                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: root.undoThemeEdit()
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "Change how the bar and widgets look. Click a color square to open the picker. Changes apply immediately and are saved."
                                    // Secondary text — body / help copy (not headers)
                                    color: bar.subtext
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontFamily
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: !!(bar && bar.themeStatus && bar.themeStatus.length)
                                    text: bar ? (bar.themeStatus || "") : ""
                                    // Secondary text — status line under the header
                                    color: bar.subtext
                                    font.pixelSize: 11
                                    font.family: bar.fontFamily
                                    wrapMode: Text.WordWrap
                                }

                                // ── Sticky sub-tabs (do not scroll with body) ──
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Repeater {
                                        model: {
                                            void root.optionsTick
                                            const tabs = [
                                                { id: "theming", label: "Theming" },
                                                { id: "thresholds", label: "Thresholds" },
                                                { id: "fonts", label: "Fonts" }
                                            ]
                                            if (bar && bar.showColorPresets !== false)
                                                tabs.push({ id: "presets", label: "Presets" })
                                            return tabs
                                        }
                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property bool active: root.colorsTab === modelData.id
                                            Layout.preferredHeight: root.chipH
                                            Layout.preferredWidth: Math.max(72, tabLbl.implicitWidth + 18)
                                            radius: root.chipR
                                            color: root.chipBg(active, tabMa.containsMouse)
                                            border.width: bar.controlBorderWidth
                                            border.color: root.chipBorder(active, tabMa.containsMouse)
                                            Text {
                                                id: tabLbl
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                font.pixelSize: bar.fontPillLabel !== undefined ? bar.fontPillLabel : 12
                                                font.family: bar.fontFamily
                                                font.bold: active
                                                color: root.chipText(active, tabMa.containsMouse)
                                            }
                                            MouseArea {
                                                id: tabMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.setColorsTab(modelData.id)
                                            }
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }

                                // ── Scrollable body under sticky tabs ──
                                Flickable {
                                    id: themesBodyFlick
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumHeight: 160
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    flickableDirection: Flickable.VerticalFlick
                                    contentWidth: width
                                    // When the color picker is open, size content to the viewport
                                    // so the picker fills height (no empty gap under it).
                                    contentHeight: {
                                        void root.colorsTick
                                        if (root.themePickerOpenOnRight() || root.thresholdsPickerOpen())
                                            return Math.max(themesBodyCol.implicitHeight, height)
                                        return themesBodyCol.implicitHeight
                                    }
                                    interactive: contentHeight > height + 4
                                                 && !(root.colorsPickerKey.length > 0)
                                    ScrollBar.vertical: ScrollBar {
                                        policy: themesBodyFlick.contentHeight > themesBodyFlick.height + 4
                                                ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                        width: 8
                                        contentItem: Rectangle {
                                            implicitWidth: 6
                                            radius: 3
                                            color: bar.accent
                                            opacity: 0.5
                                        }
                                    }

                                ColumnLayout {
                                    id: themesBodyCol
                                    width: themesBodyFlick.width - 10
                                    spacing: 8

                                // ════════ THEMING tab ════════
                                // Left: Colors / Text / Special · Right: Opacity or picker
                                // When picker is open, row height matches body viewport (no gap).
                                RowLayout {
                                    id: themingRow
                                    visible: root.colorsTab === "theming"
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignTop
                                    Layout.preferredHeight: {
                                        void root.colorsTick
                                        if (root.themePickerOpenOnRight())
                                            return Math.max(280, themesBodyFlick.height)
                                        return -1
                                    }
                                    spacing: 10

                                    // ════ LEFT — sectioned swatches (scrolls when picker is open) ════
                                    Flickable {
                                        id: themingLeftFlick
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.fillHeight: root.themePickerOpenOnRight()
                                        Layout.preferredHeight: root.themePickerOpenOnRight()
                                                                ? -1
                                                                : themingLeftCol.implicitHeight
                                        Layout.alignment: Qt.AlignTop
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds
                                        flickableDirection: Flickable.VerticalFlick
                                        contentWidth: width
                                        contentHeight: themingLeftCol.implicitHeight
                                        interactive: contentHeight > height + 4
                                        ScrollBar.vertical: ScrollBar {
                                            policy: themingLeftFlick.contentHeight > themingLeftFlick.height + 4
                                                    ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                            width: 6
                                            contentItem: Rectangle {
                                                implicitWidth: 4
                                                radius: 2
                                                color: bar.accent
                                                opacity: 0.45
                                            }
                                        }

                                    ColumnLayout {
                                        id: themingLeftCol
                                        width: themingLeftFlick.width - 8
                                        spacing: 8

                                        // ── Colors (collapsible) ──
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 28
                                            radius: root.chipR
                                            color: secColorsMa.containsMouse ? bar.glassHover : "transparent"
                                            border.width: 1
                                            border.color: bar.dividerStrong
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 6
                                                Text {
                                                    text: root.themeSecColorsOpen ? "▾" : "▸"
                                                    color: bar.text
                                                    font.pixelSize: 12
                                                    font.family: bar.fontFamily
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: "Colors"
                                                    color: bar.text
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                    font.family: bar.fontFamily
                                                }
                                            }
                                            MouseArea {
                                                id: secColorsMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.toggleThemeSection("colors")
                                            }
                                        }
                                        Repeater {
                                            model: {
                                                void root.colorsTick
                                                return root.themeSecColorsOpen ? root.themeColorRows() : []
                                            }
                                            delegate: Rectangle {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 34
                                                radius: root.chipR
                                                color: Qt.rgba(0.08, 0.10, 0.14, 0.55)
                                                border.width: 1
                                                border.color: root.colorsPickerKey === modelData.key ? bar.accent : bar.dividerStrong
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 8
                                                    spacing: 6
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.label
                                                        color: bar.subtext
                                                        font.pixelSize: 11
                                                        font.family: bar.fontFamily
                                                        elide: Text.ElideRight
                                                    }
                                                    Rectangle {
                                                        Layout.preferredWidth: 24
                                                        Layout.preferredHeight: 18
                                                        radius: 4
                                                        color: {
                                                            void root.colorsTick
                                                            return root.themeColorFor(modelData.key)
                                                        }
                                                        border.width: 1
                                                        border.color: Qt.rgba(1, 1, 1, 0.25)
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (root.colorsPickerKey === modelData.key)
                                                                    root.closeColorPicker()
                                                                else
                                                                    root.openColorPicker(modelData.key)
                                                            }
                                                        }
                                                    }
                                                    Text {
                                                        text: {
                                                            void root.colorsTick
                                                            return root.themeHexFor(modelData.key)
                                                        }
                                                        color: bar.subtext
                                                        font.pixelSize: 10
                                                        font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                        Layout.preferredWidth: 56
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }
                                        }

                                        // ── Text (collapsible) ──
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 28
                                            Layout.topMargin: 4
                                            radius: root.chipR
                                            color: secTextMa.containsMouse ? bar.glassHover : "transparent"
                                            border.width: 1
                                            border.color: bar.dividerStrong
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 6
                                                Text {
                                                    text: root.themeSecTextOpen ? "▾" : "▸"
                                                    color: bar.text
                                                    font.pixelSize: 12
                                                    font.family: bar.fontFamily
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: "Text"
                                                    color: bar.text
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                    font.family: bar.fontFamily
                                                }
                                            }
                                            MouseArea {
                                                id: secTextMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.toggleThemeSection("text")
                                            }
                                        }
                                        Repeater {
                                            model: {
                                                void root.colorsTick
                                                return root.themeSecTextOpen ? root.themeTextRows() : []
                                            }
                                            delegate: Rectangle {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 34
                                                radius: root.chipR
                                                color: Qt.rgba(0.08, 0.10, 0.14, 0.55)
                                                border.width: 1
                                                border.color: root.colorsPickerKey === modelData.key ? bar.accent : bar.dividerStrong
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 8
                                                    spacing: 6
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.label
                                                        color: bar.subtext
                                                        font.pixelSize: 11
                                                        font.family: bar.fontFamily
                                                        elide: Text.ElideRight
                                                    }
                                                    Rectangle {
                                                        Layout.preferredWidth: 24
                                                        Layout.preferredHeight: 18
                                                        radius: 4
                                                        color: {
                                                            void root.colorsTick
                                                            return root.themeColorFor(modelData.key)
                                                        }
                                                        border.width: 1
                                                        border.color: Qt.rgba(1, 1, 1, 0.25)
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (root.colorsPickerKey === modelData.key)
                                                                    root.closeColorPicker()
                                                                else
                                                                    root.openColorPicker(modelData.key)
                                                            }
                                                        }
                                                    }
                                                    Text {
                                                        text: {
                                                            void root.colorsTick
                                                            return root.themeHexFor(modelData.key)
                                                        }
                                                        color: bar.subtext
                                                        font.pixelSize: 10
                                                        font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                        Layout.preferredWidth: 56
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }
                                        }

                                        // ── Special / Effects (collapsible) ──
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 28
                                            Layout.topMargin: 4
                                            radius: root.chipR
                                            color: secFxMa.containsMouse ? bar.glassHover : "transparent"
                                            border.width: 1
                                            border.color: bar.dividerStrong
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 6
                                                Text {
                                                    text: root.themeSecEffectsOpen ? "▾" : "▸"
                                                    color: bar.text
                                                    font.pixelSize: 12
                                                    font.family: bar.fontFamily
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: "Special / Effects"
                                                    color: bar.text
                                                    font.pixelSize: 12
                                                    font.bold: true
                                                    font.family: bar.fontFamily
                                                }
                                            }
                                            MouseArea {
                                                id: secFxMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.toggleThemeSection("effects")
                                            }
                                        }
                                        Repeater {
                                            model: {
                                                void root.colorsTick
                                                return root.themeSecEffectsOpen ? root.themeEffectsRows() : []
                                            }
                                            delegate: Rectangle {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 34
                                                radius: root.chipR
                                                color: Qt.rgba(0.08, 0.10, 0.14, 0.55)
                                                border.width: 1
                                                border.color: root.colorsPickerKey === modelData.key ? bar.accent : bar.dividerStrong
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 8
                                                    spacing: 6
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.label
                                                        color: bar.subtext
                                                        font.pixelSize: 11
                                                        font.family: bar.fontFamily
                                                        elide: Text.ElideRight
                                                    }
                                                    Rectangle {
                                                        Layout.preferredWidth: 24
                                                        Layout.preferredHeight: 18
                                                        radius: 4
                                                        color: {
                                                            void root.colorsTick
                                                            return root.themeColorFor(modelData.key)
                                                        }
                                                        border.width: 1
                                                        border.color: Qt.rgba(1, 1, 1, 0.25)
                                                        MouseArea {
                                                            anchors.fill: parent
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (root.colorsPickerKey === modelData.key)
                                                                    root.closeColorPicker()
                                                                else
                                                                    root.openColorPicker(modelData.key)
                                                            }
                                                        }
                                                    }
                                                    Text {
                                                        text: {
                                                            void root.colorsTick
                                                            return root.themeHexFor(modelData.key)
                                                        }
                                                        color: bar.subtext
                                                        font.pixelSize: 10
                                                        font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                        Layout.preferredWidth: 56
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }
                                        }

                                    } // themingLeftCol
                                    } // themingLeftFlick

                                    // ════ RIGHT — Opacity OR color picker ════
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.fillHeight: true
                                        Layout.alignment: Qt.AlignTop
                                        spacing: 6

                                        Text {
                                            text: root.themePickerOpenOnRight()
                                                  ? ("Picker · " + root.themeLabelForKey(root.colorsPickerKey))
                                                  : "Opacity"
                                            color: bar.text
                                            font.pixelSize: 12
                                            font.bold: true
                                            font.family: bar.fontFamily
                                        }

                                        // Opacity sliders
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            visible: !root.themePickerOpenOnRight()

                                            Repeater {
                                                model: {
                                                    void root.colorsTick
                                                    return root.themeOpacityRows()
                                                }
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 34
                                                    radius: root.chipR
                                                    color: Qt.rgba(0.08, 0.10, 0.14, 0.55)
                                                    border.width: 1
                                                    border.color: bar.dividerStrong
                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 8
                                                        anchors.rightMargin: 8
                                                        spacing: 6
                                                        Text {
                                                            text: modelData.label
                                                            color: bar.subtext
                                                            font.pixelSize: 11
                                                            font.family: bar.fontFamily
                                                            wrapMode: Text.NoWrap
                                                            // No width cap — full labels (e.g. "Widget / pill fill")
                                                            Layout.preferredWidth: implicitWidth
                                                            Layout.maximumWidth: 160
                                                        }
                                                        Slider {
                                                            Layout.fillWidth: true
                                                            from: 0
                                                            to: 100
                                                            stepSize: 1
                                                            value: {
                                                                void root.colorsTick
                                                                return root.themeAlphaPct(modelData.key)
                                                            }
                                                            onMoved: root.setThemeAlphaPct(modelData.key, value)
                                                        }
                                                        Text {
                                                            text: {
                                                                void root.colorsTick
                                                                return root.themeAlphaPct(modelData.key) + "%"
                                                            }
                                                            color: bar.subtext
                                                            font.pixelSize: 11
                                                            font.family: bar.fontFamily
                                                            Layout.preferredWidth: 36
                                                            horizontalAlignment: Text.AlignRight
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Color picker — fills remaining height; bottom chrome always reserved
                                        ColorPickerPanel {
                                            id: colorsPickerRight
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            Layout.minimumHeight: 220
                                            visible: root.themePickerOpenOnRight()
                                            title: root.themeLabelForKey(root.colorsPickerKey)
                                            showOpacity: root.themeKeyHasOpacity(root.colorsPickerKey)
                                            panelBg: bar.glassPopupBg
                                            panelBorder: bar.glassPopupBorder
                                            labelColor: bar.text
                                            fieldBg: root.optFieldBg
                                            accentColor: bar.accent
                                            fontFamily: bar.fontFamily
                                            onVisibleChanged: {
                                                if (visible && root.colorsPickerKey.length)
                                                    colorsPickerRight.loadFromColor(root.themeColorFor(root.colorsPickerKey))
                                            }
                                            Connections {
                                                target: root
                                                function onColorsPickerKeyChanged() {
                                                    if (root.themePickerOpenOnRight())
                                                        colorsPickerRight.loadFromColor(root.themeColorFor(root.colorsPickerKey))
                                                }
                                            }
                                            onColorEdited: (c) => root.applyPickedColor(c)
                                            onAccepted: root.closeColorPicker()
                                        }
                                    }
                                }

                                // ════════ THRESHOLDS tab (volume + sys stats) ════════
                                // Left: threshold controls · Right: color picker (no scroll to bottom)
                                RowLayout {
                                    id: thresholdsRow
                                    visible: root.colorsTab === "thresholds"
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignTop
                                    Layout.preferredHeight: {
                                        void root.colorsTick
                                        if (root.thresholdsPickerOpen())
                                            return Math.max(280, themesBodyFlick.height)
                                        return -1
                                    }
                                    spacing: 10

                                    // ════ LEFT — volume + sys stats controls (scroll when picker open) ════
                                    Flickable {
                                        id: thresholdsLeftFlick
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.fillHeight: root.thresholdsPickerOpen()
                                        Layout.preferredHeight: root.thresholdsPickerOpen()
                                                                ? -1
                                                                : thresholdsLeftCol.implicitHeight
                                        Layout.alignment: Qt.AlignTop
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds
                                        flickableDirection: Flickable.VerticalFlick
                                        contentWidth: width
                                        contentHeight: thresholdsLeftCol.implicitHeight
                                        interactive: contentHeight > height + 4
                                        ScrollBar.vertical: ScrollBar {
                                            policy: thresholdsLeftFlick.contentHeight > thresholdsLeftFlick.height + 4
                                                    ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                            width: 6
                                            contentItem: Rectangle {
                                                implicitWidth: 4
                                                radius: 2
                                                color: bar.accent
                                                opacity: 0.45
                                            }
                                        }

                                    ColumnLayout {
                                        id: thresholdsLeftCol
                                        width: thresholdsLeftFlick.width - 8
                                        spacing: 10

                                    // ── Output volume (speaker) ──
                                    Text {
                                        text: "Output volume"
                                        color: bar.text
                                        font.pixelSize: 13
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        text: "Speaker / output bars on the status bar and in Audio panels."
                                        color: bar.subtext
                                        font.pixelSize: (bar.popupHintSize !== undefined ? bar.popupHintSize : 11) + 1
                                        font.family: bar.fontFamily
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Repeater {
                                            model: [
                                                { key: "audioUtilThreshold1", label: "Low ≤" },
                                                { key: "audioUtilThreshold2", label: "Mid ≤" },
                                                { key: "audioUtilThreshold3", label: "High ≤" }
                                            ]
                                            delegate: Rectangle {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 36
                                                radius: root.chipR
                                                color: Qt.rgba(0.08, 0.10, 0.14, 0.55)
                                                border.width: 1
                                                border.color: bar.dividerStrong
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 6
                                                    spacing: 4
                                                    Text {
                                                        text: modelData.label
                                                        color: bar.text
                                                        font.pixelSize: 12
                                                        font.family: bar.fontFamily
                                                    }
                                                    TextInput {
                                                        Layout.fillWidth: true
                                                        horizontalAlignment: Text.AlignRight
                                                        color: bar.text
                                                        font.pixelSize: 13
                                                        font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                        selectByMouse: true
                                                        validator: IntValidator { bottom: 1; top: 99 }
                                                        text: {
                                                            void root.colorsTick
                                                            return "" + root.themeNumberFor(modelData.key)
                                                        }
                                                        onEditingFinished: {
                                                            const n = parseInt(text, 10)
                                                            if (!isNaN(n))
                                                                root.setThemeNumberValue(modelData.key, n)
                                                            root.colorsTick++
                                                        }
                                                    }
                                                    Text {
                                                        text: "%"
                                                        color: bar.subtext
                                                        font.pixelSize: 12
                                                        font.family: bar.fontFamily
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Repeater {
                                            model: {
                                                void root.colorsTick
                                                return root.volumeTierRows()
                                            }
                                            delegate: Rectangle {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 42
                                                radius: root.chipR
                                                color: Qt.rgba(0.08, 0.10, 0.14, 0.55)
                                                border.width: 1
                                                border.color: root.colorsPickerKey === modelData.key ? bar.accent : bar.dividerStrong
                                                ColumnLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 6
                                                    spacing: 2
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.label
                                                        color: bar.subtext
                                                        font.pixelSize: 11
                                                        font.family: bar.fontFamily
                                                        elide: Text.ElideRight
                                                    }
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 4
                                                        Rectangle {
                                                            Layout.preferredWidth: 22
                                                            Layout.preferredHeight: 14
                                                            radius: 3
                                                            color: {
                                                                void root.colorsTick
                                                                return root.themeColorFor(modelData.key)
                                                            }
                                                            border.width: 1
                                                            border.color: Qt.rgba(1, 1, 1, 0.25)
                                                            MouseArea {
                                                                anchors.fill: parent
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    if (root.colorsPickerKey === modelData.key)
                                                                        root.closeColorPicker()
                                                                    else
                                                                        root.openColorPicker(modelData.key)
                                                                }
                                                            }
                                                        }
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: {
                                                                void root.colorsTick
                                                                return root.themeHexFor(modelData.key)
                                                            }
                                                            color: bar.subtext
                                                            font.pixelSize: 10
                                                            font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                            elide: Text.ElideRight
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // ── Input volume (microphone) ──
                                    Text {
                                        text: "Input volume"
                                        color: bar.text
                                        font.pixelSize: 13
                                        font.bold: true
                                        font.family: bar.fontFamily
                                        Layout.topMargin: 6
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        text: "Microphone / input bars on the status bar and in Audio panels."
                                        color: bar.subtext
                                        font.pixelSize: (bar.popupHintSize !== undefined ? bar.popupHintSize : 11) + 1
                                        font.family: bar.fontFamily
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Repeater {
                                            model: [
                                                { key: "audioMicUtilThreshold1", label: "Low ≤" },
                                                { key: "audioMicUtilThreshold2", label: "Mid ≤" },
                                                { key: "audioMicUtilThreshold3", label: "High ≤" }
                                            ]
                                            delegate: Rectangle {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 36
                                                radius: root.chipR
                                                color: Qt.rgba(0.08, 0.10, 0.14, 0.55)
                                                border.width: 1
                                                border.color: bar.dividerStrong
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 6
                                                    spacing: 4
                                                    Text {
                                                        text: modelData.label
                                                        color: bar.text
                                                        font.pixelSize: 12
                                                        font.family: bar.fontFamily
                                                    }
                                                    TextInput {
                                                        Layout.fillWidth: true
                                                        horizontalAlignment: Text.AlignRight
                                                        color: bar.text
                                                        font.pixelSize: 13
                                                        font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                        selectByMouse: true
                                                        validator: IntValidator { bottom: 1; top: 99 }
                                                        text: {
                                                            void root.colorsTick
                                                            return "" + root.themeNumberFor(modelData.key)
                                                        }
                                                        onEditingFinished: {
                                                            const n = parseInt(text, 10)
                                                            if (!isNaN(n))
                                                                root.setThemeNumberValue(modelData.key, n)
                                                            root.colorsTick++
                                                        }
                                                    }
                                                    Text {
                                                        text: "%"
                                                        color: bar.subtext
                                                        font.pixelSize: 12
                                                        font.family: bar.fontFamily
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Repeater {
                                            model: {
                                                void root.colorsTick
                                                return root.micVolumeTierRows()
                                            }
                                            delegate: Rectangle {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 42
                                                radius: root.chipR
                                                color: Qt.rgba(0.08, 0.10, 0.14, 0.55)
                                                border.width: 1
                                                border.color: root.colorsPickerKey === modelData.key ? bar.accent : bar.dividerStrong
                                                ColumnLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 6
                                                    spacing: 2
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.label
                                                        color: bar.subtext
                                                        font.pixelSize: 11
                                                        font.family: bar.fontFamily
                                                        elide: Text.ElideRight
                                                    }
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 4
                                                        Rectangle {
                                                            Layout.preferredWidth: 22
                                                            Layout.preferredHeight: 14
                                                            radius: 3
                                                            color: {
                                                                void root.colorsTick
                                                                return root.themeColorFor(modelData.key)
                                                            }
                                                            border.width: 1
                                                            border.color: Qt.rgba(1, 1, 1, 0.25)
                                                            MouseArea {
                                                                anchors.fill: parent
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    if (root.colorsPickerKey === modelData.key)
                                                                        root.closeColorPicker()
                                                                    else
                                                                        root.openColorPicker(modelData.key)
                                                                }
                                                            }
                                                        }
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: {
                                                                void root.colorsTick
                                                                return root.themeHexFor(modelData.key)
                                                            }
                                                            color: bar.subtext
                                                            font.pixelSize: 10
                                                            font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                            elide: Text.ElideRight
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // ── Sys Stats (CPU / Memory / GPU util bars) ──
                                    Text {
                                        text: "Sys Stats load"
                                        color: bar.text
                                        font.pixelSize: 13
                                        font.bold: true
                                        font.family: bar.fontFamily
                                        Layout.topMargin: 6
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        text: "Utilization bar and % colors for CPU, Memory, and GPU on the Sys Stats pill."
                                        color: bar.subtext
                                        font.pixelSize: (bar.popupHintSize !== undefined ? bar.popupHintSize : 11) + 1
                                        font.family: bar.fontFamily
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Repeater {
                                            model: [
                                                { key: "statUtilThreshold1", label: "Low ≤" },
                                                { key: "statUtilThreshold2", label: "Mid ≤" },
                                                { key: "statUtilThreshold3", label: "High ≤" }
                                            ]
                                            delegate: Rectangle {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 36
                                                radius: root.chipR
                                                color: Qt.rgba(0.08, 0.10, 0.14, 0.55)
                                                border.width: 1
                                                border.color: bar.dividerStrong
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 6
                                                    spacing: 4
                                                    Text {
                                                        text: modelData.label
                                                        color: bar.text
                                                        font.pixelSize: 11
                                                        font.family: bar.fontFamily
                                                    }
                                                    TextInput {
                                                        Layout.fillWidth: true
                                                        horizontalAlignment: Text.AlignRight
                                                        color: bar.text
                                                        font.pixelSize: 12
                                                        font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                        selectByMouse: true
                                                        validator: IntValidator { bottom: 1; top: 99 }
                                                        text: {
                                                            void root.colorsTick
                                                            return "" + root.themeNumberFor(modelData.key)
                                                        }
                                                        onEditingFinished: {
                                                            const n = parseInt(text, 10)
                                                            if (!isNaN(n))
                                                                root.setThemeNumberValue(modelData.key, n)
                                                            root.colorsTick++
                                                        }
                                                    }
                                                    Text {
                                                        text: "%"
                                                        color: bar.subtext
                                                        font.pixelSize: 11
                                                        font.family: bar.fontFamily
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Repeater {
                                            model: {
                                                void root.colorsTick
                                                return root.statUtilTierRows()
                                            }
                                            delegate: Rectangle {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 40
                                                radius: root.chipR
                                                color: Qt.rgba(0.08, 0.10, 0.14, 0.55)
                                                border.width: 1
                                                border.color: root.colorsPickerKey === modelData.key ? bar.accent : bar.dividerStrong
                                                ColumnLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 6
                                                    spacing: 2
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.label
                                                        color: bar.text
                                                        font.pixelSize: 10
                                                        font.family: bar.fontFamily
                                                        elide: Text.ElideRight
                                                    }
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 4
                                                        Rectangle {
                                                            Layout.preferredWidth: 22
                                                            Layout.preferredHeight: 14
                                                            radius: 3
                                                            color: {
                                                                void root.colorsTick
                                                                return root.themeColorFor(modelData.key)
                                                            }
                                                            border.width: 1
                                                            border.color: Qt.rgba(1, 1, 1, 0.25)
                                                            MouseArea {
                                                                anchors.fill: parent
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    if (root.colorsPickerKey === modelData.key)
                                                                        root.closeColorPicker()
                                                                    else
                                                                        root.openColorPicker(modelData.key)
                                                                }
                                                            }
                                                        }
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: {
                                                                void root.colorsTick
                                                                return root.themeHexFor(modelData.key)
                                                            }
                                                            color: bar.subtext
                                                            font.pixelSize: 9
                                                            font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                            elide: Text.ElideRight
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // ── Sys Stats temperature labels (CPU / GPU) ──
                                    Text {
                                        text: "Sys Stats temperature"
                                        color: bar.text
                                        font.pixelSize: 12
                                        font.bold: true
                                        font.family: bar.fontFamily
                                        Layout.topMargin: 4
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        text: "CPU/GPU temperature label colors and °C cutoffs (Memory uses secondary text for used GiB)."
                                        color: bar.subtext
                                        font.pixelSize: bar.popupHintSize
                                        font.family: bar.fontFamily
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Repeater {
                                            model: [
                                                { key: "statTempWarmAt", label: "Warm ≥", unit: "°C" },
                                                { key: "statTempHotAt", label: "Hot ≥", unit: "°C" }
                                            ]
                                            delegate: Rectangle {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 36
                                                radius: root.chipR
                                                color: Qt.rgba(0.08, 0.10, 0.14, 0.55)
                                                border.width: 1
                                                border.color: bar.dividerStrong
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 8
                                                    anchors.rightMargin: 6
                                                    spacing: 4
                                                    Text {
                                                        text: modelData.label
                                                        color: bar.text
                                                        font.pixelSize: 11
                                                        font.family: bar.fontFamily
                                                    }
                                                    TextInput {
                                                        Layout.fillWidth: true
                                                        horizontalAlignment: Text.AlignRight
                                                        color: bar.text
                                                        font.pixelSize: 12
                                                        font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                        selectByMouse: true
                                                        validator: IntValidator { bottom: 1; top: 150 }
                                                        text: {
                                                            void root.colorsTick
                                                            return "" + root.themeNumberFor(modelData.key)
                                                        }
                                                        onEditingFinished: {
                                                            const n = parseInt(text, 10)
                                                            if (!isNaN(n))
                                                                root.setThemeNumberValue(modelData.key, n)
                                                            root.colorsTick++
                                                        }
                                                    }
                                                    Text {
                                                        text: modelData.unit
                                                        color: bar.subtext
                                                        font.pixelSize: 11
                                                        font.family: bar.fontFamily
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Repeater {
                                            model: {
                                                void root.colorsTick
                                                return root.statTempRows()
                                            }
                                            delegate: Rectangle {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 40
                                                radius: root.chipR
                                                color: Qt.rgba(0.08, 0.10, 0.14, 0.55)
                                                border.width: 1
                                                border.color: root.colorsPickerKey === modelData.key ? bar.accent : bar.dividerStrong
                                                ColumnLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: 6
                                                    spacing: 2
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.label
                                                        color: bar.text
                                                        font.pixelSize: 10
                                                        font.family: bar.fontFamily
                                                        elide: Text.ElideRight
                                                    }
                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: 4
                                                        Rectangle {
                                                            Layout.preferredWidth: 22
                                                            Layout.preferredHeight: 14
                                                            radius: 3
                                                            color: {
                                                                void root.colorsTick
                                                                return root.themeColorFor(modelData.key)
                                                            }
                                                            border.width: 1
                                                            border.color: Qt.rgba(1, 1, 1, 0.25)
                                                            MouseArea {
                                                                anchors.fill: parent
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    if (root.colorsPickerKey === modelData.key)
                                                                        root.closeColorPicker()
                                                                    else
                                                                        root.openColorPicker(modelData.key)
                                                                }
                                                            }
                                                        }
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: {
                                                                void root.colorsTick
                                                                return root.themeHexFor(modelData.key)
                                                            }
                                                            color: bar.subtext
                                                            font.pixelSize: 9
                                                            font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                            elide: Text.ElideRight
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        } // temp color swatches RowLayout
                                    } // thresholdsLeftCol
                                    } // thresholdsLeftFlick

                                    // ════ RIGHT — color picker ════
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        Layout.fillHeight: true
                                        Layout.alignment: Qt.AlignTop
                                        spacing: 6

                                        Text {
                                            text: root.thresholdsPickerOpen()
                                                  ? ("Picker · " + root.themeLabelForKey(root.colorsPickerKey))
                                                  : "Picker"
                                            color: bar.text
                                            font.pixelSize: 12
                                            font.bold: true
                                            font.family: bar.fontFamily
                                        }
                                        Text {
                                            visible: !root.thresholdsPickerOpen()
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                            text: "Click a volume or Sys Stats color swatch to edit it here."
                                            color: bar.subtext
                                            font.pixelSize: bar.popupHintSize
                                            font.family: bar.fontFamily
                                        }
                                        ColorPickerPanel {
                                            id: colorsPickerThresholds
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            Layout.minimumHeight: 220
                                            visible: root.thresholdsPickerOpen()
                                            title: root.themeLabelForKey(root.colorsPickerKey)
                                            showOpacity: root.themeKeyHasOpacity(root.colorsPickerKey)
                                            panelBg: bar.glassPopupBg
                                            panelBorder: bar.glassPopupBorder
                                            labelColor: bar.text
                                            fieldBg: root.optFieldBg
                                            accentColor: bar.accent
                                            fontFamily: bar.fontFamily
                                            onVisibleChanged: {
                                                if (visible && root.colorsPickerKey.length)
                                                    colorsPickerThresholds.loadFromColor(root.themeColorFor(root.colorsPickerKey))
                                            }
                                            Connections {
                                                target: root
                                                function onColorsPickerKeyChanged() {
                                                    if (root.thresholdsPickerOpen())
                                                        colorsPickerThresholds.loadFromColor(root.themeColorFor(root.colorsPickerKey))
                                                }
                                            }
                                            onColorEdited: (c) => root.applyPickedColor(c)
                                            onAccepted: root.closeColorPicker()
                                        }
                                    } // thresholds right column
                                } // thresholdsRow

                                // ════════ FONTS tab ════════
                                ColumnLayout {
                                    visible: root.colorsTab === "fonts"
                                    Layout.fillWidth: true
                                    spacing: 10

                                    Text {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        text: "Font on the left · size on the right. UI keeps a Nerd Font first for icons. Role fonts inherit UI when unset. Saves with the theme."
                                        color: bar.subtext
                                        font.pixelSize: bar.popupHintSize
                                        font.family: (bar.fontSecondaryResolved !== undefined) ? bar.fontSecondaryResolved : bar.fontFamily
                                    }

                                    // ── header row labels ──
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        Text {
                                            Layout.fillWidth: true
                                            text: "Typeface"
                                            color: bar.subtext
                                            font.pixelSize: 10
                                            font.bold: true
                                            font.family: bar.fontFamily
                                        }
                                        Text {
                                            Layout.preferredWidth: root.fontSizeChipWidth()
                                            text: "Size"
                                            color: bar.subtext
                                            font.pixelSize: 10
                                            font.bold: true
                                            font.family: bar.fontFamily
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                    }

                                    // ════════ UI font ════════
                                    Text {
                                        text: "UI font"
                                        color: bar.text
                                        font.pixelSize: 12
                                        font.bold: true
                                        font.family: (bar.fontMainResolved !== undefined) ? bar.fontMainResolved : bar.fontFamily
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        ComboBox {
                                            id: uiFontCombo
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 36
                                            Layout.minimumWidth: 120
                                            model: { void root.colorsTick; return root.systemFontFamilies }
                                            currentIndex: {
                                                void root.colorsTick
                                                void root.systemFontFamilies
                                                return root.fontIndexFor(root.currentUiFontName())
                                            }
                                            onActivated: function(index) { root.applyUiFontFromCombo(index) }
                                            contentItem: Text {
                                                leftPadding: 10
                                                rightPadding: uiFontCombo.indicator.width + 12
                                                text: {
                                                    void root.colorsTick
                                                    const n = root.currentUiFontName()
                                                    return n.length ? n : uiFontCombo.displayText
                                                }
                                                font.pixelSize: 13
                                                font.family: {
                                                    void root.colorsTick
                                                    const n = root.currentUiFontName()
                                                    return n.length ? n : bar.fontFamily
                                                }
                                                color: bar.text
                                                verticalAlignment: Text.AlignVCenter
                                                elide: Text.ElideRight
                                            }
                                            background: Rectangle {
                                                radius: 6
                                                color: root.optFieldBg
                                                border.width: 1
                                                border.color: uiFontCombo.popup.visible ? bar.accent : bar.pillBorder
                                            }
                                            indicator: Text {
                                                x: uiFontCombo.width - width - 10
                                                y: (uiFontCombo.height - height) / 2
                                                text: uiFontCombo.popup.visible ? "▴" : "▾"
                                                color: bar.subtext
                                                font.pixelSize: 11
                                            }
                                            popup: Popup {
                                                y: uiFontCombo.height + 2
                                                width: uiFontCombo.width
                                                implicitHeight: Math.min(300, contentItem.implicitHeight + 4)
                                                padding: 2
                                                contentItem: ListView {
                                                    clip: true
                                                    implicitHeight: contentHeight
                                                    model: uiFontCombo.popup.visible ? uiFontCombo.delegateModel : null
                                                    currentIndex: uiFontCombo.highlightedIndex
                                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                                                }
                                                background: Rectangle {
                                                    radius: 8
                                                    color: bar.glassPopupBg !== undefined ? bar.glassPopupBg : Qt.rgba(0.06, 0.08, 0.12, 0.96)
                                                    border.width: 1
                                                    border.color: bar.glassPopupBorder !== undefined ? bar.glassPopupBorder : bar.pillBorder
                                                }
                                            }
                                            delegate: ItemDelegate {
                                                width: uiFontCombo.width
                                                height: 32
                                                required property int index
                                                required property string modelData
                                                highlighted: uiFontCombo.highlightedIndex === index
                                                contentItem: Text {
                                                    text: modelData + "  ·  Aa Bb 123"
                                                    color: bar.text
                                                    font.family: modelData
                                                    font.pixelSize: 13
                                                    elide: Text.ElideRight
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                                background: Rectangle {
                                                    color: parent.highlighted
                                                           ? (bar.controlActiveBg !== undefined ? bar.controlActiveBg : Qt.rgba(0, 0.7, 0.75, 0.35))
                                                           : "transparent"
                                                    radius: 4
                                                }
                                            }
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: root.fontSizeChipWidth()
                                            Layout.maximumWidth: root.fontSizeChipWidth()
                                            Layout.preferredHeight: 36
                                            radius: root.chipR
                                            color: Qt.rgba(0.08, 0.10, 0.14, 0.55)
                                            border.width: 1
                                            border.color: bar.dividerStrong
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 4
                                                Slider {
                                                    Layout.fillWidth: true
                                                    from: 70; to: 150; stepSize: 1
                                                    value: root.currentRoleFontScalePct("ui")
                                                    onPressedChanged: { if (pressed) root.pushThemeUndo() }
                                                    onMoved: root.applyFontScalePct(value)
                                                }
                                                Text {
                                                    text: root.currentRoleFontScalePct("ui") + "%"
                                                    color: bar.subtext
                                                    font.pixelSize: 11
                                                    font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                    Layout.preferredWidth: 40
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }
                                        }
                                    }

                                    // ════════ Monospace ════════
                                    Text {
                                        text: "Monospace font"
                                        color: bar.text
                                        font.pixelSize: 12
                                        font.bold: true
                                        font.family: (bar.fontMainResolved !== undefined) ? bar.fontMainResolved : bar.fontFamily
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        ComboBox {
                                            id: monoFontCombo
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 36
                                            Layout.minimumWidth: 120
                                            model: { void root.colorsTick; return root.systemFontFamilies }
                                            currentIndex: {
                                                void root.colorsTick
                                                void root.systemFontFamilies
                                                return root.fontIndexFor(root.currentMonoFontName())
                                            }
                                            onActivated: function(index) { root.applyMonoFontFromCombo(index) }
                                            contentItem: Text {
                                                leftPadding: 10
                                                rightPadding: monoFontCombo.indicator.width + 12
                                                text: {
                                                    void root.colorsTick
                                                    const n = root.currentMonoFontName()
                                                    return n.length ? n : monoFontCombo.displayText
                                                }
                                                font.pixelSize: 13
                                                font.family: {
                                                    void root.colorsTick
                                                    const n = root.currentMonoFontName()
                                                    return n.length ? n : (bar.fontMono || bar.fontFamily)
                                                }
                                                color: bar.text
                                                verticalAlignment: Text.AlignVCenter
                                                elide: Text.ElideRight
                                            }
                                            background: Rectangle {
                                                radius: 6
                                                color: root.optFieldBg
                                                border.width: 1
                                                border.color: monoFontCombo.popup.visible ? bar.accent : bar.pillBorder
                                            }
                                            indicator: Text {
                                                x: monoFontCombo.width - width - 10
                                                y: (monoFontCombo.height - height) / 2
                                                text: monoFontCombo.popup.visible ? "▴" : "▾"
                                                color: bar.subtext
                                                font.pixelSize: 11
                                            }
                                            popup: Popup {
                                                y: monoFontCombo.height + 2
                                                width: monoFontCombo.width
                                                implicitHeight: Math.min(300, contentItem.implicitHeight + 4)
                                                padding: 2
                                                contentItem: ListView {
                                                    clip: true
                                                    implicitHeight: contentHeight
                                                    model: monoFontCombo.popup.visible ? monoFontCombo.delegateModel : null
                                                    currentIndex: monoFontCombo.highlightedIndex
                                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                                                }
                                                background: Rectangle {
                                                    radius: 8
                                                    color: bar.glassPopupBg !== undefined ? bar.glassPopupBg : Qt.rgba(0.06, 0.08, 0.12, 0.96)
                                                    border.width: 1
                                                    border.color: bar.glassPopupBorder !== undefined ? bar.glassPopupBorder : bar.pillBorder
                                                }
                                            }
                                            delegate: ItemDelegate {
                                                width: monoFontCombo.width
                                                height: 32
                                                required property int index
                                                required property string modelData
                                                highlighted: monoFontCombo.highlightedIndex === index
                                                contentItem: Text {
                                                    text: modelData + "  ·  0xFF {} []"
                                                    color: bar.text
                                                    font.family: modelData
                                                    font.pixelSize: 13
                                                    elide: Text.ElideRight
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                                background: Rectangle {
                                                    color: parent.highlighted
                                                           ? (bar.controlActiveBg !== undefined ? bar.controlActiveBg : Qt.rgba(0, 0.7, 0.75, 0.35))
                                                           : "transparent"
                                                    radius: 4
                                                }
                                            }
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: root.fontSizeChipWidth()
                                            Layout.maximumWidth: root.fontSizeChipWidth()
                                            Layout.preferredHeight: 36
                                            radius: root.chipR
                                            color: Qt.rgba(0.08, 0.10, 0.14, 0.55)
                                            border.width: 1
                                            border.color: bar.dividerStrong
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 4
                                                Slider {
                                                    Layout.fillWidth: true
                                                    from: 70; to: 150; stepSize: 1
                                                    value: root.currentRoleFontScalePct("mono")
                                                    onPressedChanged: { if (pressed) root.pushThemeUndo() }
                                                    onMoved: root.applyRoleFontScalePct("mono", value)
                                                }
                                                Text {
                                                    text: root.currentRoleFontScalePct("mono") + "%"
                                                    color: bar.subtext
                                                    font.pixelSize: 11
                                                    font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                    Layout.preferredWidth: 40
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }
                                        }
                                    }

                                    // ── role divider ──
                                    Text {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 4
                                        wrapMode: Text.WordWrap
                                        text: "Menu & bar roles (optional — inherit UI when unset)"
                                        color: bar.subtext
                                        font.pixelSize: 10
                                        font.family: (bar.fontSecondaryResolved !== undefined) ? bar.fontSecondaryResolved : bar.fontFamily
                                    }

                                    // ════════ Main ════════
                                    Text {
                                        text: "Main text (menu headers)"
                                        color: bar.text
                                        font.pixelSize: 12
                                        font.bold: true
                                        font.family: (bar.fontMainResolved !== undefined) ? bar.fontMainResolved : bar.fontFamily
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        ComboBox {
                                            id: mainFontCombo
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 34
                                            Layout.minimumWidth: 120
                                            model: { void root.colorsTick; return root.systemFontFamilies }
                                            currentIndex: {
                                                void root.colorsTick
                                                void root.systemFontFamilies
                                                return root.fontIndexFor(root.currentRoleFontName("main"))
                                            }
                                            onActivated: function(index) { root.applyRoleFontFromCombo("main", index) }
                                            contentItem: Text {
                                                leftPadding: 10
                                                rightPadding: mainFontCombo.indicator.width + 12
                                                text: {
                                                    void root.colorsTick
                                                    const n = root.currentRoleFontName("main")
                                                    return n.length ? n : mainFontCombo.displayText
                                                }
                                                font.pixelSize: 12
                                                font.family: {
                                                    void root.colorsTick
                                                    const n = root.currentRoleFontName("main")
                                                    return n.length ? n : bar.fontFamily
                                                }
                                                color: bar.text
                                                verticalAlignment: Text.AlignVCenter
                                                elide: Text.ElideRight
                                            }
                                            background: Rectangle {
                                                radius: 6
                                                color: root.optFieldBg
                                                border.width: 1
                                                border.color: mainFontCombo.popup.visible ? bar.accent : bar.pillBorder
                                            }
                                            indicator: Text {
                                                x: mainFontCombo.width - width - 10
                                                y: (mainFontCombo.height - height) / 2
                                                text: mainFontCombo.popup.visible ? "▴" : "▾"
                                                color: bar.subtext
                                                font.pixelSize: 11
                                            }
                                            popup: Popup {
                                                y: mainFontCombo.height + 2
                                                width: mainFontCombo.width
                                                implicitHeight: Math.min(260, contentItem.implicitHeight + 4)
                                                padding: 2
                                                contentItem: ListView {
                                                    clip: true
                                                    implicitHeight: contentHeight
                                                    model: mainFontCombo.popup.visible ? mainFontCombo.delegateModel : null
                                                    currentIndex: mainFontCombo.highlightedIndex
                                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                                                }
                                                background: Rectangle {
                                                    radius: 8
                                                    color: bar.glassPopupBg !== undefined ? bar.glassPopupBg : Qt.rgba(0.06, 0.08, 0.12, 0.96)
                                                    border.width: 1
                                                    border.color: bar.glassPopupBorder !== undefined ? bar.glassPopupBorder : bar.pillBorder
                                                }
                                            }
                                            delegate: ItemDelegate {
                                                width: mainFontCombo.width
                                                height: 30
                                                required property int index
                                                required property string modelData
                                                highlighted: mainFontCombo.highlightedIndex === index
                                                contentItem: Text {
                                                    text: modelData + "  ·  Header"
                                                    color: bar.text
                                                    font.family: modelData
                                                    font.pixelSize: 12
                                                    elide: Text.ElideRight
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                                background: Rectangle {
                                                    color: parent.highlighted
                                                           ? (bar.controlActiveBg !== undefined ? bar.controlActiveBg : Qt.rgba(0, 0.7, 0.75, 0.35))
                                                           : "transparent"
                                                    radius: 4
                                                }
                                            }
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: root.fontSizeChipWidth()
                                            Layout.maximumWidth: root.fontSizeChipWidth()
                                            Layout.preferredHeight: 34
                                            radius: root.chipR
                                            color: Qt.rgba(0.08, 0.10, 0.14, 0.55)
                                            border.width: 1
                                            border.color: bar.dividerStrong
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 4
                                                Slider {
                                                    Layout.fillWidth: true
                                                    from: 70; to: 150; stepSize: 1
                                                    value: root.currentRoleFontScalePct("main")
                                                    onPressedChanged: { if (pressed) root.pushThemeUndo() }
                                                    onMoved: root.applyRoleFontScalePct("main", value)
                                                }
                                                Text {
                                                    text: root.currentRoleFontScalePct("main") + "%"
                                                    color: bar.subtext
                                                    font.pixelSize: 11
                                                    font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                    Layout.preferredWidth: 40
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }
                                        }
                                    }

                                    // ════════ Secondary ════════
                                    Text {
                                        text: "Secondary text (menu body)"
                                        color: bar.text
                                        font.pixelSize: 12
                                        font.bold: true
                                        font.family: (bar.fontMainResolved !== undefined) ? bar.fontMainResolved : bar.fontFamily
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        ComboBox {
                                            id: secondaryFontCombo
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 34
                                            Layout.minimumWidth: 120
                                            model: { void root.colorsTick; return root.systemFontFamilies }
                                            currentIndex: {
                                                void root.colorsTick
                                                void root.systemFontFamilies
                                                return root.fontIndexFor(root.currentRoleFontName("secondary"))
                                            }
                                            onActivated: function(index) { root.applyRoleFontFromCombo("secondary", index) }
                                            contentItem: Text {
                                                leftPadding: 10
                                                rightPadding: secondaryFontCombo.indicator.width + 12
                                                text: {
                                                    void root.colorsTick
                                                    const n = root.currentRoleFontName("secondary")
                                                    return n.length ? n : secondaryFontCombo.displayText
                                                }
                                                font.pixelSize: 12
                                                font.family: {
                                                    void root.colorsTick
                                                    const n = root.currentRoleFontName("secondary")
                                                    return n.length ? n : bar.fontFamily
                                                }
                                                color: bar.subtext
                                                verticalAlignment: Text.AlignVCenter
                                                elide: Text.ElideRight
                                            }
                                            background: Rectangle {
                                                radius: 6
                                                color: root.optFieldBg
                                                border.width: 1
                                                border.color: secondaryFontCombo.popup.visible ? bar.accent : bar.pillBorder
                                            }
                                            indicator: Text {
                                                x: secondaryFontCombo.width - width - 10
                                                y: (secondaryFontCombo.height - height) / 2
                                                text: secondaryFontCombo.popup.visible ? "▴" : "▾"
                                                color: bar.subtext
                                                font.pixelSize: 11
                                            }
                                            popup: Popup {
                                                y: secondaryFontCombo.height + 2
                                                width: secondaryFontCombo.width
                                                implicitHeight: Math.min(260, contentItem.implicitHeight + 4)
                                                padding: 2
                                                contentItem: ListView {
                                                    clip: true
                                                    implicitHeight: contentHeight
                                                    model: secondaryFontCombo.popup.visible ? secondaryFontCombo.delegateModel : null
                                                    currentIndex: secondaryFontCombo.highlightedIndex
                                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                                                }
                                                background: Rectangle {
                                                    radius: 8
                                                    color: bar.glassPopupBg !== undefined ? bar.glassPopupBg : Qt.rgba(0.06, 0.08, 0.12, 0.96)
                                                    border.width: 1
                                                    border.color: bar.glassPopupBorder !== undefined ? bar.glassPopupBorder : bar.pillBorder
                                                }
                                            }
                                            delegate: ItemDelegate {
                                                width: secondaryFontCombo.width
                                                height: 30
                                                required property int index
                                                required property string modelData
                                                highlighted: secondaryFontCombo.highlightedIndex === index
                                                contentItem: Text {
                                                    text: modelData + "  ·  Body"
                                                    color: bar.subtext
                                                    font.family: modelData
                                                    font.pixelSize: 12
                                                    elide: Text.ElideRight
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                                background: Rectangle {
                                                    color: parent.highlighted
                                                           ? (bar.controlActiveBg !== undefined ? bar.controlActiveBg : Qt.rgba(0, 0.7, 0.75, 0.35))
                                                           : "transparent"
                                                    radius: 4
                                                }
                                            }
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: root.fontSizeChipWidth()
                                            Layout.maximumWidth: root.fontSizeChipWidth()
                                            Layout.preferredHeight: 34
                                            radius: root.chipR
                                            color: Qt.rgba(0.08, 0.10, 0.14, 0.55)
                                            border.width: 1
                                            border.color: bar.dividerStrong
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 4
                                                Slider {
                                                    Layout.fillWidth: true
                                                    from: 70; to: 150; stepSize: 1
                                                    value: root.currentRoleFontScalePct("secondary")
                                                    onPressedChanged: { if (pressed) root.pushThemeUndo() }
                                                    onMoved: root.applyRoleFontScalePct("secondary", value)
                                                }
                                                Text {
                                                    text: root.currentRoleFontScalePct("secondary") + "%"
                                                    color: bar.subtext
                                                    font.pixelSize: 11
                                                    font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                    Layout.preferredWidth: 40
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }
                                        }
                                    }

                                    // ════════ Bar widget ════════
                                    Text {
                                        text: "Bar widget text"
                                        color: bar.text
                                        font.pixelSize: 12
                                        font.bold: true
                                        font.family: (bar.fontMainResolved !== undefined) ? bar.fontMainResolved : bar.fontFamily
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        ComboBox {
                                            id: barFaceFontCombo
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 34
                                            Layout.minimumWidth: 120
                                            model: { void root.colorsTick; return root.systemFontFamilies }
                                            currentIndex: {
                                                void root.colorsTick
                                                void root.systemFontFamilies
                                                return root.fontIndexFor(root.currentRoleFontName("bar"))
                                            }
                                            onActivated: function(index) { root.applyRoleFontFromCombo("bar", index) }
                                            contentItem: Text {
                                                leftPadding: 10
                                                rightPadding: barFaceFontCombo.indicator.width + 12
                                                text: {
                                                    void root.colorsTick
                                                    const n = root.currentRoleFontName("bar")
                                                    return n.length ? n : barFaceFontCombo.displayText
                                                }
                                                font.pixelSize: 12
                                                font.family: {
                                                    void root.colorsTick
                                                    const n = root.currentRoleFontName("bar")
                                                    return n.length ? n : bar.fontFamily
                                                }
                                                color: (bar.barText !== undefined) ? bar.barText : bar.text
                                                verticalAlignment: Text.AlignVCenter
                                                elide: Text.ElideRight
                                            }
                                            background: Rectangle {
                                                radius: 6
                                                color: root.optFieldBg
                                                border.width: 1
                                                border.color: barFaceFontCombo.popup.visible ? bar.accent : bar.pillBorder
                                            }
                                            indicator: Text {
                                                x: barFaceFontCombo.width - width - 10
                                                y: (barFaceFontCombo.height - height) / 2
                                                text: barFaceFontCombo.popup.visible ? "▴" : "▾"
                                                color: bar.subtext
                                                font.pixelSize: 11
                                            }
                                            popup: Popup {
                                                y: barFaceFontCombo.height + 2
                                                width: barFaceFontCombo.width
                                                implicitHeight: Math.min(260, contentItem.implicitHeight + 4)
                                                padding: 2
                                                contentItem: ListView {
                                                    clip: true
                                                    implicitHeight: contentHeight
                                                    model: barFaceFontCombo.popup.visible ? barFaceFontCombo.delegateModel : null
                                                    currentIndex: barFaceFontCombo.highlightedIndex
                                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                                                }
                                                background: Rectangle {
                                                    radius: 8
                                                    color: bar.glassPopupBg !== undefined ? bar.glassPopupBg : Qt.rgba(0.06, 0.08, 0.12, 0.96)
                                                    border.width: 1
                                                    border.color: bar.glassPopupBorder !== undefined ? bar.glassPopupBorder : bar.pillBorder
                                                }
                                            }
                                            delegate: ItemDelegate {
                                                width: barFaceFontCombo.width
                                                height: 30
                                                required property int index
                                                required property string modelData
                                                highlighted: barFaceFontCombo.highlightedIndex === index
                                                contentItem: Text {
                                                    text: modelData + "  ·  12:34"
                                                    color: (bar.barText !== undefined) ? bar.barText : bar.text
                                                    font.family: modelData
                                                    font.pixelSize: 12
                                                    elide: Text.ElideRight
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                                background: Rectangle {
                                                    color: parent.highlighted
                                                           ? (bar.controlActiveBg !== undefined ? bar.controlActiveBg : Qt.rgba(0, 0.7, 0.75, 0.35))
                                                           : "transparent"
                                                    radius: 4
                                                }
                                            }
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: root.fontSizeChipWidth()
                                            Layout.maximumWidth: root.fontSizeChipWidth()
                                            Layout.preferredHeight: 34
                                            radius: root.chipR
                                            color: Qt.rgba(0.08, 0.10, 0.14, 0.55)
                                            border.width: 1
                                            border.color: bar.dividerStrong
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 4
                                                Slider {
                                                    Layout.fillWidth: true
                                                    from: 70; to: 150; stepSize: 1
                                                    value: root.currentRoleFontScalePct("bar")
                                                    onPressedChanged: { if (pressed) root.pushThemeUndo() }
                                                    onMoved: root.applyRoleFontScalePct("bar", value)
                                                }
                                                Text {
                                                    text: root.currentRoleFontScalePct("bar") + "%"
                                                    color: bar.subtext
                                                    font.pixelSize: 11
                                                    font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                    Layout.preferredWidth: 40
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }
                                        }
                                    }

                                    // ════════ Preview (all options) ════════
                                    Text {
                                        Layout.topMargin: 4
                                        text: "Preview"
                                        color: bar.text
                                        font.pixelSize: 12
                                        font.bold: true
                                        font.family: (bar.fontMainResolved !== undefined) ? bar.fontMainResolved : bar.fontFamily
                                    }
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: fontPreviewCol.implicitHeight + 18
                                        radius: root.chipR
                                        color: Qt.rgba(0.08, 0.10, 0.14, 0.55)
                                        border.width: 1
                                        border.color: bar.dividerStrong
                                        ColumnLayout {
                                            id: fontPreviewCol
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 10
                                            spacing: 8
                                            Text {
                                                Layout.fillWidth: true
                                                wrapMode: Text.WordWrap
                                                text: {
                                                    void root.colorsTick
                                                    return "UI · The quick brown fox — " + root.currentUiFontName() + " · " + root.currentRoleFontScalePct("ui") + "%"
                                                }
                                                color: bar.text
                                                font.pixelSize: bar.fontBody !== undefined ? bar.fontBody : 13
                                                font.family: bar.fontFamily
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                wrapMode: Text.WordWrap
                                                text: {
                                                    void root.colorsTick
                                                    return "Mono · const x = 0xDEAD; // " + root.currentMonoFontName() + " · " + root.currentRoleFontScalePct("mono") + "%"
                                                }
                                                color: bar.subtext
                                                font.pixelSize: bar.fontMonoFace !== undefined ? bar.fontMonoFace : 12
                                                font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                wrapMode: Text.WordWrap
                                                text: {
                                                    void root.colorsTick
                                                    return "Main · Menu headers — " + root.currentRoleFontName("main") + " · " + (bar.popupTitleSize || 16) + "px"
                                                }
                                                color: bar.text
                                                font.pixelSize: bar.popupTitleSize !== undefined ? bar.popupTitleSize : 16
                                                font.bold: true
                                                font.family: (bar.fontMainResolved !== undefined) ? bar.fontMainResolved : bar.fontFamily
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                wrapMode: Text.WordWrap
                                                text: {
                                                    void root.colorsTick
                                                    return "Secondary · Body & hints — " + root.currentRoleFontName("secondary") + " · " + (bar.fontBody || 12) + "px"
                                                }
                                                color: bar.subtext
                                                font.pixelSize: bar.fontBody !== undefined ? bar.fontBody : 12
                                                font.family: (bar.fontSecondaryResolved !== undefined) ? bar.fontSecondaryResolved : bar.fontFamily
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                wrapMode: Text.WordWrap
                                                text: {
                                                    void root.colorsTick
                                                    return "Bar · 12:34  CPU 42%  · " + root.currentRoleFontName("bar") + " · " + ((bar.fontBarFace !== undefined) ? bar.fontBarFace : 13) + "px"
                                                }
                                                color: (bar.barText !== undefined) ? bar.barText : bar.text
                                                font.pixelSize: bar.fontBarFace !== undefined ? bar.fontBarFace : 13
                                                font.bold: true
                                                font.family: (bar.fontBarResolved !== undefined) ? bar.fontBarResolved : bar.fontFamily
                                            }
                                        }
                                    }
                                }

                                // ════════ PRESETS tab ════════
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    visible: {
                                        void root.optionsTick
                                        return root.colorsTab === "presets"
                                               && bar && bar.showColorPresets !== false
                                    }

                                    // Built-in presets (cannot be removed)
                                    Text {
                                        text: "Built-in presets"
                                        color: bar.text
                                        font.pixelSize: 12
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        wrapMode: Text.WordWrap
                                        text: "Always available — these cannot be removed."
                                        color: bar.subtext
                                        font.pixelSize: 11
                                        font.family: bar.fontFamily
                                    }
                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Repeater {
                                            model: {
                                                void root.colorsTick
                                                if (bar && typeof bar.themeBuiltinList === "function")
                                                    return bar.themeBuiltinList()
                                                return []
                                            }
                                            delegate: Rectangle {
                                                required property var modelData
                                                width: Math.max(88, presetLbl.implicitWidth + 14)
                                                height: 26
                                                radius: root.chipR
                                                color: presetMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                                border.width: 1
                                                border.color: bar.pillBorder
                                                Text {
                                                    id: presetLbl
                                                    anchors.centerIn: parent
                                                    text: modelData.name || modelData.id
                                                    color: bar.subtext
                                                    font.pixelSize: 11
                                                    font.family: bar.fontFamily
                                                }
                                                MouseArea {
                                                    id: presetMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (bar && typeof bar.applyThemePreset === "function")
                                                            bar.applyThemePreset(modelData.id)
                                                        root.colorsPickerKey = ""
                                                        root.colorsTick++
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // User presets — save / apply / remove
                                    Text {
                                        text: "Your presets"
                                        color: bar.text
                                        font.pixelSize: 12
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        TextField {
                                            id: exportNameField
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 28
                                            placeholderText: "Name for new preset…"
                                            text: root.colorsExportName
                                            font.pixelSize: 12
                                            font.family: bar.fontFamily
                                            color: bar.text
                                            placeholderTextColor: bar.subtext
                                            selectedTextColor: "#000000"
                                            selectionColor: bar.accent
                                            background: Rectangle {
                                                radius: 5
                                                color: root.optFieldBg
                                                border.width: 1
                                                border.color: exportNameField.activeFocus ? bar.accent : bar.pillBorder
                                            }
                                            onTextChanged: root.colorsExportName = text
                                            Keys.onReturnPressed: {
                                                if (bar && typeof bar.saveThemePreset === "function")
                                                    bar.saveThemePreset(root.colorsExportName)
                                                else if (bar && typeof bar.exportTheme === "function")
                                                    bar.exportTheme(root.colorsExportName)
                                            }
                                        }
                                        Rectangle {
                                            Layout.preferredHeight: 28
                                            Layout.preferredWidth: savePresetLbl.implicitWidth + 14
                                            radius: root.chipR
                                            color: savePresetMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                            border.width: 1
                                            border.color: bar.pillBorder
                                            Text {
                                                id: savePresetLbl
                                                anchors.centerIn: parent
                                                text: "Save as preset"
                                                color: bar.subtext
                                                font.pixelSize: 11
                                                font.family: bar.fontFamily
                                            }
                                            MouseArea {
                                                id: savePresetMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (bar && typeof bar.saveThemePreset === "function")
                                                        bar.saveThemePreset(root.colorsExportName)
                                                    else if (bar && typeof bar.exportTheme === "function")
                                                        bar.exportTheme(root.colorsExportName)
                                                }
                                            }
                                        }
                                    }

                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        visible: {
                                            void root.colorsTick
                                            void bar.themeSavedList
                                            const list = (bar && bar.themeSavedList) ? bar.themeSavedList : []
                                            return list.length > 0
                                        }
                                        Repeater {
                                            model: {
                                                void root.colorsTick
                                                void bar.themeSavedList
                                                return (bar && bar.themeSavedList) ? bar.themeSavedList : []
                                            }
                                            delegate: Rectangle {
                                                required property var modelData
                                                readonly property string presetTarget: modelData.path || modelData.id || ""
                                                width: userPresetRow.implicitWidth + 12
                                                height: 28
                                                radius: root.chipR
                                                color: userPresetMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                                border.width: 1
                                                border.color: bar.pillBorder

                                                Row {
                                                    id: userPresetRow
                                                    anchors.centerIn: parent
                                                    spacing: 6
                                                    Text {
                                                        text: modelData.name || modelData.id
                                                        color: bar.subtext
                                                        font.pixelSize: 11
                                                        font.family: bar.fontFamily
                                                        anchors.verticalCenter: parent.verticalCenter
                                                    }
                                                    // Remove (user presets only — builtins never appear here)
                                                    Rectangle {
                                                        width: 18
                                                        height: 18
                                                        radius: 4
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        color: removePresetMa.containsMouse ? Qt.rgba(1, 0.24, 0.54, 0.35) : Qt.rgba(1, 1, 1, 0.08)
                                                        border.width: 1
                                                        border.color: Qt.rgba(1, 1, 1, 0.15)
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: "×"
                                                            color: bar.text
                                                            font.pixelSize: 12
                                                            font.bold: true
                                                        }
                                                        MouseArea {
                                                            id: removePresetMa
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (bar && typeof bar.deleteThemePreset === "function")
                                                                    bar.deleteThemePreset(presetTarget)
                                                                root.colorsTick++
                                                            }
                                                        }
                                                    }
                                                }
                                                MouseArea {
                                                    id: userPresetMa
                                                    anchors.fill: parent
                                                    anchors.rightMargin: 24
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (bar && typeof bar.importTheme === "function")
                                                            bar.importTheme(presetTarget)
                                                        root.colorsPickerKey = ""
                                                        root.colorsTick++
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        visible: {
                                            void root.colorsTick
                                            void bar.themeSavedList
                                            const list = (bar && bar.themeSavedList) ? bar.themeSavedList : []
                                            return list.length === 0
                                        }
                                        text: "No custom presets yet — save the current look with a name above."
                                        color: bar.subtext
                                        font.pixelSize: 11
                                        font.family: bar.fontFamily
                                        wrapMode: Text.WordWrap
                                    }

                                    // Optional load-from-file
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Text {
                                            text: "Load file"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        TextField {
                                            id: importPathField
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 26
                                            placeholderText: "/path/to/theme.json"
                                            text: root.colorsImportPath
                                            font.pixelSize: 11
                                            font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                            color: bar.text
                                            placeholderTextColor: bar.subtext
                                            selectedTextColor: "#000000"
                                            selectionColor: bar.accent
                                            background: Rectangle {
                                                radius: 5
                                                color: root.optFieldBg
                                                border.width: 1
                                                border.color: importPathField.activeFocus ? bar.accent : bar.pillBorder
                                            }
                                            onTextChanged: root.colorsImportPath = text
                                            Keys.onReturnPressed: {
                                                if (bar && typeof bar.importTheme === "function")
                                                    bar.importTheme(root.colorsImportPath)
                                                root.colorsTick++
                                            }
                                        }
                                        Rectangle {
                                            Layout.preferredHeight: 26
                                            Layout.preferredWidth: loadPathLbl.implicitWidth + 12
                                            radius: root.chipR
                                            color: loadPathMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                            border.width: 1
                                            border.color: bar.pillBorder
                                            Text {
                                                id: loadPathLbl
                                                anchors.centerIn: parent
                                                text: "Load"
                                                color: bar.subtext
                                                font.pixelSize: 11
                                                font.family: bar.fontFamily
                                            }
                                            MouseArea {
                                                id: loadPathMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (bar && typeof bar.importTheme === "function")
                                                        bar.importTheme(root.colorsImportPath)
                                                    root.colorsTick++
                                                }
                                            }
                                        }
                                    }
                                }
                                } // themesBodyCol
                                } // themesBodyFlick

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Rectangle {
                                        Layout.preferredHeight: 24
                                        Layout.preferredWidth: resetThemeLbl.implicitWidth + 12
                                        radius: root.chipR
                                        color: resetThemeMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: resetThemeLbl
                                            anchors.centerIn: parent
                                            text: "Reset"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: resetThemeMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.pushThemeUndo()
                                                if (bar && typeof bar.resetThemeColors === "function")
                                                    bar.resetThemeColors()
                                                root.colorsPickerKey = ""
                                                root.colorsTick++
                                            }
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                            } // themesPanel

                            // ===== CLOCK / REGION =====
                            ColumnLayout {
                                id: clockPanel
                                visible: root.activeMenu === "clock"
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(280, root.panelMaxH - 12)
                                spacing: 8

                                Text {
                                    text: "Region & Clock"
                                    color: bar.text
                                    font.pixelSize: bar.popupTitleSize
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Repeater {
                                        model: [
                                            { id: "region", label: "Region" },
                                            { id: "clock", label: "Clock" }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property bool on: root.clockTab === modelData.id
                                            Layout.preferredHeight: root.chipH
                                            Layout.preferredWidth: clockTabLbl.implicitWidth + 16
                                            radius: 6
                                            color: on ? Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.22)
                                                      : (clockTabMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent")
                                            border.width: 1
                                            border.color: on ? bar.accent : bar.pillBorder
                                            Text {
                                                id: clockTabLbl
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                color: on ? bar.accent : bar.subtext
                                                font.pixelSize: 11
                                                font.bold: on
                                                font.family: bar.fontFamily
                                            }
                                            MouseArea {
                                                id: clockTabMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.clockTab = modelData.id
                                                    root.menuTick++
                                                    Qt.callLater(root.reposition)
                                                }
                                            }
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                }

                                TimezoneMapView {
                                    id: clockTzMap
                                    visible: root.clockTab === "region"
                                    Layout.fillWidth: true
                                    Layout.fillHeight: visible
                                    Layout.minimumHeight: visible ? 200 : 0
                                    active: visible && clockPanel.visible && controlPopup.visible
                                    keyboardGrab: function() { root.armControlFocusGrab() }
                                    beforeApply: function() { root.hide() }
                                    textColor: bar.text
                                    subtextColor: bar.subtext
                                    accentColor: bar.accent
                                    surfaceColor: bar.surface !== undefined ? bar.surface : Qt.rgba(0.10, 0.12, 0.18, 0.9)
                                    oceanColor: "#8aa0b5"
                                    landColor: "#e7e2d6"
                                    highlightColor: "#6fbf3a"
                                    gridColor: Qt.rgba(1, 1, 1, 0.16)
                                    fieldBg: root.optFieldBg
                                    fieldBgFocus: root.optFieldBgFocus
                                    pillBorder: bar.pillBorder
                                    okColor: root.onGreen
                                    errorColor: root.offRed
                                    fontFamily: bar.fontFamily
                                    fontMono: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                    chipR: root.chipR
                                }

                                Flickable {
                                    id: clockBodyFlick
                                    visible: root.clockTab === "clock"
                                    Layout.fillWidth: true
                                    Layout.fillHeight: visible
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    flickableDirection: Flickable.VerticalFlick
                                    contentWidth: width
                                    contentHeight: clockBodyCol.implicitHeight
                                    interactive: contentHeight > height + 4
                                    ScrollBar.vertical: ScrollBar {
                                        policy: clockBodyFlick.contentHeight > clockBodyFlick.height + 4
                                                ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                        width: 8
                                        contentItem: Rectangle {
                                            implicitWidth: 6
                                            radius: 3
                                            color: bar.accent
                                            opacity: 0.5
                                        }
                                    }

                                    ColumnLayout {
                                        id: clockBodyCol
                                        width: clockBodyFlick.width
                                        spacing: 8

                                        Text {
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                            text: "Preview: " + Qt.formatDateTime(new Date(), String(root.clockFormatDraft || root.currentClockFormat()))
                                            color: bar.accent
                                            font.pixelSize: 12
                                            font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                            text: "Presets stay as they are. Custom uses Qt format tokens (HH:mm:ss, dddd, MMM d yyyy, AP)."
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }

                                        Repeater {
                                            model: root.clockPresets()
                                            delegate: Rectangle {
                                                required property var modelData
                                                readonly property bool active: root.currentClockFormat() === modelData.format
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 36
                                                radius: root.chipR
                                                color: cRowMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                                border.width: bar.controlBorderWidth
                                                border.color: active ? root.activeLabelColor() : bar.dividerStrong

                                                ColumnLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 10
                                                    anchors.rightMargin: 10
                                                    anchors.topMargin: 4
                                                    anchors.bottomMargin: 4
                                                    spacing: 0
                                                    Text {
                                                        text: modelData.label + (active ? "  · active" : "")
                                                        color: active ? root.activeLabelColor() : bar.text
                                                        font.pixelSize: 12
                                                        font.bold: active
                                                        font.family: bar.fontFamily
                                                    }
                                                    Text {
                                                        text: modelData.tip || modelData.format
                                                        color: bar.subtext
                                                        font.pixelSize: 10
                                                        font.family: bar.fontFamily
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }
                                                }
                                                MouseArea {
                                                    id: cRowMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setClockFormat(modelData.format)
                                                }
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: customFmtCol.implicitHeight + 14
                                            radius: root.chipR
                                            color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                            border.width: bar.controlBorderWidth
                                            border.color: root.clockFormatIsPreset(root.currentClockFormat())
                                                          ? bar.dividerStrong
                                                          : root.activeLabelColor()
                                            ColumnLayout {
                                                id: customFmtCol
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.margins: 8
                                                spacing: 6
                                                Text {
                                                    text: "Custom" + (root.clockFormatIsPreset(root.currentClockFormat()) ? "" : "  · active")
                                                    color: root.clockFormatIsPreset(root.currentClockFormat())
                                                           ? bar.text
                                                           : root.activeLabelColor()
                                                    font.pixelSize: 12
                                                    font.bold: !root.clockFormatIsPreset(root.currentClockFormat())
                                                    font.family: bar.fontFamily
                                                }
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 6
                                                    TextField {
                                                        id: clockFmtField
                                                        Layout.fillWidth: true
                                                        Layout.preferredHeight: 30
                                                        text: root.clockFormatDraft
                                                        placeholderText: "e.g. ddd HH:mm"
                                                        color: bar.text
                                                        placeholderTextColor: bar.subtext
                                                        font.pixelSize: 12
                                                        font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                        background: Rectangle {
                                                            radius: root.chipR
                                                            color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                                            border.width: 1
                                                            border.color: clockFmtField.activeFocus ? bar.accent : bar.pillBorder
                                                        }
                                                        onPressed: root.armControlFocusGrab()
                                                        onActiveFocusChanged: if (activeFocus) root.armControlFocusGrab()
                                                        onTextChanged: root.clockFormatDraft = text
                                                        Keys.onReturnPressed: root.applyClockFormatDraft()
                                                        Keys.onEnterPressed: root.applyClockFormatDraft()
                                                    }
                                                    Rectangle {
                                                        Layout.preferredHeight: 30
                                                        Layout.preferredWidth: setFmtLbl.implicitWidth + 14
                                                        radius: root.chipR
                                                        color: setFmtMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                                        border.width: 1
                                                        border.color: setFmtMa.containsMouse ? bar.accent : bar.pillBorder
                                                        Text {
                                                            id: setFmtLbl
                                                            anchors.centerIn: parent
                                                            text: "Set"
                                                            color: bar.text
                                                            font.pixelSize: 12
                                                            font.family: bar.fontFamily
                                                        }
                                                        MouseArea {
                                                            id: setFmtMa
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: root.applyClockFormatDraft()
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                            Rectangle {
                                anchors.fill: parent
                                visible: wpDropArea.containsDrag && root.activeMenu === "wallpaper"
                                z: 20
                                radius: panelBox.radius
                                color: Qt.rgba(bar.accent.r, bar.accent.g, bar.accent.b, 0.16)
                                border.width: 2
                                border.color: bar.accent
                                Text {
                                    anchors.centerIn: parent
                                    text: "Drop images to add"
                                    color: bar.text
                                    font.pixelSize: 16
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                            }
                    }

                    MouseArea {
                        anchors.fill: parent
                        visible: root.activeMenu === "wallpaper"
                                 && root.wallpaperMenuPath.length > 0
                                 && root.wallpaperDialog === ""
                        z: 30
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: root.closeWallpaperUi()
                    }

                    Rectangle {
                        visible: root.activeMenu === "wallpaper" && root.wallpaperMenuPath.length > 0
                                 && root.wallpaperDialog === ""
                        x: root.wallpaperMenuX
                        y: root.wallpaperMenuY
                        z: 40
                        width: 156
                        height: wpMenuCol.implicitHeight + 12
                        radius: root.chipR
                        color: bar.glassPopupBg
                        border.width: bar.controlBorderWidth
                        border.color: bar.glassPopupBorder

                        ColumnLayout {
                            id: wpMenuCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 6
                            spacing: 4

                            Repeater {
                                model: [
                                    { id: "apply", label: "Apply" },
                                    { id: "rename", label: "Rename…" },
                                    { id: "delete", label: "Delete…" }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    radius: 5
                                    color: wpMenuItemMa.containsMouse
                                           ? (modelData.id === "delete" ? Qt.rgba(1, 0.24, 0.54, 0.22) : bar.popupButtonHoverBg)
                                           : Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: wpMenuItemMa.containsMouse
                                                  ? (modelData.id === "delete" ? root.offRed : bar.accent)
                                                  : bar.dividerStrong
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        text: modelData.label
                                        color: modelData.id === "delete" ? root.offRed : bar.text
                                        font.pixelSize: 12
                                        font.family: bar.fontFamily
                                    }
                                    MouseArea {
                                        id: wpMenuItemMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const p = root.wallpaperMenuPath
                                            const n = root.wallpaperMenuName
                                            if (modelData.id === "apply") {
                                                root.closeWallpaperUi()
                                                root.applyWallpaper(p)
                                            } else if (modelData.id === "rename") {
                                                root.beginRenameWallpaper(p, n)
                                            } else if (modelData.id === "delete") {
                                                root.beginDeleteWallpaper(p, n)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: root.activeMenu === "wallpaper" && root.wallpaperDialog === "rename"
                        z: 50
                        color: Qt.rgba(0, 0, 0, 0.55)
                        radius: panelBox.radius
                        focus: visible
                        onVisibleChanged: {
                            if (visible) {
                                wpRenameField.text = root.wallpaperRenameDraft
                                wpRenameField.forceActiveFocus()
                                wpRenameField.selectAll()
                            }
                        }
                        Keys.onEscapePressed: root.closeWallpaperUi()

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.closeWallpaperUi()
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 28, 360)
                            height: wpRenameCol.implicitHeight + 24
                            radius: root.chipR
                            color: bar.glassPopupBg
                            border.width: bar.controlBorderWidth
                            border.color: bar.glassPopupBorder

                            MouseArea {
                                anchors.fill: parent
                            }

                            ColumnLayout {
                                id: wpRenameCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 12
                                spacing: 8

                                Text {
                                    text: "Rename wallpaper"
                                    color: bar.text
                                    font.pixelSize: bar.popupTitleSize
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                TextField {
                                    id: wpRenameField
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 30
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.family: bar.fontFamily
                                    selectByMouse: true
                                    background: Rectangle {
                                        radius: 4
                                        color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                        border.width: 1
                                        border.color: wpRenameField.activeFocus ? bar.accent : bar.pillBorder
                                    }
                                    onTextEdited: root.wallpaperRenameDraft = text
                                    onAccepted: root.confirmRenameWallpaper()
                                    Keys.onEscapePressed: root.closeWallpaperUi()
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        Layout.preferredHeight: 28
                                        Layout.preferredWidth: wpRenameCancelLbl.implicitWidth + 16
                                        radius: root.chipR
                                        color: wpRenameCancelMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: wpRenameCancelLbl
                                            anchors.centerIn: parent
                                            text: "Cancel"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: wpRenameCancelMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.closeWallpaperUi()
                                        }
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 28
                                        Layout.preferredWidth: wpRenameOkLbl.implicitWidth + 16
                                        radius: root.chipR
                                        color: wpRenameOkMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                        border.width: 1
                                        border.color: wpRenameOkMa.containsMouse ? bar.accent : bar.pillBorder
                                        Text {
                                            id: wpRenameOkLbl
                                            anchors.centerIn: parent
                                            text: "Rename"
                                            color: wpRenameOkMa.containsMouse ? root.activeLabelColor() : bar.text
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: wpRenameOkMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.confirmRenameWallpaper()
                                        }
                                    }
                                }
                            }
                        }

                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: root.activeMenu === "wallpaper" && root.wallpaperDialog === "delete"
                        z: 50
                        color: Qt.rgba(0, 0, 0, 0.55)
                        radius: panelBox.radius
                        focus: visible
                        Keys.onEscapePressed: root.closeWallpaperUi()

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.closeWallpaperUi()
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 28, 360)
                            height: wpDeleteCol.implicitHeight + 24
                            radius: root.chipR
                            color: bar.glassPopupBg
                            border.width: bar.controlBorderWidth
                            border.color: bar.glassPopupBorder

                            MouseArea {
                                anchors.fill: parent
                            }

                            ColumnLayout {
                                id: wpDeleteCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 12
                                spacing: 8

                                Text {
                                    text: "Delete wallpaper"
                                    color: bar.text
                                    font.pixelSize: bar.popupTitleSize
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "Remove “" + root.wallpaperDialogName + "” from this folder? This cannot be undone."
                                    color: bar.subtext
                                    font.pixelSize: 12
                                    font.family: bar.fontFamily
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Item { Layout.fillWidth: true }
                                    Rectangle {
                                        Layout.preferredHeight: 28
                                        Layout.preferredWidth: wpDeleteCancelLbl.implicitWidth + 16
                                        radius: root.chipR
                                        color: wpDeleteCancelMa.containsMouse ? bar.glassHover : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: wpDeleteCancelLbl
                                            anchors.centerIn: parent
                                            text: "Cancel"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: wpDeleteCancelMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.closeWallpaperUi()
                                        }
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 28
                                        Layout.preferredWidth: wpDeleteOkLbl.implicitWidth + 16
                                        radius: root.chipR
                                        color: wpDeleteOkMa.containsMouse ? Qt.rgba(1, 0.24, 0.54, 0.28) : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                                        border.width: 1
                                        border.color: root.offRed
                                        Text {
                                            id: wpDeleteOkLbl
                                            anchors.centerIn: parent
                                            text: "Delete"
                                            color: root.offRed
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: wpDeleteOkMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.confirmDeleteWallpaper()
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        z: 90
                        visible: root.activeMenu.length > 0
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 8
                        width: 26
                        height: 26
                        radius: root.chipR
                        color: panelCloseMa.containsMouse
                               ? Qt.rgba(1, 0.24, 0.54, 0.22)
                               : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                        border.width: 1
                        border.color: panelCloseMa.containsMouse ? root.offRed : bar.pillBorder
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: panelCloseMa.containsMouse ? root.offRed : bar.subtext
                            font.pixelSize: 12
                            font.bold: true
                            font.family: bar.fontFamily
                        }
                        MouseArea {
                            id: panelCloseMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.hide()
                        }
                    }
                }

                // ── Toolbar along the bottom (panel expands above) ──
                Rectangle {
                    visible: root.activeMenu.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: bar.dividerStrong
                }
                RowLayout {
                    id: controlRow
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    Repeater {
                        model: [
                            { id: "position",  label: "Position" },
                            { id: "display",   label: "Display" },
                            { id: "wallpaper", label: "Wallpaper" },
                            { id: "widgets",   label: "Widgets" },
                            { id: "options",   label: "Options" },
                            { id: "colors",    label: "Themes" },
                            { id: "launch",    label: "Launch" },
                            { id: "autostart", label: "Autostart" },
                            { id: "mime",      label: "MIME" },
                            { id: "services",  label: "Services" },
                            { id: "audio",     label: "Audio" },
                            { id: "keybinds",  label: "Keybinds" },
                            { id: "clock",     label: "Region & Clock" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool active: root.activeMenu === modelData.id
                            readonly property bool hovered: menuBtnMa.containsMouse
                            Layout.preferredHeight: root.chipH + 4
                            Layout.preferredWidth: Math.max(72, menuBtnLabel.implicitWidth + 20)
                            radius: root.chipR
                            color: root.chipBg(active, hovered)
                            border.width: bar.controlBorderWidth
                            border.color: root.chipBorder(active, hovered)
                            Text {
                                id: menuBtnLabel
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: bar.fontPillLabel !== undefined ? bar.fontPillLabel : 12
                                font.family: bar.fontFamily
                                font.bold: active
                                color: root.chipText(active, hovered)
                            }
                            MouseArea {
                                id: menuBtnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.id === "wallpaper")
                                        root.refreshWallpapers()
                                    if (modelData.id === "display")
                                        root.refreshDisplay()
                                    if (modelData.id === "launch")
                                        root.refreshDesktopApps()
                                    if (modelData.id === "autostart") {
                                        root.refreshAutostart()
                                        root.refreshDesktopApps()
                                    }
                                    if (modelData.id === "options")
                                        root.refreshOptions()
                                    // ServicesView loads via active binding when panel opens
                                    root.toggleMenu(modelData.id)
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredHeight: root.chipH + 4
                        Layout.preferredWidth: Math.max(36, stripCloseLbl.implicitWidth + 16)
                        radius: root.chipR
                        color: stripCloseMa.containsMouse
                               ? Qt.rgba(1, 0.24, 0.54, 0.22)
                               : (bar.buttonBg !== undefined ? bar.buttonBg : bar.pillBg)
                        border.width: bar.controlBorderWidth
                        border.color: stripCloseMa.containsMouse ? root.offRed : bar.pillBorder
                        Text {
                            id: stripCloseLbl
                            anchors.centerIn: parent
                            text: "✕"
                            color: stripCloseMa.containsMouse ? root.offRed : bar.subtext
                            font.pixelSize: 12
                            font.bold: true
                            font.family: bar.fontFamily
                        }
                        MouseArea {
                            id: stripCloseMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.hide()
                        }
                    }
                }
            }
        }
    }
}

