// =============================================================================
// shell.qml — Main Quickshell entry point for the Hyprland status bar
// =============================================================================
//
// Widget logic lives in:
//   - widgets/*.qml      (self-contained pills and menus)
//   - components/*.qml   (reusable pieces like VolumeBar, CavaVisualizer)
//   - Config.qml      (colors, spacing, metrics, workspace behavior)
//   - widgets/HyprConfigInsp.qml (Hyprland Config Inspector overlay)
//
// IPC:
//   - qs ipc call hyprConfigInsp toggle
//   - qs ipc call freshRss toggle / refresh / show / hide
//   - qs ipc call shell setShowFreshRssPill true / toggleShowFreshRssPill
//   - qs ipc call shell setShowMediaWidget true
//   - qs ipc call shell setShowStatsWidget false
//   - qs ipc call shell toggleShowMediaWidget
//   - qs ipc call shell toggleShowStatsWidget
//   - qs ipc call shell setShowMagicWorkspacePill true
//   - qs ipc call shell toggleShowMagicWorkspacePill
//   - qs ipc call shell setShowAudioPill false   (and set/toggle for each bar pill)
//   - qs ipc call shell setShowNetworkPill true / toggleShowNetworkPill
//   - qs ipc call shell setShowBluetoothPill true / toggleShowBluetoothPill
//   - qs ipc call audioPill setEchoCancel true|false
//   - qs ipc call audioPill toggleEchoCancel / enableEchoCancel / disableEchoCancel
//   - qs ipc call networkPill showPopup / hidePopup / togglePopup
//   - qs ipc call networkPill setWifi true|false / toggleWifi / enableWifi / disableWifi
//   - qs ipc call networkPill setNetworking true|false / toggleNetworking
//   - qs ipc call networkPill startScan / stopScan / connectSsid / forgetSsid
//   - qs ipc call networkPill disconnectDevice "iface" / openEditor
//   - qs ipc call networkPill refreshIp [iface] / refreshDns [iface]
//   - qs ipc call networkPill activateConnection "uuid|name" / deactivateConnection "uuid|name"
//   - qs ipc call networkPill startApplet / stopApplet / toggleApplet   (session only)
//   - qs ipc call networkPill enableApplet / disableApplet              (survives reboot)
//   - qs ipc call networkPill setAppletAutostart true|false
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
//   - qs ipc call notificationBell toggleDoNotDisturb
//   - qs ipc call sysStatsPill setMetricsLiveUpdates false
//   - qs ipc call sysStatsPill setCpuLiveUpdates false
//   - qs ipc call sysStatsPill setMemLiveUpdates false
//   - qs ipc call killTargetPill activatePickMode
//   - qs ipc call shell setShowKillTargetPill true
//   - qs ipc call sysStatsPill toggleGpuLiveUpdates
//   - qs ipc call shell setWsMinimumShown 7
//   - qs ipc call shell setWsShowOnlyActive true
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
//   LEFT:   App Launcher, Quick Launch, FreshRSS, Media Player
//   CENTER: Workspaces
//   RIGHT:  System Stats, System Tray, Connectivity (Network+Bluetooth+Audio),
//           Clock, Notifications, Power
//
// Dual default:
//   TOP:    Clock, Workspaces, System Tray, Notifications, Power
//   BOTTOM: Sys Stats, Launcher, Quick Launch, FreshRSS, Config menu,
//           Net · BT · Audio
// =============================================================================

import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.Mpris
import Quickshell.Io as Io
import "components"
import "widgets"

