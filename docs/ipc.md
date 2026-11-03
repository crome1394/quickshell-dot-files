<!-- Extracted from README for reference. See ../README.md for overview. -->

# Bar widget visibility (`Config.qml` + IPC)

Every bar pill can be hidden or shown. Defaults live in `Config.qml` (search for **WIDGET VISIBILITY**). Control-bar **Widgets** and IPC also write `state/bar-layout.json`, so most choices survive a `qs` restart.

| Config property | Default | IPC `set` / `toggle` | Widget |
|-----------------|---------|----------------------|--------|
| `showLauncherPill` | `true` | `setShowLauncherPill` / `toggleShowLauncherPill` | App Launcher (inline) |
| `showQuickLaunchPill` | `true` | `setShowQuickLaunchPill` / `toggleShowQuickLaunchPill` | Quick Launch |
| `showFreshRssPill` | `true` | `setShowFreshRssPill` / `toggleShowFreshRssPill` | FreshRSS |
| `showWorkspacesPill` | `true` | `setShowWorkspacesPill` / `toggleShowWorkspacesPill` | Workspaces strip |
| `showStatsPill` | `true` | `setShowStatsWidget` / `toggleShowStatsWidget` | System Stats |
| `showTrayPill` | `true` | `setShowTrayPill` / `toggleShowTrayPill` | System Tray |
| `showNetworkPanel` | `true` | `setShowNetworkPanel` / `toggleShowNetworkPanel` | Network |
| `showBluetoothPill` | `true` | `setShowBluetoothPill` / `toggleShowBluetoothPill` | Bluetooth |
| `showAudioPill` | `true` | `setShowAudioPill` / `toggleShowAudioPill` | Audio |
| `showClockPill` | `true` | `setShowClockPill` / `toggleShowClockPill` | Clock |
| `showNotificationPill` | `true` | `setShowNotificationPill` / `toggleShowNotificationPill` | Notifications |
| `showHyprInspPill` | `false` | `setShowHyprInspPill` / `toggleShowHyprInspPill` | Hypr Inspector |
| `showControlBarPill` | `true` | `setShowControlBarPill` / `toggleShowControlBarPill` | Config menu gear |
| `showPowerPill` | `true` | `setShowPowerPill` / `toggleShowPowerPill` | Power |
| `showTailscalePill` | `true` | `setShowTailscalePill` / `toggleShowTailscalePill` | Tailscale |
| `showOpacityPill` | `true` | `setShowOpacityPill` / `toggleShowOpacityPill` | Transparency |

The **magic workspace pill** (inside the workspaces strip) is separate: `wsShowSpecialPill` in config, plus `setShowMagicWorkspacePill` / `toggleShowMagicWorkspacePill` via IPC (also under **Options → Workspaces**).

The **active-window pill** is a corner overlay, saved in `bar-layout.json` (`showActiveWindowPill`, default on). It is not a `Config.qml` visibility flag. IPC: `setShowActiveWindowPill` / `toggleShowActiveWindowPill`, `setActiveWindowCorner` (`topLeft`, `topRight`, `bottomLeft`, `bottomRight`), `addActiveWindowExclude`, `removeActiveWindowExclude`.

Left and right edge bars are Options → **Bar** only. There is no IPC switch for them.

Sys Stats has no popup IPC. The old `sysStatsPill` live-update commands left with the metrics popups.

**Examples**

```bash
qs ipc call shell setShowAudioPill false
qs ipc call shell toggleShowPowerPill
qs ipc call shell setShowControlBarPill true
qs ipc call shell toggleBarControlBar
qs ipc call shell setBarLayoutMode dual
qs ipc call shell toggleBarLayoutMode
qs ipc call shell setBarEdgeMargin 8
qs ipc call shell setBarSizeScale 1.1
qs ipc call shell setFlushWindowsToBar true
qs ipc call shell setTooltipDelay 400

# Config.qml defaults apply when bar-layout has no override
showAudioPill: false
```

Zone dividers hide automatically when a neighboring pill is off. Run `qs ipc show` for the full command list.

## Widget actions (IPC)

Some bar widgets expose actions beyond show/hide. These work from scripts, Hyprland keybinds, or other Quickshell widgets.

