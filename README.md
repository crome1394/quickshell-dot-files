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

- Liquid-glass bar: **Classic** (one bar, left / center / right) or **Dual** (top + bottom, centered)
- **Control strip** (gear or right-click chrome): Position (layout + edge), Display, **Wallpaper**, Widgets, Options, **Themes**, Launch, Autostart, MIME, Services, Audio, Keybinds, **Region & Clock**
- **Widgets** — dual layout lists **Top bar** / **Bottom bar** (classic: Left / Center / Right); reorder, show/hide, width %
- **Wallpaper** — fill-width thumbs, tile-size slider, rename/delete, drag-and-drop add (panel stays open while dropping)
- **Dock** — Mac-style magnify / jump (Options → Dock). Quick Launch or all icon widgets; CPU/Mem/GPU and volume stay still
- **Quick Launch** — Mac-style running **dot** on the pill bottom edge (color: Themes → Running app dot)
- **Sys Stats** — per-metric load colors (CPU / Memory / GPU); left-click popups with session Show graphs and pin-to-desktop history
- **Network** — per-adapter on/off + Enable after disconnect; Options for full IP, last octet, and device name on the bar
- **Themes** — colors, opacity, fonts, per-metric thresholds; **Save as preset** (colors) and **Save setup** (colors + layout)
- **Screensaver** — idle mpv (no DPMS); tab video does not block; fullscreen does unless Always start; optional DDC dim / exit brightness
- Net · BT · Audio (combined pill), workspaces, tray, notifications (history, DND, copy, per-item dismiss), power, FreshRSS
- Hyprland Config Inspector (metrics, logs, services, Lua configs)

## Requirements

Quickshell (`qs`), Hyprland, and helpers used by scripts (`jq`, `nmcli`, PipeWire/`pactl`, optional `curl`, `btop`, `nvtop`). Screensaver DDC dim needs `ddcutil` and DDC/CI on the monitor.

## Quick start

```bash
git clone git@github.com:crome1394/quickshell-dot-files.git ~/.config/quickshell
cd ~/.config/quickshell
qs --daemonize -n
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

## Bar layout

Switch **Classic** / **Dual** in the control strip **Position** panel. Each mode keeps its own widget order in `state/bar-layout.json`.

**Classic** (default — one bar, L / C / R):

| Zone | Widgets |
|------|---------|
| **Left** | Launcher, Quick Launch, FreshRSS, Media |
| **Center** | Workspaces |
| **Right** | Sys Stats, Tray, Net·BT·Audio, Clock, Notifications, Config, Power |

**Dual** (top + bottom, centered; glass hugs the widget row):

| Bar | Widgets |
|------|---------|
| **Top** | Clock, Workspaces, Tray, Notifications, Power |
| **Bottom** | Sys Stats, Launcher, Quick Launch, FreshRSS, Config, Net·BT·Audio |

Reorder, show/hide, and scale in **Widgets** (L/C/R in Classic, T/B in Dual). Theme in **Themes**. Options for gauges, graphs, applets, dock, screensaver. **Save setup** (Themes → Presets) snapshots colors plus this layout.

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
qs ipc call networkPill togglePopup
qs ipc call notificationBell toggleDoNotDisturb
```

Full tables: [docs/ipc.md](docs/ipc.md)

## Docs

| Guide | Topic |
|-------|--------|
| [Control bar](docs/control-bar.md) | Panels, Wallpaper, Themes, Display, MIME, Dock, Screensaver |
| [Config tokens](docs/config.md) | `Config.qml` reference |
| [IPC](docs/ipc.md) | All IPC targets |
| [Screensaver](docs/screensaver.md) | Idle mpv, tab vs fullscreen, DDC dim |
| [Audio](docs/audio.md) · [Network](docs/network.md) · [Bluetooth](docs/bluetooth.md) | Connectivity pills |
| [FreshRSS](docs/freshrss.md) · [Workspaces](docs/workspaces.md) · [Inspector](docs/inspector.md) | Feature guides |
| [Changelog](CHANGELOG.md) | Upgrade notes |

## License

Personal configuration — take what you need.
