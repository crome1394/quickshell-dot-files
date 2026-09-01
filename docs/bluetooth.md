<!-- Extracted from README for reference. See ../README.md for overview. -->

# Bluetooth pill (`BluetoothPill.qml`)

Glassmorphic bar pill for day-to-day Bluetooth management via **Quickshell.Bluetooth** (BlueZ). Intended as a refined replacement for the Blueman tray applet while **keeping Blueman running** as a pairing-agent fallback for PIN/passkey dialogs.

| Input | Action |
|-------|--------|
| **Left-click** | Open / close the Bluetooth popup |
| **Right-click** | Toggle adapter radio power (`BluetoothAdapter.enabled`) |

## Popup features

| Feature | Details |
|---------|---------|
| **Adapter power** | On/off for the default adapter (radio power — not `systemctl bluetooth.service`) |
| **Scan / pair** | Start discovery (auto-stops after `bluetoothScanSeconds`, default 45s); pair nearby devices (`device.pair()`). Passkey UI may open via Blueman/agent |
| **Discoverable** | Toggle so other devices can find this computer |
| **Device list** | Connected, Paired, and Available sections with connection status and battery % when reported |
| **Connect / disconnect** | For previously paired devices |
| **Rename** | Set the BlueZ alias (`device.name`) for paired devices — **Rename** chip + Save / Enter |
| **Trust / block** | Writable BlueZ flags per device |
| **Remove** | `device.forget()` with a confirm step |
| **Adapter power** | Footer **Power off / Power on** |
| **Blueman applet** | Not in the popup. Sticky login autostart is **Options → Bluetooth**. IPC: `disableApplet` / `enableApplet` / `setAppletAutostart` |
| **Audio profile** | For connected audio devices: PipeWire `bluez_card.*` profiles (A2DP / HFP / codecs) via `scripts/audio-control.sh` |
| **Device info** | Name, address, paired/bonded/trusted/blocked, battery, adapter, D-Bus path; optional launch of `blueman-manager` |

Config tokens (search **BLUETOOTH** / `popupBluetooth*` in `Config.qml`): `showBluetoothPill`, `popupBluetoothWidth`, `popupBluetoothHeight`, `bluetoothScanSeconds`, `iconBluetooth*`.

## Implementation notes

- **Backend:** `Quickshell.Bluetooth` for adapter/devices; `scripts/audio-control.sh` for `bluez_card.*` profiles; Blueman via `scripts/blueman-applet-control.sh` (session start/stop + sticky XDG autostart override for reboot).
- **Perf:** One-pass device snapshot for bar metrics and (when the popup is open) section address lists; no multi-walk of the device model. Popup closed → empty section lists (bar still tracks connected count + primary battery via BlueZ property notifies). While open, a modest timer refreshes sparse notifies (faster during scan). Blueman status is polled slowly and on open/toggle only.
- **Safety:** Device selection is address-keyed (no long-lived BlueZ object pointers). Rename uses `HyprlandFocusGrab` so the `TextField` receives keys under Hyprland.
- **Close behavior:** Closing the popup stops discovery and clears expand/rename/profile UI state.

## IPC (`bluetoothPill`)

Visibility (show/hide the pill itself) stays on the `shell` target. All actions below are on `bluetoothPill`:

| Command | Arguments | Description |
|---------|-----------|-------------|
| `showPopup` / `hidePopup` / `togglePopup` | — | Open or close the Bluetooth menu |
| `setPower` | `true`\|`false` | Adapter radio on/off |
| `togglePower` / `enable` / `disable` | — | Same power control |
| `startScan` / `stopScan` / `toggleScan` | — | Discovery (auto-stops after `bluetoothScanSeconds`) |
| `setDiscoverable` | `true`\|`false` | Advertise this PC |
| `toggleDiscoverable` | — | Flip discoverable |
| `startApplet` / `stopApplet` / `toggleApplet` | — | Blueman tray **this session only** (returns after reboot if autostart still on) |
| `disableApplet` | — | Stop now **and** mask login autostart (`~/.config/autostart/blueman.desktop` with `Hidden=true`) so it **stays off after reboot** |
| `enableApplet` | — | Remove that mask and start the applet again |
| `setAppletAutostart` | `true`\|`false` | Same as enable / disable |
| `connectDevice` / `disconnectDevice` | `address` | Connect or disconnect |
| `pairDevice` / `cancelPair` / `forgetDevice` | `address` | Pairing lifecycle |
| `setTrusted` | `address` `true`\|`false` | Trust flag |
| `setBlocked` | `address` `true`\|`false` | Block flag |
| `renameDevice` | `address` `name` | BlueZ alias |
| `setCardProfile` | `address` `profileName` | e.g. `a2dp-sink`, `headset-head-unit` |

```bash
# Pill visibility (shell target)
qs ipc call shell setShowBluetoothPill false
qs ipc call shell toggleShowBluetoothPill

# Widget actions
qs ipc call bluetoothPill togglePopup
qs ipc call bluetoothPill setPower true
qs ipc call bluetoothPill startScan
qs ipc call bluetoothPill connectDevice "A0:0C:E2:66:FB:7D"
qs ipc call bluetoothPill setTrusted "A0:0C:E2:66:FB:7D" true
qs ipc call bluetoothPill renameDevice "A0:0C:E2:66:FB:7D" "Shokz Dark"
qs ipc call bluetoothPill setCardProfile "A0:0C:E2:66:FB:7D" "a2dp-sink-sbc_xq"
qs ipc call bluetoothPill toggleApplet
# Permanent (survives reboot) — stop tray and prevent login autostart
qs ipc call bluetoothPill disableApplet
# Undo permanent disable
qs ipc call bluetoothPill enableApplet
# Or boolean form
qs ipc call bluetoothPill setAppletAutostart false
qs ipc call bluetoothPill setAppletAutostart true
```

## Blueman tray persistence (session vs reboot)

| Action | Effect now | After reboot |
|--------|------------|--------------|
| Header left-click / `stopApplet` / `startApplet` / `toggleApplet` | Start or stop tray for **this session** | Autostart may bring Blueman back |
| Header right-click / `disableApplet` / `setAppletAutostart false` | Stop tray **and** mask login autostart | **Stays off** |
| Header right-click (when masked) / `enableApplet` / `setAppletAutostart true` | Remove mask and start tray | Starts at login again |

Sticky disable writes `~/.config/autostart/blueman.desktop` (`Hidden=true`), which overrides `/etc/xdg/autostart/blueman.desktop` for your user. Generated `app-blueman@autostart.service` cannot be `systemctl disable`'d reliably, so the desktop override is the durable mechanism (implemented in `scripts/blueman-applet-control.sh`).

```bash
# CLI (same as IPC)
~/.config/quickshell/scripts/blueman-applet-control.sh status
~/.config/quickshell/scripts/blueman-applet-control.sh disable   # permanent off
~/.config/quickshell/scripts/blueman-applet-control.sh enable    # permanent on
~/.config/quickshell/scripts/blueman-applet-control.sh stop      # session only
```

The Applet button border turns amber when login autostart is masked.
