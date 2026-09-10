<!-- Extracted from README for reference. See ../README.md for overview. -->

# Network pill (`NetworkPill.qml`)

Glassmorphic bar pill for day-to-day NetworkManager control via **Quickshell.Networking** plus `scripts/network-control.sh`. Intended as a replacement for the **nm-applet** menu. The tray applet is optional (Options → **nm-applet login autostart**).

| Input | Action |
|-------|--------|
| **Left-click** | Open / close the Network popup |
| **Right-click** | Disabled (use per-adapter **WiFi on/off** or `qs ipc call networkPill toggleWifi`) |

Bar face shows the last IPv4 octet by default. Options → **Full IP on bar** (`showNetworkFullIp` in `bar-layout.json`) shows the complete address. Options → **Device name on bar** (`showNetworkDeviceName`) adds the adapter name (`enp10s0`, `wlan0`) next to it.

## Layout

| Pane | Contents |
|------|----------|
| **Header** | Title, connectivity, optional traffic graph |
| **Left** | **Adapters** (per-device on/off + Enable/Disconnect) and **Connections** dropdown + **Editor** |
| **Right** | **WiFi** networks (scan, connect / disconnect / forget, PSK prompt) |
| **Details** | Single-column connection info (click any value to copy) |
| **Footer** | ↻ IP · ↻ DNS · **All off** |

## Popup features

| Feature | Details |
|---------|---------|
| **WiFi radio** | On each WiFi adapter card — software rfkill for wireless |
| **Wired adapter** | **Wired on/off** on ethernet cards (`nmcli device connect` / `disconnect`) |
| **Enable** | Undo a disconnect (`nmcli device connect <iface>`) without toggling Auto |
| **Disconnect** | Drop the active connection on that adapter |
| **All off** | Footer: disconnect every adapter and turn the WiFi radio off |
| **↻ IP / ↻ DNS** | Footer: reapply addressing / flush resolver caches |
| **nm-applet** | Not in the popup. Sticky login autostart is **Options → Network**. IPC: `disableApplet` / `enableApplet` / `setAppletAutostart` |
| **Adapters** | Wired and WiFi devices with state, active connection name, IPv4, link speed; Enable / Disconnect / radio / Details / Edit / Autoconnect |
| **Connections** | Dropdown of saved NM profiles (activate by selection); **Editor** opens `nm-connection-editor` for the selected profile |
| **Connection info** | Details panel (nm-applet *Connection Information* style): interface, MAC, cable/link, IPv4/IPv6, gateway, DNS, routes; click row to copy |
| **WiFi networks** | Right column: scan while popup is open; signal bars, security, saved flag; Connect (PSK prompt when needed), Disconnect, Forget |
| **Traffic graph** | Downstream (blue) + upstream (green) sparklines with live rates |

Config tokens (search **NETWORK** / `popupNetwork*` in `Config.qml`): `showNetworkPill`, `popupNetworkWidth`, `popupNetworkWifiWidth`, `popupNetworkHeight`, `iconNetwork*`.

## Implementation notes

- **Backend:** `Quickshell.Networking` for devices, WiFi scan/connect/forget, wifi radio; `scripts/network-control.sh` for live IP/DNS/routes, connection list, global networking, and nm-applet control.
- **Scanner:** WiFi `scannerEnabled` is on only while the popup is open and WiFi is enabled.
- **Safety:** Devices and SSIDs are string-keyed (no long-lived NM object pointers). Password field uses `HyprlandFocusGrab` under Hyprland. Fail handlers disconnect when the popup closes.
- **Coexistence:** nm-applet may remain enabled for migration; use header session toggle or IPC `disableApplet` for permanent off. Advanced edits stay in `nm-connection-editor`.

## Performance

