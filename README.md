# Quickshell Status Bar & Hyprland Config Inspector

Personal [Hyprland](https://hyprland.org) bar + floating Config Inspector ([Quickshell](https://quickshell.org)).

| Path | Role |
|------|------|
| `shell.qml` | Bar entry |
| `Config.qml` | Theme, fonts, defaults |
| `widgets/` | Pills, control strip, inspector |
| `scripts/` | Pollers and helpers. `window-at-point.sh` is a manual helper and is not called by the bar. |
| `docs/` | Full guides |
| `state/` | Runtime prefs (gitignored) |

## Features

- Liquid-glass bar: **Classic** (one bar, left / center / right) or **Dual** (top + bottom). Dual can also show a **left bar** and a **right bar**; both start off
- **Settings** — movable Hyprland window (gear or right-click chrome). Opens on **Position**. Tabs fill the window; actions sit bottom-right. Drag the top strip; Esc / ✕ close.
- **Widgets** — reorder, show/hide, width %. Classic zones are Left / Center / Right. Dual zones are Top / Bottom / Left / Right. **Active Window** sits under **Other** and picks a screen corner
- **Wallpaper** — fill-width thumbs, tile-size slider, rename/delete, drag-and-drop add (panel stays open while dropping)
- **Dock** — Mac-style magnify / jump (Options → Dock). Quick Launch or all icon widgets; CPU/Mem/GPU/VRAM and volume stay still
- **Quick Launch** — Mac-style running **dot** on the pill bottom edge (color: Themes → Running app dot)
- **Sys Stats** — CPU | Memory | GPU | VRAM on the bar, each with its own load colors. The button chosen in Options → Stats opens `btop` (CPU/Memory) or `nvtop` (GPU/VRAM). The other button does nothing
- **Transparency** — Apps and Satty sliders, 5–100%. 100% is solid. Fullscreen and Settings stay solid
- **Tailscale** — left click opens machines (copy IP, name, or DNS, exit node, Taildrop). Right click runs `tailscale up` or `down`
- **Active Window** — corner overlay with the focused window’s icon, class, and title. A skip list hides chosen apps (the screensaver is skipped by default)
- **Overview** — fullscreen workspace strip with live window previews. **Super+Tab** toggles it. **Super+Shift+Tab** is desktop layout. **Super+Ctrl+Tab** is every workspace on the monitor. Options → **Overview**
- **Network** — wired, Wi-Fi, airplane, and VPN in one panel. Options set full IP, last octet, and device name on the bar
- **Themes** — colors, opacity, fonts, per-metric thresholds; **Save as preset** (colors) and **Save setup** (colors + layout)
- **Screensaver** — video (mpv) or a text style (Night watch, Rain, Orbital, Warp, Pyro, Scanner). No DPMS. Mouse/click/Esc dismiss. Tab video does not block; fullscreen does unless Always start. Optional DDC dim / exit brightness
- **Bluetooth · Audio** is one pill. **Network** is its own pill. Also workspaces, tray, notifications (history window, DND, copy, per-item dismiss), power, FreshRSS
- Hyprland Config Inspector (metrics, logs, services, Lua configs)

## Requirements

The bar starts with Quickshell (`qs`) on Hyprland. Everything else degrades when the binary is missing.

| Needed for the default pills | If it is missing |
|---|---|
| `jq` | Pollers and FreshRSS exit or return an error. The bar stays up. The audio poller needs `jq` even to report a missing `pactl`. |
| `python3` | Helpers that need it fail. The QML shell still loads. |
| `nmcli` | The Network pill stays empty. No dialog. |
| PipeWire `pactl` | Audio control and the inspector poller report the error in JSON. |

| Optional | If it is missing |
|---|---|
| `nvidia-smi` | GPU and VRAM show N/A. The Display page says stats are unavailable. |
| `wpctl` | Pill volume clicks do nothing visible. |
| `curl` | FreshRSS reports a missing command. |
| `btop`, `nvtop` | The Sys Stats click does nothing visible. |
| `kitty` | The text screensaver logs that it is not on `PATH` and does not start. A stats click that targets kitty is silent. |
| `mpv` | The video screensaver fails at exec. FreshRSS play returns an error. |
| `ddcutil` | Screensaver dim is skipped and logged. The saver still runs. |
| `tailscale` | The pill says Not installed. |
| `hypridle` | Not used by the bar. Screensaver install starts it only after writing config. |
| `swaync` / `swaync-client` | History sync returns count 0 and DND false. |
| `rofi`, `wofi`, or `fuzzel` | The default menu script shows an error if none of them exist. A saved launcher command is used instead of that script. |
| `zenity` | Folder pickers print `zenity not found`. |
| `wl-copy` | Some copy buttons fall back to `xclip`. Tailscale and the network monitor do not, so those copies fail silently. |
| `hyprpaper` | Apply prints that the wallpaper command failed. |
| `fastfetch` | The inspector system tab shows a failure string. |
| `notify-send` | The default menu falls through to `zenity`, then a Hyprland notification. |

`playerctl` and `pw-cli` are not used. Satty is not launched by the bar. The opacity rule matches its window class and does nothing when that app is absent.

## Known limitations

- GPU and VRAM numbers come from `nvidia-smi` only. Intel and AMD GPUs show N/A.
- CPU temperature follows a `k10temp` sensor (`temp1_input`). Other chips are not mapped.
- Disks are `/` plus other mounted NVMe partitions. Extra mounts are opt-in through `SYSMON_EXTRA_MOUNTS` (colon-separated). The default list is empty.
- The Application Menu highlight tracks `rofi` when the saved command contains `rofi`. `scripts/app-drawer.sh` does not, so that highlight stays off on the default command.

## Quick start

```bash
git clone git@github.com:crome1394/quickshell-dot-files.git ~/.config/quickshell
cd ~/.config/quickshell
qs --daemonize -n
# Screensaver (hypridle / Super+L): player + mouse-dismiss files
./scripts/install-screensaver-helpers.sh
# Or from this worktree:  qs -p shell.qml
```

| Persist | File |
|---------|------|
| Layout / Options / wallpaper folder & tile size / dock | `state/bar-layout.json` |
| Active theme (colors, fonts, thresholds) | `state/theme-colors.json` |
| Named color presets | `themes/*.json` (gitignored) |
| Named full setups | `profiles/*.json` (gitignored; colors + layout) |
| Screensaver | `~/.config/hypr/screensaver.conf` + hypridle listener |
| Display mode | `~/.config/hypr/config/monitors.lua` (on Apply) |
| FreshRSS secrets | `~/.config/freshrss-quickshell/freshrss.env` (not in git) |
| Transparency | `~/.config/hypr/opacity.state` and `opacity.lua` |

## Bar layout

Switch **Classic** / **Dual** in **Position** (monitor mockups, then **Apply**). Each mode keeps its own widget order in `state/bar-layout.json`. Hyprland should float the window with `title = "^(Settings)$"` and `class = ^(org.quickshell)$` (size/placement are compositor rules).

**Classic** (default — one bar, L / C / R):

| Zone | Widgets |
|------|---------|
| **Left** | Application Menu, Application Launcher, FreshRSS |
| **Center** | Workspaces |
| **Right** | System Stat Bars, Tray, Bluetooth·Audio, Network, Tailscale, Clock, Notifications, Config Menu Icon, Transparency, Power |

**Dual** (top + bottom, centered; glass hugs the widget row):

| Bar | Widgets |
|------|---------|
| **Top** | Clock, Workspaces, Tray, Notifications, Power |
| **Bottom** | System Stat Bars, Application Menu, Application Launcher, FreshRSS, Config Menu Icon, Transparency, Bluetooth·Audio, Network, Tailscale |

**Left bar** and **Right bar** are off until Options → **Bar** turns them on. Faces on a side bar rotate 90° clockwise. Popups stay upright.

Reorder, show/hide, and scale in **Widgets** (L/C/R in Classic, T/B/L/R in Dual). **Active Window** is not in those lists. It lives under **Other**, and the corner chips place it. Theme in **Themes**. Options cover the overview, stats, dock, screensaver, and screenshots. **Save setup** (Themes → Presets) snapshots colors plus this layout.

## IPC (cheat sheet)

```bash
qs ipc show
qs ipc call shell toggleBarControlBar
qs ipc call shell setBarPosition bottom
qs ipc call shell setBarLayoutMode dual
qs ipc call shell setBarEdgeMargin 8
qs ipc call shell setBarSizeScale 1.1
qs ipc call shell setFlushWindowsToBar true
qs ipc call shell setUiScale 0.85
qs ipc call shell toggleShowOpacityPill
qs ipc call shell setActiveWindowCorner topLeft
qs ipc call overview toggle
qs ipc call overview desktop
qs ipc call overview all
qs ipc call networkPanel togglePopup
qs ipc call notificationBell toggleHistory
qs ipc call notificationBell showHistory
qs ipc call notificationBell hideHistory
qs ipc call notificationBell toggleDoNotDisturb
```

Full tables: [docs/ipc.md](docs/ipc.md)

## Docs

| Guide | Topic |
|-------|--------|
| [Settings](docs/control-bar.md) | Panels, Wallpaper, Themes, Display, MIME, Dock, Screensaver |
| [Config tokens](docs/config.md) | `Config.qml` reference |
| [IPC](docs/ipc.md) | All IPC targets |
| [Overview](docs/overview.md) | Workspace strip, live previews, keyboard and drag |
| [Screensaver](docs/screensaver.md) | Video or text styles, mouse dismiss, tab vs fullscreen, DDC dim |
| [Audio](docs/audio.md) · [Network](docs/network.md) · [Bluetooth](docs/bluetooth.md) | Connectivity pills |
| [FreshRSS](docs/freshrss.md) · [Workspaces](docs/workspaces.md) · [Inspector](docs/inspector.md) | Feature guides |
| [Changelog](CHANGELOG.md) | Upgrade notes |

## License

[MIT](LICENSE). Copyright 2026 crome1394.
