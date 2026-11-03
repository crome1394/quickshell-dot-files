// =============================================================================
// shell.qml — Main Quickshell entry point for the Hyprland status bar
// =============================================================================
//
// Widget logic lives in:
//   - widgets/*.qml      (self-contained pills and menus)
//   - components/*.qml   (reusable pieces like VolumeBar)
//   - Config.qml      (colors, spacing, metrics, workspace behavior)
//   - widgets/HyprConfigInsp.qml (Hyprland Config Inspector overlay)
//   - widgets/ActiveWindowBar.qml (focused-window pill, top-left overlay)
//
// IPC:
//   - qs ipc call hyprConfigInsp toggle
//   - qs ipc call freshRss toggle / refresh / show / hide
//   - qs ipc call shell setShowFreshRssPill true / toggleShowFreshRssPill
//   - qs ipc call shell setShowStatsWidget false
//   - qs ipc call shell toggleShowStatsWidget
//   - qs ipc call shell setShowMagicWorkspacePill true
//   - qs ipc call shell toggleShowMagicWorkspacePill
//   - qs ipc call shell setShowAudioPill false   (and set/toggle for each bar pill)
//   - qs ipc call shell setShowBluetoothPill true / toggleShowBluetoothPill
//   - qs ipc call audioPill setEchoCancel true|false
//   - qs ipc call audioPill toggleEchoCancel / enableEchoCancel / disableEchoCancel
//   - qs ipc call networkPanel showPopup / hidePopup / togglePopup / toggleWifi
//   - qs ipc call shell setShowNetworkPanel true / toggleShowNetworkPanel
//   - qs ipc call bluetoothPill showPopup / hidePopup / togglePopup
//   - qs ipc call bluetoothPill setPower true|false / togglePower / enable / disable
//   - qs ipc call bluetoothPill startScan / stopScan / toggleScan
//   - qs ipc call bluetoothPill setDiscoverable true|false / toggleDiscoverable
//   - qs ipc call bluetoothPill startApplet / stopApplet / toggleApplet   (session only)
//   - qs ipc call bluetoothPill disableApplet / enableApplet              (survives reboot)
//   - qs ipc call bluetoothPill setAppletAutostart true|false
//   - qs ipc call bluetoothPill connectDevice|disconnectDevice|pairDevice|forgetDevice "AA:BB:…"
//   - qs ipc call bluetoothPill setTrusted "AA:BB:…" true|false
//   - qs ipc call bluetoothPill setBlocked "AA:BB:…" true|false
//   - qs ipc call bluetoothPill renameDevice "AA:BB:…" "Name"
//   - qs ipc call bluetoothPill setCardProfile "AA:BB:…" "a2dp-sink"
//   - qs ipc call clockPill showCalendar
//   - qs ipc call notificationBell toggleHistory / showHistory / hideHistory
//   - qs ipc call notificationBell toggleDoNotDisturb
//   - qs ipc call overview toggle / open / close / desktop / all / next / prev
//   - qs ipc call shell setWsMinimumShown 7
//   - qs ipc call shell setWsShowOnlyActive true
//   - qs ipc call shell setWsShowNumbers false
//   - qs ipc call shell setWsStartupWorkspace 1
//   - qs ipc call shell setWsStartupCloseMagic false
//   (Run `qs ipc show` for the full list of shell commands.)
//
// Bar position (Config.qml):
//   - barLayoutMode: "classic" (one bar, L/C/R) or "dual" (top + bottom, centered)
//   - barPosition: "top" or "bottom" (classic only; Config default; runtime toggle + IPC)
//   - Right-click empty bar chrome → BarControlBar (layout + top/bottom live there)
//   - qs ipc call shell setBarLayoutMode classic|dual / toggleBarLayoutMode
//   - qs ipc call shell setBarPosition top|bottom / toggleBarPosition
//   - qs ipc call shell toggleBarControlBar / showBarControlBar / hideBarControlBar
//   - UI scale: auto from screen width (Config.uiDesignWidth); override with
//     qs ipc call shell setUiScale 0.8 | setUiScaleManual 0.85 | setUiScaleAuto
//   - barEdgeMargin: gap from the screen edge
//   - flushWindowsToBar: pull tiled windows against the bar (skip Hyprland gaps_out)
//
// =============================================================================
// BAR LAYOUT — classic (left / center / right) or dual (top / bottom, centered)
// =============================================================================
//
// Classic mode has three sections on one bar:
//
//   LEFT ZONE   →  pinned to the left side of the bar
//   CENTER ZONE →  always centered on the bar (screen middle)
//   RIGHT ZONE  →  pinned to the right side of the bar
//
// Dual mode has two centered bars (glass hugs the widget row):
//
//   TOP ZONE    →  centered cluster on the top edge
//   BOTTOM ZONE →  centered cluster on the bottom edge
//
// Switch layouts from BarControlBar → Position. Reorder / show / hide / scale
// from BarControlBar → Widgets (L/C/R in classic, T/B in dual). Persisted in
// state/bar-layout.json (each mode keeps its own widget order).
//
// Classic default:
//   LEFT:   App Launcher, Quick Launch, FreshRSS
//   CENTER: Workspaces
//   RIGHT:  System Stats, System Tray, Network, Bluetooth+Audio,
//           Clock, Notifications, Power
//
// Dual default:
//   TOP:    Clock, Workspaces, System Tray, Notifications, Power
//   BOTTOM: Sys Stats, Launcher, Quick Launch, FreshRSS, Config menu,
//           Bluetooth · Audio, Network
// =============================================================================

import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Hyprland
import Quickshell.Io as Io
import "components"
import "widgets"
import "widgets/network"   // NetworkButton, NetworkPopup, NetworkService