ShellRoot {
    id: root

    // --- Widget visibility (config defaults in Config.qml; IPC overrides until qs restart) ---
    property bool showLauncherPill: true
    property bool showQuickLaunchPill: true
    property bool showMediaWidget: false
    property bool showWorkspacesPill: true
    property bool showStatsWidget: true
    property bool showTrayPill: true
    property bool showNetworkPill: true
    property bool showBluetoothPill: true
    property bool showAudioPill: true
    property bool showClockPill: true
    property bool showNotificationPill: true
    property bool showPowerPill: true
    property bool showKillTargetPill: false
    property bool showFreshRssPill: true
    property bool showHyprInspPill: false
    property bool showControlBarPill: true       // Bar control / config menu icon on the bar
    property bool showColorPresets: true         // Colors panel: built-in / custom presets section
    property bool showMagicWorkspacePill: true   // Magic pill inside WorkspacesPill (wsShowSpecialPill)
    // Sys Stats gauges (Options panel; all on by default)
    property bool showStatCpu: true
    property bool showStatMem: true
    property bool showStatGpu: true
    // Util bar graphs on the Sys Stats pill face (labels / % always stay)
    property bool showStatGauges: true
    // Circular gauges + history in Sys Stats metrics popups (process lists always stay)
    property bool showStatMenuGraphs: true
    // Network details traffic sparkline (adapters / connections stay)
    property bool showNetTrafficGraph: true
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

    // Clock format string (Qt.formatDateTime); Config default, persisted override.
    property string clockFormat: "dddd, MM·dd·yyyy | HH:mm:ss"

    // "classic" = one bar with left|center|right zones; "dual" = top+bottom centered bars
    property string barLayoutMode: "classic"

    // Runtime layout: [{ id, zone }, ...] — classic: left|center|right; dual: top|bottom
    property var widgetLayout: []

    // Runtime Quick Launch pins (Config default, editable from BarControlBar, persisted)
    property var quickLaunchApps: []

    // Wallpaper directory (Config default; editable from BarControlBar, persisted)
    property string wallpaperDir: "/home/crome/Pictures/wallpapers"
    property string wallpaperCurrent: ""
    // Preferred wallpaper thumbnail width (px); grid stretches tiles to fill the panel.
    property int wallpaperTileSize: 148

    // Per-widget pill scale (1.0 = default). Keys match widgetCatalog / layout ids.
    property var widgetScales: ({})

    // Density: auto-hide deprioritized pills on narrow screens (see Config.uiDensity*).
    // User/IPC show* flags stay as preferences; density gates actual visibility.
    property bool densityHideQuickLaunch: false
    property bool densityHideStats: false
    property bool densityHideSecondary: false   // FreshRSS, media, kill-target
    property bool densityHideConnectivity: false  // Network + Bluetooth

    // Effective visibility helpers (preference AND density)
    readonly property bool effQuickLaunch: showQuickLaunchPill && !densityHideQuickLaunch
    readonly property bool effStats: showStatsWidget && !densityHideStats
    readonly property bool effFreshRss: showFreshRssPill && !densityHideSecondary
    readonly property bool effMedia: showMediaWidget && !densityHideSecondary
    readonly property bool effKillTarget: showKillTargetPill && !densityHideSecondary
    readonly property bool effNetwork: showNetworkPill && !densityHideConnectivity
    readonly property bool effBluetooth: showBluetoothPill && !densityHideConnectivity
    readonly property bool effConnectivity: effNetwork || effBluetooth

    // Catalog for BarControlBar menus (id → label + visibility property name)
    readonly property var widgetCatalog: [
        { id: "launcher",      label: "Launcher",      vis: "showLauncherPill" },
        { id: "quickLaunch",   label: "Quick Launch",  vis: "showQuickLaunchPill" },
        { id: "freshRss",      label: "FreshRSS",      vis: "showFreshRssPill" },
        { id: "media",         label: "Media",         vis: "showMediaWidget" },
        { id: "workspaces",    label: "Workspaces",    vis: "showWorkspacesPill" },
        { id: "stats",         label: "Sys Stats",     vis: "showStatsWidget" },
        { id: "tray",          label: "System Tray",   vis: "showTrayPill" },
        { id: "connectivity",  label: "Net · BT · Audio", vis: "connectivity" },
        { id: "clock",         label: "Clock",         vis: "showClockPill" },
        { id: "notifications", label: "Notifications", vis: "showNotificationPill" },
        { id: "killTarget",    label: "Kill Target",   vis: "showKillTargetPill" },
        { id: "hyprInsp",      label: "Hypr Inspector", vis: "showHyprInspPill" },
        { id: "controlBar",    label: "Config menu",   vis: "showControlBarPill" },
        { id: "power",         label: "Power",         vis: "showPowerPill" }
    ]

    // Workspace behavior (Config defaults; runtime + bar-layout.json via Options / IPC)
    property int  wsMinimumShown: 3
    property bool wsShowOnlyActive: false
    property int  wsStartupWorkspace: 0   // 0 = do not touch focus (safe for qs reload)
    property bool wsStartupCloseMagic: false

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
            root.showMediaWidget = cfg.showMediaPill
            root.showWorkspacesPill = cfg.showWorkspacesPill
            root.showStatsWidget = cfg.showStatsPill
            root.showTrayPill = cfg.showTrayPill
            root.showNetworkPill = cfg.showNetworkPill
            root.showBluetoothPill = cfg.showBluetoothPill
            root.showAudioPill = cfg.showAudioPill
            root.showClockPill = cfg.showClockPill
            root.showNotificationPill = cfg.showNotificationPill
            root.showPowerPill = cfg.showPowerPill
            root.showKillTargetPill = cfg.showKillTargetPill
            root.showFreshRssPill = cfg.showFreshRssPill
            root.showHyprInspPill = cfg.showHyprInspPill
            root.showControlBarPill = cfg.showControlBarPill
            root.showColorPresets = true
            root.showMagicWorkspacePill = cfg.wsShowSpecialPill
            root.showStatCpu = true
            root.showStatMem = true
            root.showStatGpu = true
            root.showStatGauges = true
            root.showStatMenuGraphs = true
            root.showNetTrafficGraph = true
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
            Qt.callLater(function() { bar.refreshThemeSavedList() })

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
                const p = barLayoutAdapter.barPosition
                if (p === "top" || p === "bottom")
                    bar.barPosition = p
                if (barLayoutAdapter.barLayoutMode === "dual" || barLayoutAdapter.barLayoutMode === "classic")
                    root.barLayoutMode = barLayoutAdapter.barLayoutMode
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
                // Visibility (only apply keys that exist in the adapter defaults)
                root.showLauncherPill = barLayoutAdapter.showLauncherPill
                root.showQuickLaunchPill = barLayoutAdapter.showQuickLaunchPill
                root.showMediaWidget = barLayoutAdapter.showMediaWidget
                root.showWorkspacesPill = barLayoutAdapter.showWorkspacesPill
                root.showStatsWidget = barLayoutAdapter.showStatsWidget
                root.showTrayPill = barLayoutAdapter.showTrayPill
                root.showNetworkPill = barLayoutAdapter.showNetworkPill
                root.showBluetoothPill = barLayoutAdapter.showBluetoothPill
                root.showAudioPill = barLayoutAdapter.showAudioPill
                root.showClockPill = barLayoutAdapter.showClockPill
                root.showNotificationPill = barLayoutAdapter.showNotificationPill
                root.showPowerPill = barLayoutAdapter.showPowerPill
                root.showKillTargetPill = barLayoutAdapter.showKillTargetPill
                root.showFreshRssPill = barLayoutAdapter.showFreshRssPill
                root.showHyprInspPill = barLayoutAdapter.showHyprInspPill
                root.showControlBarPill = barLayoutAdapter.showControlBarPill
                if (barLayoutAdapter.hasColorPresetPrefs)
                    root.showColorPresets = barLayoutAdapter.showColorPresets
                if (barLayoutAdapter.hasStatPrefs) {
                    root.showStatCpu = barLayoutAdapter.showStatCpu
                    root.showStatMem = barLayoutAdapter.showStatMem
                    root.showStatGpu = barLayoutAdapter.showStatGpu
                    root.showStatGauges = barLayoutAdapter.showStatGauges
                    root.showStatMenuGraphs = barLayoutAdapter.showStatMenuGraphs
                    root.showNetTrafficGraph = barLayoutAdapter.showNetTrafficGraph
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
                    root.wsStartupWorkspace = Math.max(0, Math.min(10, barLayoutAdapter.wsStartupWorkspace))
                    root.wsStartupCloseMagic = barLayoutAdapter.wsStartupCloseMagic
                }
                bar.applyUiScale()
                Qt.callLater(function() { bar.applyWidgetLayout() })
            }
            onLoadFailed: {
                // No saved preference yet — keep Config / current value.
            }
            Io.JsonAdapter {
                id: barLayoutAdapter
                property string barPosition: "top"
                property string barLayoutMode: "classic"
                property real uiScaleManual: 0
                property int barEdgeMargin: 0
                property real barSizeScale: 1.0
                property bool flushWindowsToBar: false
                property int tooltipDelay: 1550
                property string tooltipAlignJson: ""
                property string clockFormat: ""
                property string widgetLayoutJson: ""
                property string widgetLayoutClassicJson: ""
                property string widgetLayoutDualJson: ""
                property string quickLaunchAppsJson: ""
                property string wallpaperDir: ""
                property string wallpaperCurrent: ""
                property int wallpaperTileSize: 148
                property string widgetScalesJson: ""
                property bool showLauncherPill: true
                property bool showQuickLaunchPill: true
                property bool showMediaWidget: false
                property bool showWorkspacesPill: true
                property bool showStatsWidget: true
                property bool showTrayPill: true
                property bool showNetworkPill: true
                property bool showBluetoothPill: true
                property bool showAudioPill: true
                property bool showClockPill: true
                property bool showNotificationPill: true
                property bool showPowerPill: true
                property bool showKillTargetPill: false
                property bool showFreshRssPill: true
                property bool showHyprInspPill: false
                property bool showControlBarPill: true
                // Colors panel presets section (BarControlBar → Options)
                property bool hasColorPresetPrefs: false
                property bool showColorPresets: true
                // Workspace Options (BarControlBar → Options)
                property bool hasWorkspacePrefs: false
                property bool showMagicWorkspacePill: true
                property int  wsMinimumShown: 3
                property bool wsShowOnlyActive: false
                property int  wsStartupWorkspace: 0
                property bool wsStartupCloseMagic: false
                // Sys stats section visibility
                property bool hasStatPrefs: false
                property bool showStatCpu: true
                property bool showStatMem: true
                property bool showStatGpu: true
                property bool showStatGauges: true
                property bool showStatMenuGraphs: true
                property bool showNetTrafficGraph: true
                property bool showNetworkFullIp: false
                property bool showNetworkLastOctet: true
                property bool showNetworkDeviceName: false
                // Audio popup / control-bar Audio panel sections
                property bool hasAudioMenuPrefs: false
                property bool showEchoCancelInMenu: true
                property bool showAudioSummary: true
                property bool showAudioDefaults: true
                property bool showAudioLevelMeters: true
                property bool audioSummaryExpanded: true
                property bool audioDefaultsExpanded: true
                property bool hasFreshRssPrefs: false
                property bool freshRssFiltersExpanded: true
            }
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
                out.push({
                    id: "builtin:" + slug,
                    name: p.name || slug,
                    builtin: true,
                    path: ""
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
            try {
                barLayoutAdapter.widgetScalesJson = JSON.stringify(root.widgetScales || {})
            } catch (e) {
                barLayoutAdapter.widgetScalesJson = "{}"
            }
            barLayoutAdapter.showLauncherPill = root.showLauncherPill
            barLayoutAdapter.showQuickLaunchPill = root.showQuickLaunchPill
            barLayoutAdapter.showMediaWidget = root.showMediaWidget
            barLayoutAdapter.showWorkspacesPill = root.showWorkspacesPill
            barLayoutAdapter.showStatsWidget = root.showStatsWidget
            barLayoutAdapter.showTrayPill = root.showTrayPill
            barLayoutAdapter.showNetworkPill = root.showNetworkPill
            barLayoutAdapter.showBluetoothPill = root.showBluetoothPill
            barLayoutAdapter.showAudioPill = root.showAudioPill
            barLayoutAdapter.showClockPill = root.showClockPill
            barLayoutAdapter.showNotificationPill = root.showNotificationPill
            barLayoutAdapter.showPowerPill = root.showPowerPill
            barLayoutAdapter.showKillTargetPill = root.showKillTargetPill
            barLayoutAdapter.showFreshRssPill = root.showFreshRssPill
            barLayoutAdapter.showHyprInspPill = root.showHyprInspPill
            barLayoutAdapter.showControlBarPill = root.showControlBarPill
            barLayoutAdapter.hasColorPresetPrefs = true
            barLayoutAdapter.showColorPresets = root.showColorPresets
            barLayoutAdapter.hasWorkspacePrefs = true
            barLayoutAdapter.showMagicWorkspacePill = root.showMagicWorkspacePill
            barLayoutAdapter.wsMinimumShown = root.wsMinimumShown
            barLayoutAdapter.wsShowOnlyActive = root.wsShowOnlyActive
            barLayoutAdapter.wsStartupWorkspace = root.wsStartupWorkspace
            barLayoutAdapter.wsStartupCloseMagic = root.wsStartupCloseMagic
            barLayoutAdapter.hasStatPrefs = true
            barLayoutAdapter.showStatCpu = root.showStatCpu
            barLayoutAdapter.showStatMem = root.showStatMem
            barLayoutAdapter.showStatGpu = root.showStatGpu
            barLayoutAdapter.showStatGauges = root.showStatGauges
            barLayoutAdapter.showStatMenuGraphs = root.showStatMenuGraphs
            barLayoutAdapter.showNetTrafficGraph = root.showNetTrafficGraph
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
        function setShowStatMenuGraphs(enabled) {
            root.showStatMenuGraphs = !!enabled
            persistBarLayout()
        }
        function setShowNetTrafficGraph(enabled) {
            root.showNetTrafficGraph = !!enabled
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
        function setWsMinimumShown(count) {
            let n = Number(count)
            if (!(n >= 1))
                n = 1
            if (n > 10)
                n = 10
            root.wsMinimumShown = Math.round(n)
            persistBarLayout()
        }
        function setWsShowOnlyActive(enabled) {
            root.wsShowOnlyActive = !!enabled
            persistBarLayout()
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
        function setNetworkAppletAutostart(enabled) {
            if (networkPill && networkPill.setAppletAutostart)
                networkPill.setAppletAutostart(!!enabled)
        }
        function getNetworkAppletAutostart() {
            return networkPill ? !!networkPill.appletAutostartEnabled : true
        }
        function setBluetoothAppletAutostart(enabled) {
            if (bluetoothPill && bluetoothPill.setAppletAutostart)
                bluetoothPill.setAppletAutostart(!!enabled)
        }
        function getBluetoothAppletAutostart() {
            return bluetoothPill ? !!bluetoothPill.bluemanAutostartEnabled : true
        }
        function setMetricsLiveUpdates(enabled) {
            if (sysStatsPill && sysStatsPill.setMetricsLiveUpdates)
                sysStatsPill.setMetricsLiveUpdates(!!enabled)
        }
        function getMetricsLiveUpdates() {
            if (sysStatsPill)
                return !!(sysStatsPill.cpuLiveUpdates || sysStatsPill.memLiveUpdates || sysStatsPill.gpuLiveUpdates)
            return !!cfg.popupStatsLiveUpdates
        }
        function refreshOptionsState() {
            // Nudge applets / echo-cancel to refresh status for Options panel
            try {
                if (audioPill && audioPill.refreshEchoCancelStatus)
                    audioPill.refreshEchoCancelStatus()
            } catch (e) {}
            try {
                if (networkPill && networkPill.refreshAppletStatus)
                    networkPill.refreshAppletStatus()
            } catch (e2) {}
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
                if (z === "bottom" || z === "right")
                    return "bottom"
                return "top"
            }
            if (z === "center" || z === "right")
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
                    if (!known[id] || seen[id])
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
            switch (String(id)) {
            case "launcher": return launcherPill
            case "quickLaunch": return quickLaunchPill
            case "freshRss": return freshRssPill
            case "media": return mediaPill
            case "workspaces": return workspacesPill
            case "stats": return sysStatsPill
            case "tray": return trayPill
            case "connectivity": return connectivityPill
            case "audio": return null  // audio lives inside connectivityPill
            case "clock": return clockPill
            case "notifications": return notificationBell
            case "killTarget": return killTargetPill
            case "hyprInsp": return hyprInspPill
            case "controlBar": return controlBarPill
            case "power": return powerMenu
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
                    }
                } else {
                    zoneItem = entry.zone === "center" ? centerZone
                        : (entry.zone === "right" ? rightZone : leftZone)
                    chrome = barBg
                }
                w.parent = zoneItem
                bar.assignWidgetChrome(w, chrome)
                if (entry.id === "connectivity") {
                    bar.assignWidgetChrome(networkPill, chrome)
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

        function getWidgetVisible(id) {
            switch (String(id)) {
            case "launcher": return root.showLauncherPill
            case "quickLaunch": return root.showQuickLaunchPill
            case "freshRss": return root.showFreshRssPill
            case "media": return root.showMediaWidget
            case "workspaces": return root.showWorkspacesPill
            case "stats": return root.showStatsWidget
            case "tray": return root.showTrayPill
            case "connectivity": return root.showNetworkPill || root.showBluetoothPill || root.showAudioPill
            case "network": return root.showNetworkPill
            case "bluetooth": return root.showBluetoothPill
            case "audio": return root.showAudioPill
            case "clock": return root.showClockPill
            case "notifications": return root.showNotificationPill
            case "killTarget": return root.showKillTargetPill
            case "hyprInsp": return root.showHyprInspPill
            case "controlBar": return root.showControlBarPill
            case "power": return root.showPowerPill
            default: return false
            }
        }

        function setWidgetVisible(id, enabled) {
            const on = !!enabled
            switch (String(id)) {
            case "launcher": root.showLauncherPill = on; break
            case "quickLaunch": root.showQuickLaunchPill = on; break
            case "freshRss": root.showFreshRssPill = on; break
            case "media": root.showMediaWidget = on; break
            case "workspaces": root.showWorkspacesPill = on; break
            case "stats": root.showStatsWidget = on; break
            case "tray": root.showTrayPill = on; break
            case "connectivity":
                root.showNetworkPill = on
                root.showBluetoothPill = on
                root.showAudioPill = on
                break
            case "network": root.showNetworkPill = on; break
            case "bluetooth": root.showBluetoothPill = on; break
            case "audio": root.showAudioPill = on; break
            case "clock": root.showClockPill = on; break
            case "notifications": root.showNotificationPill = on; break
            case "killTarget": root.showKillTargetPill = on; break
            case "hyprInsp": root.showHyprInspPill = on; break
            case "controlBar": root.showControlBarPill = on; break
            case "power": root.showPowerPill = on; break
            default: return
            }
            persistBarLayout()
        }

        function toggleWidgetVisible(id) {
            setWidgetVisible(id, !getWidgetVisible(id))
        }

        function setWidgetZone(id, zone) {
            const z = bar.coerceZone(zone, root.barLayoutMode)
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
                out.push({
                    icon: e.icon ? String(e.icon) : "",
                    glyph: e.glyph ? String(e.glyph) : "",
                    command: command,
                    tooltip: e.tooltip ? String(e.tooltip) : ""
                })
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

        function notificationSupportsPanel() {
            return cfg.notificationSupportsPanel()
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
        readonly property alias themeStatTempUiRows: cfg.themeStatTempUiRows
        readonly property alias themeEditableNumbers: cfg.themeEditableNumbers
        readonly property string themeIoScript: "/home/crome/.config/quickshell/scripts/theme-io.sh"
        property string themeStatus: ""
        property var themeSavedList: []
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
        property alias barEdgeMargin: cfg.barEdgeMargin
        property alias barSizeScale: cfg.barSizeScale
        property alias flushWindowsToBar: cfg.flushWindowsToBar
        readonly property alias popupBarGap: cfg.popupBarGap
        readonly property alias barHeight: cfg.barHeight
        // Hyprland general:gaps_out (top / bottom). Used to pull windows against the bar.
        property int hyprGapsOutTop: 14
        property int hyprGapsOutBottom: 14
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
                    hyprGapsOutBottom = nums[2]
                } else if (nums.length === 1) {
                    hyprGapsOutTop = nums[0]
                    hyprGapsOutBottom = nums[0]
                } else if (j && j.int !== undefined) {
                    var v = Number(j.int)
                    if (v >= 0) {
                        hyprGapsOutTop = v
                        hyprGapsOutBottom = v
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
            if (bar.isDualLayout() && bar.edgeForItem(item) === "bottom")
                return bottomBarBg
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
        readonly property alias iconSizePopup: cfg.iconSizePopup
        readonly property alias iconSizePower: cfg.iconSizePower
        readonly property alias iconSizeMediaArt: cfg.iconSizeMediaArt
        readonly property alias iconSizeTray: cfg.iconSizeTray
        readonly property alias quickLaunchIcon: cfg.quickLaunchIcon
        readonly property alias quickLaunchSpacing: cfg.quickLaunchSpacing
        readonly property alias quickLaunchPaddingH: cfg.quickLaunchPaddingH
        // Runtime list (editable from BarControlBar); falls back to Config via clone on start
        property alias quickLaunchApps: root.quickLaunchApps
        property alias wallpaperDir: root.wallpaperDir
        property alias wallpaperCurrent: root.wallpaperCurrent
        property alias wallpaperTileSize: root.wallpaperTileSize
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
        readonly property alias popupMediaWidth: cfg.popupMediaWidth
        readonly property alias popupMediaHeight: cfg.popupMediaHeight
        readonly property alias popupPowerWidth: cfg.popupPowerWidth
        readonly property alias popupPowerHeight: cfg.popupPowerHeight
        readonly property alias popupContextMenuWidth: cfg.popupContextMenuWidth
        readonly property alias popupContextMenuRowHeight: cfg.popupContextMenuRowHeight
        readonly property alias popupCalendarWidth: cfg.popupCalendarWidth
        readonly property alias popupCalendarHeight: cfg.popupCalendarHeight
        readonly property alias popupBluetoothWidth: cfg.popupBluetoothWidth
        readonly property alias popupBluetoothHeight: cfg.popupBluetoothHeight
        readonly property alias bluetoothScanSeconds: cfg.bluetoothScanSeconds
        readonly property alias popupNetworkWidth: cfg.popupNetworkWidth
        readonly property alias popupNetworkWifiWidth: cfg.popupNetworkWifiWidth
        readonly property alias popupNetworkHeight: cfg.popupNetworkHeight
        readonly property alias popupStatsCpuWidth: cfg.popupStatsCpuWidth
        readonly property alias popupStatsCpuHeight: cfg.popupStatsCpuHeight
        readonly property alias popupStatsGpuWidth: cfg.popupStatsGpuWidth
        readonly property alias popupStatsGpuHeight: cfg.popupStatsGpuHeight
        readonly property alias popupStatsMemWidth: cfg.popupStatsMemWidth
        readonly property alias popupStatsMemHeight: cfg.popupStatsMemHeight
        readonly property alias popupStatsCpuAnchorX: cfg.popupStatsCpuAnchorX
        readonly property alias popupStatsCpuAnchorWholePill: cfg.popupStatsCpuAnchorWholePill
        readonly property alias popupStatsCpuOffsetX: cfg.popupStatsCpuOffsetX
        readonly property alias popupStatsCpuOffsetY: cfg.popupStatsCpuOffsetY
        readonly property alias popupStatsCpuBarGap: cfg.popupStatsCpuBarGap
        readonly property alias popupStatsGpuAnchorX: cfg.popupStatsGpuAnchorX
        readonly property alias popupStatsGpuAnchorWholePill: cfg.popupStatsGpuAnchorWholePill
        readonly property alias popupStatsGpuOffsetX: cfg.popupStatsGpuOffsetX
        readonly property alias popupStatsGpuOffsetY: cfg.popupStatsGpuOffsetY
        readonly property alias popupStatsGpuBarGap: cfg.popupStatsGpuBarGap
        readonly property alias popupStatsMemAnchorX: cfg.popupStatsMemAnchorX
        readonly property alias popupStatsMemAnchorWholePill: cfg.popupStatsMemAnchorWholePill
        readonly property alias popupStatsMemOffsetX: cfg.popupStatsMemOffsetX
        readonly property alias popupStatsMemOffsetY: cfg.popupStatsMemOffsetY
        readonly property alias popupStatsMemBarGap: cfg.popupStatsMemBarGap
        readonly property alias popupStatsLiveUpdates: cfg.popupStatsLiveUpdates
        readonly property alias popupStatsPersistPause: cfg.popupStatsPersistPause
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
        readonly property alias iconAudioHeadset: cfg.iconAudioHeadset
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
        readonly property alias iconPower: cfg.iconPower
        readonly property alias killTargetIcon: cfg.killTargetIcon
        readonly property alias killTargetTooltip: cfg.killTargetTooltip
        readonly property alias killTargetOverlayDim: cfg.killTargetOverlayDim
        readonly property alias iconLock: cfg.iconLock
        readonly property alias iconLogout: cfg.iconLogout
        readonly property alias iconReboot: cfg.iconReboot
        readonly property alias iconShutdown: cfg.iconShutdown
        readonly property alias iconBios: cfg.iconBios
        readonly property alias iconLauncher: cfg.iconLauncher
        readonly property alias iconHyprInsp: cfg.iconHyprInsp
        readonly property alias iconControlBar: cfg.iconControlBar
        readonly property alias launcherCommand: cfg.launcherCommand
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
        readonly property alias wsHoverYellow: cfg.wsHoverYellow
        property alias wsActiveBg: cfg.wsActiveBg
        readonly property alias wsActiveBorder: cfg.wsActiveBorder
        property alias wsActiveText: cfg.wsActiveText
        property alias wsInactiveText: cfg.wsInactiveText
        readonly property alias wsButtonWidth: cfg.wsButtonWidth
        readonly property alias wsButtonHeight: cfg.wsButtonHeight
        readonly property alias wsIconSize: cfg.wsIconSize
        readonly property alias wsNumberSize: cfg.wsNumberSize
        readonly property alias wsSpacing: cfg.wsSpacing
        readonly property alias wsText: cfg.wsText
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
        readonly property alias wsSpecialName: cfg.wsSpecialName
        readonly property alias wsIconSpecial: cfg.wsIconSpecial
        readonly property alias wsShowSpecialPill: cfg.wsShowSpecialPill
        // Bound to root so Options / IPC / WorkspacesPill stay in sync
        property alias wsMinimumShown: root.wsMinimumShown
        property alias wsShowOnlyActive: root.wsShowOnlyActive
        property alias wsStartupWorkspace: root.wsStartupWorkspace
        property alias wsStartupCloseMagic: root.wsStartupCloseMagic
        property alias showMagicWorkspacePill: root.showMagicWorkspacePill
        property alias showControlBarPill: root.showControlBarPill
        property alias showColorPresets: root.showColorPresets
        property alias showStatCpu: root.showStatCpu
        property alias showStatMem: root.showStatMem
        property alias showStatGpu: root.showStatGpu
        property alias showStatGauges: root.showStatGauges
        property alias showStatMenuGraphs: root.showStatMenuGraphs
        property alias showNetTrafficGraph: root.showNetTrafficGraph
        property alias showNetworkFullIp: root.showNetworkFullIp
        property alias showNetworkLastOctet: root.showNetworkLastOctet
        property alias showNetworkDeviceName: root.showNetworkDeviceName
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
        function wsIsSpecialName(name) { return cfg.wsIsSpecialName(name) }

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
        property alias statUtilThreshold1: cfg.statUtilThreshold1
        property alias statUtilThreshold2: cfg.statUtilThreshold2
        property alias statUtilThreshold3: cfg.statUtilThreshold3
        property alias statTempWarmAt: cfg.statTempWarmAt
        property alias statTempHotAt: cfg.statTempHotAt
        function statUtilColor(util) { return cfg.statUtilColor(util) }
        function statTempColor(temp) { return cfg.statTempColor(temp) }

        // --- Cava visualizer
        readonly property alias cavaBarCount: cfg.cavaBarCount
        readonly property alias cavaBarGap: cfg.cavaBarGap
        readonly property alias cavaInactive: cfg.cavaInactive
        readonly property alias cavaActive: cfg.cavaActive
        readonly property alias cavaAnimFast: cfg.cavaAnimFast
        readonly property alias cavaAnimSlow: cfg.cavaAnimSlow

        // --- Dividers
        readonly property alias divider: cfg.divider
        readonly property alias dividerStrong: cfg.dividerStrong
        readonly property alias dividerThickness: cfg.dividerThickness
        readonly property alias dividerSubtle: cfg.dividerSubtle

        // --- Animation & interaction
        readonly property alias animFast: cfg.animFast
        readonly property alias animMedium: cfg.animMedium
        readonly property alias animSlow: cfg.animSlow
        property alias tooltipDelay: cfg.tooltipDelay
        property alias tooltipAlign: root.tooltipAlign

        // --- Tray menu
        readonly property alias menuCheckMark: cfg.menuCheckMark
        readonly property alias menuUncheckedMark: cfg.menuUncheckedMark
        readonly property alias menuCheckedRow: cfg.menuCheckedRow
        readonly property alias menuBtnNone: cfg.menuBtnNone
        readonly property alias menuBtnCheck: cfg.menuBtnCheck
        readonly property alias menuBtnRadio: cfg.menuBtnRadio

        // --- Z layers
        readonly property alias zMediaPill: cfg.zMediaPill
        readonly property alias zSysStats: cfg.zSysStats

        Rectangle {
            id: barBg
            readonly property bool compact: root.barLayoutMode === "dual"
            readonly property int hugMeasured: Math.max(bar.sp(120), Math.min(parent.width - 2 * bar.sideMargin,
                              centerZone.implicitWidth + 2 * bar.barContentHMargin))
            // Ignore 1–15px text ticks (clock/stats) so the glass does not relayout every second.
            property int hugW: 200
            onHugMeasuredChanged: {
                if (compact && Math.abs(hugMeasured - hugW) >= 16)
                    hugW = hugMeasured
            }
            onCompactChanged: hugW = hugMeasured
            Component.onCompleted: hugW = hugMeasured
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: bar.barIsTopEdge ? 0 : bar.barContentVMargin
            anchors.bottomMargin: bar.barIsTopEdge ? bar.barContentVMargin : 0
            x: compact ? Math.round((parent.width - hugW) / 2) : bar.sideMargin
            width: compact ? hugW : Math.max(0, parent.width - 2 * bar.sideMargin)
            radius: bar.barRadius
            topLeftRadius: (bar.barIsTopEdge && bar.barGlassFlush) ? 0 : bar.barRadius
            topRightRadius: (bar.barIsTopEdge && bar.barGlassFlush) ? 0 : bar.barRadius
            bottomLeftRadius: (!bar.barIsTopEdge && bar.barGlassFlush) ? 0 : bar.barRadius
            bottomRightRadius: (!bar.barIsTopEdge && bar.barGlassFlush) ? 0 : bar.barRadius
            color: bar.glassBg
            border.width: Math.max(1, bar.controlBorderWidth)
            border.color: bar.glassBorder

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

            // Host for the temporary control strip (PopupWindow; zero-size Item).
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
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
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
                Layout.preferredWidth: bar.widgetW("launcher", bar.sp(42))
                Layout.preferredHeight: bar.pillHeight
                Layout.alignment: Qt.AlignVCenter
                radius: bar.pillRadius
                color: launcherMouse.containsMouse ? bar.glassHover : bar.pillBg
                border.width: bar.controlBorderWidth
                border.color: launcherMouse.containsMouse ? bar.accent : bar.pillBorder

                Text {
                    anchors.centerIn: parent
                    text: bar.iconLauncher
                    font.pixelSize: bar.widgetW("launcher", bar.iconSizePillLarge)
                    font.family: bar.fontFamily
                    color: launcherMouse.containsMouse
                           ? bar.accent
                           : (bar.iconColor !== undefined ? bar.iconColor : bar.subtext)
                }

                MouseArea {
                    id: launcherMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["sh", "-c", bar.launcherCommand])
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

            // ─ Media Player ─
            MediaPill {
                id: mediaPill
                parent: widgetPool
                visible: root.effMedia
                bar: bar
                barBg: barBg
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
                barBg: barBg
                mediaActive: mediaPill.hasMedia
            }

            // ─ System Tray ─
            SystemTrayPill {
                id: trayPill
                parent: widgetPool
                visible: root.showTrayPill
                bar: bar
                barBg: barBg
            }

            // ─ Connectivity + Audio (Network · Bluetooth · Sound as one pill) ─
            Rectangle {
                id: connectivityPill
                parent: widgetPool
                visible: root.effConnectivity || root.showAudioPill
                Layout.preferredHeight: bar.pillHeight
                Layout.preferredWidth: connectivityRow.implicitWidth + 10
                Layout.alignment: Qt.AlignVCenter
                radius: bar.pillRadius
                color: bar.pillBg
                border.width: bar.controlBorderWidth
                border.color: bar.pillBorder

                Row {
                    id: connectivityRow
                    anchors.centerIn: parent
                    spacing: Math.max(2, bar.widgetW("connectivity", 4))

                    NetworkPill {
                        id: networkPill
                        embedded: true
                        pillScale: bar.widgetScale("connectivity")
                        visible: root.effNetwork
                        bar: bar
                        barBg: barBg
                    }

                    Rectangle {
                        visible: root.effNetwork && root.effBluetooth
                        width: Math.max(1, bar.widgetW("connectivity", bar.dividerThickness))
                        height: 17
                        anchors.verticalCenter: parent.verticalCenter
                        color: bar.divider
                    }

                    BluetoothPill {
                        id: bluetoothPill
                        embedded: true
                        pillScale: bar.widgetScale("connectivity")
                        visible: root.effBluetooth
                        bar: bar
                        barBg: barBg
                    }

                    Rectangle {
                        visible: (root.effNetwork || root.effBluetooth) && root.showAudioPill
                        width: Math.max(1, bar.widgetW("connectivity", bar.dividerThickness))
                        height: 17
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

            // ─ Kill Target ─
            KillTargetPill {
                id: killTargetPill
                parent: widgetPool
                visible: root.effKillTarget
                bar: bar
            }

            // ─ Hyprland Config Inspector ─
            Rectangle {
                id: hyprInspPill
                parent: widgetPool
                visible: root.showHyprInspPill
                Layout.preferredWidth: bar.widgetW("hyprInsp", bar.sp(42))
                Layout.preferredHeight: bar.pillHeight
                Layout.alignment: Qt.AlignVCenter
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

            // ─ Bar control / config menu ─
            Rectangle {
                id: controlBarPill
                parent: widgetPool
                visible: root.showControlBarPill
                Layout.preferredWidth: bar.widgetW("controlBar", bar.sp(42))
                Layout.preferredHeight: bar.pillHeight
                Layout.alignment: Qt.AlignVCenter
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

            // ─ Power Menu ─
            PowerMenu {
                id: powerMenu
                parent: widgetPool
                visible: root.showPowerPill
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
            target: "networkPill"
            function showPopup(): void {
                if (networkPill && networkPill.showPopup) networkPill.showPopup()
            }
            function hidePopup(): void {
                if (networkPill && networkPill.hidePopup) networkPill.hidePopup()
            }
            function togglePopup(): void {
                if (networkPill && networkPill.togglePopup) networkPill.togglePopup()
            }
            function setWifi(enabled: bool): void {
                if (networkPill && networkPill.setWifi) networkPill.setWifi(enabled)
            }
            function toggleWifi(): void {
                if (networkPill && networkPill.toggleWifi) networkPill.toggleWifi()
            }
            function enableWifi(): void {
                if (networkPill && networkPill.enableWifi) networkPill.enableWifi()
            }
            function disableWifi(): void {
                if (networkPill && networkPill.disableWifi) networkPill.disableWifi()
            }
            function setNetworking(enabled: bool): void {
                if (networkPill && networkPill.setNetworking) networkPill.setNetworking(enabled)
            }
            function toggleNetworking(): void {
                if (networkPill && networkPill.toggleNetworking) networkPill.toggleNetworking()
            }
            function startScan(): void {
                if (networkPill && networkPill.startScan) networkPill.startScan()
            }
            function stopScan(): void {
                if (networkPill && networkPill.stopScan) networkPill.stopScan()
            }
            function connectSsid(ssid: string): void {
                if (networkPill && networkPill.connectSsid) networkPill.connectSsid(ssid)
            }
            function disconnectDevice(iface: string): void {
                if (networkPill && networkPill.disconnectDevice) networkPill.disconnectDevice(iface)
            }
            function enableDevice(iface: string): void {
                if (networkPill && networkPill.enableDevice) networkPill.enableDevice(iface)
            }
            function disableAllAdapters(): void {
                if (networkPill && networkPill.disableAllAdapters) networkPill.disableAllAdapters()
            }
            function forgetSsid(ssid: string): void {
                if (networkPill && networkPill.forgetSsid) networkPill.forgetSsid(ssid)
            }
            // nm-applet: session-only start/stop (does not change login enablement)
            function startApplet(): void {
                if (networkPill && networkPill.startApplet) networkPill.startApplet()
            }
            function stopApplet(): void {
                if (networkPill && networkPill.stopApplet) networkPill.stopApplet()
            }
            function toggleApplet(): void {
                if (networkPill && networkPill.toggleApplet) networkPill.toggleApplet()
            }
            // nm-applet: persist across reboots (systemctl --user enable/disable)
            function enableApplet(): void {
                if (networkPill && networkPill.enableApplet) networkPill.enableApplet()
            }
            function disableApplet(): void {
                if (networkPill && networkPill.disableApplet) networkPill.disableApplet()
            }
            function setAppletAutostart(enabled: bool): void {
                if (networkPill && networkPill.setAppletAutostart)
                    networkPill.setAppletAutostart(enabled)
            }
            function openEditor(): void {
                if (networkPill && networkPill.openConnectionEditor) networkPill.openConnectionEditor()
            }
            function refreshIp(): void {
                if (networkPill && networkPill.refreshIp) networkPill.refreshIp("")
            }
            function refreshDns(): void {
                if (networkPill && networkPill.refreshDns) networkPill.refreshDns("")
            }
            function activateConnection(id: string): void {
                if (networkPill && networkPill.activateConnection)
                    networkPill.activateConnection(id)
            }
            function deactivateConnection(id: string): void {
                if (networkPill && networkPill.deactivateConnection)
                    networkPill.deactivateConnection(id)
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
            function toggleDoNotDisturb() {
                if (notificationBell && notificationBell.toggleDoNotDisturb) notificationBell.toggleDoNotDisturb()
            }
        }

        Io.IpcHandler {
            target: "killTargetPill"
            function activatePickMode() {
                if (killTargetPill && killTargetPill.activatePickMode) killTargetPill.activatePickMode()
            }
            function cancelPickMode() {
                if (killTargetPill && killTargetPill.cancelPickMode) killTargetPill.cancelPickMode()
            }
        }

        Io.IpcHandler {
            target: "sysStatsPill"
            function setCpuLiveUpdates(enabled: bool) {
                if (sysStatsPill && sysStatsPill.setCpuLiveUpdates) sysStatsPill.setCpuLiveUpdates(enabled)
            }
            function setGpuLiveUpdates(enabled: bool) {
                if (sysStatsPill && sysStatsPill.setGpuLiveUpdates) sysStatsPill.setGpuLiveUpdates(enabled)
            }
            function setMemLiveUpdates(enabled: bool) {
                if (sysStatsPill && sysStatsPill.setMemLiveUpdates) sysStatsPill.setMemLiveUpdates(enabled)
            }
            function setMetricsLiveUpdates(enabled: bool) {
                if (sysStatsPill && sysStatsPill.setMetricsLiveUpdates) sysStatsPill.setMetricsLiveUpdates(enabled)
            }
            function toggleCpuLiveUpdates() {
                if (sysStatsPill && sysStatsPill.toggleCpuLiveUpdates) sysStatsPill.toggleCpuLiveUpdates()
            }
            function toggleGpuLiveUpdates() {
                if (sysStatsPill && sysStatsPill.toggleGpuLiveUpdates) sysStatsPill.toggleGpuLiveUpdates()
            }
            function toggleMemLiveUpdates() {
                if (sysStatsPill && sysStatsPill.toggleMemLiveUpdates) sysStatsPill.toggleMemLiveUpdates()
            }
            function toggleMetricsLiveUpdates() {
                if (sysStatsPill && sysStatsPill.toggleMetricsLiveUpdates) sysStatsPill.toggleMetricsLiveUpdates()
            }
        }

    }

    // Dual-mode bottom bar. Hidden in classic mode (no exclusive zone).
    PanelWindow {
        id: bottomBar
        visible: root.barLayoutMode === "dual"
        color: "transparent"
        implicitHeight: bar.barHeight
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
            readonly property int hugMeasured: Math.max(bar.sp(120), Math.min(parent.width - 2 * bar.sideMargin,
                           bottomCenterZone.implicitWidth + 2 * bar.barContentHMargin))
            property int hugW: 200
            onHugMeasuredChanged: {
                if (Math.abs(hugMeasured - hugW) >= 16)
                    hugW = hugMeasured
            }
            Component.onCompleted: hugW = hugMeasured
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: bar.barContentVMargin
            anchors.bottomMargin: 0
            width: hugW
            radius: bar.barRadius
            topLeftRadius: bar.barRadius
            topRightRadius: bar.barRadius
            bottomLeftRadius: bar.barGlassFlush ? 0 : bar.barRadius
            bottomRightRadius: bar.barGlassFlush ? 0 : bar.barRadius
            color: bar.glassBg
            border.width: Math.max(1, bar.controlBorderWidth)
            border.color: bar.glassBorder

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
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: bar.widgetSpacing
            }
        }

        Component.onCompleted: {
            if (root.barLayoutMode === "dual")
                Qt.callLater(function() { bar.applyWidgetLayout() })
        }
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
        function setShowMediaWidget(enabled: bool): void {
            bar.setWidgetVisible("media", enabled)
        }
        function toggleShowMediaWidget(): void {
            bar.toggleWidgetVisible("media")
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
        function setShowNetworkPill(enabled: bool): void {
            bar.setWidgetVisible("network", enabled)
        }
        function toggleShowNetworkPill(): void {
            bar.toggleWidgetVisible("network")
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
        function setClockFormat(format: string): void {
            bar.setClockFormat(format)
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
        function setShowKillTargetPill(enabled: bool): void {
            bar.setWidgetVisible("killTarget", enabled)
        }
        function setShowFreshRssPill(enabled: bool): void {
            bar.setWidgetVisible("freshRss", enabled)
        }
        function toggleShowFreshRssPill(): void {
            bar.toggleWidgetVisible("freshRss")
        }
        function toggleShowKillTargetPill(): void {
            bar.toggleWidgetVisible("killTarget")
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
    }
}