| Target | Command | Action |
|--------|---------|--------|
| `clockPill` | `showCalendar` | Open the ClockPill calendar popup |
| `audioPill` | `setEchoCancel` | Enable (`true`) or disable (`false`) system echo cancel (sticky preference) |
| `audioPill` | `enableEchoCancel` / `disableEchoCancel` | Same as `setEchoCancel true` / `false` |
| `audioPill` | `toggleEchoCancel` | Toggle system echo cancel on/off |
| `networkPanel` | `showPopup` / `hidePopup` / `togglePopup` | Open, close, or toggle the Network panel |
| `networkPanel` | `setWifi` / `toggleWifi` | Wi-Fi radio on/off |
| `overview` | `toggle` | Open or close the workspace overview |
| `overview` | `open` / `close` | Open the workspace view, or close the overview |
| `overview` | `desktop` | Desktop layout (windows in place, with close buttons). Closes when that mode is already open |
| `overview` | `all` | Every workspace on the focused monitor. Closes when that mode is already open |
| `overview` | `next` / `prev` | Step the strip. When the overview is closed, move to the next or previous workspace |
| `bluetoothPill` | `showPopup` / `hidePopup` / `togglePopup` | Open, close, or toggle the Bluetooth menu |
| `bluetoothPill` | `setPower` / `togglePower` / `enable` / `disable` | Adapter radio power on/off |
| `bluetoothPill` | `startScan` / `stopScan` / `toggleScan` | Device discovery |
| `bluetoothPill` | `setDiscoverable` / `toggleDiscoverable` | Make this PC discoverable |
| `bluetoothPill` | `startApplet` / `stopApplet` / `toggleApplet` | Blueman tray (this session only) |
| `bluetoothPill` | `disableApplet` / `enableApplet` | Blueman tray sticky autostart (survives reboot) |
| `bluetoothPill` | `setAppletAutostart` | `true`/`false` — same sticky enable/disable |
| `bluetoothPill` | `connectDevice` / `disconnectDevice` | Connect or disconnect a MAC address |
| `bluetoothPill` | `pairDevice` / `cancelPair` / `forgetDevice` | Pairing lifecycle for a MAC |
| `bluetoothPill` | `setTrusted` / `setBlocked` | Trust or block a MAC (`address` + `bool`) |
| `bluetoothPill` | `renameDevice` | Set BlueZ alias (`address` + `name`) |
| `bluetoothPill` | `setCardProfile` | Set PipeWire profile for a MAC (`address` + profile name) |
| `notificationBell` | `toggleHistory` | Open or close the notification history window |
| `notificationBell` | `showHistory` / `hideHistory` | Open the history window, or close it |
| `notificationBell` | `toggleDoNotDisturb` | Toggle Do Not Disturb for the configured notification daemon |

**Examples**

```bash
qs ipc call clockPill showCalendar
qs ipc call audioPill setEchoCancel true
qs ipc call audioPill disableEchoCancel
qs ipc call audioPill toggleEchoCancel
qs ipc call networkPanel togglePopup
qs ipc call networkPanel toggleWifi
qs ipc call shell toggleShowNetworkPanel
qs ipc call overview toggle
qs ipc call overview desktop
qs ipc call overview all
qs ipc call overview next
qs ipc call bluetoothPill togglePopup
qs ipc call bluetoothPill togglePower
qs ipc call bluetoothPill startScan
qs ipc call bluetoothPill connectDevice "A0:0C:E2:66:FB:7D"
qs ipc call bluetoothPill renameDevice "A0:0C:E2:66:FB:7D" "Shokz Dark"
qs ipc call bluetoothPill setCardProfile "A0:0C:E2:66:FB:7D" "a2dp-sink"
qs ipc call bluetoothPill toggleApplet
qs ipc call notificationBell toggleHistory
qs ipc call notificationBell showHistory
qs ipc call notificationBell hideHistory
qs ipc call notificationBell toggleDoNotDisturb
qs ipc call shell setNotificationCorner bottomRight
qs ipc call shell setNotificationTimeout 8
qs ipc call shell toggleShowOpacityPill
qs ipc call shell setActiveWindowCorner topRight
qs ipc call shell addActiveWindowExclude hypr-screensaver
```

**Overview** options (layout, strip, previews) are Settings → Options → **Overview** and `bar-layout.json`. The commands above open and drive the view. See [overview.md](overview.md).

**Dock** (magnify/jump/scope), **edge bars**, and **screensaver** (video or text, DDC dim) are Options UI + files (`bar-layout.json`, `~/.config/hypr/screensaver.conf`), not IPC. See [control-bar.md](control-bar.md) and [screensaver.md](screensaver.md).

**Hyprland keybind examples** (in `~/.config/hypr/config/keybindings.lua`):

```
SUPER + TAB         →   qs ipc call overview toggle
SUPER + SHIFT + TAB →   qs ipc call overview desktop
SUPER + CTRL + TAB  →   qs ipc call overview all
SUPER + C           →   qs ipc call clockPill showCalendar
SUPER + N           →   qs ipc call notificationBell toggleDoNotDisturb
# History window (bind the key yourself):
# qs ipc call notificationBell toggleHistory
# Optional: bind echo cancel / Bluetooth / Network
# SUPER + ALT + E   →   qs ipc call audioPill toggleEchoCancel
# SUPER + ALT + B   →   qs ipc call bluetoothPill togglePopup
# SUPER + ALT + W   →   qs ipc call networkPanel togglePopup
```
