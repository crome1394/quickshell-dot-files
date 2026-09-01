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

- Liquid-glass bar (top/bottom) · left / center / right zones
- **Control strip** (gear or right-click chrome): Position, Display, **Wallpaper**, Widgets, Options, **Themes**, Launch, Autostart, MIME, Services, Audio, Keybinds, Clock
- **Wallpaper** — fill-width thumbs, tile-size slider, rename/delete, drag-and-drop add (panel stays open while dropping)
- **Themes** — colors, opacity, fonts (UI / mono / Main / Secondary / Bar roles), thresholds, liquid + solid presets
- Net · BT · Audio (combined pill), workspaces, sys stats, tray, notifications (history + copy), power, FreshRSS
- Hyprland Config Inspector (metrics, logs, services, Lua configs)

## Requirements

Quickshell (`qs`), Hyprland, and helpers used by scripts (`jq`, `nmcli`, PipeWire/`pactl`, optional `curl`, `btop`, `nvtop`).

## Quick start

```bash
git clone git@github.com:crome1394/quickshell-dot-files.git ~/.config/quickshell
cd ~/.config/quickshell
qs --daemonize -n
# Or from this worktree:  qs -p shell.qml
```

| Persist | File |
|---------|------|
| Layout / Options / wallpaper folder & tile size | `state/bar-layout.json` |
| Active theme | `state/theme-colors.json` |
| Named presets | `themes/*.json` |
| Display mode | `~/.config/hypr/config/monitors.lua` (on Apply) |
| FreshRSS secrets | `~/.config/freshrss-quickshell/freshrss.env` (not in git) |

## Bar layout (default)

| Zone | Widgets |
|------|---------|
| **Left** | Launcher, Quick Launch, FreshRSS, Media |
| **Center** | Workspaces |
| **Right** | Sys Stats, Tray, Net·BT·Audio, Clock, Notifications, Config, Power |

Reorder in **Widgets**. Theme in **Themes**. Options for gauges, graphs, applets.

## IPC (cheat sheet)

```bash
qs ipc show
qs ipc call shell toggleBarControlBar
qs ipc call shell setBarPosition bottom
qs ipc call shell setUiScale 0.85
qs ipc call networkPill togglePopup
qs ipc call notificationBell toggleDoNotDisturb
```

Full tables: [docs/ipc.md](docs/ipc.md)

## Docs

| Guide | Topic |
|-------|--------|
| [Control bar](docs/control-bar.md) | Panels, Wallpaper, Themes, Display, MIME |
| [Config tokens](docs/config.md) | `Config.qml` reference |
| [IPC](docs/ipc.md) | All IPC targets |
| [Audio](docs/audio.md) · [Network](docs/network.md) · [Bluetooth](docs/bluetooth.md) | Connectivity pills |
| [FreshRSS](docs/freshrss.md) · [Workspaces](docs/workspaces.md) · [Inspector](docs/inspector.md) | Feature guides |
| [Changelog](CHANGELOG.md) | Upgrade notes |

## License

Personal configuration — take what you need.
