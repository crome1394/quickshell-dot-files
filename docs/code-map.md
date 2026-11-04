# Code map

Where to look in the three largest QML files. Names and section comments are the anchors. These files are too big to read or rewrite whole.

## shell.qml

Header: "Main Quickshell entry point for the Hyprland status bar". It points at `widgets/`, `components/`, `Config.qml`, `widgets/HyprlandInspectorPanel.qml`, and `widgets/ActiveWindowPill.qml`, and lists the IPC calls. The full set is `qs ipc show`.

Section comment "BAR LAYOUT — classic (left / center / right) or dual (top / bottom, centered)":

- Classic zones are LEFT ZONE, CENTER ZONE, and RIGHT ZONE on one bar.
- Dual zones are TOP ZONE and BOTTOM ZONE, each a centered cluster. Glass hugs the widget row.
- Position switches the layout. Widgets reorders, shows, hides, and scales. Each mode keeps its own order in `state/bar-layout.json`.

`ShellRoot` id `root` holds the widget visibility properties under the comment "Widget visibility".

Windows and hosts:

| Name | What it is |
|------|------------|
| `PanelWindow` id `bar` | The classic bar. In dual mode this same window is the top bar. Right-click empty chrome is `MouseArea` id `barBgContext`, which toggles `barControlBar`. |
| `SettingsPanel` id `barControlBar` | The settings window. Comment: "Host for the control strip". |
| `Item` id `widgetPool` | Holding pen for widgets the layout editor moves between zones. Parked off-screen, kept visible so children are not force-hidden. |
| `Rectangle` id `controlBarPill` | Comment: "Settings / config menu". The config-menu pill. It starts in `widgetPool`. |
| `PanelWindow` id `bottomBar` | Comment: "Dual-mode bottom bar". Hidden in classic, so it takes no exclusive zone. |
| `PanelWindow` id `leftEdgeBar` | Comment: "Left edge bar. Dual only, and off until Show left bar." Text rotates 90° clockwise. `EdgeBarFace` id `leftEdgeFace`. |
| `PanelWindow` id `rightEdgeBar` | Comment: "Right edge bar." `EdgeBarFace` id `rightEdgeFace`. |
| `ActiveWindowPill` | Comment: "Focused-window pill". Screen-corner overlay. |
| `Overview` id `overviewLayer` | Comment: "Fullscreen workspace overview". |
| `ShellIpc` | Comment: "Shell and overview IPC live in components/ShellIpc.qml." |

## widgets/settings/SettingsPanel.qml

Header: "Settings window". Right-click on blank main-bar chrome or the gear pill opens it. One `FloatingWindow` titled "Settings", an expandable panel on top, toolbar along the bottom. Window height follows the content.

The header names the toolbar as Position, Display, Wallpaper, Widgets, Options, Themes, App Launcher, Autostart, MIME, Services, Audio, Keybinds, and Clock. It also says what those words mean: Widgets is layout, Options is behavior, Themes is the bar and widget theme, MIME is `MimeAppsTab`, Services is systemd, Audio is `AudioMonitorView`, Keybinds is chord / category / description, Display is monitor resolution / refresh / bit depth, and Clock is Region & Clock.

`controlTabModel` is the button row that is built:

| id | Label | Notes |
|----|-------|-------|
| `display` | Display | `DisplayTab.qml`. Menus are `DisplayMenuRow.qml`, `DisplayModeGroup.qml`, and `DisplayModeChip.qml`. |
| `wallpaper` | Wallpaper | Rename, delete, and drag-drop live in this panel. |
| `widgets` | Widgets | `WidgetsTab.qml`. `toggleMenu("sizes")` lands here. Sizes was merged into Widgets. |
| `options` | Options | Sub-tabs from `optionsTabModel`. |
| `colors` | Themes | The menu id stays `colors`. Sub-tabs use `colorsTab`. |
| `launch` | App Launcher | Shown only when the Quick Launch widget is on. |
| `autostart` | Autostart | |
| `mime` | MIME | |
| `services` | Services | |
| `audio` | Audio | Shown only when the Audio widget is on. |
| `keybinds` | Keybinds | |
| `clock` | Region & Clock | Tabs are region and clock. If the Clock widget is off, the clock tab falls back to region. |

`toggleMenu("position")` opens Options on the Bar tab. It is not its own page.

`activeMenu` selects the page inside `panelStack`. The window is `FloatingWindow` id `controlPopup`, title "Settings", under the comment "Floating Hyprland window (drag like the inspector). Esc / ✕ close it."

Options tabs from `optionsTabModel`, gated by `optionsSectionVisible`:

| id | Label | When it shows |
|----|-------|----------------|
| `bar` | Bar | Always |
| `appmenu` | App Menu | Launcher widget is on |
| `tooltips` | Tooltips | Always |
| `workspaces` | Workspaces | Workspaces widget is on |
| `overview` | Overview | Always |
| `audio` | Audio | Audio widget is on |
| `network` | Network | Network widget is on |
| `bluetooth` | Bluetooth | Bluetooth widget is on |
| `notifications` | Notifications | Always |
| `stats` | Stats | Stats widget is on |
| `dock` | Dock | `dockSettingsVisible` (an icon pill is on) |
| `activewindow` | Active Window | Active Window widget is on |
| `screensaver` | Screensaver | Always |
| `screenshot` | ScreenShots | Always. Section comment: "ScreenShots options". |
| `freshrss` | FreshRSS | FreshRSS widget is on |

Themes sub-tabs, comment "Themes sub-tabs": Theming (`theming`), Thresholds (`thresholds`, only when Audio or Stats is on; otherwise the tab falls back to Theming), Fonts (`fonts`), and Presets (`presets`, when color presets are shown).

## widgets/AudioPill.qml

Header: "Audio control pill (speaker + mic + device menus)". The header blocks are Purpose, Popup extras, Theme Properties Consumed, Dependencies, and Notes. Default view is dual. Right-click cycles speaker, mic, and dual. Left-click opens the popup. The wheel changes volume. Peak meters run only while the popup is open.

Section comments, in order:

| Comment | What it holds |
|---------|----------------|
| `=== Layout ===` | Width and height from the active view and `pillScale`. |
| `=== Appearance via Theme ===` | Hover, fill, and border. Embedded mode is the chip inside a shared pill. |
| `===== AUDIO STATE =====` | `PwObjectTracker` id `audioTracker`. The comment says not to bind that tracker to the PipeWire default sink or source. |
| `---- Bluetooth battery poll (process-isolated; no live BlueZ QML bindings) ----` | `pollBtBatteries`. No live BlueZ QML bindings. |
| "Echo cancel (sticky system AEC — permanent preference, reversible Off)" | Preference file `echo-cancel.pref`, the systemd user unit, and `audio-control.sh` (`echo-cancel-status`, `echo-cancel-apply`, `echo-cancel-on`, `echo-cancel-off`). |
| `--- Public API (popup toggle + qs ipc call audioPill …) ---` | `setEchoCancelEnabled`, `enableEchoCancel`, `disableEchoCancel`, `toggleEchoCancel`. |
| `===== AUDIO POPUP (device selectors + full sliders) =====` | `PopupWindow` id `audioPopup`. Device selectors and the full sliders. |