- **One-pass device snapshot** for bar glyph, primary connection, WiFi connected SSID, and (when open) sorted AP list — no multi-walk of `Networking.devices` per frame.
- **Status poll:** ~12s while the popup is closed (bar only); ~1.5s while open (graph + adapters). Overlapping `nmcli` status runs are skipped.
- **Popup-gated work:** connection ComboBox model rebuild, rate history arrays, and WiFi SSID list materialization only while open; history cleared on close.
- **Connection model fingerprint:** dropdown is not rebuilt if UUID/active set is unchanged.
- **Sparse epoch timer** (3s while open) for weak NM notifies; no separate applet poll loop (status JSON carries `applet_running`).

## IPC (`networkPill`)

Visibility (show/hide the pill itself) stays on the `shell` target. Actions below are on `networkPill`:

| Command | Arguments | Description |
|---------|-----------|-------------|
| `showPopup` / `hidePopup` / `togglePopup` | — | Open or close the Network menu |
| `setWifi` | `true`\|`false` | WiFi radio on/off |
| `toggleWifi` / `enableWifi` / `disableWifi` | — | Same radio control |
| `setNetworking` | `true`\|`false` | Global networking |
| `toggleNetworking` | — | Flip networking |
| `startScan` / `stopScan` | — | WiFi scanner |
| `connectSsid` | `ssid` | Connect (known/open; PSK via UI) |
| `disconnectDevice` | `iface` | e.g. `enp10s0` |
| `enableDevice` | `iface` | `nmcli device connect` (undo disconnect) |
| `disableAllAdapters` | — | Disconnect every adapter and turn WiFi radio off |
| `forgetSsid` | `ssid` | Forget saved WiFi |
| `startApplet` / `stopApplet` / `toggleApplet` | — | nm-applet for this session only |
| `enableApplet` | — | Enable unit + start (survives reboot) |
| `disableApplet` | — | Stop + disable unit (stays off after reboot) |
| `setAppletAutostart` | `true`\|`false` | Same as enable / disable |
| `openEditor` | — | `nm-connection-editor` |
| `refreshIp` / `refreshDns` | — | Reapply / renew IP; flush DNS caches |
| `activateConnection` | `uuid` or `name` | Bring a saved profile up |
| `deactivateConnection` | `uuid` or `name` | Bring a profile down |

**Applet note (same pattern as Bluetooth / Blueman):**

| Action | Session only? | Survives reboot? |
|--------|---------------|------------------|
| Footer left-click / `startApplet` / `stopApplet` / `toggleApplet` | Yes | No (if still enabled at login) |
| Footer right-click / `disableApplet` / `setAppletAutostart false` | Stops now | **Yes — stays off** |
| Footer right-click (when sticky-off) / `enableApplet` | Starts now | **Yes — starts at login** |

Sticky disable writes `~/.config/autostart/nm-applet.desktop` (`Hidden=true`) to mask `/etc/xdg/autostart/nm-applet.desktop`, and runs `systemctl --user disable nm-applet.service`.

```bash
# Keep off after reboot (recommended when using the Network pill)
qs ipc call networkPill disableApplet
# equivalent:
qs ipc call networkPill setAppletAutostart false

# Bring login autostart back
qs ipc call networkPill enableApplet
qs ipc call networkPill setAppletAutostart true

# Check
~/.config/quickshell/scripts/network-control.sh applet status
systemctl --user is-enabled nm-applet.service
```

```bash
# Pill visibility (shell target)
qs ipc call shell setShowNetworkPill false
qs ipc call shell toggleShowNetworkPill

# Widget actions
qs ipc call networkPill togglePopup
qs ipc call networkPill toggleWifi
qs ipc call networkPill disconnectDevice "enp10s0"
qs ipc call networkPill openEditor
qs ipc call networkPill refreshIp
qs ipc call networkPill refreshDns
qs ipc call networkPill activateConnection "Wired connection 1"

# nm-applet — session only (does not change login enablement)
qs ipc call networkPill toggleApplet
qs ipc call networkPill stopApplet

# nm-applet — keep off / on after reboot
qs ipc call networkPill disableApplet
qs ipc call networkPill enableApplet
qs ipc call networkPill setAppletAutostart false
```
