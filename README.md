# Quickshell Status Bar & Hyprland Config Inspector

Personal [Hyprland](https://hyprland.org) bar + floating Config Inspector ([Quickshell](https://quickshell.org)).

| Path | Role |
|------|------|
| `shell.qml` | Bar entry |
| `Config.qml` | Theme, fonts, defaults |
| `widgets/` | Pills, control strip, inspector |
| `scripts/` | Pollers & helpers |
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
- Bluetooth · Audio (combined pill), workspaces, tray, notifications (history window, DND, copy, per-item dismiss), power, FreshRSS
- Hyprland Config Inspector (metrics, logs, services, Lua configs)

## Requirements

Quickshell (`qs`), Hyprland, and helpers used by scripts (`jq`, `nmcli`, PipeWire/`pactl`, optional `curl`, `btop`, `nvtop`). Text screensaver needs `kitty`. Transparency writes Hyprland window rules through `hyprctl`. Tailscale needs the `tailscale` CLI. Screensaver DDC dim needs `ddcutil` and DDC/CI on the monitor.

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

Personal configuration — take what you need.
