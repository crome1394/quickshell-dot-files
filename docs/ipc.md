<!-- Extracted from README for reference. See ../README.md for overview. -->

# Bar widget visibility (`Config.qml` + IPC)

Every bar pill can be hidden or shown. Defaults live in `Config.qml` (search for **WIDGET VISIBILITY**). Control-bar **Widgets** and IPC also write `state/bar-layout.json`, so most choices survive a `qs` restart.

| Config property | Default | IPC `set` / `toggle` | Widget |
|-----------------|---------|----------------------|--------|
| `showLauncherPill` | `true` | `setShowLauncherPill` / `toggleShowLauncherPill` | App Launcher (inline) |
| `showQuickLaunchPill` | `true` | `setShowQuickLaunchPill` / `toggleShowQuickLaunchPill` | Quick Launch |
| `showFreshRssPill` | `true` | `setShowFreshRssPill` / `toggleShowFreshRssPill` | FreshRSS |
| `showMediaPill` | `false` | `setShowMediaWidget` / `toggleShowMediaWidget` | Media Player |
| `showWorkspacesPill` | `true` | `setShowWorkspacesPill` / `toggleShowWorkspacesPill` | Workspaces strip |
| `showStatsPill` | `true` | `setShowStatsWidget` / `toggleShowStatsWidget` | System Stats |
| `showTrayPill` | `true` | `setShowTrayPill` / `toggleShowTrayPill` | System Tray |
| `showNetworkPill` | `true` | `setShowNetworkPill` / `toggleShowNetworkPill` | Network |
| `showBluetoothPill` | `true` | `setShowBluetoothPill` / `toggleShowBluetoothPill` | Bluetooth |
| `showAudioPill` | `true` | `setShowAudioPill` / `toggleShowAudioPill` | Audio |
| `showClockPill` | `true` | `setShowClockPill` / `toggleShowClockPill` | Clock |
| `showNotificationPill` | `true` | `setShowNotificationPill` / `toggleShowNotificationPill` | Notifications |
| `showKillTargetPill` | `false` | `setShowKillTargetPill` / `toggleShowKillTargetPill` | Kill Target |
| `showHyprInspPill` | `false` | `setShowHyprInspPill` / `toggleShowHyprInspPill` | Hypr Inspector |
| `showControlBarPill` | `true` | `setShowControlBarPill` / `toggleShowControlBarPill` | Config menu gear |
| `showPowerPill` | `true` | `setShowPowerPill` / `toggleShowPowerPill` | Power |

The **magic workspace pill** (inside the workspaces strip) is separate: `wsShowSpecialPill` in config, plus `setShowMagicWorkspacePill` / `toggleShowMagicWorkspacePill` via IPC (also under **Options → Workspaces**).

**Examples**

```bash
qs ipc call shell setShowAudioPill false
qs ipc call shell toggleShowPowerPill
qs ipc call shell setShowControlBarPill true
qs ipc call shell toggleBarControlBar

# Config.qml defaults apply when bar-layout has no override
showAudioPill: false
showMediaPill: true
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
| `networkPill` | `showPopup` / `hidePopup` / `togglePopup` | Open, close, or toggle the Network menu |
| `networkPill` | `setWifi` / `toggleWifi` / `enableWifi` / `disableWifi` | WiFi radio on/off |
| `networkPill` | `setNetworking` / `toggleNetworking` | Global NetworkManager networking on/off |
| `networkPill` | `startScan` / `stopScan` | WiFi network scan |
| `networkPill` | `connectSsid` / `forgetSsid` / `disconnectDevice` / `enableDevice` | Connect (SSID), forget SSID, disconnect/enable iface |
| `networkPill` | `disableAllAdapters` | Disconnect every adapter and turn WiFi radio off |
| `networkPill` | `startApplet` / `stopApplet` / `toggleApplet` | nm-applet tray (session only) |
| `networkPill` | `enableApplet` / `disableApplet` / `setAppletAutostart` | nm-applet autostart (survives reboot) |
| `networkPill` | `openEditor` | Launch `nm-connection-editor` |
| `networkPill` | `refreshIp` / `refreshDns` | Reapply IP / flush DNS |
| `networkPill` | `activateConnection` / `deactivateConnection` | `uuid` or connection name |
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
| `notificationBell` | `toggleDoNotDisturb` | Toggle Do Not Disturb for the configured notification daemon |
| `killTargetPill` | `activatePickMode` / `cancelPickMode` | Arm or cancel the click-to-kill picker (same as clicking the pill) |
| `sysStatsPill` | `setMetricsLiveUpdates` | Pause (`false`) or resume (`true`) metrics-popup polling for all CPU/Memory/GPU sections |
| `sysStatsPill` | `setCpuLiveUpdates` / `setMemLiveUpdates` / `setGpuLiveUpdates` | Pause or resume metrics-popup polling for one section |
| `sysStatsPill` | `toggleMetricsLiveUpdates` | Toggle metrics-popup polling for all sections |
| `sysStatsPill` | `toggleCpuLiveUpdates` / `toggleMemLiveUpdates` / `toggleGpuLiveUpdates` | Toggle metrics-popup polling for one section |

**Examples**

```bash
qs ipc call clockPill showCalendar
qs ipc call audioPill setEchoCancel true
qs ipc call audioPill disableEchoCancel
qs ipc call audioPill toggleEchoCancel
qs ipc call networkPill togglePopup
qs ipc call networkPill toggleWifi
qs ipc call networkPill enableDevice enp10s0
qs ipc call networkPill disableAllAdapters
qs ipc call networkPill openEditor
qs ipc call networkPill toggleApplet
qs ipc call bluetoothPill togglePopup
qs ipc call bluetoothPill togglePower
qs ipc call bluetoothPill startScan
qs ipc call bluetoothPill connectDevice "A0:0C:E2:66:FB:7D"
qs ipc call bluetoothPill renameDevice "A0:0C:E2:66:FB:7D" "Shokz Dark"
qs ipc call bluetoothPill setCardProfile "A0:0C:E2:66:FB:7D" "a2dp-sink"
qs ipc call bluetoothPill toggleApplet
qs ipc call notificationBell toggleDoNotDisturb
qs ipc call sysStatsPill setMetricsLiveUpdates false
qs ipc call sysStatsPill toggleMetricsLiveUpdates
qs ipc call sysStatsPill setCpuLiveUpdates false
qs ipc call shell setShowKillTargetPill true
qs ipc call killTargetPill activatePickMode
```

Metrics-popup IPC pauses sparklines, gauges, and process lists in the right-click dropdowns — not the compact CPU/Memory/GPU stats on the bar pill. Takes effect immediately while a popup is open; otherwise the paused state applies the next time you open that section. When `popupStatsPersistPause` is `true` in `Config.qml`, the choice is saved to `state/popup-stats.json`.

**Hyprland keybind examples** (in `~/.config/hypr/config/keybindings.lua`):

```
SUPER + C   →   qs ipc call clockPill showCalendar
SUPER + N   →   qs ipc call notificationBell toggleDoNotDisturb
SUPER + M   →   qs ipc call sysStatsPill toggleMetricsLiveUpdates
SUPER + X   →   qs ipc call killTargetPill activatePickMode
# Optional: bind echo cancel / Bluetooth / Network
# SUPER + ALT + E   →   qs ipc call audioPill toggleEchoCancel
# SUPER + ALT + B   →   qs ipc call bluetoothPill togglePopup
# SUPER + ALT + W   →   qs ipc call networkPill togglePopup
```