ShellRoot {
    id: root

    // --- Widget visibility (config defaults in Config.qml; IPC overrides until qs restart) ---
    property bool showLauncherPill: true
    property bool showQuickLaunchPill: true
    property bool showWorkspacesPill: true
    property bool showStatsWidget: true
    property bool showTrayPill: true
    property bool showNetworkPanel: true
    property bool showBluetoothPill: true
    property bool showAudioPill: true
    property bool showClockPill: true
    property bool showNotificationPill: true
    property bool showPowerPill: true
    property bool showOpacityPill: true
    property bool showTailscalePill: true
    property bool showFreshRssPill: true
    property bool showHyprInspPill: false
    property bool showControlBarPill: true       // Settings / config menu icon on the bar
    // Screen-corner overlays (not part of the bar layout)
    property bool showActiveWindowPill: true
    property string activeWindowPillCorner: "topLeft"   // topLeft | topRight | bottomLeft | bottomRight
    // Classes, app ids, and titles the focused-window pill skips. * is a wildcard.
    // Options → Active Window. hypr-screensaver is the idle saver's window class.
    property var activeWindowExcludes: ["hypr-screensaver"]
    // Bumped by every Widgets on/off so control-bar pages can follow the switch.
    property int widgetVisTick: 0
    property bool showColorPresets: true         // Colors panel: built-in / custom presets section
    property bool showMagicWorkspacePill: true   // Magic pill inside WorkspacesPill (wsShowSpecialPill)
    // Sys Stats gauges (Options panel; all on by default)
    property bool showStatCpu: true
    property bool showStatVram: true
    property bool showStatMem: true
    property bool showStatGpu: true
    // Util bar graphs on the Sys Stats pill face (labels / % always stay)
    property bool showStatGauges: true
    // Terminal for Sys Stats pill launches (Options → Stats).
    // Default from Config statTerminal; the pick persists in state/bar-layout.json.
    property string statTerminal: cfg.statTerminal
    // Which mouse button on the Sys Stats pill launches btop/nvtop ("left"/"right").
    property string statLaunchButton: cfg.statLaunchButton
    // Network pill face: last IPv4 octet (false) vs full address (true)
    property bool showNetworkFullIp: false
    // Network pill face: show last IPv4 octet when full IP is off (default on)
    property bool showNetworkLastOctet: true
    // Network pill face: show adapter name (enp10s0, wlan0) next to the IP
    property bool showNetworkDeviceName: false
    // Per-widget tooltip side: "above" | "below" | "left" | "right" (missing = auto)
    property var tooltipAlign: ({})
    // Hide Echo cancel block in Audio popup / control-bar Audio panel when false (Options)
    property bool showEchoCancelInMenu: true
    // Control-bar Audio panel section visibility (Options + bar-layout.json)
    property bool showAudioSummary: true
    property bool showAudioDefaults: true
    property bool showAudioLevelMeters: true
    // Keep sections expanded when the Audio panel opens
    property bool audioSummaryExpanded: true
    property bool audioDefaultsExpanded: true
    // FreshRSS reader: Filters section open on window start (Options + bar-layout.json)
    property bool freshRssFiltersExpanded: true
    // Dock-style hover (Options → Dock). off | magnify | jump | both
    // dockScope: "icons" (all icon widgets) | "quicklaunch"
    property string dockEffect: "both"
    property real dockMaxScale: 1.28
    property int dockRadius: 72
    property int dockJumpPx: 8
    property string dockScope: "icons"

    // Clock format string (Qt.formatDateTime); Config default, persisted override.
    property string clockFormat: "dddd, MM·dd·yyyy | HH:mm:ss"

    // "classic" = one bar with left|center|right zones
    // "dual" = top and bottom bars, plus optional left and right edge bars
    property string barLayoutMode: "classic"
    // Extra full-width span. Classic already spans; Dual's top bar hugs until this is on.
    property bool barSpanFull: false
    // Bottom strip in Dual. Off hugs the widgets; on spans the monitor.
    property bool panelSpanFull: false
    // 0 = same height as the bar. Otherwise 0.80–1.40 for the bottom strip only.
    property real panelSizeScale: 0
    // Audio pill view: 0 speaker, 1 microphone, 2 both.
    property int audioViewMode: 2
    // Widget cluster on each strip: "left" | "center" | "right".
    // On a side bar, left is the top of the screen and right is the bottom.
    property string topBarAlign: "center"
    property string bottomBarAlign: "center"
    // Side bars stay off until the user turns them on. Missing state keys stay off.
    property bool showLeftBar: false
    property bool showRightBar: false
    property string leftBarAlign: "center"
    property string rightBarAlign: "center"
    property bool leftBarSpanFull: false
    property bool rightBarSpanFull: false

    // Runtime layout: [{ id, zone }, ...]
    // classic: left|center|right (groups on the one horizontal bar)
    // dual: top|bottom|left|right (edge bars)
    property var widgetLayout: []

    // Runtime Quick Launch pins (Config default, editable from BarControlBar, persisted)
    property var quickLaunchApps: []

    // Wallpaper directory (Config default; editable from BarControlBar, persisted)
    property string wallpaperDir: "/home/crome/Pictures/wallpapers"
    property string wallpaperCurrent: ""
    // Preferred wallpaper thumbnail width (px); grid stretches tiles to fill the panel.
    property int wallpaperTileSize: 148
    // Screenshot output folder (blank = XDG Pictures; editable from Options → ScreenShots, persisted)
    property string screenshotDir: ""

    // Workspace overview (Options → Overview, state/bar-layout.json).
    property bool hasOverviewPrefs: false
    property string ovLayout: "rows"          // rows | grid | natural
    property string ovAnchor: "top"           // top | bottom | left | right
    property int ovGap: 34
    property int ovPadding: 80
    property int ovPaddingTop: 40
    property int ovPaddingBottom: 70
    property real ovMaxScale: 1.0
    property int ovDuration: 360
    property int ovPreviewRound: 12
    property real ovBlur: 1.0
    property bool ovBackdropBlur: false
    property bool ovSwitchAnimation: true
    property int ovSwitchDuration: 260
    property bool ovMoveAnimation: true
    property int ovMoveDuration: 240
    property int ovStripOffset: 0
    property int ovStripHeight: 150
    property int ovStripWidth: 150
    property int ovStripCardMax: 300
    property int ovStripMargin: 22
    property int ovStripGap: 18
    property int ovStripCardRound: 10
    property int ovHoverBorder: 3
    property int ovSelectBorder: 3
    property bool ovLivePreviews: true
    property bool ovShowWindowLabels: true
    property bool ovShowWsLabels: true
    property bool ovStripPreviews: true
    property bool ovNumberLabels: false
    property bool ovDynamic: true
    property bool ovAutodelete: true
    property bool ovShowEmpty: true
    property bool ovShowSpecial: false
    property bool ovStripAllCard: false
    property bool ovShowAll: false
    property bool ovSwitchOnNew: true
    property bool ovSwitchOnDrop: false
    property bool ovDragToSwap: true
    property bool ovFocusFollowsMouse: true
    property bool ovScrollSwitches: true
    property bool ovExitOnClick: true
    property bool ovExitOnSwitch: false

    // Per-widget pill scale (1.0 = default). Keys match widgetCatalog / layout ids.
    property var widgetScales: ({})

    // Density: auto-hide deprioritized pills on narrow screens (see Config.uiDensity*).
    // User/IPC show* flags stay as preferences; density gates actual visibility.
    property bool densityHideQuickLaunch: false
    property bool densityHideStats: false
    property bool densityHideSecondary: false   // FreshRSS
    property bool densityHideConnectivity: false  // Bluetooth

    // Effective visibility helpers (preference AND density)
    readonly property bool effQuickLaunch: showQuickLaunchPill && !densityHideQuickLaunch
    readonly property bool effStats: showStatsWidget && !densityHideStats
    readonly property bool effFreshRss: showFreshRssPill && !densityHideSecondary
    readonly property bool effBluetooth: showBluetoothPill && !densityHideConnectivity
    readonly property bool effConnectivity: effBluetooth

    // Catalog for BarControlBar menus (id → label + visibility property name)
    readonly property var widgetCatalog: [
        { id: "launcher",      label: "Application Menu",      vis: "showLauncherPill" },
        { id: "quickLaunch",   label: "Application Launcher",  vis: "showQuickLaunchPill" },
        { id: "freshRss",      label: "FreshRSS",      vis: "showFreshRssPill" },
        { id: "workspaces",    label: "Workspaces",    vis: "showWorkspacesPill" },
        { id: "stats",         label: "System Stat Bars",     vis: "showStatsWidget" },
        { id: "tray",          label: "System Tray",   vis: "showTrayPill" },
        { id: "connectivity",  label: "BT · Audio", vis: "connectivity" },
        { id: "networkPanel",  label: "Network",          vis: "showNetworkPanel" },
        { id: "clock",         label: "Clock",         vis: "showClockPill" },
        { id: "notifications", label: "Notifications", vis: "showNotificationPill" },
        { id: "hyprInsp",      label: "Hypr Inspector", vis: "showHyprInspPill" },
        { id: "controlBar",    label: "Config Menu Icon",   vis: "showControlBarPill" },
        { id: "tailscale",     label: "Tailscale",     vis: "showTailscalePill" },
        { id: "opacity",       label: "Transparency",  vis: "showOpacityPill" },
        { id: "power",         label: "Power",         vis: "showPowerPill" }
    ]

    // Workspace behavior (Config defaults; runtime + bar-layout.json via Options / IPC)
    property int  wsMinimumShown: 3
    property bool wsShowOnlyActive: false
    property bool wsShowNumbers: true     // false = symbol and label only, no workspace number
    property int  wsStartupWorkspace: 0   // 0 = do not touch focus (safe for qs reload)
    property bool wsStartupCloseMagic: false
    // Options → Notifications. When on, the history list opens fully expanded.
    property bool notificationAutoExpand: false
    // Options → Notifications. When on, history rows alternate a modest shade.
    property bool notificationStaggerRows: true
    // Options → Notifications. When on, the history file is emptied on a new boot.
    property bool notificationClearOnBoot: false
    // Options → Notifications. When off, the bell shows no number.
    property bool notificationShowCount: true
    // Options → Notifications. SwayNC toast corner.
    // topLeft | topRight | bottomLeft | bottomRight. Bottom stacks upward.
    property string notificationCorner: "bottomRight"
    // Options → Notifications. Seconds a normal toast stays. 0 stays until closed.
    property int notificationTimeout: 8
    // Empty uses Config.wsIconSpecial. Options → Workspaces can override the special pill glyph.
    property string wsIconSpecialCustom: ""
    // Empty name uses Config.wsSpecialName. The rest match a numbered workspace row.
    property string wsSpecialNameCustom: ""
    property string wsSpecialFont: ""
    property int wsSpecialFontPx: 0
    property string wsSpecialText: ""
    property bool wsSpecialBold: true
    property bool wsSpecialItalic: false
    property string wsSpecialColor: ""
    // Application Menu pill. Empty icon keeps the drawn 3×3 grid. Icon px 0 uses
    // Config.iconSizeLauncher. Empty command uses Config.launcherCommand.
    property string launcherIconCustom: ""
    property int launcherIconPx: 0
    property string launcherCommandCustom: ""
    // Ordered default workspace pills: [{ id, label }]. Empty until Options saves a custom set.
    property bool hasWsSlots: false
    property var wsSlots: []

    // Optional startup focus (Config.wsStartupWorkspace > 0 only).
    // IMPORTANT: Quickshell reloads re-run this whole tree — treating reload like login
    // is what forced workspace 1. Default is 0 (no-op). When N > 0, only dispatch if
    // current focus differs; never re-focus a workspace you are already on.
    property int _startupWsAttempts: 0
    Timer {
        id: startupWorkspaceTimer
        interval: 350
        // Stay dormant when disabled; bar.Component.onCompleted can start it if needed.
        running: false
        repeat: true
        onTriggered: {
            const targetWs = root.wsStartupWorkspace
            if (targetWs <= 0) {
                stop()
                root._startupWsAttempts = 0
                return
            }

            root._startupWsAttempts += 1

            // Resolve current Hyprland focus before any dispatch.
            Hyprland.refreshMonitors()
            const focused = Hyprland.focusedWorkspace
            const focusedId = (focused && focused.id > 0) ? focused.id : 0

            let magicOpen = false
            if (bar.wsStartupCloseMagic) {
                const mon = Hyprland.focusedMonitor
                const sw = (mon && mon.lastIpcObject) ? mon.lastIpcObject.specialWorkspace : null
                const magicName = sw ? (sw.name || "") : ""
                magicOpen = magicName.length > 0 && bar.wsIsSpecialName(magicName)
                if (magicOpen) {
                    Hyprland.dispatch("hl.dsp.workspace.toggle_special('" + bar.wsSpecialName + "')")
                }
            }

            // Guard: only focus when not already there (focus(N) can still have side effects).
            if (focusedId !== targetWs) {
                Hyprland.dispatch("hl.dsp.focus({ workspace = " + targetWs + " })")
            }

            // Done when already correct (and magic closed if requested), or after retries.
            const done = (!magicOpen && focusedId === targetWs) || root._startupWsAttempts >= 4
            if (done) {
                stop()
                root._startupWsAttempts = 0
            }
        }
    }

    PanelWindow {
        id: bar
        color: "transparent"
        implicitHeight: bar.barHeight
        mask: Region { item: barBg }
        anchors.left: true
        anchors.right: true
        // Dual mode always uses this window as the top bar; classic follows barPosition.
        anchors.top: root.barLayoutMode === "dual" || bar.barPosition === "top"
        anchors.bottom: root.barLayoutMode !== "dual" && bar.barPosition === "bottom"
        margins.top: (root.barLayoutMode === "dual" || bar.barPosition === "top") ? bar.barEdgeMargin : 0
        margins.bottom: (root.barLayoutMode !== "dual" && bar.barPosition === "bottom") ? bar.barEdgeMargin : 0
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: bar.edgeExclusiveZone

        // --- Config (single source of truth — see Config.qml) ---
        Config { id: cfg }

        Component.onCompleted: {
            root.showLauncherPill = cfg.showLauncherPill
            root.showQuickLaunchPill = cfg.showQuickLaunchPill
            root.showWorkspacesPill = cfg.showWorkspacesPill
            root.showStatsWidget = cfg.showStatsPill
            root.showTrayPill = cfg.showTrayPill
            root.showNetworkPanel = cfg.showNetworkPanel
            root.showBluetoothPill = cfg.showBluetoothPill
            root.showAudioPill = cfg.showAudioPill
            root.showClockPill = cfg.showClockPill
            root.showNotificationPill = cfg.showNotificationPill
            root.showPowerPill = cfg.showPowerPill
            root.showOpacityPill = cfg.showOpacityPill
            root.showTailscalePill = cfg.showTailscalePill
            root.showFreshRssPill = cfg.showFreshRssPill
            root.showHyprInspPill = cfg.showHyprInspPill
            root.showControlBarPill = cfg.showControlBarPill
            root.showColorPresets = true
            root.showMagicWorkspacePill = cfg.wsShowSpecialPill
            root.showStatCpu = true
            root.showStatVram = true
            root.showStatMem = true
            root.showStatGpu = true
            root.showStatGauges = true
            root.statTerminal = cfg.statTerminal
            root.statLaunchButton = cfg.statLaunchButton
            root.showEchoCancelInMenu = true
            root.showAudioSummary = true
            root.showAudioDefaults = true
            root.showAudioLevelMeters = true
            root.audioSummaryExpanded = true
            root.audioDefaultsExpanded = true
            root.freshRssFiltersExpanded = cfg.freshRssFiltersExpandedDefault !== undefined
                ? !!cfg.freshRssFiltersExpandedDefault
                : true
            root.wsMinimumShown = cfg.wsMinimumShown
            root.wsShowOnlyActive = cfg.wsShowOnlyActive
            root.wsShowNumbers = cfg.wsShowNumbers
            root.wsStartupWorkspace = cfg.wsStartupWorkspace
            root.wsStartupCloseMagic = cfg.wsStartupCloseMagic
            root.clockFormat = cfg.clockFormat || root.clockFormat
            root.barLayoutMode = (cfg.barLayoutMode === "dual") ? "dual" : "classic"
            root.widgetLayout = (root.barLayoutMode === "dual")
                ? bar.cloneDualDefaultLayout()
                : bar.cloneDefaultLayout()
            root.quickLaunchApps = bar.cloneQuickLaunchApps()
            root.wallpaperDir = cfg.wallpaperDir || root.wallpaperDir
            root.wallpaperTileSize = cfg.wallpaperTileSize || root.wallpaperTileSize

            // Bar edge: Config default, then optional persisted override from state file.
            bar.barPosition = (cfg.barPosition === "bottom") ? "bottom" : "top"
            barLayoutFile.reload()
            themeColorsFile.reload()
            bar.applyUiScale()
            Qt.callLater(function() { bar.applyWidgetLayout() })
            Qt.callLater(function() {
                bar.refreshThemeSavedList()
                if (typeof bar.refreshSetupSavedList === "function")
                    bar.refreshSetupSavedList()
            })

            // Start optional startup focus only after config is applied (avoids
            // racing the property default before cfg loads). No-op when 0.
            if (root.wsStartupWorkspace > 0)
                startupWorkspaceTimer.start()
        }

        // Recompute scale when the panel is mapped / screen geometry is known.
        onWidthChanged: bar.applyUiScale()
        onScreenChanged: bar.applyUiScale()

        // ---- UI scale (auto from screen width; optional manual override) ----
        function _screenSize() {
            var w = 0
            var h = 0
            try {
                if (bar.screen) {
                    w = bar.screen.width || 0
                    h = bar.screen.height || 0
                }
            } catch (e) {}
            if (!(w > 0))
                w = bar.width || 0
            if (!(w > 0) && Quickshell.screens && Quickshell.screens.length)
                w = Quickshell.screens[0].width || 0
            if (!(h > 0) && Quickshell.screens && Quickshell.screens.length)
                h = Quickshell.screens[0].height || 0
            if (!(w > 0))
                w = cfg.uiDesignWidth
            if (!(h > 0))
                h = 1080
            return { w: w, h: h }
        }

        function applyUiScale() {
            var sz = bar._screenSize()
            cfg.screenWidth = sz.w
            cfg.screenHeight = sz.h
            var next = cfg.computeUiScale(sz.w)
            if (Math.abs(cfg.uiScale - next) > 0.001)
                cfg.uiScale = next
            bar.applyDensity()
        }

        // Hide deprioritized pills so workspaces + core right-side widgets stay visible.
        function applyDensity() {
            var d = cfg.computeDensity(cfg.screenWidth)
            root.densityHideQuickLaunch = !!d.hideQuickLaunch
            root.densityHideStats = !!d.hideStats
            root.densityHideSecondary = !!d.hideSecondary
            root.densityHideConnectivity = !!d.hideConnectivity
            cfg.densityHideQuickLaunch = root.densityHideQuickLaunch
            cfg.densityHideStats = root.densityHideStats
            cfg.densityHideSecondary = root.densityHideSecondary
            cfg.densityHideConnectivity = root.densityHideConnectivity
        }

        // Force scale (persisted). Pass 0 for auto-from-width.
        function setUiScale(scale) {
            var s = Number(scale)
            if (!(s >= 0))
                return
            if (s > 0) {
                if (s < cfg.uiScaleMin) s = cfg.uiScaleMin
                if (s > cfg.uiScaleMax) s = cfg.uiScaleMax
            }
            cfg.uiScaleManual = s
            barLayoutAdapter.uiScaleManual = s
            barLayoutFile.writeAdapter()
            bar.applyUiScale()
        }

        function setUiScaleManual(scale) {
            bar.setUiScale(scale)
        }

        function setUiScaleAuto() {
            bar.setUiScale(0)
        }

        function setBarEdgeMargin(px) {
            var n = Math.round(Number(px))
            if (!(n >= 0))
                n = 0
            if (n > 48)
                n = 48
            if (cfg.barEdgeMargin === n)
                return
            cfg.barEdgeMargin = n
            barGeomPersistTimer.restart()
        }

        function setBarSpanFull(enabled) {
            root.barSpanFull = !!enabled
            persistBarLayout()
        }
        function setPanelSpanFull(enabled) {
            root.panelSpanFull = !!enabled
            persistBarLayout()
        }
        function setPanelSizeScale(scale) {
            var n = Number(scale) || 0
            if (n > 0)
                n = Math.max(0.8, Math.min(1.4, n))
            if (Math.abs((root.panelSizeScale || 0) - n) < 0.001)
                return
            root.panelSizeScale = n
            barGeomPersistTimer.restart()
        }
        function panelBarHeight() {
            var scale = (root.panelSizeScale >= 0.8 && root.panelSizeScale <= 1.4)
                    ? root.panelSizeScale
                    : (Number(cfg.barSizeScale) || 1)
            return Math.max(36, Math.round((cfg.sp ? cfg.sp(58) : 58) * scale))
        }
        function setAudioViewMode(mode) {
            var n = Math.round(Number(mode))
            var next = (n === 0 || n === 1) ? n : 2
            if (root.audioViewMode === next)
                return
            root.audioViewMode = next
            persistBarLayout()
        }
        property alias barSpanFull: root.barSpanFull
        property alias panelSpanFull: root.panelSpanFull
        property alias panelSizeScale: root.panelSizeScale
        property alias audioViewMode: root.audioViewMode
        property alias topBarAlign: root.topBarAlign
        property alias bottomBarAlign: root.bottomBarAlign
        property alias showLeftBar: root.showLeftBar
        property alias showRightBar: root.showRightBar
        property alias leftBarAlign: root.leftBarAlign
        property alias rightBarAlign: root.rightBarAlign
        property alias leftBarSpanFull: root.leftBarSpanFull
        property alias rightBarSpanFull: root.rightBarSpanFull
        function coerceAlign(v) {
            var s = String(v || "")
            return (s === "left" || s === "right") ? s : "center"
        }
        function coerceActiveWindowCorner(v) {
            const s = String(v || "")
            if (s === "topRight" || s === "bottomLeft" || s === "bottomRight")
                return s
            return "topLeft"
        }
        function isActiveWindowTop(corner) {
            const c = coerceActiveWindowCorner(corner)
            return c === "topLeft" || c === "topRight"
        }
        // Margin between the pill and the screen edge. Match the bar edge when a
        // bar is on that side; otherwise use a small floating inset.
        function activeWindowEdgeMargin(corner) {
            const atTop = isActiveWindowTop(corner)
            const barOnEdge = root.barLayoutMode === "dual"
                             || (atTop ? barPosition === "top" : barPosition === "bottom")
            return barOnEdge ? (barEdgeMargin || 0) : 6
        }
        // Height of the bar strip the pill should center on, if any.
        function activeWindowStripHeight(corner) {
            const atTop = isActiveWindowTop(corner)
            let h = 0
            if (root.barLayoutMode === "dual")
                h = atTop ? barHeight : panelBarHeight()
            else if ((atTop && barPosition === "top") || (!atTop && barPosition === "bottom"))
                h = barHeight
            else
                return 0
            return Math.max(0, h - barContentVMargin)
        }
        function setActiveWindowCorner(corner) {
            const next = coerceActiveWindowCorner(corner)
            if (root.activeWindowPillCorner === next)
                return
            root.activeWindowPillCorner = next
            persistBarLayout()
        }
        // Trim, drop one-character and catch-all entries, and ignore duplicate
        // spellings. A pattern must contain at least two characters besides *.
        function normalizeActiveWindowExcludes(list) {
            const src = list || []
            const out = []
            const seen = {}
            for (let i = 0; i < src.length && out.length < 40; i++) {
                const s = String(src[i] || "").replace(/[\r\n]/g, " ").trim()
                if (s.length < 2 || s.length > 80)
                    continue
                if (s.replace(/\*/g, "").trim().length < 2)
                    continue
                const key = s.toLowerCase()
                if (seen[key])
                    continue
                seen[key] = true
                out.push(s)
            }
            return out
        }
        function setActiveWindowExcludes(list) {
            root.activeWindowExcludes = bar.normalizeActiveWindowExcludes(list)
            persistBarLayout()
        }
        function addActiveWindowExclude(pattern) {
            const cleaned = bar.normalizeActiveWindowExcludes([pattern])
            if (!cleaned.length)
                return false
            const cur = root.activeWindowExcludes || []
            const key = cleaned[0].toLowerCase()
            for (let i = 0; i < cur.length; i++) {
                if (String(cur[i] || "").trim().toLowerCase() === key)
                    return false
            }
            const next = cur.slice()
            next.push(cleaned[0])
            root.activeWindowExcludes = next
            persistBarLayout()
            return true
        }
        function removeActiveWindowExclude(pattern) {
            const want = String(pattern || "").trim().toLowerCase()
            if (!want.length)
                return
            const cur = root.activeWindowExcludes || []
            const next = []
            for (let i = 0; i < cur.length; i++) {
                if (String(cur[i] || "").trim().toLowerCase() !== want)
                    next.push(cur[i])
            }
            root.activeWindowExcludes = next
            persistBarLayout()
        }
        function alignX(align, parentW, itemW, margin) {
            var a = bar.coerceAlign(align)
            var m = Number(margin) || 0
            var w = Number(itemW) || 0
            var pw = Number(parentW) || 0
            if (a === "left")
                return m
            if (a === "right")
                return Math.max(m, pw - w - m)
            return Math.max(0, Math.round((pw - w) / 2))
        }
        // Same mapping as alignX. On a side bar the long axis is vertical:
        // left = top of the screen (start of 90° clockwise text), right = bottom.
        function alignY(align, parentH, itemH, margin) {
            return bar.alignX(align, parentH, itemH, margin)
        }
        function setTopBarAlign(v) {
            var next = bar.coerceAlign(v)
            if (root.topBarAlign === next)
                return
            root.topBarAlign = next
            persistBarLayout()
        }
        function setBottomBarAlign(v) {
            var next = bar.coerceAlign(v)
            if (root.bottomBarAlign === next)
                return
            root.bottomBarAlign = next
            persistBarLayout()
        }
        function setLeftBarAlign(v) {
            var next = bar.coerceAlign(v)
            if (root.leftBarAlign === next)
                return
            root.leftBarAlign = next
            persistBarLayout()
        }
        function setRightBarAlign(v) {
            var next = bar.coerceAlign(v)
            if (root.rightBarAlign === next)
                return
            root.rightBarAlign = next
            persistBarLayout()
        }
        function setLeftBarSpanFull(enabled) {
            root.leftBarSpanFull = !!enabled
            persistBarLayout()
        }
        function setRightBarSpanFull(enabled) {
            root.rightBarSpanFull = !!enabled
            persistBarLayout()
        }
        function setShowLeftBar(enabled) {
            var on = !!enabled
            if (root.showLeftBar === on)
                return
            root.showLeftBar = on
            persistBarLayout()
            if (on)
                Qt.callLater(function() { bar.applyWidgetLayout() })
        }
        function setShowRightBar(enabled) {
            var on = !!enabled
            if (root.showRightBar === on)
                return
            root.showRightBar = on
            persistBarLayout()
            if (on)
                Qt.callLater(function() { bar.applyWidgetLayout() })
        }

        function setBarSizeScale(scale) {
            var v = Number(scale)
            if (!(v > 0))
                return
            if (v < 0.8)
                v = 0.8
            if (v > 1.4)
                v = 1.4
            v = Math.round(v * 20) / 20
            if (Math.abs(cfg.barSizeScale - v) < 0.001)
                return
            cfg.barSizeScale = v
            barGeomPersistTimer.restart()
        }

        function setFlushWindowsToBar(enabled) {
            var on = !!enabled
            if (cfg.flushWindowsToBar === on)
                return
            cfg.flushWindowsToBar = on
            bar.refreshHyprGapsOut()
            barGeomPersistTimer.restart()
        }

        function setTooltipDelay(ms) {
            var n = Math.round(Number(ms))
            if (!(n >= 0))
                n = 0
            if (n > 3000)
                n = 3000
            if (n < 0)
                n = 0
            if (cfg.tooltipDelay === n)
                return
            cfg.tooltipDelay = n
            barGeomPersistTimer.restart()
        }

        function tooltipAlignFor(id) {
            const key = String(id || "")
            const map = root.tooltipAlign || {}
            const v = map[key]
            if (v === "above" || v === "below" || v === "left" || v === "right")
                return v
            return ""
        }

        function setTooltipAlign(id, side) {
            const key = String(id || "")
            if (!key.length)
                return
            let next = "auto"
            const s = String(side || "")
            if (s === "above" || s === "below" || s === "left" || s === "right")
                next = s
            const cur = Object.assign({}, root.tooltipAlign || {})
            if (next === "auto")
                delete cur[key]
            else
                cur[key] = next
            root.tooltipAlign = cur
            persistBarLayout()
        }

        // Persist bar layout prefs (edge, scale, widgets, clock, order/zones).
        // Guard: our own writeAdapter() must not re-enter onLoaded (that reparented
        // widgets and dismissed the control bar via focus loss).
        property bool _barLayoutWriteGuard: false

        Io.FileView {
            id: barLayoutFile
            path: "/home/crome/.config/quickshell/state/bar-layout.json"
            watchChanges: true
            onFileChanged: {
                if (bar._barLayoutWriteGuard)
                    return
                reload()
            }
            onLoaded: {
                if (bar._barLayoutWriteGuard)
                    return
                bar.applyBarLayoutFromAdapter()
            }
            onLoadFailed: {
                // No saved preference yet — keep Config / current value.
            }
            Io.JsonAdapter {
                id: barLayoutAdapter
                property string barPosition: "top"
                property string barLayoutMode: "classic"
                property bool barSpanFull: false
                property bool panelSpanFull: false
                property real panelSizeScale: 0
                property int audioViewMode: 2
                property string topBarAlign: "center"
                property string bottomBarAlign: "center"
                property bool showLeftBar: false
                property bool showRightBar: false
                property string leftBarAlign: "center"
                property string rightBarAlign: "center"
                property bool leftBarSpanFull: false
                property bool rightBarSpanFull: false
                property real uiScaleManual: 0
                property int barEdgeMargin: 0
                property real barSizeScale: 1.0
                property bool flushWindowsToBar: false
                property int tooltipDelay: 1550
                property string tooltipAlignJson: ""
                property string clockFormat: ""
                property string clockFont: ""
                property real clockFontScale: 1.0
                property string widgetLayoutJson: ""
                property string widgetLayoutClassicJson: ""
                property string widgetLayoutDualJson: ""
                property string quickLaunchAppsJson: ""
                property string wallpaperDir: ""
                property string wallpaperCurrent: ""
                property int wallpaperTileSize: 148
                property string screenshotDir: ""
                property bool hasOverviewPrefs: false
                property string ovLayout: "rows"
                property string ovAnchor: "top"
                property int ovGap: 34
                property int ovPadding: 80
                property int ovPaddingTop: 40
                property int ovPaddingBottom: 70
                property real ovMaxScale: 1.0
                property int ovDuration: 360
                property int ovPreviewRound: 12
                property real ovBlur: 1.0
                property bool ovBackdropBlur: false
                property bool ovSwitchAnimation: true
                property int ovSwitchDuration: 260
                property bool ovMoveAnimation: true
                property int ovMoveDuration: 240
                property int ovStripOffset: 0
                property int ovStripHeight: 150
                property int ovStripWidth: 150
                property int ovStripCardMax: 300
                property int ovStripMargin: 22
                property int ovStripGap: 18
                property int ovStripCardRound: 10
                property int ovHoverBorder: 3
                property int ovSelectBorder: 3
                property bool ovLivePreviews: true
                property bool ovShowWindowLabels: true
                property bool ovShowWsLabels: true
                property bool ovStripPreviews: true
                property bool ovNumberLabels: false
                property bool ovDynamic: true
                property bool ovAutodelete: true
                property bool ovShowEmpty: true
                property bool ovShowSpecial: false
                property bool ovStripAllCard: false
                property bool ovShowAll: false
                property bool ovSwitchOnNew: true
                property bool ovSwitchOnDrop: false
                property bool ovDragToSwap: true
                property bool ovFocusFollowsMouse: true
                property bool ovScrollSwitches: true
                property bool ovExitOnClick: true
                property bool ovExitOnSwitch: false
                property string widgetScalesJson: ""
                property bool showLauncherPill: true
                property bool showQuickLaunchPill: true
                property bool showWorkspacesPill: true
                property bool showStatsWidget: true
                property bool showTrayPill: true
                property bool showNetworkPanel: true
                property bool showBluetoothPill: true
                property bool showAudioPill: true
                property bool showClockPill: true
                property bool showNotificationPill: true
                property bool showPowerPill: true
                property bool showOpacityPill: true
                property bool showTailscalePill: true
                property bool showFreshRssPill: true
                property bool showHyprInspPill: false
                property bool showControlBarPill: true
                property bool showActiveWindowPill: true
                property string activeWindowPillCorner: "topLeft"
                property string activeWindowExcludesJson: "[\"hypr-screensaver\"]"
                property bool hasColorPresetPrefs: false
                property bool showColorPresets: true
                property bool hasWorkspacePrefs: false
                property bool showMagicWorkspacePill: true
                property int  wsMinimumShown: 3
                property bool wsShowOnlyActive: false
                property bool wsShowNumbers: true
                property bool notificationAutoExpand: false
                property bool notificationStaggerRows: true
                property bool notificationClearOnBoot: false
                property bool notificationShowCount: true
                property string notificationCorner: "bottomRight"
                property int notificationTimeout: 8
                property int  wsStartupWorkspace: 0
                property bool wsStartupCloseMagic: false
                property string wsIconSpecialCustom: ""
                property string wsSpecialNameCustom: ""
                property string wsSpecialFont: ""
                property int wsSpecialFontPx: 0
                property string wsSpecialText: ""
                property bool wsSpecialBold: true
                property bool wsSpecialItalic: false
                property string wsSpecialColor: ""
                property bool hasLauncherPrefs: false
                property string launcherIconCustom: ""
                property int launcherIconPx: 0
                property string launcherCommandCustom: ""
                property bool hasWsSlots: false
                property string wsSlotsJson: ""
                property bool hasStatPrefs: false
                property bool showStatCpu: true
                property bool showStatVram: true
                property bool showStatMem: true
                property bool showStatGpu: true
                property bool showStatGauges: true
                property string statTerminal: ""
                property string statLaunchButton: ""
                property bool showNetworkFullIp: false
                property bool showNetworkLastOctet: true
                property bool showNetworkDeviceName: false
                property bool hasAudioMenuPrefs: false
                property bool showEchoCancelInMenu: true
                property bool showAudioSummary: true
                property bool showAudioDefaults: true
                property bool showAudioLevelMeters: true
                property bool audioSummaryExpanded: true
                property bool audioDefaultsExpanded: true
                property bool hasFreshRssPrefs: false
                property bool freshRssFiltersExpanded: true
                property bool hasDockPrefs: false
                property string dockEffect: "both"
                property real dockMaxScale: 1.28
                property int dockRadius: 72
                property int dockJumpPx: 8
                property string dockScope: "icons"
            }
        }

        function applyBarLayoutFromAdapter() {
                const p = barLayoutAdapter.barPosition
                if (p === "top" || p === "bottom")
                    bar.barPosition = p
                if (barLayoutAdapter.barLayoutMode === "dual" || barLayoutAdapter.barLayoutMode === "classic")
                    root.barLayoutMode = barLayoutAdapter.barLayoutMode
                root.barSpanFull = !!barLayoutAdapter.barSpanFull
                root.panelSpanFull = !!barLayoutAdapter.panelSpanFull
                const panelScale = Number(barLayoutAdapter.panelSizeScale) || 0
                root.panelSizeScale = (panelScale >= 0.8 && panelScale <= 1.4) ? panelScale : 0
                const audioView = Math.round(Number(barLayoutAdapter.audioViewMode))
                root.audioViewMode = (audioView === 0 || audioView === 1 || audioView === 2) ? audioView : 2
                root.topBarAlign = bar.coerceAlign(barLayoutAdapter.topBarAlign)
                root.bottomBarAlign = bar.coerceAlign(barLayoutAdapter.bottomBarAlign)
                root.showLeftBar = !!barLayoutAdapter.showLeftBar
                root.showRightBar = !!barLayoutAdapter.showRightBar
                root.leftBarAlign = bar.coerceAlign(barLayoutAdapter.leftBarAlign)
                root.rightBarAlign = bar.coerceAlign(barLayoutAdapter.rightBarAlign)
                root.leftBarSpanFull = !!barLayoutAdapter.leftBarSpanFull
                root.rightBarSpanFull = !!barLayoutAdapter.rightBarSpanFull
                // Manual scale from state overrides Config default when present.
                if (barLayoutAdapter.uiScaleManual >= 0)
                    cfg.uiScaleManual = barLayoutAdapter.uiScaleManual
                if (barLayoutAdapter.barEdgeMargin >= 0)
                    cfg.barEdgeMargin = Math.max(0, Math.min(48, Math.round(barLayoutAdapter.barEdgeMargin)))
                if (barLayoutAdapter.barSizeScale > 0)
                    cfg.barSizeScale = Math.max(0.8, Math.min(1.4, Number(barLayoutAdapter.barSizeScale)))
                if (barLayoutAdapter.flushWindowsToBar !== undefined)
                    cfg.flushWindowsToBar = !!barLayoutAdapter.flushWindowsToBar
                if (barLayoutAdapter.tooltipDelay !== undefined)
                    cfg.tooltipDelay = Math.max(0, Math.min(3000, Math.round(barLayoutAdapter.tooltipDelay)))
                if (barLayoutAdapter.tooltipAlignJson && barLayoutAdapter.tooltipAlignJson.length > 2) {
                    try {
                        const ta = JSON.parse(barLayoutAdapter.tooltipAlignJson)
                        if (ta && typeof ta === "object")
                            root.tooltipAlign = ta
                    } catch (e) {}
                }
                if (barLayoutAdapter.clockFormat && barLayoutAdapter.clockFormat.length)
                    root.clockFormat = barLayoutAdapter.clockFormat
                if (barLayoutAdapter.clockFont !== undefined)
                    cfg.clockFont = String(barLayoutAdapter.clockFont || "")
                if (barLayoutAdapter.clockFontScale > 0)
                    cfg.clockFontScale = Math.max(0.70, Math.min(1.50, Number(barLayoutAdapter.clockFontScale)))
                // Visibility (only apply keys that exist in the adapter defaults)
                root.showLauncherPill = barLayoutAdapter.showLauncherPill
                root.showQuickLaunchPill = barLayoutAdapter.showQuickLaunchPill
                root.showWorkspacesPill = barLayoutAdapter.showWorkspacesPill
                root.showStatsWidget = barLayoutAdapter.showStatsWidget
                root.showTrayPill = barLayoutAdapter.showTrayPill
                root.showNetworkPanel = barLayoutAdapter.showNetworkPanel
                root.showBluetoothPill = barLayoutAdapter.showBluetoothPill
                root.showAudioPill = barLayoutAdapter.showAudioPill
                root.showClockPill = barLayoutAdapter.showClockPill
                root.showNotificationPill = barLayoutAdapter.showNotificationPill
                root.showPowerPill = barLayoutAdapter.showPowerPill
                root.showOpacityPill = barLayoutAdapter.showOpacityPill
                root.showTailscalePill = barLayoutAdapter.showTailscalePill
                root.showFreshRssPill = barLayoutAdapter.showFreshRssPill
                root.showHyprInspPill = barLayoutAdapter.showHyprInspPill
                root.showControlBarPill = barLayoutAdapter.showControlBarPill
                root.showActiveWindowPill = barLayoutAdapter.showActiveWindowPill
                root.activeWindowPillCorner = bar.coerceActiveWindowCorner(barLayoutAdapter.activeWindowPillCorner)
                if (barLayoutAdapter.activeWindowExcludesJson !== undefined) {
                    try {
                        const excluded = JSON.parse(barLayoutAdapter.activeWindowExcludesJson || "[]")
                        if (excluded && excluded.length !== undefined)
                            root.activeWindowExcludes = bar.normalizeActiveWindowExcludes(excluded)
                    } catch (e) {}
                }
                if (barLayoutAdapter.hasColorPresetPrefs)
                    root.showColorPresets = barLayoutAdapter.showColorPresets
                if (barLayoutAdapter.hasStatPrefs) {
                    root.showStatCpu = barLayoutAdapter.showStatCpu
                    root.showStatVram = barLayoutAdapter.showStatVram
                    root.showStatMem = barLayoutAdapter.showStatMem
                    root.showStatGpu = barLayoutAdapter.showStatGpu
                    root.showStatGauges = barLayoutAdapter.showStatGauges
                    if (barLayoutAdapter.statTerminal.length)
                        root.statTerminal = barLayoutAdapter.statTerminal
                    if (barLayoutAdapter.statLaunchButton === "left" || barLayoutAdapter.statLaunchButton === "right")
                        root.statLaunchButton = barLayoutAdapter.statLaunchButton
                    if (barLayoutAdapter.showNetworkFullIp !== undefined)
                        root.showNetworkFullIp = barLayoutAdapter.showNetworkFullIp
                    if (barLayoutAdapter.showNetworkLastOctet !== undefined)
                        root.showNetworkLastOctet = barLayoutAdapter.showNetworkLastOctet
                    if (barLayoutAdapter.showNetworkDeviceName !== undefined)
                        root.showNetworkDeviceName = barLayoutAdapter.showNetworkDeviceName
                }
                if (barLayoutAdapter.hasAudioMenuPrefs) {
                    root.showEchoCancelInMenu = barLayoutAdapter.showEchoCancelInMenu
                    root.showAudioSummary = barLayoutAdapter.showAudioSummary
                    root.showAudioDefaults = barLayoutAdapter.showAudioDefaults
                    root.showAudioLevelMeters = barLayoutAdapter.showAudioLevelMeters
                    root.audioSummaryExpanded = barLayoutAdapter.audioSummaryExpanded
                    root.audioDefaultsExpanded = barLayoutAdapter.audioDefaultsExpanded
                }
                if (barLayoutAdapter.hasFreshRssPrefs)
                    root.freshRssFiltersExpanded = barLayoutAdapter.freshRssFiltersExpanded
                if (barLayoutAdapter.hasDockPrefs) {
                    const de = String(barLayoutAdapter.dockEffect || "both")
                    root.dockEffect = (de === "off" || de === "magnify" || de === "jump" || de === "both") ? de : "both"
                    root.dockMaxScale = Math.max(1.05, Math.min(1.8, Number(barLayoutAdapter.dockMaxScale) || 1.28))
                    root.dockRadius = Math.max(32, Math.min(160, Math.round(barLayoutAdapter.dockRadius || 72)))
                    root.dockJumpPx = Math.max(4, Math.min(20, Math.round(barLayoutAdapter.dockJumpPx || 8)))
                    const ds = String(barLayoutAdapter.dockScope || "icons")
                    root.dockScope = (ds === "quicklaunch") ? "quicklaunch" : "icons"
                }
                // Layout JSON (normalize with the active mode so zones stay valid)
                if (barLayoutAdapter.widgetLayoutJson && barLayoutAdapter.widgetLayoutJson.length > 2) {
                    try {
                        const parsed = JSON.parse(barLayoutAdapter.widgetLayoutJson)
                        if (parsed && parsed.length)
                            root.widgetLayout = bar.normalizeLayout(parsed, root.barLayoutMode)
                    } catch (e) {}
                }
                if (barLayoutAdapter.quickLaunchAppsJson && barLayoutAdapter.quickLaunchAppsJson.length > 2) {
                    try {
                        const qa = JSON.parse(barLayoutAdapter.quickLaunchAppsJson)
                        if (qa && qa.length !== undefined)
                            root.quickLaunchApps = bar.normalizeQuickLaunchApps(qa)
                    } catch (e) {}
                }
                if (barLayoutAdapter.wallpaperDir && barLayoutAdapter.wallpaperDir.length)
                    root.wallpaperDir = barLayoutAdapter.wallpaperDir
                if (barLayoutAdapter.wallpaperCurrent && barLayoutAdapter.wallpaperCurrent.length)
                    root.wallpaperCurrent = barLayoutAdapter.wallpaperCurrent
                if (barLayoutAdapter.wallpaperTileSize >= 100)
                    root.wallpaperTileSize = Math.max(100, Math.min(260, barLayoutAdapter.wallpaperTileSize))
                if (barLayoutAdapter.screenshotDir !== undefined)
                    root.screenshotDir = String(barLayoutAdapter.screenshotDir || "").trim()
                if (barLayoutAdapter.hasOverviewPrefs)
                    bar.applyOverviewFromAdapter()
                root.notificationAutoExpand = !!barLayoutAdapter.notificationAutoExpand
                root.notificationStaggerRows = barLayoutAdapter.notificationStaggerRows !== false
                root.notificationClearOnBoot = !!barLayoutAdapter.notificationClearOnBoot
                root.notificationShowCount = barLayoutAdapter.notificationShowCount !== false
                root.notificationCorner = bar.coerceNotificationCorner(barLayoutAdapter.notificationCorner)
                root.notificationTimeout = bar.coerceNotificationTimeout(barLayoutAdapter.notificationTimeout)
                bar.applyNotificationToast()
                if (root.notificationAutoExpand) {
                    Qt.callLater(function() {
                        if (notificationBell && notificationBell.expandAllHistory)
                            notificationBell.expandAllHistory(true)
                    })
                }
                if (barLayoutAdapter.widgetScalesJson && barLayoutAdapter.widgetScalesJson.length > 2) {
                    try {
                        const sc = JSON.parse(barLayoutAdapter.widgetScalesJson)
                        if (sc && typeof sc === "object")
                            root.widgetScales = sc
                    } catch (e) {}
                }
                // Workspace Options (persisted; fall back to Config defaults when absent)
                if (barLayoutAdapter.hasWorkspacePrefs) {
                    root.showMagicWorkspacePill = barLayoutAdapter.showMagicWorkspacePill
                    root.wsMinimumShown = Math.max(1, Math.min(10, barLayoutAdapter.wsMinimumShown))
                    root.wsShowOnlyActive = barLayoutAdapter.wsShowOnlyActive
                    root.wsShowNumbers = barLayoutAdapter.wsShowNumbers !== false
                    root.wsStartupWorkspace = Math.max(0, Math.min(10, barLayoutAdapter.wsStartupWorkspace))
                    root.wsStartupCloseMagic = barLayoutAdapter.wsStartupCloseMagic
                    root.wsIconSpecialCustom = String(barLayoutAdapter.wsIconSpecialCustom || "")
                    root.wsSpecialNameCustom = bar.wsSpecialNameNorm(barLayoutAdapter.wsSpecialNameCustom)
                    root.wsSpecialFont = String(barLayoutAdapter.wsSpecialFont || "").trim().substring(0, 120)
                    root.wsSpecialFontPx = bar.wsFontPxClamp(barLayoutAdapter.wsSpecialFontPx)
                    root.wsSpecialText = bar.wsTextClamp(barLayoutAdapter.wsSpecialText)
                    root.wsSpecialBold = barLayoutAdapter.wsSpecialBold !== false
                    root.wsSpecialItalic = !!barLayoutAdapter.wsSpecialItalic
                    root.wsSpecialColor = bar.wsColorNorm(barLayoutAdapter.wsSpecialColor)
                }
                if (barLayoutAdapter.hasLauncherPrefs) {
                    root.launcherIconCustom = String(barLayoutAdapter.launcherIconCustom || "").trim().substring(0, 4)
                    const lip = Math.round(Number(barLayoutAdapter.launcherIconPx) || 0)
                    root.launcherIconPx = (lip >= 14 && lip <= 36) ? lip : 0
                    root.launcherCommandCustom = String(barLayoutAdapter.launcherCommandCustom || "").trim().substring(0, 300)
                }
                if (barLayoutAdapter.hasWsSlots && barLayoutAdapter.wsSlotsJson
                        && barLayoutAdapter.wsSlotsJson.length > 2) {
                    try {
                        const parsedSlots = JSON.parse(barLayoutAdapter.wsSlotsJson)
                        const cleanSlots = bar.sanitizeWsSlots(parsedSlots)
                        if (cleanSlots.length) {
                            root.wsSlots = cleanSlots
                            root.hasWsSlots = true
                            root.wsMinimumShown = cleanSlots.length
                        }
                    } catch (e) {}
                }
                bar.applyUiScale()
                Qt.callLater(function() { bar.applyWidgetLayout() })
        }

        // =====================================================================
        // Theme colors (Colors panel) — active look in state/theme-colors.json
        // Named exports in ~/.config/quickshell/themes/ via theme-io.sh
        // =====================================================================
        Io.FileView {
            id: themeColorsFile
            path: "/home/crome/.config/quickshell/state/theme-colors.json"
            watchChanges: true
            onFileChanged: {
                if (bar._themeWriteGuard)
                    return
                reload()
            }
            onLoaded: {
                if (bar._themeWriteGuard)
                    return
                if (themeColorsAdapter.themeJson && themeColorsAdapter.themeJson.length > 2) {
                    try {
                        const obj = JSON.parse(themeColorsAdapter.themeJson)
                        if (obj)
                            cfg.themeApply(obj)
                    } catch (e) {}
                }
            }
            onLoadFailed: {
                // No saved theme yet — keep Config defaults.
            }
            Io.JsonAdapter {
                id: themeColorsAdapter
                property string themeJson: ""
            }
        }

        function persistThemeColors() {
            bar._themeWriteGuard = true
            try {
                const obj = cfg.themeExport("Active")
                themeColorsAdapter.themeJson = JSON.stringify(obj)
            } catch (e) {
                themeColorsAdapter.themeJson = "{}"
            }
            themeColorsFile.writeAdapter()
            Qt.callLater(function() {
                Qt.callLater(function() {
                    bar._themeWriteGuard = false
                })
            })
        }

        function schedulePersistThemeColors() {
            if (bar._themePersistScheduled)
                return
            bar._themePersistScheduled = true
            Qt.callLater(function() {
                bar._themePersistScheduled = false
                bar.persistThemeColors()
            })
        }

        function setThemeColor(key, color) {
            if (!cfg.setThemeColor(key, color))
                return false
            bar.schedulePersistThemeColors()
            return true
        }

        function setThemeAlpha(key, alpha) {
            if (!cfg.setThemeAlpha(key, alpha))
                return false
            bar.schedulePersistThemeColors()
            return true
        }

        function getThemeNumber(key) {
            return cfg.getThemeNumber(key)
        }

        function setThemeNumber(key, n) {
            if (!cfg.setThemeNumber(key, n))
                return false
            bar.schedulePersistThemeColors()
            return true
        }

        function setThemeFont(key, value) {
            if (!cfg.setThemeFont(key, value))
                return false
            bar.schedulePersistThemeColors()
            return true
        }

        // Full theme snapshot for Themes-panel undo
        function getThemeSnapshot() {
            return cfg.themeExport("Active")
        }

        function resetThemeColors() {
            cfg.themeReset()
            bar.persistThemeColors()
            bar.themeStatus = "Reset to Liquid glass defaults"
            return true
        }

        function applyThemeObject(obj) {
            if (!obj)
                return false
            const ok = cfg.themeApply(obj)
            if (ok) {
                bar.persistThemeColors()
                bar.themeStatus = "Theme applied"
            } else {
                bar.themeStatus = "Could not apply theme"
            }
            return ok
        }

        function applyThemePreset(id) {
            const builtins = cfg.themeBuiltinPresets()
            for (let i = 0; i < builtins.length; i++) {
                const p = builtins[i]
                const slug = (p.name || "").toLowerCase().replace(/\s+/g, "-")
                if (p.name === id || slug === id || ("builtin:" + slug) === id) {
                    bar.applyThemeObject(p)
                    bar.themeStatus = "Applied " + (p.name || id)
                    return true
                }
            }
            // Saved file id
            return bar.importTheme(id)
        }

        function themeBuiltinList() {
            const builtins = cfg.themeBuiltinPresets()
            const out = []
            for (let i = 0; i < builtins.length; i++) {
                const p = builtins[i]
                const slug = (p.name || "preset").toLowerCase().replace(/\s+/g, "-")
                let accent = ""
                if (p.colors && p.colors.accent && p.colors.accent.hex)
                    accent = String(p.colors.accent.hex)
                out.push({
                    id: "builtin:" + slug,
                    name: p.name || slug,
                    builtin: true,
                    path: "",
                    tone: p.tone === "light" ? "light" : "dark",
                    accent: accent
                })
            }
            return out
        }

        function refreshThemeSavedList() {
            themeListProc.running = false
            themeListProc.command = [bar.themeIoScript, "list"]
            themeListProc.running = true
        }

        Io.Process {
            id: themeListProc
            running: false
            stdout: Io.StdioCollector {
                id: themeListStdout
                onStreamFinished: {
                    try {
                        const raw = (themeListStdout.text || "").trim()
                        if (!raw.length) {
                            bar.themeSavedList = []
                            return
                        }
                        const arr = JSON.parse(raw)
                        bar.themeSavedList = Array.isArray(arr) ? arr : []
                    } catch (e) {
                        bar.themeSavedList = []
                    }
                }
            }
        }

        property string _themeExportName: ""
        property string _themeImportTarget: ""

        function exportTheme(name) {
            const n = (name || "").trim()
            if (!n.length) {
                bar.themeStatus = "Enter a name to export"
                return false
            }
            bar._themeExportName = n
            let json = ""
            try {
                json = JSON.stringify(cfg.themeExport(n))
            } catch (e) {
                bar.themeStatus = "Export failed"
                return false
            }
            themeExportProc.running = false
            // Python avoids shell-quoting issues with JSON payloads
            themeExportProc.command = [
                "python3", "-c",
                "import json,os,re,sys\n"
                + "name=sys.argv[1]\n"
                + "data=json.loads(sys.argv[2])\n"
                + "root=os.path.expanduser('~/.config/quickshell/themes')\n"
                + "os.makedirs(root, exist_ok=True)\n"
                + "safe=re.sub(r'[^A-Za-z0-9._-]+','_', name).strip('_') or 'theme'\n"
                + "path=os.path.join(root, safe + '.json')\n"
                + "if not data.get('name'): data['name']=name\n"
                + "data['version']=int(data.get('version') or 1)\n"
                + "open(path,'w',encoding='utf-8').write(json.dumps(data, indent=2) + chr(10))\n"
                + "print(path)\n",
                n,
                json
            ]
            themeExportProc.running = true
            return true
        }

        Io.Process {
            id: themeExportProc
            running: false
            stdout: Io.StdioCollector {
                id: themeExportStdout
                onStreamFinished: {
                    const path = (themeExportStdout.text || "").trim()
                    if (path.length)
                        bar.themeStatus = "Saved preset: " + (bar._themeExportName || path)
                    else
                        bar.themeStatus = "Preset saved"
                    bar.refreshThemeSavedList()
                }
            }
            stderr: Io.StdioCollector {
                id: themeExportStderr
                onStreamFinished: {
                    const err = (themeExportStderr.text || "").trim()
                    if (err.length)
                        bar.themeStatus = err
                }
            }
        }

        function importTheme(nameOrPath) {
            const t = (nameOrPath || "").trim()
            if (!t.length) {
                bar.themeStatus = "Pick a theme to import"
                return false
            }
            // Built-in presets are not files — apply from code
            if (("" + t).indexOf("builtin:") === 0) {
                return bar.applyThemePreset(t)
            }
            bar._themeImportTarget = t
            themeImportProc.running = false
            themeImportProc.command = [bar.themeIoScript, "import", t]
            themeImportProc.running = true
            return true
        }

        Io.Process {
            id: themeImportProc
            running: false
            stdout: Io.StdioCollector {
                id: themeImportStdout
                onStreamFinished: {
                    const raw = (themeImportStdout.text || "").trim()
                    if (!raw.length) {
                        bar.themeStatus = "Import failed (empty)"
                        return
                    }
                    try {
                        const obj = JSON.parse(raw)
                        if (bar.applyThemeObject(obj))
                            bar.themeStatus = "Loaded " + (obj.name || bar._themeImportTarget)
                    } catch (e) {
                        bar.themeStatus = "Import failed (bad JSON)"
                    }
                }
            }
            stderr: Io.StdioCollector {
                id: themeImportStderr
                onStreamFinished: {
                    const err = (themeImportStderr.text || "").trim()
                    if (err.length)
                        bar.themeStatus = err
                }
            }
        }

        // Save current colors as a named user preset (same as export)
        function saveThemePreset(name) {
            const n = (name || "").trim()
            if (!n.length) {
                bar.themeStatus = "Enter a name for the preset"
                return false
            }
            // Never overwrite built-in names as "removable" confusion — still allow save
            // with that display name; file lives in themes/ and is user-owned.
            const ok = bar.exportTheme(n)
            if (ok)
                bar.themeStatus = "Saving preset…"
            return ok
        }

        function deleteThemePreset(nameOrPath) {
            const t = (nameOrPath || "").trim()
            if (!t.length) {
                bar.themeStatus = "Nothing to remove"
                return false
            }
            // Built-ins are code-defined and cannot be removed
            if (("" + t).indexOf("builtin:") === 0) {
                bar.themeStatus = "Built-in presets cannot be removed"
                return false
            }
            const builtins = cfg.themeBuiltinPresets()
            for (let i = 0; i < builtins.length; i++) {
                const p = builtins[i]
                const slug = (p.name || "").toLowerCase().replace(/\s+/g, "-")
                if (p.name === t || slug === t) {
                    bar.themeStatus = "Built-in presets cannot be removed"
                    return false
                }
            }
            bar._themeDeleteTarget = t
            themeDeleteProc.running = false
            themeDeleteProc.command = [bar.themeIoScript, "delete", t]
            themeDeleteProc.running = true
            return true
        }

        property string _themeDeleteTarget: ""

        Io.Process {
            id: themeDeleteProc
            running: false
            stdout: Io.StdioCollector {
                id: themeDeleteStdout
                onStreamFinished: {
                    const msg = (themeDeleteStdout.text || "").trim()
                    bar.themeStatus = msg.length ? msg.replace(/^deleted /, "Removed ") : "Preset removed"
                    bar.refreshThemeSavedList()
                }
            }
            stderr: Io.StdioCollector {
                id: themeDeleteStderr
                onStreamFinished: {
                    const err = (themeDeleteStderr.text || "").trim()
                    if (err.length)
                        bar.themeStatus = err
                }
            }
        }

        function refreshSetupSavedList() {
            setupListProc.running = false
            setupListProc.command = [bar.profileIoScript, "list"]
            setupListProc.running = true
        }

        Io.Process {
            id: setupListProc
            running: false
            stdout: Io.StdioCollector {
                id: setupListStdout
                onStreamFinished: {
                    try {
                        const raw = (setupListStdout.text || "").trim()
                        if (!raw.length) {
                            bar.setupSavedList = []
                            return
                        }
                        const arr = JSON.parse(raw)
                        bar.setupSavedList = Array.isArray(arr) ? arr : []
                    } catch (e) {
                        bar.setupSavedList = []
                    }
                }
            }
        }

        property string _setupExportName: ""
        property string _setupImportTarget: ""
        property string _setupDeleteTarget: ""

        function saveSetup(name) {
            const n = (name || "").trim()
            if (!n.length) {
                bar.themeStatus = "Enter a name for the setup"
                return false
            }
            bar.persistBarLayout()
            bar.persistThemeColors()
            bar._setupExportName = n
            setupExportProc.running = false
            setupExportProc.command = [bar.profileIoScript, "export", n]
            setupExportProc.running = true
            bar.themeStatus = "Saving setup…"
            return true
        }

        Io.Process {
            id: setupExportProc
            running: false
            stdout: Io.StdioCollector {
                id: setupExportStdout
                onStreamFinished: {
                    const path = (setupExportStdout.text || "").trim()
                    if (path.length)
                        bar.themeStatus = "Saved setup: " + (bar._setupExportName || path)
                    else
                        bar.themeStatus = "Setup saved"
                    bar.refreshSetupSavedList()
                }
            }
            stderr: Io.StdioCollector {
                id: setupExportStderr
                onStreamFinished: {
                    const err = (setupExportStderr.text || "").trim()
                    if (err.length)
                        bar.themeStatus = err
                }
            }
        }

        function applyLayoutSnapshot(layout) {
            if (!layout || typeof layout !== "object")
                return false
            const keys = Object.keys(layout)
            for (let i = 0; i < keys.length; i++) {
                const k = keys[i]
                try {
                    if (barLayoutAdapter[k] !== undefined)
                        barLayoutAdapter[k] = layout[k]
                } catch (e) {}
            }
            bar.applyBarLayoutFromAdapter()
            bar.persistBarLayout()
            return true
        }

        function loadSetup(nameOrPath) {
            const t = (nameOrPath || "").trim()
            if (!t.length) {
                bar.themeStatus = "Pick a setup to load"
                return false
            }
            bar._setupImportTarget = t
            setupImportProc.running = false
            setupImportProc.command = [bar.profileIoScript, "import", t]
            setupImportProc.running = true
            return true
        }

        Io.Process {
            id: setupImportProc
            running: false
            stdout: Io.StdioCollector {
                id: setupImportStdout
                onStreamFinished: {
                    const raw = (setupImportStdout.text || "").trim()
                    if (!raw.length) {
                        bar.themeStatus = "Load setup failed (empty)"
                        return
                    }
                    try {
                        const obj = JSON.parse(raw)
                        if (obj.theme)
                            bar.applyThemeObject(obj.theme)
                        if (obj.layout)
                            bar.applyLayoutSnapshot(obj.layout)
                        bar.themeStatus = "Loaded setup " + (obj.name || bar._setupImportTarget)
                    } catch (e) {
                        bar.themeStatus = "Load setup failed (bad JSON)"
                    }
                }
            }
            stderr: Io.StdioCollector {
                id: setupImportStderr
                onStreamFinished: {
                    const err = (setupImportStderr.text || "").trim()
                    if (err.length)
                        bar.themeStatus = err
                }
            }
        }

        function deleteSetup(nameOrPath) {
            const t = (nameOrPath || "").trim()
            if (!t.length) {
                bar.themeStatus = "Nothing to remove"
                return false
            }
            bar._setupDeleteTarget = t
            setupDeleteProc.running = false
            setupDeleteProc.command = [bar.profileIoScript, "delete", t]
            setupDeleteProc.running = true
            return true
        }

        Io.Process {
            id: setupDeleteProc
            running: false
            stdout: Io.StdioCollector {
                id: setupDeleteStdout
                onStreamFinished: {
                    const msg = (setupDeleteStdout.text || "").trim()
                    bar.themeStatus = msg.length ? msg.replace(/^deleted /, "Removed ") : "Setup removed"
                    bar.refreshSetupSavedList()
                }
            }
            stderr: Io.StdioCollector {
                id: setupDeleteStderr
                onStreamFinished: {
                    const err = (setupDeleteStderr.text || "").trim()
                    if (err.length)
                        bar.themeStatus = err
                }
            }
        }

        function getThemeColor(key) {
            return cfg.getThemeColor(key)
        }

        function colorToHex(c) {
            return cfg.colorToHex(c)
        }

        function colorWithAlpha(c, a) {
            return cfg.colorWithAlpha(c, a)
        }

        function persistBarLayout() {
            bar._barLayoutWriteGuard = true
            barLayoutAdapter.barPosition = bar.barPosition
            barLayoutAdapter.barLayoutMode = root.barLayoutMode === "dual" ? "dual" : "classic"
            barLayoutAdapter.barSpanFull = !!root.barSpanFull
            barLayoutAdapter.panelSpanFull = !!root.panelSpanFull
            barLayoutAdapter.panelSizeScale = (root.panelSizeScale >= 0.8 && root.panelSizeScale <= 1.4)
                    ? root.panelSizeScale : 0
            barLayoutAdapter.audioViewMode = (root.audioViewMode === 0 || root.audioViewMode === 1)
                    ? root.audioViewMode : 2
            barLayoutAdapter.topBarAlign = bar.coerceAlign(root.topBarAlign)
            barLayoutAdapter.bottomBarAlign = bar.coerceAlign(root.bottomBarAlign)
            barLayoutAdapter.showLeftBar = !!root.showLeftBar
            barLayoutAdapter.showRightBar = !!root.showRightBar
            barLayoutAdapter.leftBarAlign = bar.coerceAlign(root.leftBarAlign)
            barLayoutAdapter.rightBarAlign = bar.coerceAlign(root.rightBarAlign)
            barLayoutAdapter.leftBarSpanFull = !!root.leftBarSpanFull
            barLayoutAdapter.rightBarSpanFull = !!root.rightBarSpanFull
            barLayoutAdapter.uiScaleManual = cfg.uiScaleManual
            barLayoutAdapter.barEdgeMargin = Math.max(0, Math.min(48, cfg.barEdgeMargin || 0))
            barLayoutAdapter.barSizeScale = Math.max(0.8, Math.min(1.4, Number(cfg.barSizeScale) || 1.0))
            barLayoutAdapter.flushWindowsToBar = !!cfg.flushWindowsToBar
            barLayoutAdapter.tooltipDelay = Math.max(0, Math.min(3000, cfg.tooltipDelay || 0))
            try {
                barLayoutAdapter.tooltipAlignJson = JSON.stringify(root.tooltipAlign || {})
            } catch (e) {
                barLayoutAdapter.tooltipAlignJson = "{}"
            }
            barLayoutAdapter.clockFormat = root.clockFormat
            barLayoutAdapter.clockFont = cfg.clockFont || ""
            barLayoutAdapter.clockFontScale = Number(cfg.clockFontScale) || 1.0
            try {
                const json = JSON.stringify(root.widgetLayout || [])
                barLayoutAdapter.widgetLayoutJson = json
                if (root.barLayoutMode === "dual")
                    barLayoutAdapter.widgetLayoutDualJson = json
                else
                    barLayoutAdapter.widgetLayoutClassicJson = json
            } catch (e) {
                barLayoutAdapter.widgetLayoutJson = "[]"
            }
            try {
                barLayoutAdapter.quickLaunchAppsJson = JSON.stringify(root.quickLaunchApps || [])
            } catch (e) {
                barLayoutAdapter.quickLaunchAppsJson = "[]"
            }
            barLayoutAdapter.wallpaperDir = root.wallpaperDir || ""
            barLayoutAdapter.wallpaperCurrent = root.wallpaperCurrent || ""
            barLayoutAdapter.wallpaperTileSize = Math.max(100, Math.min(260, root.wallpaperTileSize || 148))
            barLayoutAdapter.screenshotDir = String(root.screenshotDir || "")
            barLayoutAdapter.hasOverviewPrefs = true
            barLayoutAdapter.ovLayout = root.ovLayout
            barLayoutAdapter.ovAnchor = root.ovAnchor
            barLayoutAdapter.ovGap = root.ovGap
            barLayoutAdapter.ovPadding = root.ovPadding
            barLayoutAdapter.ovPaddingTop = root.ovPaddingTop
            barLayoutAdapter.ovPaddingBottom = root.ovPaddingBottom
            barLayoutAdapter.ovMaxScale = root.ovMaxScale
            barLayoutAdapter.ovDuration = root.ovDuration
            barLayoutAdapter.ovPreviewRound = root.ovPreviewRound
            barLayoutAdapter.ovBlur = root.ovBlur
            barLayoutAdapter.ovBackdropBlur = root.ovBackdropBlur
            barLayoutAdapter.ovSwitchAnimation = root.ovSwitchAnimation
            barLayoutAdapter.ovSwitchDuration = root.ovSwitchDuration
            barLayoutAdapter.ovMoveAnimation = root.ovMoveAnimation
            barLayoutAdapter.ovMoveDuration = root.ovMoveDuration
            barLayoutAdapter.ovStripOffset = root.ovStripOffset
            barLayoutAdapter.ovStripHeight = root.ovStripHeight
            barLayoutAdapter.ovStripWidth = root.ovStripWidth
            barLayoutAdapter.ovStripCardMax = root.ovStripCardMax
            barLayoutAdapter.ovStripMargin = root.ovStripMargin
            barLayoutAdapter.ovStripGap = root.ovStripGap
            barLayoutAdapter.ovStripCardRound = root.ovStripCardRound
            barLayoutAdapter.ovHoverBorder = root.ovHoverBorder
            barLayoutAdapter.ovSelectBorder = root.ovSelectBorder
            barLayoutAdapter.ovLivePreviews = root.ovLivePreviews
            barLayoutAdapter.ovShowWindowLabels = root.ovShowWindowLabels
            barLayoutAdapter.ovShowWsLabels = root.ovShowWsLabels
            barLayoutAdapter.ovStripPreviews = root.ovStripPreviews
            barLayoutAdapter.ovNumberLabels = root.ovNumberLabels
            barLayoutAdapter.ovDynamic = root.ovDynamic
            barLayoutAdapter.ovAutodelete = root.ovAutodelete
            barLayoutAdapter.ovShowEmpty = root.ovShowEmpty
            barLayoutAdapter.ovShowSpecial = root.ovShowSpecial
            barLayoutAdapter.ovStripAllCard = root.ovStripAllCard
            barLayoutAdapter.ovShowAll = root.ovShowAll
            barLayoutAdapter.ovSwitchOnNew = root.ovSwitchOnNew
            barLayoutAdapter.ovSwitchOnDrop = root.ovSwitchOnDrop
            barLayoutAdapter.ovDragToSwap = root.ovDragToSwap
            barLayoutAdapter.ovFocusFollowsMouse = root.ovFocusFollowsMouse
            barLayoutAdapter.ovScrollSwitches = root.ovScrollSwitches
            barLayoutAdapter.ovExitOnClick = root.ovExitOnClick
            barLayoutAdapter.ovExitOnSwitch = root.ovExitOnSwitch
            try {
                barLayoutAdapter.widgetScalesJson = JSON.stringify(root.widgetScales || {})
            } catch (e) {
                barLayoutAdapter.widgetScalesJson = "{}"
            }
            barLayoutAdapter.showLauncherPill = root.showLauncherPill
            barLayoutAdapter.showQuickLaunchPill = root.showQuickLaunchPill
            barLayoutAdapter.showWorkspacesPill = root.showWorkspacesPill
            barLayoutAdapter.showStatsWidget = root.showStatsWidget
            barLayoutAdapter.showTrayPill = root.showTrayPill
            barLayoutAdapter.showNetworkPanel = root.showNetworkPanel
            barLayoutAdapter.showBluetoothPill = root.showBluetoothPill
            barLayoutAdapter.showAudioPill = root.showAudioPill
            barLayoutAdapter.showClockPill = root.showClockPill
            barLayoutAdapter.showNotificationPill = root.showNotificationPill
            barLayoutAdapter.showPowerPill = root.showPowerPill
            barLayoutAdapter.showOpacityPill = root.showOpacityPill
            barLayoutAdapter.showTailscalePill = root.showTailscalePill
            barLayoutAdapter.showFreshRssPill = root.showFreshRssPill
            barLayoutAdapter.showHyprInspPill = root.showHyprInspPill
            barLayoutAdapter.showControlBarPill = root.showControlBarPill
            barLayoutAdapter.showActiveWindowPill = root.showActiveWindowPill
            barLayoutAdapter.activeWindowPillCorner = bar.coerceActiveWindowCorner(root.activeWindowPillCorner)
            try {
                barLayoutAdapter.activeWindowExcludesJson = JSON.stringify(
                    bar.normalizeActiveWindowExcludes(root.activeWindowExcludes))
            } catch (e) {
                barLayoutAdapter.activeWindowExcludesJson = "[\"hypr-screensaver\"]"
            }
            barLayoutAdapter.hasColorPresetPrefs = true
            barLayoutAdapter.showColorPresets = root.showColorPresets
            barLayoutAdapter.hasWorkspacePrefs = true
            barLayoutAdapter.showMagicWorkspacePill = root.showMagicWorkspacePill
            barLayoutAdapter.wsMinimumShown = root.wsMinimumShown
            barLayoutAdapter.wsShowOnlyActive = root.wsShowOnlyActive
            barLayoutAdapter.wsShowNumbers = root.wsShowNumbers !== false
            barLayoutAdapter.notificationAutoExpand = !!root.notificationAutoExpand
            barLayoutAdapter.notificationStaggerRows = root.notificationStaggerRows !== false
            barLayoutAdapter.notificationClearOnBoot = !!root.notificationClearOnBoot
            barLayoutAdapter.notificationShowCount = root.notificationShowCount !== false
            barLayoutAdapter.notificationCorner = bar.coerceNotificationCorner(root.notificationCorner)
            barLayoutAdapter.notificationTimeout = bar.coerceNotificationTimeout(root.notificationTimeout)
            barLayoutAdapter.wsStartupWorkspace = root.wsStartupWorkspace
            barLayoutAdapter.wsStartupCloseMagic = root.wsStartupCloseMagic
            barLayoutAdapter.wsIconSpecialCustom = String(root.wsIconSpecialCustom || "")
            barLayoutAdapter.wsSpecialNameCustom = String(root.wsSpecialNameCustom || "")
            barLayoutAdapter.wsSpecialFont = String(root.wsSpecialFont || "")
            barLayoutAdapter.wsSpecialFontPx = bar.wsFontPxClamp(root.wsSpecialFontPx)
            barLayoutAdapter.wsSpecialText = String(root.wsSpecialText || "")
            barLayoutAdapter.wsSpecialBold = root.wsSpecialBold !== false
            barLayoutAdapter.wsSpecialItalic = !!root.wsSpecialItalic
            barLayoutAdapter.wsSpecialColor = String(root.wsSpecialColor || "")
            barLayoutAdapter.hasLauncherPrefs = true
            barLayoutAdapter.launcherIconCustom = String(root.launcherIconCustom || "")
            barLayoutAdapter.launcherIconPx = root.launcherIconPx || 0
            barLayoutAdapter.launcherCommandCustom = String(root.launcherCommandCustom || "")
            barLayoutAdapter.hasWsSlots = !!root.hasWsSlots
            try {
                barLayoutAdapter.wsSlotsJson = JSON.stringify(root.wsSlots || [])
            } catch (e) {
                barLayoutAdapter.wsSlotsJson = "[]"
            }
            barLayoutAdapter.hasStatPrefs = true
            barLayoutAdapter.showStatCpu = root.showStatCpu
            barLayoutAdapter.showStatVram = root.showStatVram
            barLayoutAdapter.showStatMem = root.showStatMem
            barLayoutAdapter.showStatGpu = root.showStatGpu
            barLayoutAdapter.showStatGauges = root.showStatGauges
            barLayoutAdapter.statTerminal = root.statTerminal
            barLayoutAdapter.statLaunchButton = root.statLaunchButton
            barLayoutAdapter.showNetworkFullIp = root.showNetworkFullIp
            barLayoutAdapter.showNetworkLastOctet = root.showNetworkLastOctet
            barLayoutAdapter.showNetworkDeviceName = root.showNetworkDeviceName
            barLayoutAdapter.hasAudioMenuPrefs = true
            barLayoutAdapter.showEchoCancelInMenu = root.showEchoCancelInMenu
            barLayoutAdapter.showAudioSummary = root.showAudioSummary
            barLayoutAdapter.showAudioDefaults = root.showAudioDefaults
            barLayoutAdapter.showAudioLevelMeters = root.showAudioLevelMeters
            barLayoutAdapter.audioSummaryExpanded = root.audioSummaryExpanded
            barLayoutAdapter.audioDefaultsExpanded = root.audioDefaultsExpanded
            barLayoutAdapter.hasFreshRssPrefs = true
            barLayoutAdapter.freshRssFiltersExpanded = root.freshRssFiltersExpanded
            barLayoutAdapter.hasDockPrefs = true
            barLayoutAdapter.dockEffect = root.dockEffect || "both"
            barLayoutAdapter.dockMaxScale = Math.max(1.05, Math.min(1.8, Number(root.dockMaxScale) || 1.28))
            barLayoutAdapter.dockRadius = Math.max(32, Math.min(160, Math.round(root.dockRadius || 72)))
            barLayoutAdapter.dockJumpPx = Math.max(4, Math.min(20, Math.round(root.dockJumpPx || 8)))
            barLayoutAdapter.dockScope = root.dockScope === "quicklaunch" ? "quicklaunch" : "icons"
            barLayoutFile.writeAdapter()
            // Clear guard after filesystem watcher has had a chance to fire.
            Qt.callLater(function() {
                Qt.callLater(function() {
                    bar._barLayoutWriteGuard = false
                })
            })
        }

        // --- Options panel setters (shared with shell IPC) ---
        function setShowControlBarPill(enabled) {
            root.showControlBarPill = !!enabled
            persistBarLayout()
        }
        function setShowColorPresets(enabled) {
            root.showColorPresets = !!enabled
            persistBarLayout()
        }
        function setShowStatCpu(enabled) {
            root.showStatCpu = !!enabled
            persistBarLayout()
        }
        function setShowStatVram(enabled) {
            root.showStatVram = !!enabled
            persistBarLayout()
        }
        function setShowStatMem(enabled) {
            root.showStatMem = !!enabled
            persistBarLayout()
        }
        function setShowStatGpu(enabled) {
            root.showStatGpu = !!enabled
            persistBarLayout()
        }
        function setShowStatGauges(enabled) {
            root.showStatGauges = !!enabled
            persistBarLayout()
        }
        function setStatTerminal(name) {
            const t = String(name || "").trim()
            if (!t.length)
                return
            root.statTerminal = t
            persistBarLayout()
        }
        function setStatLaunchButton(button) {
            root.statLaunchButton = String(button || "").toLowerCase() === "left" ? "left" : "right"
            persistBarLayout()
        }
        function setShowNetworkFullIp(enabled) {
            root.showNetworkFullIp = !!enabled
            persistBarLayout()
        }
        function setShowNetworkLastOctet(enabled) {
            root.showNetworkLastOctet = !!enabled
            persistBarLayout()
        }
        function setShowNetworkDeviceName(enabled) {
            root.showNetworkDeviceName = !!enabled
            persistBarLayout()
        }
        function setDockEffect(mode) {
            const m = String(mode || "off")
            root.dockEffect = (m === "off" || m === "magnify" || m === "jump" || m === "both") ? m : "off"
            persistBarLayout()
        }
        function setDockMaxScale(v) {
            root.dockMaxScale = Math.max(1.05, Math.min(1.8, Number(v) || 1.28))
            persistBarLayout()
        }
        function setDockRadius(v) {
            root.dockRadius = Math.max(32, Math.min(160, Math.round(Number(v) || 72)))
            persistBarLayout()
        }
        function setDockJumpPx(v) {
            root.dockJumpPx = Math.max(4, Math.min(20, Math.round(Number(v) || 8)))
            persistBarLayout()
        }
        function setDockScope(mode) {
            root.dockScope = String(mode) === "quicklaunch" ? "quicklaunch" : "icons"
            persistBarLayout()
        }

        function ovClamp(value, lo, hi, fallback) {
            let n = Number(value)
            if (n !== n)
                n = fallback
            if (n < lo)
                n = lo
            if (n > hi)
                n = hi
            return n
        }

        function applyOverviewFromAdapter() {
            const layout = String(barLayoutAdapter.ovLayout || "rows")
            root.ovLayout = (layout === "grid" || layout === "natural") ? layout : "rows"
            const anchor = String(barLayoutAdapter.ovAnchor || "top")
            root.ovAnchor = (anchor === "bottom" || anchor === "left" || anchor === "right") ? anchor : "top"
            root.ovGap = Math.round(bar.ovClamp(barLayoutAdapter.ovGap, 0, 120, 34))
            root.ovPadding = Math.round(bar.ovClamp(barLayoutAdapter.ovPadding, 0, 200, 80))
            root.ovPaddingTop = Math.round(bar.ovClamp(barLayoutAdapter.ovPaddingTop, 0, 160, 40))
            root.ovPaddingBottom = Math.round(bar.ovClamp(barLayoutAdapter.ovPaddingBottom, 0, 160, 70))
            root.ovMaxScale = bar.ovClamp(barLayoutAdapter.ovMaxScale, 0.2, 1.5, 1)
            root.ovDuration = Math.round(bar.ovClamp(barLayoutAdapter.ovDuration, 0, 800, 360))
            root.ovPreviewRound = Math.round(bar.ovClamp(barLayoutAdapter.ovPreviewRound, 0, 32, 12))
            root.ovBlur = bar.ovClamp(barLayoutAdapter.ovBlur, 0, 1, 1)
            root.ovBackdropBlur = !!barLayoutAdapter.ovBackdropBlur
            root.ovSwitchAnimation = !!barLayoutAdapter.ovSwitchAnimation
            root.ovSwitchDuration = Math.round(bar.ovClamp(barLayoutAdapter.ovSwitchDuration, 0, 800, 260))
            root.ovMoveAnimation = !!barLayoutAdapter.ovMoveAnimation
            root.ovMoveDuration = Math.round(bar.ovClamp(barLayoutAdapter.ovMoveDuration, 0, 800, 240))
            root.ovStripOffset = Math.round(bar.ovClamp(barLayoutAdapter.ovStripOffset, 0, 120, 0))
            root.ovStripHeight = Math.round(bar.ovClamp(barLayoutAdapter.ovStripHeight, 72, 640, 150))
            root.ovStripWidth = Math.round(bar.ovClamp(barLayoutAdapter.ovStripWidth, 72, 640, 150))
            root.ovStripCardMax = Math.round(bar.ovClamp(barLayoutAdapter.ovStripCardMax, 160, 960, 300))
            root.ovStripMargin = Math.round(bar.ovClamp(barLayoutAdapter.ovStripMargin, 0, 64, 22))
            root.ovStripGap = Math.round(bar.ovClamp(barLayoutAdapter.ovStripGap, 0, 64, 18))
            root.ovStripCardRound = Math.round(bar.ovClamp(barLayoutAdapter.ovStripCardRound, 0, 28, 10))
            root.ovHoverBorder = Math.round(bar.ovClamp(barLayoutAdapter.ovHoverBorder, 0, 8, 3))
            root.ovSelectBorder = Math.round(bar.ovClamp(barLayoutAdapter.ovSelectBorder, 0, 8, 3))
            root.ovLivePreviews = barLayoutAdapter.ovLivePreviews !== false
            root.ovShowWindowLabels = barLayoutAdapter.ovShowWindowLabels !== false
            root.ovShowWsLabels = barLayoutAdapter.ovShowWsLabels !== false
            root.ovStripPreviews = barLayoutAdapter.ovStripPreviews !== false
            root.ovNumberLabels = !!barLayoutAdapter.ovNumberLabels
            root.ovDynamic = barLayoutAdapter.ovDynamic !== false
            root.ovAutodelete = barLayoutAdapter.ovAutodelete !== false
            root.ovShowEmpty = barLayoutAdapter.ovShowEmpty !== false
            root.ovShowSpecial = !!barLayoutAdapter.ovShowSpecial
            root.ovStripAllCard = !!barLayoutAdapter.ovStripAllCard
            root.ovShowAll = !!barLayoutAdapter.ovShowAll
            root.ovSwitchOnNew = barLayoutAdapter.ovSwitchOnNew !== false
            root.ovSwitchOnDrop = !!barLayoutAdapter.ovSwitchOnDrop
            root.ovDragToSwap = barLayoutAdapter.ovDragToSwap !== false
            root.ovFocusFollowsMouse = barLayoutAdapter.ovFocusFollowsMouse !== false
            root.ovScrollSwitches = barLayoutAdapter.ovScrollSwitches !== false
            root.ovExitOnClick = barLayoutAdapter.ovExitOnClick !== false
            root.ovExitOnSwitch = !!barLayoutAdapter.ovExitOnSwitch
            root.hasOverviewPrefs = true
            Qt.callLater(function () { bar.syncOverviewBlur() })
        }

        // Hyprland blurs the overview layer. BackgroundEffect on the panel blanks it.
        function syncOverviewBlur() {
            // layer_rule is config, not a dispatcher. A dispatched function can still add it.
            const on = !!root.ovBackdropBlur
            Hyprland.dispatch("function() hl.layer_rule({ name = \"quickshell-overview-blur\", match = { namespace = \"^quickshell-overview$\" }, blur = "
                + (on ? "true" : "false") + ", ignore_alpha = 0.05 }) end")
        }

        // Options → Overview. persist === false updates the live value without writing.
        function setOverview(key, value, persist) {
            const k = String(key || "")
            switch (k) {
            case "layout": {
                const v = String(value || "")
                root.ovLayout = (v === "grid" || v === "natural") ? v : "rows"
                break
            }
            case "anchor": {
                const v = String(value || "")
                root.ovAnchor = (v === "bottom" || v === "left" || v === "right") ? v : "top"
                break
            }
            case "gap": root.ovGap = Math.round(bar.ovClamp(value, 0, 120, 34)); break
            case "padding": root.ovPadding = Math.round(bar.ovClamp(value, 0, 200, 80)); break
            case "paddingTop": root.ovPaddingTop = Math.round(bar.ovClamp(value, 0, 160, 40)); break
            case "paddingBottom": root.ovPaddingBottom = Math.round(bar.ovClamp(value, 0, 160, 70)); break
            case "maxScale": root.ovMaxScale = bar.ovClamp(value, 0.2, 1.5, 1); break
            case "duration": root.ovDuration = Math.round(bar.ovClamp(value, 0, 800, 360)); break
            case "round": root.ovPreviewRound = Math.round(bar.ovClamp(value, 0, 32, 12)); break
            case "blur": root.ovBlur = bar.ovClamp(value, 0, 1, 1); break
            case "backdropBlur": root.ovBackdropBlur = !!value; bar.syncOverviewBlur(); break
            case "switchAnim": root.ovSwitchAnimation = !!value; break
            case "switchDuration": root.ovSwitchDuration = Math.round(bar.ovClamp(value, 0, 800, 260)); break
            case "moveAnim": root.ovMoveAnimation = !!value; break
            case "moveDuration": root.ovMoveDuration = Math.round(bar.ovClamp(value, 0, 800, 240)); break
            case "stripOffset": root.ovStripOffset = Math.round(bar.ovClamp(value, 0, 120, 0)); break
            case "stripHeight": root.ovStripHeight = Math.round(bar.ovClamp(value, 72, 640, 150)); break
            case "stripWidth": root.ovStripWidth = Math.round(bar.ovClamp(value, 72, 640, 150)); break
            case "cardMax": root.ovStripCardMax = Math.round(bar.ovClamp(value, 160, 960, 300)); break
            case "stripMargin": root.ovStripMargin = Math.round(bar.ovClamp(value, 0, 64, 22)); break
            case "stripGap": root.ovStripGap = Math.round(bar.ovClamp(value, 0, 64, 18)); break
            case "stripRound": root.ovStripCardRound = Math.round(bar.ovClamp(value, 0, 28, 10)); break
            case "hoverBorder": root.ovHoverBorder = Math.round(bar.ovClamp(value, 0, 8, 3)); break
            case "selectBorder": root.ovSelectBorder = Math.round(bar.ovClamp(value, 0, 8, 3)); break
            case "live": root.ovLivePreviews = !!value; break
            case "windowLabels": root.ovShowWindowLabels = !!value; break
            case "wsLabels": root.ovShowWsLabels = !!value; break
            case "stripPreviews": root.ovStripPreviews = !!value; break
            case "numberLabels": root.ovNumberLabels = !!value; break
            case "dynamic": root.ovDynamic = !!value; break
            case "autodelete": root.ovAutodelete = !!value; break
            case "showEmpty": root.ovShowEmpty = !!value; break
            case "showSpecial": root.ovShowSpecial = !!value; break
            case "allCard": root.ovStripAllCard = !!value; break
            case "showAll": root.ovShowAll = !!value; break
            case "switchOnNew": root.ovSwitchOnNew = !!value; break
            case "switchOnDrop": root.ovSwitchOnDrop = !!value; break
            case "dragSwap": root.ovDragToSwap = !!value; break
            case "focusFollowsMouse": root.ovFocusFollowsMouse = !!value; break
            case "scroll": root.ovScrollSwitches = !!value; break
            case "exitOnClick": root.ovExitOnClick = !!value; break
            case "exitOnSwitch": root.ovExitOnSwitch = !!value; break
            default:
                return
            }
            root.hasOverviewPrefs = true
            if (persist !== false)
                persistBarLayout()
        }
        function dockMagnifyOn() {
            const e = String(root.dockEffect || "off")
            return e === "magnify" || e === "both"
        }
        function dockJumpOn() {
            const e = String(root.dockEffect || "off")
            return e === "jump" || e === "both"
        }
        function dockScopeAll() {
            return String(root.dockScope || "icons") !== "quicklaunch"
        }
        function dockSelfMag(hovered) {
            void root.dockEffect
            void root.dockScope
            void root.dockMaxScale
            if (!hovered || !bar.dockMagnifyOn() || !bar.dockScopeAll())
                return 1
            return Math.max(1.05, Math.min(1.8, Number(root.dockMaxScale) || 1.28))
        }
        function dockGrowUpFor(item) {
            try {
                if (bar.isDualLayout())
                    return bar.edgeForItem(item) === "bottom"
            } catch (e) {}
            return bar.barPosition === "bottom"
        }
        function dockJumpPixels() {
            return Math.max(4, Math.min(20, Math.round(root.dockJumpPx || 8)))
        }
        function setShowEchoCancelInMenu(enabled) {
            root.showEchoCancelInMenu = !!enabled
            persistBarLayout()
        }
        function setShowAudioSummary(enabled) {
            root.showAudioSummary = !!enabled
            persistBarLayout()
        }
        function setShowAudioDefaults(enabled) {
            root.showAudioDefaults = !!enabled
            persistBarLayout()
        }
        function setShowAudioLevelMeters(enabled) {
            root.showAudioLevelMeters = !!enabled
            persistBarLayout()
        }
        function setAudioSummaryExpanded(enabled) {
            root.audioSummaryExpanded = !!enabled
            persistBarLayout()
        }
        function setAudioDefaultsExpanded(enabled) {
            root.audioDefaultsExpanded = !!enabled
            persistBarLayout()
        }
        function setFreshRssFiltersExpanded(enabled) {
            root.freshRssFiltersExpanded = !!enabled
            persistBarLayout()
        }
        function setShowMagicWorkspacePill(enabled) {
            root.showMagicWorkspacePill = !!enabled
            persistBarLayout()
        }
        // Hyprland special name. Blank or the Config default stores as "" so the
        // factory name stays the fallback. Strips a pasted "special:" prefix and
        // drops quotes/spaces so the dispatch string cannot break.
        function wsSpecialNameNorm(v) {
            let s = String(v || "").trim()
            if (s.length >= 8 && s.substring(0, 8).toLowerCase() === "special:")
                s = s.substring(8).trim()
            s = s.replace(/[^A-Za-z0-9_.-]/g, "")
            if (s.length > 32)
                s = s.substring(0, 32)
            if (!s.length || s === cfg.wsSpecialName)
                return ""
            return s
        }
        function wsSymbolClamp(v) {
            let label = String(v || "").trim()
            const chars = Array.from(label)
            if (chars.length > 3)
                label = chars.slice(0, 3).join("")
            return label
        }
        function wsTextClamp(v) {
            let text = String(v || "").trim()
            const chars = Array.from(text)
            if (chars.length > 24)
                text = chars.slice(0, 24).join("")
            return text
        }
        function normalizeWsSpecial(raw) {
            const src = raw || {}
            let font = String(src.font || "").trim()
            if (font.length > 120)
                font = font.substring(0, 120)
            return {
                name: bar.wsSpecialNameNorm(src.name),
                label: bar.wsSymbolClamp(src.label),
                font: font,
                fontPx: bar.wsFontPxClamp(src.fontPx),
                text: bar.wsTextClamp(src.text),
                bold: src.bold === undefined ? true : !!src.bold,
                italic: !!src.italic,
                color: bar.wsColorNorm(src.color)
            }
        }
        // Writes the special-workspace fields. Caller persists (Apply goes through commitWsSlots).
        function applyWsSpecialFields(spec) {
            const s = bar.normalizeWsSpecial(spec)
            root.wsSpecialNameCustom = s.name
            root.wsIconSpecialCustom = s.label
            root.wsSpecialFont = s.font
            root.wsSpecialFontPx = s.fontPx
            root.wsSpecialText = s.text
            root.wsSpecialBold = s.bold
            root.wsSpecialItalic = s.italic
            root.wsSpecialColor = s.color
        }
        // Normalize a user color to "#rrggbb" ("" = use theme default). Accepts
        // "#rgb"/"rgb"/"#rrggbb"/"rrggbb"; anything else clears to "".
        function wsColorNorm(v) {
            let c = String(v || "").trim()
            if (!c.length)
                return ""
            if (c.charAt(0) !== "#")
                c = "#" + c
            if (/^#[0-9a-fA-F]{3}$/.test(c))
                c = "#" + c.charAt(1) + c.charAt(1) + c.charAt(2) + c.charAt(2) + c.charAt(3) + c.charAt(3)
            if (/^#[0-9a-fA-F]{6}$/.test(c))
                return c.toLowerCase()
            return ""
        }
        function sanitizeWsSlots(slots) {
            const used = {}
            const out = []
            const list = slots || []
            for (let i = 0; i < list.length && out.length < 10; i++) {
                const raw = list[i] || {}
                let id = Math.round(Number(raw.id))
                if (!(id >= 1) || id > 10 || used[id])
                    continue
                used[id] = true
                // Symbol: max 3 characters (code points — Nerd Font glyphs and
                // emoji can be surrogate pairs, so never slice raw UTF-16).
                let label = String(raw.label || "").trim()
                const labelChars = Array.from(label)
                if (labelChars.length > 3)
                    label = labelChars.slice(0, 3).join("")
                // "" stays "" — no built-in icon fallback; an empty symbol
                // leaves the pill with just the word label and number.
                let font = String(raw.font || "").trim()
                if (font.length > 120)
                    font = font.substring(0, 120)
                let text = String(raw.text || "").trim()
                const textChars = Array.from(text)
                if (textChars.length > 24)
                    text = textChars.slice(0, 24).join("")
                out.push({
                    id: id,
                    label: label,
                    font: font,
                    fontPx: bar.wsFontPxClamp(raw.fontPx),
                    text: text,
                    bold: raw.bold === undefined ? true : !!raw.bold,
                    italic: !!raw.italic,
                    color: bar.wsColorNorm(raw.color)
                })
            }
            return out
        }
        function defaultWsSlots(count) {
            let n = Math.round(Number(count))
            if (!(n >= 1))
                n = 1
            if (n > 10)
                n = 10
            const out = []
            for (let i = 1; i <= n; i++)
                out.push({ id: i, label: bar.wsIconForId(i), font: "", fontPx: 0, text: "", bold: true, italic: false, color: "" })
            return out
        }
        function wsSlotsEffective() {
            if (root.hasWsSlots && root.wsSlots && root.wsSlots.length)
                return bar.sanitizeWsSlots(root.wsSlots)
            return bar.defaultWsSlots(root.wsMinimumShown)
        }
        function wsLabelForId(id) {
            const n = Math.round(Number(id))
            const slots = bar.wsSlotsEffective()
            for (let i = 0; i < slots.length; i++) {
                if (slots[i].id === n)
                    return String(slots[i].label || "")
            }
            return ""
        }
        function wsFontForId(id) {
            const n = Math.round(Number(id))
            const slots = bar.wsSlotsEffective()
            for (let i = 0; i < slots.length; i++) {
                if (slots[i].id === n)
                    return String(slots[i].font || "")
            }
            return ""
        }
        // 0 means “use bar.wsIconSize”. Explicit sizes are 8–32 px and apply to the emoji only.
        function wsFontPxClamp(v) {
            const n = Math.round(Number(v))
            if (n >= 8 && n <= 32)
                return n
            return 0
        }
        function wsFontPxForId(id) {
            const n = Math.round(Number(id))
            const slots = bar.wsSlotsEffective()
            for (let i = 0; i < slots.length; i++) {
                if (slots[i].id === n)
                    return bar.wsFontPxClamp(slots[i].fontPx)
            }
            return 0
        }
        // Word label next to the symbol on the pill ("" = none).
        function wsTextForId(id) {
            const n = Math.round(Number(id))
            const slots = bar.wsSlotsEffective()
            for (let i = 0; i < slots.length; i++) {
                if (slots[i].id === n)
                    return String(slots[i].text || "")
            }
            return ""
        }
        // Custom label color ("#rrggbb"); "" = theme state colors.
        function wsColorForId(id) {
            const n = Math.round(Number(id))
            const slots = bar.wsSlotsEffective()
            for (let i = 0; i < slots.length; i++) {
                if (slots[i].id === n)
                    return bar.wsColorNorm(slots[i].color)
            }
            return ""
        }
        // Bold/italic apply to symbol + label. Bold defaults true (historic look).
        function wsBoldForId(id) {
            const n = Math.round(Number(id))
            const slots = bar.wsSlotsEffective()
            for (let i = 0; i < slots.length; i++) {
                if (slots[i].id === n)
                    return slots[i].bold === undefined ? true : !!slots[i].bold
            }
            return true
        }
        function wsItalicForId(id) {
            const n = Math.round(Number(id))
            const slots = bar.wsSlotsEffective()
            for (let i = 0; i < slots.length; i++) {
                if (slots[i].id === n)
                    return !!slots[i].italic
            }
            return false
        }
        function nextFreeWsId(slots) {
            const used = {}
            const list = slots || []
            for (let i = 0; i < list.length; i++)
                used[Math.round(Number(list[i].id))] = true
            for (let id = 1; id <= 10; id++) {
                if (!used[id])
                    return id
            }
            return -1
        }
        function commitWsSlots(slots) {
            const clean = bar.sanitizeWsSlots(slots)
            const next = clean.length ? clean : bar.defaultWsSlots(1)
            root.wsSlots = next
            root.hasWsSlots = true
            root.wsMinimumShown = next.length
            persistBarLayout()
        }
        function setWsMinimumShown(count) {
            let n = Math.round(Number(count))
            if (!(n >= 1))
                n = 1
            if (n > 10)
                n = 10
            if (root.hasWsSlots) {
                const cur = bar.sanitizeWsSlots(root.wsSlots).slice()
                while (cur.length > n)
                    cur.pop()
                while (cur.length < n) {
                    const id = bar.nextFreeWsId(cur)
                    if (id < 0)
                        break
                    cur.push({ id: id, label: bar.wsIconForId(id), font: "", fontPx: 0 })
                }
                root.wsSlots = cur
                n = cur.length || 1
            }
            root.wsMinimumShown = n
            persistBarLayout()
        }
        function addWsSlot() {
            const base = bar.wsSlotsEffective().slice()
            if (base.length >= 10)
                return
            const id = bar.nextFreeWsId(base)
            if (id < 0)
                return
            base.push({ id: id, label: bar.wsIconForId(id), font: "", fontPx: 0 })
            bar.commitWsSlots(base)
        }
        function removeWsSlot(index) {
            const base = bar.wsSlotsEffective().slice()
            const i = Math.round(Number(index))
            if (base.length <= 1 || i < 0 || i >= base.length)
                return
            base.splice(i, 1)
            bar.commitWsSlots(base)
        }
        function moveWsSlot(index, delta) {
            const base = bar.wsSlotsEffective().slice()
            const i = Math.round(Number(index))
            const j = i + Math.round(Number(delta))
            if (i < 0 || j < 0 || i >= base.length || j >= base.length)
                return
            const tmp = base[i]
            base[i] = base[j]
            base[j] = tmp
            bar.commitWsSlots(base)
        }
        function setWsSlotLabel(index, label) {
            const base = bar.wsSlotsEffective().slice()
            const i = Math.round(Number(index))
            if (i < 0 || i >= base.length)
                return
            base[i] = {
                id: base[i].id,
                label: String(label || ""),
                font: String(base[i].font || ""),
                fontPx: bar.wsFontPxClamp(base[i].fontPx),
                text: String(base[i].text || ""),
                bold: base[i].bold === undefined ? true : !!base[i].bold,
                italic: !!base[i].italic,
                color: bar.wsColorNorm(base[i].color)
            }
            bar.commitWsSlots(base)
        }
        function setWsSlotFont(index, font) {
            const base = bar.wsSlotsEffective().slice()
            const i = Math.round(Number(index))
            if (i < 0 || i >= base.length)
                return
            base[i] = {
                id: base[i].id,
                label: base[i].label,
                font: String(font || ""),
                fontPx: bar.wsFontPxClamp(base[i].fontPx),
                text: String(base[i].text || ""),
                bold: base[i].bold === undefined ? true : !!base[i].bold,
                italic: !!base[i].italic,
                color: bar.wsColorNorm(base[i].color)
            }
            bar.commitWsSlots(base)
        }
        function setWsShowOnlyActive(enabled) {
            root.wsShowOnlyActive = !!enabled
            persistBarLayout()
        }
        function setWsShowNumbers(enabled) {
            root.wsShowNumbers = !!enabled
            persistBarLayout()
        }
        function setNotificationAutoExpand(enabled) {
            root.notificationAutoExpand = !!enabled
            persistBarLayout()
            if (root.notificationAutoExpand && notificationBell && notificationBell.expandAllHistory)
                notificationBell.expandAllHistory(true)
        }
        function setNotificationStaggerRows(enabled) {
            root.notificationStaggerRows = !!enabled
            persistBarLayout()
        }
        function setNotificationClearOnBoot(enabled) {
            root.notificationClearOnBoot = !!enabled
            persistBarLayout()
        }
        function setNotificationShowCount(enabled) {
            root.notificationShowCount = !!enabled
            persistBarLayout()
        }
        function coerceNotificationCorner(v) {
            const s = String(v || "")
            if (s === "topLeft" || s === "topRight" || s === "bottomLeft" || s === "bottomRight")
                return s
            return "bottomRight"
        }
        function coerceNotificationTimeout(v) {
            let n = Math.round(Number(v))
            if (!(n >= 0))
                n = 8
            if (n > 60)
                n = 60
            return n
        }
        property string _appliedNotificationCorner: ""
        property int _appliedNotificationTimeout: -1
        function applyNotificationToast() {
            const corner = bar.coerceNotificationCorner(root.notificationCorner)
            const timeout = bar.coerceNotificationTimeout(root.notificationTimeout)
            if (bar._appliedNotificationCorner === corner
                    && bar._appliedNotificationTimeout === timeout)
                return
            bar._appliedNotificationCorner = corner
            bar._appliedNotificationTimeout = timeout
            Quickshell.execDetached([
                "/home/crome/.config/quickshell/scripts/swaync-corner.py",
                corner,
                String(timeout)
            ])
        }
        function setNotificationCorner(corner) {
            const next = bar.coerceNotificationCorner(corner)
            if (root.notificationCorner !== next) {
                root.notificationCorner = next
                persistBarLayout()
            }
            bar.applyNotificationToast()
        }
        function setNotificationTimeout(seconds) {
            const next = bar.coerceNotificationTimeout(seconds)
            root.notificationTimeout = next
            persistBarLayout()
            bar.applyNotificationToast()
        }
        function setWsStartupWorkspace(workspace) {
            let n = Number(workspace)
            if (!(n >= 0))
                n = 0
            if (n > 10)
                n = 10
            root.wsStartupWorkspace = Math.round(n)
            persistBarLayout()
        }
        function setWsStartupCloseMagic(enabled) {
            root.wsStartupCloseMagic = !!enabled
            persistBarLayout()
        }
        function setEchoCancel(enabled) {
            if (audioPill && audioPill.setEchoCancelEnabled)
                audioPill.setEchoCancelEnabled(!!enabled)
        }
        function getEchoCancelEnabled() {
            return !!(audioPill && audioPill.echoCancelEnabled)
        }
        function setBluetoothAppletAutostart(enabled) {
            if (bluetoothPill && bluetoothPill.setAppletAutostart)
                bluetoothPill.setAppletAutostart(!!enabled)
        }
        function getBluetoothAppletAutostart() {
            return bluetoothPill ? !!bluetoothPill.bluemanAutostartEnabled : true
        }
        function refreshOptionsState() {
            // Nudge applets / echo-cancel to refresh status for Options panel
            try {
                if (audioPill && audioPill.refreshEchoCancelStatus)
                    audioPill.refreshEchoCancelStatus()
            } catch (e) {}
            try {
                if (bluetoothPill && bluetoothPill.refreshBluemanStatus)
                    bluetoothPill.refreshBluemanStatus()
            } catch (e3) {}
        }

        function setBarPosition(pos) {
            const next = (pos === "bottom") ? "bottom" : "top"
            if (bar.barPosition === next)
                return
            bar.barPosition = next
            persistBarLayout()
        }

        function toggleBarPosition() {
            setBarPosition(bar.barPosition === "top" ? "bottom" : "top")
        }

        function setBarLayoutMode(mode) {
            const next = (String(mode) === "dual") ? "dual" : "classic"
            if (root.barLayoutMode === next)
                return
            // Keep the layout the user is leaving so switching back restores it.
            try {
                const json = JSON.stringify(root.widgetLayout || [])
                if (root.barLayoutMode === "dual")
                    barLayoutAdapter.widgetLayoutDualJson = json
                else
                    barLayoutAdapter.widgetLayoutClassicJson = json
            } catch (e) {}

            root.barLayoutMode = next

            let loaded = null
            try {
                const raw = (next === "dual")
                    ? barLayoutAdapter.widgetLayoutDualJson
                    : barLayoutAdapter.widgetLayoutClassicJson
                if (raw && String(raw).length > 2)
                    loaded = JSON.parse(raw)
            } catch (e2) {}

            if (loaded && loaded.length)
                root.widgetLayout = bar.normalizeLayout(loaded, next)
            else
                root.widgetLayout = (next === "dual")
                    ? bar.cloneDualDefaultLayout()
                    : bar.cloneDefaultLayout()

            bar.applyWidgetLayout()
            persistBarLayout()
        }

        function toggleBarLayoutMode() {
            setBarLayoutMode(root.barLayoutMode === "dual" ? "classic" : "dual")
        }

        function coerceZone(zone, mode) {
            const m = mode || root.barLayoutMode || "classic"
            const z = String(zone || "")
            if (m === "dual") {
                // left/right are the edge bars. Do not fold them into top/bottom.
                if (z === "top" || z === "bottom" || z === "left" || z === "right")
                    return z
                if (z === "center")
                    return "top"
                return "top"
            }
            // Classic left/center/right are groups on the one horizontal bar.
            if (z === "center" || z === "right" || z === "left")
                return z
            if (z === "top")
                return "center"
            if (z === "bottom")
                return "right"
            return "left"
        }

        function cloneDefaultLayout() {
            const src = cfg.defaultWidgetLayout || []
            const out = []
            for (let i = 0; i < src.length; i++) {
                const e = src[i]
                if (!e || !e.id)
                    continue
                out.push({ id: String(e.id), zone: bar.coerceZone(e.zone, "classic") })
            }
            return out
        }

        function cloneDualDefaultLayout() {
            const src = cfg.defaultDualWidgetLayout || []
            const out = []
            for (let i = 0; i < src.length; i++) {
                const e = src[i]
                if (!e || !e.id)
                    continue
                out.push({ id: String(e.id), zone: bar.coerceZone(e.zone, "dual") })
            }
            return out
        }

        function cloneLayoutForMode(mode) {
            return (mode === "dual") ? bar.cloneDualDefaultLayout() : bar.cloneDefaultLayout()
        }

        function normalizeLayout(arr, mode) {
            const m = mode || root.barLayoutMode || "classic"
            const known = {}
            const cat = root.widgetCatalog
            for (let i = 0; i < cat.length; i++)
                known[cat[i].id] = true
            const out = []
            const seen = {}
            if (arr && arr.length) {
                for (let i = 0; i < arr.length; i++) {
                    const e = arr[i]
                    if (!e || !e.id)
                        continue
                    // Migrate legacy standalone "audio" layout entry into connectivity unit
                    let id = String(e.id)
                    if (id === "audio")
                        id = "connectivity"
                    const ok = known[id] || bar.isDividerId(id)
                    if (!ok || seen[id])
                        continue
                    seen[id] = true
                    out.push({
                        id: id,
                        zone: bar.coerceZone(e.zone, m)
                    })
                }
            }
            // Append any missing catalog ids at end of their default zones
            const defaults = bar.cloneLayoutForMode(m)
            for (let i = 0; i < defaults.length; i++) {
                if (!seen[defaults[i].id])
                    out.push(defaults[i])
            }
            return out
        }

        function widgetItemById(id) {
            const sid = String(id)
            const dm = sid.match(/^divider([1-8])$/)
            if (dm && typeof dividerRepeater !== "undefined" && dividerRepeater)
                return dividerRepeater.itemAt(Number(dm[1]) - 1)
            switch (sid) {
            case "launcher": return launcherPill
            case "quickLaunch": return quickLaunchPill
            case "freshRss": return freshRssPill
            case "workspaces": return workspacesPill
            case "stats": return sysStatsPill
            case "tray": return trayPill
            case "connectivity": return connectivityPill
            case "networkPanel": return networkPanel
            case "audio": return null  // audio lives inside connectivityPill
            case "clock": return clockPill
            case "notifications": return notificationBell
            case "hyprInsp": return hyprInspPill
            case "controlBar": return controlBarPill
            case "tailscale": return tailscalePill
            case "power": return powerMenu
            case "opacity": return opacityPill
            default: return null
            }
        }

        function assignWidgetChrome(w, chrome) {
            if (!w || chrome === undefined || chrome === null)
                return
            try {
                if (w.barBg !== undefined)
                    w.barBg = chrome
            } catch (e) {}
        }

        function applyWidgetLayout() {
            const dual = root.barLayoutMode === "dual"
            if (!widgetPool || !centerZone)
                return
            if (dual && !bottomCenterZone)
                return
            if (!dual && (!leftZone || !rightZone))
                return
            const layout = (root.widgetLayout && root.widgetLayout.length)
                ? root.widgetLayout
                : bar.cloneLayoutForMode(root.barLayoutMode)
            const items = []
            for (let i = 0; i < layout.length; i++) {
                const w = bar.widgetItemById(layout[i].id)
                if (w)
                    items.push(w)
            }
            // Park everything in the pool first (stable reparent order)
            for (let i = 0; i < items.length; i++)
                items[i].parent = widgetPool
            for (let i = 0; i < layout.length; i++) {
                const entry = layout[i]
                const w = bar.widgetItemById(entry.id)
                if (!w)
                    continue
                let zoneItem = centerZone
                let chrome = barBg
                if (dual) {
                    if (entry.zone === "bottom" && bottomCenterZone) {
                        zoneItem = bottomCenterZone
                        chrome = bottomBarBg
                    } else if (entry.zone === "left") {
                        if (!leftEdgeZone) {
                            w.parent = widgetPool
                            continue
                        }
                        zoneItem = leftEdgeZone
                        chrome = leftEdgeBg
                    } else if (entry.zone === "right") {
                        if (!rightEdgeZone) {
                            w.parent = widgetPool
                            continue
                        }
                        zoneItem = rightEdgeZone
                        chrome = rightEdgeBg
                    }
                } else {
                    // Classic left/right stay on the horizontal bar. They are not side bars.
                    zoneItem = entry.zone === "center" ? centerZone
                        : (entry.zone === "right" ? rightZone : leftZone)
                    chrome = barBg
                }
                w.parent = zoneItem
                bar.assignWidgetChrome(w, chrome)
                if (entry.id === "connectivity") {
                    bar.assignWidgetChrome(bluetoothPill, chrome)
                    bar.assignWidgetChrome(audioPill, chrome)
                }
            }
            bar.layoutEpoch++
        }

        function setClockFormat(fmt) {
            const next = String(fmt || "").trim()
            if (!next.length)
                return
            if (root.clockFormat === next)
                return
            root.clockFormat = next
            persistBarLayout()
        }

        function setClockFont(name) {
            const next = String(name || "").trim()
            if (cfg.clockFont === next)
                return
            cfg.clockFont = next
            persistBarLayout()
        }

        function setClockFontScale(scale) {
            var v = Number(scale)
            if (!(v > 0))
                return
            if (v < 0.70)
                v = 0.70
            if (v > 1.50)
                v = 1.50
            v = Math.round(v * 100) / 100
            if (Math.abs(cfg.clockFontScale - v) < 0.001)
                return
            cfg.clockFontScale = v
            persistBarLayout()
        }

        function isDividerId(id) {
            return /^divider[1-8]$/.test(String(id || ""))
        }

        function addWidgetDivider() {
            const layout = bar.normalizeLayout(root.widgetLayout, root.barLayoutMode)
            const used = {}
            for (let i = 0; i < layout.length; i++)
                used[layout[i].id] = true
            let id = ""
            for (let n = 1; n <= 8; n++) {
                const cand = "divider" + n
                if (!used[cand]) {
                    id = cand
                    break
                }
            }
            if (!id.length)
                return
            const dual = root.barLayoutMode === "dual"
            layout.push({ id: id, zone: dual ? "bottom" : "center" })
            root.widgetLayout = layout
            bar.applyWidgetLayout()
            persistBarLayout()
        }

        function removeWidgetDivider(id) {
            if (!bar.isDividerId(id))
                return
            const layout = bar.normalizeLayout(root.widgetLayout, root.barLayoutMode)
            const next = []
            for (let i = 0; i < layout.length; i++) {
                if (layout[i].id !== id)
                    next.push(layout[i])
            }
            root.widgetLayout = next
            bar.applyWidgetLayout()
            persistBarLayout()
        }

        function getWidgetVisible(id) {
            switch (String(id)) {
            case "launcher": return root.showLauncherPill
            case "quickLaunch": return root.showQuickLaunchPill
            case "freshRss": return root.showFreshRssPill
            case "workspaces": return root.showWorkspacesPill
            case "stats": return root.showStatsWidget
            case "tray": return root.showTrayPill
            case "connectivity": return root.showBluetoothPill || root.showAudioPill
            case "networkPanel": return root.showNetworkPanel
            case "bluetooth": return root.showBluetoothPill
            case "audio": return root.showAudioPill
            case "clock": return root.showClockPill
            case "notifications": return root.showNotificationPill
            case "hyprInsp": return root.showHyprInspPill
            case "controlBar": return root.showControlBarPill
            case "activeWindow": return root.showActiveWindowPill
            case "tailscale": return root.showTailscalePill
            case "power": return root.showPowerPill
            case "opacity": return root.showOpacityPill
            default:
                if (bar.isDividerId(id)) {
                    const layout = root.widgetLayout || []
                    for (let i = 0; i < layout.length; i++) {
                        if (layout[i] && layout[i].id === String(id))
                            return true
                    }
                    return false
                }
                return false
            }
        }

        function setWidgetVisible(id, enabled) {
            const on = !!enabled
            switch (String(id)) {
            case "launcher": root.showLauncherPill = on; break
            case "quickLaunch": root.showQuickLaunchPill = on; break
            case "freshRss": root.showFreshRssPill = on; break
            case "workspaces": root.showWorkspacesPill = on; break
            case "stats": root.showStatsWidget = on; break
            case "tray": root.showTrayPill = on; break
            case "connectivity":
                root.showBluetoothPill = on
                root.showAudioPill = on
                break
            case "networkPanel": root.showNetworkPanel = on; break
            case "bluetooth": root.showBluetoothPill = on; break
            case "audio": root.showAudioPill = on; break
            case "clock": root.showClockPill = on; break
            case "notifications": root.showNotificationPill = on; break
            case "hyprInsp": root.showHyprInspPill = on; break
            case "controlBar": root.showControlBarPill = on; break
            case "activeWindow": root.showActiveWindowPill = on; break
            case "tailscale": root.showTailscalePill = on; break
            case "power": root.showPowerPill = on; break
            case "opacity": root.showOpacityPill = on; break
            default:
                if (bar.isDividerId(id)) {
                    if (on)
                        bar.addWidgetDivider()
                    else
                        bar.removeWidgetDivider(id)
                    return
                }
                return
            }
            root.widgetVisTick++
            persistBarLayout()
        }

        function toggleWidgetVisible(id) {
            setWidgetVisible(id, !getWidgetVisible(id))
        }

        function setWidgetZone(id, zone) {
            const z = bar.coerceZone(zone, root.barLayoutMode)
            // Assigning a widget to a side bar turns that bar on so the widget is visible.
            if (root.barLayoutMode === "dual" && z === "left")
                root.showLeftBar = true
            if (root.barLayoutMode === "dual" && z === "right")
                root.showRightBar = true
            const layout = bar.normalizeLayout(root.widgetLayout, root.barLayoutMode)
            let found = false
            for (let i = 0; i < layout.length; i++) {
                if (layout[i].id === id) {
                    layout[i].zone = z
                    found = true
                    break
                }
            }
            if (!found)
                layout.push({ id: String(id), zone: z })
            root.widgetLayout = layout
            bar.applyWidgetLayout()
            persistBarLayout()
        }

        function moveWidget(id, delta) {
            const layout = bar.normalizeLayout(root.widgetLayout, root.barLayoutMode)
            let idx = -1
            for (let i = 0; i < layout.length; i++) {
                if (layout[i].id === id) {
                    idx = i
                    break
                }
            }
            if (idx < 0)
                return
            const zone = layout[idx].zone
            // Move among siblings in the same zone
            const zoneIdxs = []
            for (let i = 0; i < layout.length; i++) {
                if (layout[i].zone === zone)
                    zoneIdxs.push(i)
            }
            let posInZone = zoneIdxs.indexOf(idx)
            const newPos = posInZone + (delta < 0 ? -1 : 1)
            if (newPos < 0 || newPos >= zoneIdxs.length)
                return
            const swapWith = zoneIdxs[newPos]
            const tmp = layout[idx]
            layout[idx] = layout[swapWith]
            layout[swapWith] = tmp
            root.widgetLayout = layout
            bar.applyWidgetLayout()
            persistBarLayout()
        }

        function resetWidgetLayout() {
            root.widgetLayout = bar.cloneLayoutForMode(root.barLayoutMode)
            bar.applyWidgetLayout()
            persistBarLayout()
        }

        function cloneQuickLaunchApps() {
            const src = cfg.quickLaunchApps || []
            return bar.normalizeQuickLaunchApps(src)
        }

        function normalizeQuickLaunchApps(arr) {
            const out = []
            if (!arr || arr.length === undefined)
                return out
            for (let i = 0; i < arr.length; i++) {
                const e = arr[i]
                if (!e)
                    continue
                let command = e.command
                if (typeof command !== "string" && command && command.length !== undefined) {
                    const args = []
                    for (let j = 0; j < command.length; j++)
                        args.push(String(command[j]))
                    command = args
                } else if (command === undefined || command === null) {
                    command = ""
                } else {
                    command = String(command)
                }
                // Skip empty entries
                const hasCmd = (typeof command === "string")
                    ? command.length > 0
                    : (command.length > 0)
                if (!hasCmd && !(e.tooltip || e.icon || e.glyph))
                    continue
                const matchClass = []
                if (typeof e.matchClass === "string") {
                    const s = e.matchClass.trim()
                    if (s.length)
                        matchClass.push(s)
                } else if (e.matchClass && e.matchClass.length !== undefined) {
                    for (let j = 0; j < e.matchClass.length; j++) {
                        const s = String(e.matchClass[j] || "").trim()
                        if (s.length)
                            matchClass.push(s)
                    }
                }
                const item = {
                    icon: e.icon ? String(e.icon) : "",
                    glyph: e.glyph ? String(e.glyph) : "",
                    command: command,
                    tooltip: e.tooltip ? String(e.tooltip) : ""
                }
                if (matchClass.length)
                    item.matchClass = matchClass.length === 1 ? matchClass[0] : matchClass
                out.push(item)
            }
            return out
        }

        function setQuickLaunchApps(arr) {
            root.quickLaunchApps = bar.normalizeQuickLaunchApps(arr)
            persistBarLayout()
        }

        function addQuickLaunchApp(entry) {
            const list = bar.normalizeQuickLaunchApps(root.quickLaunchApps)
            const one = bar.normalizeQuickLaunchApps([entry])
            if (!one.length)
                return false
            list.push(one[0])
            root.quickLaunchApps = list
            persistBarLayout()
            return true
        }

        function removeQuickLaunchApp(index) {
            const list = bar.normalizeQuickLaunchApps(root.quickLaunchApps)
            const i = Number(index)
            if (!(i >= 0) || i >= list.length)
                return
            list.splice(i, 1)
            root.quickLaunchApps = list
            persistBarLayout()
        }

        function moveQuickLaunchApp(index, delta) {
            const list = bar.normalizeQuickLaunchApps(root.quickLaunchApps)
            const i = Number(index)
            const d = Number(delta) || 0
            const j = i + d
            if (!(i >= 0) || i >= list.length || j < 0 || j >= list.length)
                return
            const tmp = list[i]
            list[i] = list[j]
            list[j] = tmp
            root.quickLaunchApps = list
            persistBarLayout()
        }

        function resetQuickLaunchApps() {
            root.quickLaunchApps = bar.cloneQuickLaunchApps()
            persistBarLayout()
        }

        function setWallpaperDir(dir) {
            const d = String(dir || "").trim()
            if (!d.length)
                return
            root.wallpaperDir = d
            persistBarLayout()
        }

        function setWallpaperCurrent(path) {
            root.wallpaperCurrent = String(path || "")
            persistBarLayout()
        }

        function applyWallpaper(path) {
            const p = String(path || "").trim()
            if (!p.length)
                return
            const script = cfg.wallpaperApplyScript || ""
            const mon = cfg.wallpaperMonitor || "DP-1"
            if (!script.length)
                return
            Quickshell.execDetached([script, p, mon])
            root.wallpaperCurrent = p
            persistBarLayout()
        }

        function setWallpaperTileSize(n) {
            let v = Math.round(Number(n))
            if (!(v > 0))
                return
            if (v < 100)
                v = 100
            if (v > 260)
                v = 260
            if (root.wallpaperTileSize === v)
                return
            root.wallpaperTileSize = v
            wallpaperTilePersistTimer.restart()
        }

        function setScreenshotDir(dir) {
            root.screenshotDir = String(dir || "").trim()
            persistBarLayout()
        }

        function widgetScale(id) {
            const key = String(id || "")
            const m = root.widgetScales || {}
            let s = 1.0
            try {
                if (m[key] !== undefined && m[key] !== null)
                    s = Number(m[key])
            } catch (e) {}
            if (!(s > 0))
                s = 1.0
            // Floor at 80% — below that labels/icons start colliding even when
            // fonts/gauges scale (especially Sys Stats and Quick Launch).
            if (s < 0.8)
                s = 0.8
            if (s > 1.8)
                s = 1.8
            return s
        }

        // Height stays at the global pill height — scale is horizontal only.
        function widgetPillH(id) {
            return pillHeight
        }

        // Scale a base width (or any horizontal metric) by the widget's size factor.
        function widgetW(id, base) {
            const b = Number(base)
            if (!(b > 0))
                return 0
            return Math.max(1, Math.round(b * widgetScale(id)))
        }

        // Debounce disk writes while dragging size sliders (avoid thrashing bar-layout.json).
        Timer {
            id: scalePersistTimer
            interval: 280
            repeat: false
            onTriggered: bar.persistBarLayout()
        }

        Timer {
            id: barGeomPersistTimer
            interval: 280
            repeat: false
            onTriggered: bar.persistBarLayout()
        }

        Timer {
            id: wallpaperTilePersistTimer
            interval: 280
            repeat: false
            onTriggered: bar.persistBarLayout()
        }

        function setWidgetScale(id, scale) {
            const key = String(id || "")
            if (!key.length)
                return
            let s = Number(scale)
            if (!(s > 0))
                return
            if (s < 0.8)
                s = 0.8
            if (s > 1.8)
                s = 1.8
            // Round to 2 decimals for stable UI / fewer no-op updates
            s = Math.round(s * 100) / 100
            const cur = root.widgetScales || {}
            const prev = (cur[key] !== undefined && cur[key] !== null) ? Number(cur[key]) : 1.0
            if (Math.abs(prev - s) < 0.001)
                return
            const next = {}
            const keys = Object.keys(cur)
            for (let i = 0; i < keys.length; i++)
                next[keys[i]] = cur[keys[i]]
            next[key] = s
            root.widgetScales = next
            // Live UI updates via property binding; persist shortly after drag settles
            scalePersistTimer.restart()
        }

        function resetWidgetScales() {
            scalePersistTimer.stop()
            root.widgetScales = ({})
            persistBarLayout()
        }

        readonly property alias notificationSubscribe: cfg.notificationSubscribe
        readonly property alias notificationSyncIntervalMs: cfg.notificationSyncIntervalMs
        readonly property alias notificationDndAccent: cfg.notificationDndAccent

        function notificationCommand(action) {
            return cfg.notificationCommand(action)
        }

        function notificationCmdArray(action) {
            const cmd = cfg.notificationCommand(action)
            if (!cmd || cmd.length === undefined || cmd.length <= 0)
                return []
            const args = []
            for (let i = 0; i < cmd.length; i++)
                args.push(cmd[i])
            return args
        }

        function execNotificationCommand(action) {
            const args = notificationCmdArray(action)
            if (args.length <= 0)
                return
            Quickshell.execDetached(args)
        }

        function notificationUsesLiveSubscribe() {
            return cfg.notificationUsesLiveSubscribe()
        }

        function notificationSupportsDnd() {
            return cfg.notificationSupportsDnd()
        }

        function notificationSupportsClearAll() {
            return cfg.notificationSupportsClearAll()
        }

        function notificationSyncEnabled() {
            return cfg.notificationSyncEnabled()
        }

        function refreshNotificationState() {
            if (notificationBell && notificationBell.refreshState)
                notificationBell.refreshState()
        }

        function powerCmdArray(action) {
            const cmd = cfg.powerCommand(action)
            if (!cmd || cmd.length === undefined || cmd.length <= 0)
                return []
            const args = []
            for (let i = 0; i < cmd.length; i++)
                args.push(cmd[i])
            return args
        }

        function execPowerCommand(action) {
            const cmd = cfg.powerCommand(action)
            if (cmd === undefined || cmd === null)
                return
            if (typeof cmd === "string") {
                if (cmd.length > 0)
                    Quickshell.execDetached(["sh", "-c", cmd])
                return
            }
            const args = powerCmdArray(action)
            if (args.length > 0)
                Quickshell.execDetached(args)
        }

        function powerMenuItems() {
            return cfg.powerMenuItems()
        }

        // --- Base palette
        property alias bg: cfg.bg
        property alias surface: cfg.surface
        property alias text: cfg.text
        property alias subtext: cfg.subtext
        property alias barText: cfg.barText
        property alias overlay: cfg.overlay
        property alias accent: cfg.accent
        property alias muted: cfg.muted
        property alias todayBg: cfg.todayBg
        property alias weekday: cfg.weekday
        property alias clock: cfg.clock
        property alias statTempCool: cfg.statTempCool
        property alias statTempWarm: cfg.statTempWarm
        property alias statTempHot: cfg.statTempHot
        readonly property alias statValueSeparator: cfg.statValueSeparator

        // --- Glassmorphic tokens (writable for Colors panel live editing)
        property alias glassBg: cfg.glassBg
        property alias glassBorder: cfg.glassBorder
        property alias glassHighlight: cfg.glassHighlight
        property alias glassPillBg: cfg.glassPillBg
        property alias glassHover: cfg.glassHover
        property alias glassPopupBg: cfg.glassPopupBg
        property alias glassPopupBorder: cfg.glassPopupBorder
        property alias glassPopupHighlight: cfg.glassPopupHighlight
        property alias pillBg: cfg.pillBg
        property alias pillBorder: cfg.pillBorder
        property alias pillHover: cfg.pillHover

        // --- State colors (writable for Colors panel)
        property alias pillHoverBorder: cfg.pillHoverBorder
        property alias iconHoverBg: cfg.iconHoverBg
        property alias controlHoverBg: cfg.controlHoverBg
        property alias buttonBg: cfg.buttonBg
        property alias controlActiveBg: cfg.controlActiveBg
        property alias popupButtonHoverBg: cfg.popupButtonHoverBg
        property alias buttonText: cfg.buttonText
        property alias buttonTextActive: cfg.buttonTextActive

        // --- Theme editor (Colors panel)
        readonly property alias themeUiRows: cfg.themeUiRows
        readonly property alias themeVolumeTierUiRows: cfg.themeVolumeTierUiRows
        readonly property alias themeMicVolumeTierUiRows: cfg.themeMicVolumeTierUiRows
        readonly property alias themeStatUtilTierUiRows: cfg.themeStatUtilTierUiRows
        readonly property alias themeStatCpuTierUiRows: cfg.themeStatCpuTierUiRows
        readonly property alias themeStatMemTierUiRows: cfg.themeStatMemTierUiRows
        readonly property alias themeStatGpuTierUiRows: cfg.themeStatGpuTierUiRows
        readonly property alias themeStatVramTierUiRows: cfg.themeStatVramTierUiRows
        readonly property alias themeStatTempUiRows: cfg.themeStatTempUiRows
        readonly property alias themeEditableNumbers: cfg.themeEditableNumbers
        readonly property string themeIoScript: "/home/crome/.config/quickshell/scripts/theme-io.sh"
        readonly property string profileIoScript: "/home/crome/.config/quickshell/scripts/profile-io.sh"
        property string themeStatus: ""
        property var themeSavedList: []
        property var setupSavedList: []
        property bool _themeWriteGuard: false
        property bool _themePersistScheduled: false

        // --- Radii
        property alias barRadius: cfg.barRadius
        property alias pillRadius: cfg.pillRadius
        property alias popupRadius: cfg.popupRadius
        property alias popupRadiusLarge: cfg.popupRadiusLarge
        property alias buttonRadius: cfg.buttonRadius
        property alias smallButtonRadius: cfg.smallButtonRadius
        property alias sliderRadius: cfg.sliderRadius
        property alias workspaceRadius: cfg.workspaceRadius
        readonly property alias controlBorderWidth: cfg.controlBorderWidth

        // --- Spacing & padding
        property alias sideMargin: cfg.sideMargin
        readonly property alias barContentHMargin: cfg.barContentHMargin
        readonly property alias barContentVMargin: cfg.barContentVMargin
        readonly property alias pillHPadding: cfg.pillHPadding
        readonly property alias popupPadding: cfg.popupPadding
        readonly property alias popupPaddingSmall: cfg.popupPaddingSmall
        readonly property alias popupHeaderHighlightHeight: cfg.popupHeaderHighlightHeight
        readonly property alias popupTitleSize: cfg.popupTitleSize
        readonly property alias popupSectionSize: cfg.popupSectionSize
        readonly property alias popupHintSize: cfg.popupHintSize
        readonly property alias popupSpacing: cfg.popupSpacing
        readonly property alias popupSpacingTight: cfg.popupSpacingTight
        readonly property alias popupSectionSpacing: cfg.popupSectionSpacing
        readonly property alias popupGridSpacing: cfg.popupGridSpacing
        readonly property alias widgetSpacing: cfg.widgetSpacing
        readonly property alias iconTextGap: cfg.iconTextGap
        readonly property alias dualAudioSidePadding: cfg.dualAudioSidePadding

        // --- Sizing & bar position (barPosition is runtime-mutable; Config is the default)
        property string barPosition: "top"
        // Clock format is owned on root (persisted); bar exposes it for ClockPill / control bar.
        property alias clockFormat: root.clockFormat
        readonly property alias clockFormatPresets: cfg.clockFormatPresets
        property alias clockFont: cfg.clockFont
        property alias clockFontScale: cfg.clockFontScale
        readonly property alias clockFontResolved: cfg.clockFontResolved
        readonly property alias clockFontFace: cfg.clockFontFace
        readonly property alias pillChipInset: cfg.pillChipInset
        readonly property alias pillFaceTopPad: cfg.pillFaceTopPad
        property alias barEdgeMargin: cfg.barEdgeMargin
        property alias barSizeScale: cfg.barSizeScale
        property alias flushWindowsToBar: cfg.flushWindowsToBar
        readonly property alias popupBarGap: cfg.popupBarGap
        readonly property alias barHeight: cfg.barHeight
        // Hyprland general:gaps_out. CSS order is top, right, bottom, left.
        property int hyprGapsOutTop: 14
        property int hyprGapsOutRight: 14
        property int hyprGapsOutBottom: 14
        property int hyprGapsOutLeft: 14
        // Exclusive zone for this window: Auto-equivalent, or flush (minus gaps_out + inner pad).
        readonly property int edgeExclusiveZone: {
            void flushWindowsToBar
            void barEdgeMargin
            void barHeight
            void barContentVMargin
            void hyprGapsOutTop
            void hyprGapsOutBottom
            void barIsTopEdge
            return exclusiveZoneFor(barIsTopEdge)
        }
        function exclusiveZoneFor(isTop) {
            var h = cfg.barHeight
            var edge = cfg.barEdgeMargin || 0
            var inner = cfg.barContentVMargin || 0
            var hypr = isTop ? hyprGapsOutTop : hyprGapsOutBottom
            if (!(hypr >= 0))
                hypr = 14
            var base = h + edge
            if (!cfg.flushWindowsToBar)
                return base
            return Math.max(0, base - inner - hypr)
        }
        // Thickness of a side bar plus its screen-edge margin. Flush pulls tiled
        // windows in by the inner pad and that edge's gaps_out.
        function sideExclusiveZoneFor(isLeft) {
            var thick = cfg.barHeight
            var edge = cfg.barEdgeMargin || 0
            var inner = cfg.barContentVMargin || 0
            var hypr = isLeft ? hyprGapsOutLeft : hyprGapsOutRight
            if (!(hypr >= 0))
                hypr = 14
            var base = thick + edge
            if (!cfg.flushWindowsToBar)
                return base
            return Math.max(0, base - inner - hypr)
        }
        // Keep side bars in the gap between the horizontal bars so the glass does not overlap them.
        function sideTopInset() {
            var edge = bar.barEdgeMargin || 0
            var topOn = root.barLayoutMode === "dual" || bar.barPosition === "top"
            if (!topOn)
                return edge
            return bar.barHeight + edge
        }
        function sideBottomInset() {
            var edge = bar.barEdgeMargin || 0
            var bottomOn = root.barLayoutMode === "dual" || bar.barPosition === "bottom"
            if (!bottomOn)
                return edge
            var h = (root.barLayoutMode === "dual") ? bar.panelBarHeight() : bar.barHeight
            return h + edge
        }
        function parseHyprGapsOut(text) {
            try {
                var j = JSON.parse(text)
                var raw = (j && j.css !== undefined) ? String(j.css) : ""
                var css = raw.trim().split(/\s+/)
                var nums = []
                for (var i = 0; i < css.length; i++) {
                    var n = parseInt(css[i], 10)
                    if (!isNaN(n))
                        nums.push(n)
                }
                if (nums.length >= 4) {
                    hyprGapsOutTop = nums[0]
                    hyprGapsOutRight = nums[1]
                    hyprGapsOutBottom = nums[2]
                    hyprGapsOutLeft = nums[3]
                } else if (nums.length === 1) {
                    hyprGapsOutTop = nums[0]
                    hyprGapsOutRight = nums[0]
                    hyprGapsOutBottom = nums[0]
                    hyprGapsOutLeft = nums[0]
                } else if (j && j.int !== undefined) {
                    var v = Number(j.int)
                    if (v >= 0) {
                        hyprGapsOutTop = v
                        hyprGapsOutRight = v
                        hyprGapsOutBottom = v
                        hyprGapsOutLeft = v
                    }
                }
            } catch (e) {}
        }
        function refreshHyprGapsOut() {
            hyprGapsOutProc.running = false
            hyprGapsOutProc.running = true
        }
        Io.Process {
            id: hyprGapsOutProc
            command: ["hyprctl", "getoption", "general:gaps_out", "-j"]
            running: true
            stdout: Io.StdioCollector {
                onStreamFinished: bar.parseHyprGapsOut(text)
            }
        }
        // This window sits on the top edge in dual mode, or when classic is pinned top.
        readonly property bool barIsTopEdge: root.barLayoutMode === "dual" || barPosition === "top"
        // Screen-edge gap is only barEdgeMargin (window margin). Do not add barContentVMargin
        // on the outer side — that is what left a visible strip at "Gap from edge: 0".
        readonly property bool barGlassFlush: barEdgeMargin <= 0
        readonly property alias barTopMargin: cfg.barTopMargin
        readonly property alias barPositionIconTop: cfg.barPositionIconTop
        readonly property alias barPositionIconBottom: cfg.barPositionIconBottom
        readonly property alias hyprResolutionBin: cfg.hyprResolutionBin
        readonly property alias uiScale: cfg.uiScale
        readonly property alias uiScaleManual: cfg.uiScaleManual
        readonly property alias uiDesignWidth: cfg.uiDesignWidth
        function sp(n) { return cfg.sp(n) }

        // Widget catalog + layout helpers for BarControlBar
        readonly property alias widgetCatalog: root.widgetCatalog
        readonly property alias widgetLayout: root.widgetLayout
        readonly property alias barLayoutMode: root.barLayoutMode
        property int layoutEpoch: 0
        readonly property var bottomBarWindow: bottomBar
        readonly property var controlBarItem: controlBarPill
        readonly property var topBarChrome: barBg
        readonly property var bottomBarChrome: bottomBarBg

        function isDualLayout() {
            return root.barLayoutMode === "dual"
        }

        function edgeForItem(item) {
            if (!bar.isDualLayout())
                return barPosition
            var p = item
            var hops = 0
            while (p && hops < 32) {
                if (p === leftEdgeBar || p === leftEdgeBg || p === leftEdgeStack || p === leftEdgeZone)
                    return "left"
                if (p === rightEdgeBar || p === rightEdgeBg || p === rightEdgeStack || p === rightEdgeZone)
                    return "right"
                if (p === bottomBar || p === bottomBarBg || p === bottomCenterZone)
                    return "bottom"
                if (p === barBg || p === centerZone || p === leftZone || p === rightZone)
                    return "top"
                p = p.parent
                hops++
            }
            return "top"
        }

        function chromeForItem(item) {
            if (!bar.isDualLayout())
                return barBg
            var edge = bar.edgeForItem(item)
            if (edge === "bottom")
                return bottomBarBg
            if (edge === "left")
                return leftEdgeBg
            if (edge === "right")
                return rightEdgeBg
            return barBg
        }

        function popupAnchorWindow(item) {
            if (bar.isDualLayout() && bar.edgeForItem(item) === "bottom")
                return bottomBar
            return bar
        }

        function controlPopupEdge() {
            if (!bar.isDualLayout())
                return barPosition
            return bar.edgeForItem(controlBarPill)
        }

        // Control strip PopupWindow is parented to `bar` (the top/classic window)
        // and must stay anchored there. Dual + gear-on-bottom uses a screen-relative
        // Y so the strip sits above the bottom bar instead of reparenting the popup.
        function controlPopupAnchorY(popupHeight, gap) {
            return bar.popupAnchorY(popupHeight, gap, controlBarPill)
        }

        function popupX(item, localX, popupWidth, extraOffset) {
            var extra = extraOffset || 0
            var edge = barPosition
            if (bar.isDualLayout() && item)
                edge = bar.edgeForItem(item)
            // Side-bar popups open inward, next to the edge bar. Layer-shell side
            // windows report a local origin, so mapToGlobal X is not a screen X
            // and a right-bar click was opening on the left of the monitor.
            // Place from the anchor window's edges instead.
            if (edge === "left" || edge === "right") {
                var screenWSide = 1920
                try {
                    if (bar.width > 100)
                        screenWSide = bar.width
                    else if (bar.screen && bar.screen.width)
                        screenWSide = bar.screen.width
                } catch (eSideX) {}
                var gapX = bar.popupBarGap || 8
                var thick = (bar.barHeight || 0) + (bar.barEdgeMargin || 0)
                var sideX = (edge === "right")
                    ? (screenWSide - thick - popupWidth - gapX)
                    : (thick + gapX)
                sideX += extra
                var minSideX = 12
                var maxSideX = screenWSide - popupWidth - 12
                if (maxSideX < minSideX)
                    maxSideX = minSideX
                return Math.max(minSideX, Math.min(sideX, maxSideX))
            }
            var chrome = bar.chromeForItem(item)
            var pos
            try {
                pos = item.mapToItem(chrome, localX, 0)
            } catch (e) {
                pos = { x: localX, y: 0 }
            }
            var originX = 0
            try {
                originX = chrome ? chrome.x : bar.sideMargin
            } catch (e2) {
                originX = bar.sideMargin
            }
            var x = originX + pos.x - (popupWidth / 2) + extra
            var win = bar.popupAnchorWindow(item)
            var screenW = 1920
            try {
                if (win && win.screen && win.screen.width)
                    screenW = win.screen.width
                else if (bar.screen && bar.screen.width)
                    screenW = bar.screen.width
            } catch (e3) {}
            var minX = 12
            var maxX = screenW - popupWidth - 12
            if (maxX < minX)
                maxX = minX
            return Math.max(minX, Math.min(x, maxX))
        }

        function placePopup(popup, item, popupW, popupH, gap, localX, extraX, extraY) {
            if (!popup || !popup.anchor)
                return
            // Always keep the popup on `bar`. Pointing it at the dual bottom window
            // made bottom-bar menus unclickable and hitch whenever they resized.
            if (popup.anchor.window !== bar)
                popup.anchor.window = bar
            var lx = (localX !== undefined && localX !== null) ? localX : (item ? item.width / 2 : 0)
            popup.anchor.rect.x = bar.popupX(item, lx, popupW, extraX || 0)
            popup.anchor.rect.y = bar.popupAnchorY(popupH, gap, item) + (extraY || 0)
            popup.anchor.rect.width = 1
            popup.anchor.rect.height = 1
        }

        // Popup Y anchor — opens below the bar (top) or above it (bottom).
        // Optional `item` selects the dual-mode edge. Dual popups stay anchored
        // to `bar` (top window); bottom-edge Y is screen-relative.
        function popupAnchorY(popupHeight, gap, item) {
            var spacing = (gap !== undefined) ? gap : popupBarGap
            var edge = barPosition
            if (bar.isDualLayout())
                edge = (item !== undefined && item !== null) ? bar.edgeForItem(item) : "top"
            if (edge === "left" || edge === "right") {
                var screenHSide = 1080
                try {
                    if (bar.screen && bar.screen.height)
                        screenHSide = bar.screen.height
                } catch (eSideY) {}
                var mid = screenHSide / 2
                try {
                    if (item && item.mapToGlobal) {
                        var c = item.mapToGlobal(item.width / 2, item.height / 2)
                        if (c && c.y !== undefined)
                            mid = c.y
                    }
                } catch (eSideY2) {}
                var sideY = Math.round(mid - (Number(popupHeight) || 0) / 2)
                var maxSideY = screenHSide - (Number(popupHeight) || 0) - 12
                if (maxSideY < 12)
                    maxSideY = 12
                return Math.max(12, Math.min(sideY, maxSideY))
            }
            if (edge === "bottom") {
                if (bar.isDualLayout()) {
                    var screenH = 1080
                    try {
                        if (bar.screen && bar.screen.height)
                            screenH = bar.screen.height
                    } catch (e) {}
                    var bottomH = implicitHeight
                    try {
                        if (bottomBar && bottomBar.implicitHeight)
                            bottomH = bottomBar.implicitHeight
                    } catch (e2) {}
                    return screenH - bottomH - popupHeight - spacing
                }
                return -popupHeight - spacing
            }
            return implicitHeight + spacing
        }
        readonly property alias pillHeight: cfg.pillHeight
        readonly property alias audioViewContentWidth: cfg.audioViewContentWidth
        readonly property alias audioViewSidePadding: cfg.audioViewSidePadding
        readonly property alias audioDualBarWidth: cfg.audioDualBarWidth
        readonly property alias audioDualPercentWidth: cfg.audioDualPercentWidth
        readonly property alias iconSizePill: cfg.iconSizePill
        readonly property alias iconSizePillLarge: cfg.iconSizePillLarge
        readonly property alias iconSizeLauncher: cfg.iconSizeLauncher
        readonly property alias iconSizePopup: cfg.iconSizePopup
        readonly property alias iconSizePower: cfg.iconSizePower
        readonly property alias iconSizeTray: cfg.iconSizeTray
        readonly property alias quickLaunchIcon: cfg.quickLaunchIcon
        readonly property alias quickLaunchSpacing: cfg.quickLaunchSpacing
        readonly property alias quickLaunchPaddingH: cfg.quickLaunchPaddingH
        // Runtime list (editable from BarControlBar); falls back to Config via clone on start
        property alias quickLaunchApps: root.quickLaunchApps
        property alias wallpaperDir: root.wallpaperDir
        property alias wallpaperCurrent: root.wallpaperCurrent
        property alias wallpaperTileSize: root.wallpaperTileSize
        property alias screenshotDir: root.screenshotDir
        property alias ovLayout: root.ovLayout
        property alias ovAnchor: root.ovAnchor
        property alias ovGap: root.ovGap
        property alias ovPadding: root.ovPadding
        property alias ovPaddingTop: root.ovPaddingTop
        property alias ovPaddingBottom: root.ovPaddingBottom
        property alias ovMaxScale: root.ovMaxScale
        property alias ovDuration: root.ovDuration
        property alias ovPreviewRound: root.ovPreviewRound
        property alias ovBlur: root.ovBlur
        property alias ovBackdropBlur: root.ovBackdropBlur
        property alias ovSwitchAnimation: root.ovSwitchAnimation
        property alias ovSwitchDuration: root.ovSwitchDuration
        property alias ovMoveAnimation: root.ovMoveAnimation
        property alias ovMoveDuration: root.ovMoveDuration
        property alias ovStripOffset: root.ovStripOffset
        property alias ovStripHeight: root.ovStripHeight
        property alias ovStripWidth: root.ovStripWidth
        property alias ovStripCardMax: root.ovStripCardMax
        property alias ovStripMargin: root.ovStripMargin
        property alias ovStripGap: root.ovStripGap
        property alias ovStripCardRound: root.ovStripCardRound
        property alias ovHoverBorder: root.ovHoverBorder
        property alias ovSelectBorder: root.ovSelectBorder
        property alias ovLivePreviews: root.ovLivePreviews
        property alias ovShowWindowLabels: root.ovShowWindowLabels
        property alias ovShowWsLabels: root.ovShowWsLabels
        property alias ovStripPreviews: root.ovStripPreviews
        property alias ovNumberLabels: root.ovNumberLabels
        property alias ovDynamic: root.ovDynamic
        property alias ovAutodelete: root.ovAutodelete
        property alias ovShowEmpty: root.ovShowEmpty
        property alias ovShowSpecial: root.ovShowSpecial
        property alias ovStripAllCard: root.ovStripAllCard
        property alias ovShowAll: root.ovShowAll
        property alias ovSwitchOnNew: root.ovSwitchOnNew
        property alias ovSwitchOnDrop: root.ovSwitchOnDrop
        property alias ovDragToSwap: root.ovDragToSwap
        property alias ovFocusFollowsMouse: root.ovFocusFollowsMouse
        property alias ovScrollSwitches: root.ovScrollSwitches
        property alias ovExitOnClick: root.ovExitOnClick
        property alias ovExitOnSwitch: root.ovExitOnSwitch
        property alias widgetScales: root.widgetScales
        // Desktop app picker script for the Launch panel
        readonly property string desktopAppsJsonScript: "/home/crome/.config/quickshell/scripts/desktop-apps-json.sh"
        readonly property alias wallpaperListScript: cfg.wallpaperListScript
        readonly property alias wallpaperApplyScript: cfg.wallpaperApplyScript
        readonly property alias wallpaperAddScript: cfg.wallpaperAddScript
        readonly property alias wallpaperRenameScript: cfg.wallpaperRenameScript
        readonly property alias wallpaperDeleteScript: cfg.wallpaperDeleteScript
        readonly property alias wallpaperPickDirScript: cfg.wallpaperPickDirScript
        readonly property alias wallpaperMonitor: cfg.wallpaperMonitor
        readonly property alias monitorModeScript: cfg.monitorModeScript
        readonly property alias monitorName: cfg.monitorName
        // hyprResolutionBin is aliased once above (Display / hypr-resolution CLI)
        readonly property alias autostartListScript: cfg.autostartListScript
        readonly property alias autostartSetScript: cfg.autostartSetScript
        readonly property alias autostartAddScript: cfg.autostartAddScript
        readonly property alias autostartRunScript: cfg.autostartRunScript

        // --- Popup sizes
        readonly property alias popupAudioWidth: cfg.popupAudioWidth
        readonly property alias popupAudioHeight: cfg.popupAudioHeight
        readonly property alias popupPowerWidth: cfg.popupPowerWidth
        readonly property alias popupPowerHeight: cfg.popupPowerHeight
        readonly property alias popupContextMenuWidth: cfg.popupContextMenuWidth
        readonly property alias popupContextMenuRowHeight: cfg.popupContextMenuRowHeight
        readonly property alias popupCalendarWidth: cfg.popupCalendarWidth
        readonly property alias popupCalendarHeight: cfg.popupCalendarHeight
        readonly property alias popupBluetoothWidth: cfg.popupBluetoothWidth
        readonly property alias popupBluetoothHeight: cfg.popupBluetoothHeight
        readonly property alias popupTailscaleWidth: cfg.popupTailscaleWidth
        readonly property alias popupTailscaleHeight: cfg.popupTailscaleHeight
        readonly property alias bluetoothScanSeconds: cfg.bluetoothScanSeconds
        readonly property alias popupNetworkPanelWidth: cfg.popupNetworkPanelWidth
        readonly property alias popupNetworkPanelMaxHeight: cfg.popupNetworkPanelMaxHeight
        readonly property alias popupHelpWidth: cfg.popupHelpWidth
        readonly property alias popupHelpHeight: cfg.popupHelpHeight

        // --- Fonts (writable via Themes → Fonts tab)
        property alias fontFamily: cfg.fontFamily
        property alias fontMono: cfg.fontMono
        property alias fontScale: cfg.fontScale
        property alias fontMonoScale: cfg.fontMonoScale
        property alias fontMain: cfg.fontMain
        property alias fontSecondary: cfg.fontSecondary
        property alias fontBar: cfg.fontBar
        property alias fontMainScale: cfg.fontMainScale
        property alias fontSecondaryScale: cfg.fontSecondaryScale
        property alias fontBarScale: cfg.fontBarScale
        readonly property alias fontMainResolved: cfg.fontMainResolved
        readonly property alias fontSecondaryResolved: cfg.fontSecondaryResolved
        readonly property alias fontBarResolved: cfg.fontBarResolved
        readonly property alias fontBarFace: cfg.fontBarFace
        readonly property alias fontMonoFace: cfg.fontMonoFace
        readonly property alias fontClock: cfg.fontClock
        readonly property alias fontPillLabel: cfg.fontPillLabel
        readonly property alias fontPopupTitle: cfg.fontPopupTitle
        readonly property alias fontSection: cfg.fontSection
        readonly property alias fontBody: cfg.fontBody
        readonly property alias fontSmall: cfg.fontSmall
        readonly property alias fontTiny: cfg.fontTiny
        function primaryUiFontFamily() { return cfg.primaryUiFontFamily() }
        function primaryFontFamily(stack) { return cfg.primaryFontFamily(stack) }
        function primaryRoleFontFamily(role) { return cfg.primaryRoleFontFamily(role) }
        function setUiFontFamily(name) {
            if (!cfg.setUiFontFamily(name))
                return false
            bar.schedulePersistThemeColors()
            return true
        }
        function setMonoFontFamily(name) {
            if (!cfg.setMonoFontFamily(name))
                return false
            bar.schedulePersistThemeColors()
            return true
        }
        function setThemeFontScale(s) {
            if (!cfg.setThemeFontScale(s))
                return false
            bar.schedulePersistThemeColors()
            return true
        }
        function setRoleFontFamily(role, name) {
            if (!cfg.setRoleFontFamily(role, name))
                return false
            bar.schedulePersistThemeColors()
            return true
        }
        function setThemeFontRoleScale(role, s) {
            if (!cfg.setThemeFontRoleScale(role, s))
                return false
            bar.schedulePersistThemeColors()
            return true
        }

        // --- Icon glyphs
        readonly property alias iconSpeaker: cfg.iconSpeaker
        readonly property alias iconSpeakerMuted: cfg.iconSpeakerMuted
        readonly property alias iconMic: cfg.iconMic
        readonly property alias iconMicMuted: cfg.iconMicMuted
        readonly property alias iconAudioBluetooth: cfg.iconAudioBluetooth
        readonly property alias iconAudioUsb: cfg.iconAudioUsb
        readonly property alias iconAudioHdmi: cfg.iconAudioHdmi
        readonly property alias iconAudioInternal: cfg.iconAudioInternal
        readonly property alias iconAudioBattery: cfg.iconAudioBattery
        readonly property alias iconBluetooth: cfg.iconBluetooth
        readonly property alias iconBluetoothOff: cfg.iconBluetoothOff
        readonly property alias iconBluetoothConnected: cfg.iconBluetoothConnected
        readonly property alias iconBluetoothScanning: cfg.iconBluetoothScanning
        readonly property alias iconNetworkWired: cfg.iconNetworkWired
        readonly property alias iconNetworkWifi: cfg.iconNetworkWifi
        readonly property alias iconNetworkWifiFair: cfg.iconNetworkWifiFair
        readonly property alias iconNetworkWifiWeak: cfg.iconNetworkWifiWeak
        readonly property alias iconNetworkWifiNone: cfg.iconNetworkWifiNone
        readonly property alias iconNetworkWifiOff: cfg.iconNetworkWifiOff
        readonly property alias iconNetworkDisconnected: cfg.iconNetworkDisconnected
        readonly property alias iconNetworkOff: cfg.iconNetworkOff
        readonly property alias iconNetworkPortal: cfg.iconNetworkPortal
        readonly property alias iconNetworkVpn: cfg.iconNetworkVpn
        readonly property alias iconNetworkAirplane: cfg.iconNetworkAirplane
        readonly property alias iconPower: cfg.iconPower
        readonly property alias iconOpacity: cfg.iconOpacity
        readonly property alias opacityApplyScript: cfg.opacityApplyScript
        readonly property alias iconLock: cfg.iconLock
        readonly property alias iconLogout: cfg.iconLogout
        readonly property alias iconReboot: cfg.iconReboot
        readonly property alias iconShutdown: cfg.iconShutdown
        readonly property alias iconBios: cfg.iconBios
        readonly property alias iconHyprInsp: cfg.iconHyprInsp
        readonly property alias iconControlBar: cfg.iconControlBar
        readonly property string launcherCommand: {
            const custom = String(root.launcherCommandCustom || "").trim()
            return custom.length ? custom : cfg.launcherCommand
        }
        readonly property alias launcherTooltip: cfg.launcherTooltip
        property alias iconColor: cfg.iconColor
        property alias audioSpeakerIcon: cfg.audioSpeakerIcon
        property alias audioMicIcon: cfg.audioMicIcon
        readonly property alias audioSpeakerIconMuted: cfg.audioSpeakerIconMuted
        readonly property alias audioMicIconMuted: cfg.audioMicIconMuted

        // --- Sliders / volume tier colors (writable for Themes panel)
        readonly property alias sliderBarHeight: cfg.sliderBarHeight
        readonly property alias sliderPopupHeight: cfg.sliderPopupHeight
        readonly property alias sliderMiniHeight: cfg.sliderMiniHeight
        readonly property alias sliderFill: cfg.sliderFill
        readonly property alias sliderFillMuted: cfg.sliderFillMuted
        readonly property alias sliderTrack: cfg.sliderTrack
        property alias audioUtilThreshold1: cfg.audioUtilThreshold1
        property alias audioUtilThreshold2: cfg.audioUtilThreshold2
        property alias audioUtilThreshold3: cfg.audioUtilThreshold3
        property alias audioMicUtilThreshold1: cfg.audioMicUtilThreshold1
        property alias audioMicUtilThreshold2: cfg.audioMicUtilThreshold2
        property alias audioMicUtilThreshold3: cfg.audioMicUtilThreshold3
        property alias audioSpeakerTier1: cfg.audioSpeakerTier1
        property alias audioSpeakerTier2: cfg.audioSpeakerTier2
        property alias audioSpeakerTier3: cfg.audioSpeakerTier3
        property alias audioSpeakerTier4: cfg.audioSpeakerTier4
        property alias audioMicTier1: cfg.audioMicTier1
        property alias audioMicTier2: cfg.audioMicTier2
        property alias audioMicTier3: cfg.audioMicTier3
        property alias audioMicTier4: cfg.audioMicTier4
        function audioSpeakerUtilColor(percent) { return cfg.audioSpeakerUtilColor(percent) }
        function audioMicUtilColor(percent) { return cfg.audioMicUtilColor(percent) }

        // --- Workspaces
        property alias wsActiveBg: cfg.wsActiveBg
        readonly property alias wsActiveBorder: cfg.wsActiveBorder
        property alias wsActiveText: cfg.wsActiveText
        property alias wsInactiveText: cfg.wsInactiveText
        readonly property alias wsButtonWidth: cfg.wsButtonWidth
        readonly property alias wsButtonHeight: cfg.wsButtonHeight
        readonly property alias wsIconSize: cfg.wsIconSize
        readonly property alias wsNumberSize: cfg.wsNumberSize
        readonly property alias wsSpacing: cfg.wsSpacing
        readonly property alias wsIcon1: cfg.wsIcon1
        readonly property alias wsIcon2: cfg.wsIcon2
        readonly property alias wsIcon3: cfg.wsIcon3
        readonly property alias wsIcon4: cfg.wsIcon4
        readonly property alias wsIcon5: cfg.wsIcon5
        readonly property alias wsIcon6: cfg.wsIcon6
        readonly property alias wsIcon7: cfg.wsIcon7
        readonly property alias wsIcon8: cfg.wsIcon8
        readonly property alias wsIcon9: cfg.wsIcon9
        readonly property alias wsIcon10: cfg.wsIcon10
        readonly property alias wsIconDefault: cfg.wsIconDefault
        // Factory name when Options leaves the special name blank.
        readonly property alias wsSpecialNameDefault: cfg.wsSpecialName
        readonly property string wsSpecialName: {
            const custom = String(root.wsSpecialNameCustom || "").trim()
            return custom.length ? custom : cfg.wsSpecialName
        }
        readonly property alias wsIconSpecial: cfg.wsIconSpecial
        property alias wsIconSpecialCustom: root.wsIconSpecialCustom
        property alias wsSpecialNameCustom: root.wsSpecialNameCustom
        property alias wsSpecialFont: root.wsSpecialFont
        property alias wsSpecialFontPx: root.wsSpecialFontPx
        property alias wsSpecialText: root.wsSpecialText
        property alias wsSpecialBold: root.wsSpecialBold
        property alias wsSpecialItalic: root.wsSpecialItalic
        property alias wsSpecialColor: root.wsSpecialColor
        function wsSpecialIcon() {
            const custom = String(root.wsIconSpecialCustom || "").trim()
            if (custom.length)
                return custom
            // A label with no symbol stays text-only. Both empty keeps the built-in glyph.
            if (String(root.wsSpecialText || "").trim().length)
                return ""
            return cfg.wsIconSpecial
        }
        function setWsIconSpecial(glyph) {
            root.wsIconSpecialCustom = bar.wsSymbolClamp(glyph)
            persistBarLayout()
        }
        property alias launcherIconCustom: root.launcherIconCustom
        property alias launcherIconPx: root.launcherIconPx
        function launcherIconSize() {
            const n = Number(root.launcherIconPx) || 0
            if (n >= 14 && n <= 36)
                return n
            return cfg.iconSizeLauncher || 26
        }
        function setLauncherIcon(glyph) {
            root.launcherIconCustom = String(glyph || "").trim().substring(0, 4)
            persistBarLayout()
        }
        function stepLauncherIconPx(dir) {
            const cur = launcherIconSize()
            const step = dir < 0 ? -2 : 2
            const next = Math.max(14, Math.min(36, cur + step))
            root.launcherIconPx = next
            persistBarLayout()
        }
        function resetLauncherIconPx() {
            root.launcherIconPx = 0
            persistBarLayout()
        }
        function setLauncherCommand(cmd) {
            let s = String(cmd || "").replace(/[\r\n]/g, "").trim()
            if (s.length > 300)
                s = s.substring(0, 300)
            if (s === String(cfg.launcherCommand || "").trim())
                s = ""
            root.launcherCommandCustom = s
            persistBarLayout()
            launcherPill._appMenuWatch = 2
        }
        function setLauncherPrefs(icon, px, cmd) {
            root.launcherIconCustom = String(icon || "").trim().substring(0, 4)
            let n = Math.round(Number(px) || 0)
            if (n !== 0)
                n = Math.max(14, Math.min(36, n))
            root.launcherIconPx = n
            let s = String(cmd || "").replace(/[\r\n]/g, "").trim()
            if (s.length > 300)
                s = s.substring(0, 300)
            if (s === String(cfg.launcherCommand || "").trim())
                s = ""
            root.launcherCommandCustom = s
            persistBarLayout()
            launcherPill._appMenuWatch = 2
        }
        readonly property alias wsShowSpecialPill: cfg.wsShowSpecialPill
        // Bound to root so Options / IPC / WorkspacesPill stay in sync
        property alias wsMinimumShown: root.wsMinimumShown
        property alias wsShowOnlyActive: root.wsShowOnlyActive
        property alias wsShowNumbers: root.wsShowNumbers
        property alias notificationAutoExpand: root.notificationAutoExpand
        property alias notificationStaggerRows: root.notificationStaggerRows
        property alias notificationClearOnBoot: root.notificationClearOnBoot
        property alias notificationShowCount: root.notificationShowCount
        property alias notificationCorner: root.notificationCorner
        property alias notificationTimeout: root.notificationTimeout
        property alias wsStartupWorkspace: root.wsStartupWorkspace
        property alias wsStartupCloseMagic: root.wsStartupCloseMagic
        property alias hasWsSlots: root.hasWsSlots
        property alias wsSlots: root.wsSlots
        property alias showMagicWorkspacePill: root.showMagicWorkspacePill
        property alias showControlBarPill: root.showControlBarPill
        property alias showActiveWindowPill: root.showActiveWindowPill
        property alias activeWindowPillCorner: root.activeWindowPillCorner
        property alias activeWindowExcludes: root.activeWindowExcludes
        property alias widgetVisTick: root.widgetVisTick
        property alias showColorPresets: root.showColorPresets
        property alias showStatCpu: root.showStatCpu
        property alias showStatVram: root.showStatVram
        property alias showStatMem: root.showStatMem
        property alias showStatGpu: root.showStatGpu
        property alias showStatGauges: root.showStatGauges
        property alias statTerminal: root.statTerminal
        property alias statLaunchButton: root.statLaunchButton
        property alias showNetworkFullIp: root.showNetworkFullIp
        property alias showNetworkLastOctet: root.showNetworkLastOctet
        property alias showNetworkDeviceName: root.showNetworkDeviceName
        property alias dockEffect: root.dockEffect
        property alias dockMaxScale: root.dockMaxScale
        property alias dockRadius: root.dockRadius
        property alias dockJumpPx: root.dockJumpPx
        property alias dockScope: root.dockScope
        property alias showEchoCancelInMenu: root.showEchoCancelInMenu
        property alias showAudioSummary: root.showAudioSummary
        property alias showAudioDefaults: root.showAudioDefaults
        property alias showAudioLevelMeters: root.showAudioLevelMeters
        property alias audioSummaryExpanded: root.audioSummaryExpanded
        property alias audioDefaultsExpanded: root.audioDefaultsExpanded
        property alias freshRssFiltersExpanded: root.freshRssFiltersExpanded
        readonly property alias freshRssSecretsReadScript: cfg.freshRssSecretsReadScript
        readonly property alias freshRssSecretsWriteScript: cfg.freshRssSecretsWriteScript
        readonly property alias freshRssConnectionTestScript: cfg.freshRssConnectionTestScript
        function wsIconForId(id) { return cfg.wsIconForId(id) }
        function wsIsSpecialName(name) {
            if (!name || name.length === 0)
                return false
            const n = wsSpecialName
            return name === n || name === ("special:" + n)
        }

        // --- System stats gauges
        readonly property alias statGaugeWidth: cfg.statGaugeWidth
        readonly property alias statGaugeHeight: cfg.statGaugeHeight
        readonly property alias statGaugeRadius: cfg.statGaugeRadius
        readonly property alias statPillWidth: cfg.statPillWidth
        readonly property alias statPillSectionWidth: cfg.statPillSectionWidth
        readonly property alias statPillSpacing: cfg.statPillSpacing
        readonly property alias statPillPaddingH: cfg.statPillPaddingH
        readonly property alias statTrack: cfg.statTrack
        readonly property alias gaugeLow: cfg.gaugeLow
        readonly property alias gaugeMid: cfg.gaugeMid
        readonly property alias gaugeHigh: cfg.gaugeHigh
        property alias statUtilTier1: cfg.statUtilTier1
        property alias statUtilTier2: cfg.statUtilTier2
        property alias statUtilTier3: cfg.statUtilTier3
        property alias statUtilTier4: cfg.statUtilTier4
        property alias statCpuTier1: cfg.statCpuTier1
        property alias statCpuTier2: cfg.statCpuTier2
        property alias statCpuTier3: cfg.statCpuTier3
        property alias statCpuTier4: cfg.statCpuTier4
        property alias statMemTier1: cfg.statMemTier1
        property alias statMemTier2: cfg.statMemTier2
        property alias statMemTier3: cfg.statMemTier3
        property alias statMemTier4: cfg.statMemTier4
        property alias statGpuTier1: cfg.statGpuTier1
        property alias statGpuTier2: cfg.statGpuTier2
        property alias statGpuTier3: cfg.statGpuTier3
        property alias statGpuTier4: cfg.statGpuTier4
        property alias statVramTier1: cfg.statVramTier1
        property alias statVramTier2: cfg.statVramTier2
        property alias statVramTier3: cfg.statVramTier3
        property alias statVramTier4: cfg.statVramTier4
        property alias qlRunningDot: cfg.qlRunningDot
        property alias statUtilThreshold1: cfg.statUtilThreshold1
        property alias statUtilThreshold2: cfg.statUtilThreshold2
        property alias statUtilThreshold3: cfg.statUtilThreshold3
        property alias statTempWarmAt: cfg.statTempWarmAt
        property alias statTempHotAt: cfg.statTempHotAt
        function statUtilColor(util, metric) { return cfg.statUtilColor(util, metric) }
        function statTempColor(temp) { return cfg.statTempColor(temp) }

        // --- Dividers
        readonly property alias divider: cfg.divider
        readonly property alias dividerStrong: cfg.dividerStrong
        readonly property alias dividerThickness: cfg.dividerThickness
        readonly property alias dividerSubtle: cfg.dividerSubtle

        // --- Animation & interaction
        property alias tooltipDelay: cfg.tooltipDelay
        property alias tooltipAlign: root.tooltipAlign

        // --- Tray menu
        readonly property alias menuCheckMark: cfg.menuCheckMark
        readonly property alias menuUncheckedMark: cfg.menuUncheckedMark
        readonly property alias menuCheckedRow: cfg.menuCheckedRow
        readonly property alias menuBtnNone: cfg.menuBtnNone
        readonly property alias menuBtnCheck: cfg.menuBtnCheck
        readonly property alias menuBtnRadio: cfg.menuBtnRadio

        Rectangle {
            id: barBg
            readonly property bool compact: root.barLayoutMode === "dual"
            // Classic always spans. Dual hugs unless Bar spans the monitor is on.
            readonly property bool spanWidth: root.barSpanFull || !compact
            readonly property int hugMeasured: Math.max(bar.sp(120), Math.min(parent.width - 2 * bar.sideMargin,
                              centerZone.implicitWidth + 2 * bar.barContentHMargin))
            // Ignore 1–15px text ticks (clock/stats) so the glass does not relayout every second.
            property int hugW: 200
            onHugMeasuredChanged: {
                if (!spanWidth && Math.abs(hugMeasured - hugW) >= 16)
                    hugW = hugMeasured
            }
            onCompactChanged: hugW = hugMeasured
            onSpanWidthChanged: hugW = hugMeasured
            Component.onCompleted: hugW = hugMeasured
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: bar.barIsTopEdge ? 0 : bar.barContentVMargin
            anchors.bottomMargin: bar.barIsTopEdge ? bar.barContentVMargin : 0
            x: spanWidth ? bar.sideMargin : bar.alignX(root.topBarAlign, parent.width, hugW, bar.sideMargin)
            width: spanWidth ? Math.max(0, parent.width - 2 * bar.sideMargin) : hugW
            radius: bar.barRadius
            topLeftRadius: (bar.barIsTopEdge && bar.barGlassFlush) ? 0 : bar.barRadius
            topRightRadius: (bar.barIsTopEdge && bar.barGlassFlush) ? 0 : bar.barRadius
            bottomLeftRadius: (!bar.barIsTopEdge && bar.barGlassFlush) ? 0 : bar.barRadius
            bottomRightRadius: (!bar.barIsTopEdge && bar.barGlassFlush) ? 0 : bar.barRadius
            color: bar.glassBg
            border.width: Math.max(1, bar.controlBorderWidth)
            border.color: bar.glassBorder
            clip: false

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassHighlight
                radius: parent.radius
                topLeftRadius: parent.topLeftRadius
                topRightRadius: parent.topRightRadius
                bottomLeftRadius: 0
                bottomRightRadius: 0
            }

            // Right-click empty bar chrome → open/close the control mini-bar
            // (top/bottom toggle; room for display controls later).
            // Lives under the widget row (z: 0) so pill MouseAreas still own left-clicks.
            MouseArea {
                id: barBgContext
                anchors.fill: parent
                z: 0
                acceptedButtons: Qt.RightButton
                hoverEnabled: false
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton)
                        barControlBar.toggle()
                }
            }

            // Host for the control strip (FloatingWindow; zero-size Item).
            BarControlBar {
                id: barControlBar
                bar: bar
            }

            // Holding pen for reparentable widgets (layout editor moves them between zones).
            // Keep visible so parked children are not force-hidden; park off-screen.
            Item {
                id: widgetPool
                width: 0
                height: 0
                x: -10000
                y: -10000

                Repeater {
                    id: dividerRepeater
                    model: 8
                    delegate: Item {
                        Layout.preferredWidth: 12
                        Layout.preferredHeight: bar.pillHeight
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 12
                        implicitHeight: bar.pillHeight
                        width: 12
                        height: bar.pillHeight
                        Text {
                            anchors.centerIn: parent
                            text: "|"
                            color: bar.subtext
                            opacity: 0.75
                            font.pixelSize: Math.max(12, Math.round((bar.pillHeight || 36) * 0.58))
                            font.bold: true
                            font.family: bar.fontFamily
                        }
                    }
                }
            }

            RowLayout {
                z: 1
                visible: root.barLayoutMode !== "dual"
                anchors.fill: parent
                anchors.leftMargin: bar.barContentHMargin
                anchors.rightMargin: bar.barContentHMargin
                spacing: 0

                // --- LEFT ZONE (receives reparented widgets) ---
                RowLayout {
                    id: leftZone
                    spacing: bar.widgetSpacing
                    Layout.alignment: Qt.AlignVCenter
                }

                Item { Layout.fillWidth: true }

                // --- RIGHT ZONE ---
                RowLayout {
                    id: rightZone
                    spacing: bar.widgetSpacing
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            // --- CENTER ZONE (true screen center; receives reparented widgets) ---
            RowLayout {
                id: centerZone
                z: 1
                anchors.verticalCenter: parent.verticalCenter
                x: bar.alignX(root.topBarAlign, parent.width, width, bar.barContentHMargin)
                spacing: bar.widgetSpacing
            }

            // =================================================================
            // Widget instances (reparented into left/center/right via applyWidgetLayout)
            // Initial parent is widgetPool; Component.onCompleted places them.
            // =================================================================

            // ─ App Launcher ─
            Rectangle {
                id: launcherPill
                parent: widgetPool
                visible: root.showLauncherPill
                Layout.preferredWidth: Math.max(bar.widgetW("launcher", bar.sp(42)), (bar.launcherIconSize() + bar.sp(16)))
                Layout.preferredHeight: bar.pillHeight
                Layout.alignment: Qt.AlignVCenter
                clip: false
                DockFace {
                    id: launcherDock
                    bar: bar
                    host: launcherPill
                    hovered: launcherMouse.containsMouse
                }
                transform: [
                    Scale {
                        xScale: launcherDock.mag
                        yScale: launcherDock.mag
                        origin.x: launcherPill.width / 2
                        origin.y: launcherDock.growUp ? launcherPill.height : 0
                    },
                    Translate { y: launcherDock.jumpY }
                ]
                radius: bar.pillRadius
                color: launcherMouse.containsMouse || appMenuOpen ? bar.glassHover : bar.pillBg
                border.width: bar.controlBorderWidth
                border.color: launcherMouse.containsMouse || appMenuOpen ? bar.accent : bar.pillBorder

                // Click toggles the drawer (rofi-app-drawer closes it when it is open).
                property bool appMenuOpen: false
                property int _appMenuWatch: 0
                // Stock drawer script exits; rofi is what stays mapped. Any other
                // command is probed by its own program name.
                readonly property string probeBin: {
                    const cmd = String(bar.launcherCommand || "")
                    if (cmd.indexOf("rofi") >= 0)
                        return "rofi"
                    const tok = cmd.trim().split(/\s+/)[0] || ""
                    const base = tok.split("/").pop()
                    if (!base || base === "sh" || base === "bash" || base === "env")
                        return ""
                    return base.substring(0, 64)
                }
                function toggleAppMenu() {
                    launcherDock.jump()
                    Quickshell.execDetached(["sh", "-c", bar.launcherCommand])
                    launcherPill._appMenuWatch = 8
                }
                Component.onCompleted: launcherPill._appMenuWatch = 2
                Timer {
                    interval: 280
                    repeat: true
                    running: launcherPill.appMenuOpen || launcherPill._appMenuWatch > 0
                    onTriggered: {
                        if (launcherPill._appMenuWatch > 0)
                            launcherPill._appMenuWatch -= 1
                        if (!appMenuProbe.running)
                            appMenuProbe.running = true
                    }
                }
                Io.Process {
                    id: appMenuProbe
                    command: ["pgrep", "-x", launcherPill.probeBin.length ? launcherPill.probeBin : "qs-no-such-launcher"]
                    running: false
                    onExited: (code) => {
                        launcherPill.appMenuOpen = (code === 0)
                    }
                }

                // Drawn 3×3 grid (same idea as 󰀻) so it fills the box like Quick
                // Launch images — nerd-font glyphs keep empty em-square padding.
                Item {
                    id: launcherGlyph
                    readonly property string _glyph: String(root.launcherIconCustom || "").trim()
                    readonly property int _sz: Math.max(12, Math.round(bar.launcherIconSize() * (bar.widgetScale ? bar.widgetScale("launcher") : 1.0)))
                    readonly property int _gap: Math.max(2, Math.round(_sz * 0.15))
                    readonly property int _cell: Math.max(2, Math.floor((_sz - 2 * _gap) / 3))
                    readonly property color _c: launcherMouse.containsMouse || launcherPill.appMenuOpen
                        ? bar.accent
                        : (bar.iconColor !== undefined ? bar.iconColor : bar.subtext)

                    anchors.centerIn: parent
                    width: _sz
                    height: _sz

                    Grid {
                        visible: launcherGlyph._glyph.length === 0
                        anchors.centerIn: parent
                        columns: 3
                        spacing: launcherGlyph._gap
                        Repeater {
                            model: 9
                            Rectangle {
                                width: launcherGlyph._cell
                                height: launcherGlyph._cell
                                radius: Math.max(1, Math.round(launcherGlyph._cell * 0.28))
                                color: launcherGlyph._c
                                Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }
                            }
                        }
                    }
                    Text {
                        visible: launcherGlyph._glyph.length > 0
                        anchors.centerIn: parent
                        text: launcherGlyph._glyph
                        color: launcherGlyph._c
                        font.pixelSize: launcherGlyph._sz
                        font.family: bar.fontFamily
                    }
                }

                MouseArea {
                    id: launcherMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: launcherPill.toggleAppMenu()
                }

                BarToolTip {
                    bar: bar
                    widgetId: "launcher"
                    visible: launcherMouse.containsMouse
                    text: bar.launcherTooltip
                    anchorItem: launcherMouse
                }
            }

            // ─ Quick Launch ─
            QuickLaunchPill {
                id: quickLaunchPill
                parent: widgetPool
                visible: root.effQuickLaunch
                bar: bar
            }

            // ─ FreshRSS ─
            FreshRssPill {
                id: freshRssPill
                parent: widgetPool
                visible: root.effFreshRss
                bar: bar
            }

            // ─ Workspaces ─
            WorkspacesPill {
                id: workspacesPill
                parent: widgetPool
                visible: root.showWorkspacesPill
                bar: bar
            }

            // ─ System Stats ─
            SysStatsPill {
                id: sysStatsPill
                parent: widgetPool
                visible: root.effStats
                bar: bar
            }

            // ─ System Tray ─
            SystemTrayPill {
                id: trayPill
                parent: widgetPool
                visible: root.showTrayPill
                bar: bar
                barBg: barBg
            }

            // ─ Bluetooth + Audio as one pill. Network is its own widget. ─
            Rectangle {
                id: connectivityPill
                parent: widgetPool
                visible: root.effConnectivity || root.showAudioPill
                Layout.preferredHeight: bar.pillHeight
                Layout.preferredWidth: connectivityRow.implicitWidth + 10
                Layout.alignment: Qt.AlignVCenter
                clip: false
                radius: bar.pillRadius
                color: bar.pillBg
                border.width: bar.controlBorderWidth
                border.color: bar.pillBorder

                Row {
                    id: connectivityRow
                    anchors.centerIn: parent
                    spacing: Math.max(2, bar.widgetW("connectivity", 4))

                    BluetoothPill {
                        id: bluetoothPill
                        embedded: true
                        pillScale: bar.widgetScale("connectivity")
                        visible: root.effBluetooth
                        bar: bar
                        barBg: barBg
                    }

                    Rectangle {
                        visible: root.effBluetooth && root.showAudioPill
                        width: Math.max(1, bar.widgetW("connectivity", bar.dividerThickness))
                        height: Math.max(14, Math.round((bar.wsButtonHeight || 32) * 0.55))
                        anchors.verticalCenter: parent.verticalCenter
                        color: bar.divider
                    }

                    AudioPill {
                        id: audioPill
                        embedded: true
                        pillScale: bar.widgetScale("connectivity")
                        visible: root.showAudioPill
                        bar: bar
                        barBg: barBg
                    }
                }
            }

            // Network panel. Import is `import "widgets/network"` at the top of this file.
            NetworkButton {
                id: networkPanel
                parent: widgetPool
                visible: root.showNetworkPanel
                bar: bar
                barBg: barBg
                pillScale: {
                    void (root.widgetScales)
                    return bar.widgetScale("networkPanel")
                }
            }

            // ─ Clock + Calendar ─
            ClockPill {
                id: clockPill
                parent: widgetPool
                visible: root.showClockPill
                bar: bar
                barBg: barBg
            }

            // ─ Notifications ─
            NotificationBell {
                id: notificationBell
                parent: widgetPool
                visible: root.showNotificationPill
                bar: bar
                barBg: barBg
            }

            // ─ Hyprland Config Inspector ─
            Rectangle {
                id: hyprInspPill
                parent: widgetPool
                visible: root.showHyprInspPill
                Layout.preferredWidth: bar.widgetW("hyprInsp", bar.sp(42))
                Layout.preferredHeight: bar.pillHeight
                Layout.alignment: Qt.AlignVCenter
                clip: false
                DockFace {
                    id: hyprInspDock
                    bar: bar
                    host: hyprInspPill
                    hovered: hyprInspMouse.containsMouse
                }
                transform: [
                    Scale {
                        xScale: hyprInspDock.mag
                        yScale: hyprInspDock.mag
                        origin.x: hyprInspPill.width / 2
                        origin.y: hyprInspDock.growUp ? hyprInspPill.height : 0
                    },
                    Translate { y: hyprInspDock.jumpY }
                ]
                radius: bar.pillRadius
                color: hyprInspMouse.containsMouse ? bar.glassHover : bar.pillBg
                border.width: bar.controlBorderWidth
                border.color: hyprInspMouse.containsMouse ? bar.accent : bar.pillBorder

                Text {
                    anchors.centerIn: parent
                    text: bar.iconHyprInsp
                    font.pixelSize: bar.widgetW("hyprInsp", bar.iconSizePillLarge)
                    font.family: bar.fontFamily
                    color: hyprInspMouse.containsMouse ? bar.accent : (bar.iconColor !== undefined ? bar.iconColor : bar.subtext)
                }

                MouseArea {
                    id: hyprInspMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        hyprInspDock.jump()
                        if (hyprConfigInsp && hyprConfigInsp.toggle)
                            hyprConfigInsp.toggle()
                    }
                    BarToolTip {
                        bar: bar
                        widgetId: "hyprInsp"
                        visible: hyprInspMouse.containsMouse
                        text: "Hyprland Config Inspector"
                        anchorItem: hyprInspMouse
                    }
                }
            }

            // ─ Settings / config menu ─
            Rectangle {
                id: controlBarPill
                parent: widgetPool
                visible: root.showControlBarPill
                Layout.preferredWidth: bar.widgetW("controlBar", bar.sp(42))
                Layout.preferredHeight: bar.pillHeight
                Layout.alignment: Qt.AlignVCenter
                clip: false
                DockFace {
                    id: controlBarDock
                    bar: bar
                    host: controlBarPill
                    hovered: controlBarMouse.containsMouse
                }
                transform: [
                    Scale {
                        xScale: controlBarDock.mag
                        yScale: controlBarDock.mag
                        origin.x: controlBarPill.width / 2
                        origin.y: controlBarDock.growUp ? controlBarPill.height : 0
                    },
                    Translate { y: controlBarDock.jumpY }
                ]
                radius: bar.pillRadius
                color: controlBarMouse.containsMouse || (barControlBar && barControlBar.open)
                       ? bar.glassHover : bar.pillBg
                border.width: bar.controlBorderWidth
                border.color: controlBarMouse.containsMouse || (barControlBar && barControlBar.open)
                              ? bar.accent : bar.pillBorder

                Text {
                    anchors.centerIn: parent
                    text: bar.iconControlBar
                    font.pixelSize: bar.widgetW("controlBar", bar.iconSizePillLarge)
                    font.family: bar.fontFamily
                    color: controlBarMouse.containsMouse || (barControlBar && barControlBar.open)
                           ? bar.accent : (bar.iconColor !== undefined ? bar.iconColor : bar.subtext)
                }

                MouseArea {
                    id: controlBarMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        controlBarDock.jump()
                        if (barControlBar && barControlBar.toggle)
                            barControlBar.toggle()
                    }
                    BarToolTip {
                        bar: bar
                        widgetId: "controlBar"
                        visible: controlBarMouse.containsMouse
                        text: "Config menu (or right-click empty bar)"
                        anchorItem: controlBarMouse
                    }
                }
            }

            // ─ Tailscale ─
            TailscalePill {
                id: tailscalePill
                parent: widgetPool
                visible: root.showTailscalePill
                bar: bar
                barBg: barBg
            }

            // ─ Power Menu ─
            PowerMenu {
                id: powerMenu
                parent: widgetPool
                visible: root.showPowerPill
                bar: bar
                barBg: barBg
            }

            OpacityPill {
                id: opacityPill
                parent: widgetPool
                visible: root.showOpacityPill
                bar: bar
                barBg: barBg
            }
        }

        // --- Background services (do not move to zones) ---
        HyprConfigInsp { id: hyprConfigInsp; bar: bar }

        Io.IpcHandler {
            target: "hyprConfigInsp"
            function toggle() {
                if (hyprConfigInsp && hyprConfigInsp.toggle) hyprConfigInsp.toggle()
            }
        }

        Io.IpcHandler {
            target: "freshRss"
            function toggle() {
                if (freshRssPill && freshRssPill.toggle)
                    freshRssPill.toggle()
            }
            function refresh() {
                if (freshRssPill && freshRssPill.refresh)
                    freshRssPill.refresh()
            }
            function show() {
                if (freshRssPill && freshRssPill.show)
                    freshRssPill.show()
            }
            function hide() {
                if (freshRssPill && freshRssPill.hide)
                    freshRssPill.hide()
            }
        }

        Io.IpcHandler {
            target: "audioPill"
            // Echo cancel (sticky AEC). Same as the popup On/Off toggle.
            // Examples:
            //   qs ipc call audioPill setEchoCancel true
            //   qs ipc call audioPill setEchoCancel false
            //   qs ipc call audioPill toggleEchoCancel
            //   qs ipc call audioPill enableEchoCancel
            //   qs ipc call audioPill disableEchoCancel
            function setEchoCancel(enabled: bool): void {
                if (audioPill && audioPill.setEchoCancelEnabled)
                    audioPill.setEchoCancelEnabled(enabled)
            }
            function toggleEchoCancel(): void {
                if (audioPill && audioPill.toggleEchoCancel)
                    audioPill.toggleEchoCancel()
            }
            function enableEchoCancel(): void {
                if (audioPill && audioPill.enableEchoCancel)
                    audioPill.enableEchoCancel()
            }
            function disableEchoCancel(): void {
                if (audioPill && audioPill.disableEchoCancel)
                    audioPill.disableEchoCancel()
            }
        }

        Io.IpcHandler {
            target: "networkPanel"
            function showPopup(): void {
                if (networkPanel && networkPanel.showPopup) networkPanel.showPopup()
            }
            function hidePopup(): void {
                if (networkPanel && networkPanel.hidePopup) networkPanel.hidePopup()
            }
            function togglePopup(): void {
                if (networkPanel && networkPanel.togglePopup) networkPanel.togglePopup()
            }
            function toggleWifi(): void {
                if (networkPanel && networkPanel.toggleWifi) networkPanel.toggleWifi()
            }
            function setWifi(enabled: bool): void {
                if (networkPanel && networkPanel.setWifi) networkPanel.setWifi(enabled)
            }
        }

        Io.IpcHandler {
            target: "bluetoothPill"
            // Popup
            function showPopup(): void {
                if (bluetoothPill && bluetoothPill.showPopup) bluetoothPill.showPopup()
            }
            function hidePopup(): void {
                if (bluetoothPill && bluetoothPill.hidePopup) bluetoothPill.hidePopup()
            }
            function togglePopup(): void {
                if (bluetoothPill && bluetoothPill.togglePopup) bluetoothPill.togglePopup()
            }
            // Adapter radio power
            function setPower(enabled: bool): void {
                if (bluetoothPill && bluetoothPill.setPower) bluetoothPill.setPower(enabled)
            }
            function togglePower(): void {
                if (bluetoothPill && bluetoothPill.togglePower) bluetoothPill.togglePower()
            }
            function enable(): void {
                if (bluetoothPill && bluetoothPill.enable) bluetoothPill.enable()
            }
            function disable(): void {
                if (bluetoothPill && bluetoothPill.disable) bluetoothPill.disable()
            }
            // Discovery
            function startScan(): void {
                if (bluetoothPill && bluetoothPill.startScan) bluetoothPill.startScan()
            }
            function stopScan(): void {
                if (bluetoothPill && bluetoothPill.stopScan) bluetoothPill.stopScan()
            }
            function toggleScan(): void {
                if (bluetoothPill && bluetoothPill.toggleScan) bluetoothPill.toggleScan()
            }
            function setDiscoverable(enabled: bool): void {
                if (bluetoothPill && bluetoothPill.setDiscoverable) bluetoothPill.setDiscoverable(enabled)
            }
            function toggleDiscoverable(): void {
                if (bluetoothPill && bluetoothPill.toggleDiscoverable) bluetoothPill.toggleDiscoverable()
            }
            // Blueman monitor applet — session vs sticky (reboot)
            function startApplet(): void {
                if (bluetoothPill && bluetoothPill.startApplet) bluetoothPill.startApplet()
            }
            function stopApplet(): void {
                if (bluetoothPill && bluetoothPill.stopApplet) bluetoothPill.stopApplet()
            }
            function toggleApplet(): void {
                if (bluetoothPill && bluetoothPill.toggleApplet) bluetoothPill.toggleApplet()
            }
            // Permanent: XDG autostart override so applet stays off after reboot
            function disableApplet(): void {
                if (bluetoothPill && bluetoothPill.disableApplet) bluetoothPill.disableApplet()
            }
            function enableApplet(): void {
                if (bluetoothPill && bluetoothPill.enableApplet) bluetoothPill.enableApplet()
            }
            function setAppletAutostart(enabled: bool): void {
                if (bluetoothPill && bluetoothPill.setAppletAutostart)
                    bluetoothPill.setAppletAutostart(enabled)
            }
            // Devices — address is MAC string e.g. "A0:0C:E2:66:FB:7D"
            function connectDevice(address: string): void {
                if (bluetoothPill && bluetoothPill.connectDevice) bluetoothPill.connectDevice(address)
            }
            function disconnectDevice(address: string): void {
                if (bluetoothPill && bluetoothPill.disconnectDevice) bluetoothPill.disconnectDevice(address)
            }
            function pairDevice(address: string): void {
                if (bluetoothPill && bluetoothPill.pairDevice) bluetoothPill.pairDevice(address)
            }
            function cancelPair(address: string): void {
                if (bluetoothPill && bluetoothPill.cancelPair) bluetoothPill.cancelPair(address)
            }
            function forgetDevice(address: string): void {
                if (bluetoothPill && bluetoothPill.forgetDevice) bluetoothPill.forgetDevice(address)
            }
            function setTrusted(address: string, trusted: bool): void {
                if (bluetoothPill && bluetoothPill.setTrusted) bluetoothPill.setTrusted(address, trusted)
            }
            function setBlocked(address: string, blocked: bool): void {
                if (bluetoothPill && bluetoothPill.setBlocked) bluetoothPill.setBlocked(address, blocked)
            }
            function renameDevice(address: string, name: string): void {
                if (bluetoothPill && bluetoothPill.renameDevice) bluetoothPill.renameDevice(address, name)
            }
            // PipeWire bluez card profile for a device (e.g. a2dp-sink, headset-head-unit)
            function setCardProfile(address: string, profileName: string): void {
                if (bluetoothPill && bluetoothPill.setCardProfile) bluetoothPill.setCardProfile(address, profileName)
            }
        }

        Io.IpcHandler {
            target: "clockPill"
            function showCalendar() {
                if (clockPill && clockPill.showCalendar) clockPill.showCalendar()
            }
        }

        Io.IpcHandler {
            target: "notificationBell"
            function toggleHistory() {
                if (notificationBell && notificationBell.toggleHistory) notificationBell.toggleHistory()
            }
            function showHistory() {
                if (notificationBell && notificationBell.showHistory) notificationBell.showHistory()
            }
            function hideHistory() {
                if (notificationBell && notificationBell.hideHistory) notificationBell.hideHistory()
            }
            function toggleDoNotDisturb() {
                if (notificationBell && notificationBell.toggleDoNotDisturb) notificationBell.toggleDoNotDisturb()
            }
        }

    }

    // Dual-mode bottom bar. Hidden in classic mode (no exclusive zone).
    PanelWindow {
        id: bottomBar
        visible: root.barLayoutMode === "dual"
        color: "transparent"
        implicitHeight: bar.panelBarHeight()
        screen: bar.screen
        exclusionMode: root.barLayoutMode === "dual" ? ExclusionMode.Normal : ExclusionMode.Ignore
        exclusiveZone: {
            void (bar.flushWindowsToBar)
            void (bar.barEdgeMargin)
            void (bar.barHeight)
            void (bar.barContentVMargin)
            void (bar.hyprGapsOutBottom)
            return bar.exclusiveZoneFor(false)
        }
        mask: Region { item: bottomBarBg }
        anchors.left: true
        anchors.right: true
        anchors.bottom: root.barLayoutMode === "dual"
        margins.bottom: root.barLayoutMode === "dual" ? bar.barEdgeMargin : 0

        Rectangle {
            id: bottomBarBg
            readonly property bool spanWidth: !!root.panelSpanFull
            readonly property int hugMeasured: Math.max(bar.sp(120), Math.min(parent.width - 2 * bar.sideMargin,
                           bottomCenterZone.implicitWidth + 2 * bar.barContentHMargin))
            property int hugW: 200
            onHugMeasuredChanged: {
                if (!spanWidth && Math.abs(hugMeasured - hugW) >= 16)
                    hugW = hugMeasured
            }
            onSpanWidthChanged: hugW = hugMeasured
            Component.onCompleted: hugW = hugMeasured
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: bar.barContentVMargin
            anchors.bottomMargin: 0
            x: spanWidth ? bar.sideMargin : bar.alignX(root.bottomBarAlign, parent.width, hugW, bar.sideMargin)
            width: spanWidth ? Math.max(0, parent.width - 2 * bar.sideMargin) : hugW
            radius: bar.barRadius
            topLeftRadius: bar.barRadius
            topRightRadius: bar.barRadius
            bottomLeftRadius: bar.barGlassFlush ? 0 : bar.barRadius
            bottomRightRadius: bar.barGlassFlush ? 0 : bar.barRadius
            color: bar.glassBg
            border.width: Math.max(1, bar.controlBorderWidth)
            border.color: bar.glassBorder
            clip: false

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassHighlight
                radius: parent.radius
                topLeftRadius: parent.topLeftRadius
                topRightRadius: parent.topRightRadius
                bottomLeftRadius: 0
                bottomRightRadius: 0
            }

            MouseArea {
                anchors.fill: parent
                z: 0
                acceptedButtons: Qt.RightButton
                hoverEnabled: false
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton)
                        barControlBar.toggle()
                }
            }

            RowLayout {
                id: bottomCenterZone
                z: 1
                anchors.verticalCenter: parent.verticalCenter
                x: bar.alignX(root.bottomBarAlign, parent.width, width, bar.barContentHMargin)
                spacing: bar.widgetSpacing
            }
        }

        Component.onCompleted: {
            if (root.barLayoutMode === "dual")
                Qt.callLater(function() { bar.applyWidgetLayout() })
        }
    }

    // Left edge bar. Dual only, and off until Show left bar. Widget text rotates
    // 90° clockwise inside the row. Popups stay on their own windows.
    PanelWindow {
        id: leftEdgeBar
        visible: root.barLayoutMode === "dual" && root.showLeftBar
        color: "transparent"
        implicitWidth: bar.barHeight
        screen: bar.screen
        exclusionMode: (root.barLayoutMode === "dual" && root.showLeftBar)
                       ? ExclusionMode.Normal : ExclusionMode.Ignore
        exclusiveZone: {
            void (root.showLeftBar)
            void (root.barLayoutMode)
            void (bar.flushWindowsToBar)
            void (bar.barEdgeMargin)
            void (bar.barHeight)
            void (bar.barContentVMargin)
            void (bar.hyprGapsOutLeft)
            if (!(root.barLayoutMode === "dual" && root.showLeftBar))
                return 0
            return bar.sideExclusiveZoneFor(true)
        }
        mask: Region { item: leftEdgeBg }
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        margins.left: bar.barEdgeMargin
        margins.top: bar.sideTopInset()
        margins.bottom: bar.sideBottomInset()

        Rectangle {
            id: leftEdgeBg
            readonly property bool spanHeight: !!root.leftBarSpanFull
            readonly property int hugMeasured: Math.max(bar.sp(80), Math.min(parent.height,
                              leftEdgeStack.height + 2 * bar.barContentHMargin))
            property int hugH: 80
            onHugMeasuredChanged: {
                if (!spanHeight && Math.abs(hugMeasured - hugH) >= 16)
                    hugH = hugMeasured
            }
            onSpanHeightChanged: hugH = hugMeasured
            Component.onCompleted: hugH = hugMeasured
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 0
            anchors.rightMargin: bar.barContentVMargin
            y: spanHeight ? 0 : bar.alignY(root.leftBarAlign, parent.height, hugH, bar.barContentHMargin)
            height: spanHeight ? parent.height : hugH
            radius: bar.barRadius
            topLeftRadius: bar.barGlassFlush ? 0 : bar.barRadius
            bottomLeftRadius: bar.barGlassFlush ? 0 : bar.barRadius
            topRightRadius: bar.barRadius
            bottomRightRadius: bar.barRadius
            color: bar.glassBg
            border.width: Math.max(1, bar.controlBorderWidth)
            border.color: bar.glassBorder
            clip: true

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: bar.popupHeaderHighlightHeight
                color: bar.glassHighlight
            }

            MouseArea {
                anchors.fill: parent
                z: 0
                acceptedButtons: Qt.RightButton
                hoverEnabled: false
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton)
                        barControlBar.toggle()
                }
            }

            // Unrotated box is swapped so a 90° clockwise row lands inside it.
            // Left alignment is the top of the screen, where that text starts.
            Item {
                id: leftEdgeStack
                z: 1
                width: Math.max(1, leftEdgeZone.implicitHeight)
                height: Math.max(1, leftEdgeZone.implicitWidth)
                x: Math.max(0, (parent.width - width) / 2)
                y: leftEdgeBg.spanHeight
                   ? bar.alignY(root.leftBarAlign, parent.height, height, bar.barContentHMargin)
                   : Math.max(0, (parent.height - height) / 2)

                RowLayout {
                    id: leftEdgeZone
                    rotation: 90
                    transformOrigin: Item.Center
                    spacing: bar.widgetSpacing
                    x: (leftEdgeStack.width - implicitWidth) / 2
                    y: (leftEdgeStack.height - implicitHeight) / 2
                    onImplicitWidthChanged: width = implicitWidth
                    onImplicitHeightChanged: height = implicitHeight
                    Component.onCompleted: {
                        width = implicitWidth
                        height = implicitHeight
                    }
                }
            }
        }

        Component.onCompleted: {
            Qt.callLater(function() { bar.applyWidgetLayout() })
        }
    }

    // Right edge bar. Same thickness as the top bar. Text reads downward.
    PanelWindow {
        id: rightEdgeBar
        visible: root.barLayoutMode === "dual" && root.showRightBar
        color: "transparent"
        implicitWidth: bar.barHeight
        screen: bar.screen
        exclusionMode: (root.barLayoutMode === "dual" && root.showRightBar)
                       ? ExclusionMode.Normal : ExclusionMode.Ignore
        exclusiveZone: {
            void (root.showRightBar)
            void (root.barLayoutMode)
            void (bar.flushWindowsToBar)
            void (bar.barEdgeMargin)
            void (bar.barHeight)
            void (bar.barContentVMargin)
            void (bar.hyprGapsOutRight)
            if (!(root.barLayoutMode === "dual" && root.showRightBar))
                return 0
            return bar.sideExclusiveZoneFor(false)
        }
        mask: Region { item: rightEdgeBg }
        anchors.top: true
        anchors.bottom: true
        anchors.right: true
        margins.right: bar.barEdgeMargin
        margins.top: bar.sideTopInset()
        margins.bottom: bar.sideBottomInset()

        Rectangle {
            id: rightEdgeBg
            readonly property bool spanHeight: !!root.rightBarSpanFull
            readonly property int hugMeasured: Math.max(bar.sp(80), Math.min(parent.height,
                              rightEdgeStack.height + 2 * bar.barContentHMargin))
            property int hugH: 80
            onHugMeasuredChanged: {
                if (!spanHeight && Math.abs(hugMeasured - hugH) >= 16)
                    hugH = hugMeasured
            }
            onSpanHeightChanged: hugH = hugMeasured
            Component.onCompleted: hugH = hugMeasured
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: bar.barContentVMargin
            anchors.rightMargin: 0
            y: spanHeight ? 0 : bar.alignY(root.rightBarAlign, parent.height, hugH, bar.barContentHMargin)
            height: spanHeight ? parent.height : hugH
            radius: bar.barRadius
            topLeftRadius: bar.barRadius
            bottomLeftRadius: bar.barRadius
            topRightRadius: bar.barGlassFlush ? 0 : bar.barRadius
            bottomRightRadius: bar.barGlassFlush ? 0 : bar.barRadius
            color: bar.glassBg
            border.width: Math.max(1, bar.controlBorderWidth)
            border.color: bar.glassBorder
            clip: true

            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: bar.popupHeaderHighlightHeight
                color: bar.glassHighlight
            }

            MouseArea {
                anchors.fill: parent
                z: 0
                acceptedButtons: Qt.RightButton
                hoverEnabled: false
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton)
                        barControlBar.toggle()
                }
            }

            Item {
                id: rightEdgeStack
                z: 1
                width: Math.max(1, rightEdgeZone.implicitHeight)
                height: Math.max(1, rightEdgeZone.implicitWidth)
                x: Math.max(0, (parent.width - width) / 2)
                y: rightEdgeBg.spanHeight
                   ? bar.alignY(root.rightBarAlign, parent.height, height, bar.barContentHMargin)
                   : Math.max(0, (parent.height - height) / 2)

                RowLayout {
                    id: rightEdgeZone
                    rotation: 90
                    transformOrigin: Item.Center
                    spacing: bar.widgetSpacing
                    x: (rightEdgeStack.width - implicitWidth) / 2
                    y: (rightEdgeStack.height - implicitHeight) / 2
                    onImplicitWidthChanged: width = implicitWidth
                    onImplicitHeightChanged: height = implicitHeight
                    Component.onCompleted: {
                        width = implicitWidth
                        height = implicitHeight
                    }
                }
            }
        }

        Component.onCompleted: {
            Qt.callLater(function() { bar.applyWidgetLayout() })
        }
    }

    // Focused-window pill. Screen-corner overlay, vertically centered on the
    // matching bar strip when there is one. Overlay keeps it above windows.
    ActiveWindowBar {
        hostBar: bar
        shown: root.showActiveWindowPill
        corner: root.activeWindowPillCorner
        excludes: root.activeWindowExcludes
        leftMargin: bar.sideMargin
        rightMargin: bar.sideMargin
        topMargin: bar.activeWindowEdgeMargin(root.activeWindowPillCorner)
        bottomMargin: bar.activeWindowEdgeMargin(root.activeWindowPillCorner)
        stripHeight: bar.activeWindowStripHeight(root.activeWindowPillCorner)
    }

    // Fullscreen workspace overview. Super+Tab is bound in Hyprland.
    Overview {
        id: overviewLayer
        hostBar: bar
    }

    Io.IpcHandler {
        target: "overview"
        function toggle(): void { overviewLayer.toggle() }
        function open(): void { overviewLayer.openOverview("workspace") }
        function close(): void { overviewLayer.closeOverview() }
        function desktop(): void { overviewLayer.openMode("desktop") }
        function all(): void { overviewLayer.openMode("all") }
        function next(): void { overviewLayer.step(1) }
        function prev(): void { overviewLayer.step(-1) }
    }

    // IPC handlers must use explicit types (bool, string, etc.) — `var` is not supported
    Io.IpcHandler {
        target: "shell"
        function setShowLauncherPill(enabled: bool): void {
            bar.setWidgetVisible("launcher", enabled)
        }
        function toggleShowLauncherPill(): void {
            bar.toggleWidgetVisible("launcher")
        }
        function setShowQuickLaunchPill(enabled: bool): void {
            bar.setWidgetVisible("quickLaunch", enabled)
        }
        function toggleShowQuickLaunchPill(): void {
            bar.toggleWidgetVisible("quickLaunch")
        }
        function setShowWorkspacesPill(enabled: bool): void {
            bar.setWidgetVisible("workspaces", enabled)
        }
        function toggleShowWorkspacesPill(): void {
            bar.toggleWidgetVisible("workspaces")
        }
        function setShowStatsWidget(enabled: bool): void {
            bar.setWidgetVisible("stats", enabled)
        }
        function toggleShowStatsWidget(): void {
            bar.toggleWidgetVisible("stats")
        }
        function setShowTrayPill(enabled: bool): void {
            bar.setWidgetVisible("tray", enabled)
        }
        function toggleShowTrayPill(): void {
            bar.toggleWidgetVisible("tray")
        }
        function setShowNetworkPanel(enabled: bool): void {
            bar.setWidgetVisible("networkPanel", enabled)
        }
        function toggleShowNetworkPanel(): void {
            bar.toggleWidgetVisible("networkPanel")
        }
        function setShowBluetoothPill(enabled: bool): void {
            bar.setWidgetVisible("bluetooth", enabled)
        }
        function toggleShowBluetoothPill(): void {
            bar.toggleWidgetVisible("bluetooth")
        }
        function setShowAudioPill(enabled: bool): void {
            bar.setWidgetVisible("audio", enabled)
        }
        function toggleShowAudioPill(): void {
            bar.toggleWidgetVisible("audio")
        }
        function setShowClockPill(enabled: bool): void {
            bar.setWidgetVisible("clock", enabled)
        }
        function toggleShowClockPill(): void {
            bar.toggleWidgetVisible("clock")
        }
        function setShowNotificationPill(enabled: bool): void {
            bar.setWidgetVisible("notifications", enabled)
        }
        function toggleShowNotificationPill(): void {
            bar.toggleWidgetVisible("notifications")
        }
        function setShowPowerPill(enabled: bool): void {
            bar.setWidgetVisible("power", enabled)
        }
        function toggleShowPowerPill(): void {
            bar.toggleWidgetVisible("power")
        }
        function setShowOpacityPill(enabled: bool): void {
            bar.setWidgetVisible("opacity", enabled)
        }
        function toggleShowOpacityPill(): void {
            bar.toggleWidgetVisible("opacity")
        }
        function setShowTailscalePill(enabled: bool): void {
            bar.setWidgetVisible("tailscale", enabled)
        }
        function toggleShowTailscalePill(): void {
            bar.toggleWidgetVisible("tailscale")
        }
        function setClockFormat(format: string): void {
            bar.setClockFormat(format)
        }
        function setClockFont(name: string): void {
            bar.setClockFont(name)
        }
        function setClockFontScale(scale: string): void {
            bar.setClockFontScale(scale)
        }
        function setWidgetZone(widgetId: string, zone: string): void {
            bar.setWidgetZone(widgetId, zone)
        }
        function moveWidget(widgetId: string, delta: string): void {
            bar.moveWidget(widgetId, Number(delta) || 0)
        }
        function resetWidgetLayout(): void {
            bar.resetWidgetLayout()
        }
        function setBarPosition(position: string): void {
            bar.setBarPosition(position)
        }
        function toggleBarPosition(): void {
            bar.toggleBarPosition()
        }
        function setBarLayoutMode(mode: string): void {
            bar.setBarLayoutMode(mode)
        }
        function toggleBarLayoutMode(): void {
            bar.toggleBarLayoutMode()
        }
        function toggleBarControlBar(): void {
            barControlBar.toggle()
        }
        function showBarControlBar(): void {
            barControlBar.show()
        }
        function hideBarControlBar(): void {
            barControlBar.hide()
        }
        function setUiScale(scale: string): void {
            bar.setUiScale(scale)
        }
        function setUiScaleManual(scale: string): void {
            bar.setUiScaleManual(scale)
        }
        function setUiScaleAuto(): void {
            bar.setUiScaleAuto()
        }
        function setBarEdgeMargin(px: string): void {
            bar.setBarEdgeMargin(px)
        }
        function setBarSizeScale(scale: string): void {
            bar.setBarSizeScale(scale)
        }
        function setFlushWindowsToBar(enabled: bool): void {
            bar.setFlushWindowsToBar(enabled)
        }
        function setTooltipDelay(ms: string): void {
            bar.setTooltipDelay(ms)
        }
        function setShowFreshRssPill(enabled: bool): void {
            bar.setWidgetVisible("freshRss", enabled)
        }
        function toggleShowFreshRssPill(): void {
            bar.toggleWidgetVisible("freshRss")
        }
        function setShowHyprInspPill(enabled: bool): void {
            bar.setWidgetVisible("hyprInsp", enabled)
        }
        function toggleShowHyprInspPill(): void {
            bar.toggleWidgetVisible("hyprInsp")
        }
        function setShowControlBarPill(enabled: bool): void {
            bar.setWidgetVisible("controlBar", enabled)
        }
        function toggleShowControlBarPill(): void {
            bar.toggleWidgetVisible("controlBar")
        }
        function setShowActiveWindowPill(enabled: bool): void {
            bar.setWidgetVisible("activeWindow", enabled)
        }
        function toggleShowActiveWindowPill(): void {
            bar.toggleWidgetVisible("activeWindow")
        }
        function setActiveWindowCorner(corner: string): void {
            bar.setActiveWindowCorner(corner)
        }
        function setNotificationCorner(corner: string): void {
            if (bar && bar.setNotificationCorner)
                bar.setNotificationCorner(corner)
        }
        function setNotificationTimeout(seconds: string): void {
            if (bar && bar.setNotificationTimeout)
                bar.setNotificationTimeout(seconds)
        }
        function addActiveWindowExclude(pattern: string): void {
            if (bar && bar.addActiveWindowExclude)
                bar.addActiveWindowExclude(pattern)
        }
        function removeActiveWindowExclude(pattern: string): void {
            if (bar && bar.removeActiveWindowExclude)
                bar.removeActiveWindowExclude(pattern)
        }
        function setShowMagicWorkspacePill(enabled: bool): void {
            if (bar && bar.setShowMagicWorkspacePill)
                bar.setShowMagicWorkspacePill(enabled)
            else
                root.showMagicWorkspacePill = enabled
        }
        function toggleShowMagicWorkspacePill(): void {
            setShowMagicWorkspacePill(!root.showMagicWorkspacePill)
        }
        function setWsMinimumShown(count: int): void {
            if (bar && bar.setWsMinimumShown)
                bar.setWsMinimumShown(count)
            else
                root.wsMinimumShown = Math.max(1, Math.min(10, count))
        }
        function setWsShowOnlyActive(enabled: bool): void {
            if (bar && bar.setWsShowOnlyActive)
                bar.setWsShowOnlyActive(enabled)
            else
                root.wsShowOnlyActive = enabled
        }
        function setWsShowNumbers(enabled: bool): void {
            if (bar && bar.setWsShowNumbers)
                bar.setWsShowNumbers(enabled)
            else
                root.wsShowNumbers = !!enabled
        }
        function setWsStartupWorkspace(workspace: int): void {
            if (bar && bar.setWsStartupWorkspace)
                bar.setWsStartupWorkspace(workspace)
            else
                root.wsStartupWorkspace = Math.max(0, Math.min(10, workspace))
        }
        function setWsStartupCloseMagic(enabled: bool): void {
            if (bar && bar.setWsStartupCloseMagic)
                bar.setWsStartupCloseMagic(enabled)
            else
                root.wsStartupCloseMagic = enabled
        }
        function addWsSlot(): void {
            if (bar && bar.addWsSlot)
                bar.addWsSlot()
        }
        function removeWsSlot(index: int): void {
            if (bar && bar.removeWsSlot)
                bar.removeWsSlot(index)
        }
        function moveWsSlot(index: int, delta: int): void {
            if (bar && bar.moveWsSlot)
                bar.moveWsSlot(index, delta)
        }
        function setWsSlotLabel(index: int, label: string): void {
            if (bar && bar.setWsSlotLabel)
                bar.setWsSlotLabel(index, label)
        }
        function setWsSlotFont(index: int, font: string): void {
            if (bar && bar.setWsSlotFont)
                bar.setWsSlotFont(index, font)
        }
    }
}