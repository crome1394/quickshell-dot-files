<!-- Extracted from README for reference. See ../README.md for overview. -->

# Hyprland Config Inspector

A resizable floating window (`Hyprland Config Inspector`) for reading Hyprland config, monitoring the system, and performing common admin tasks without leaving the desktop.

# Purpose

- Inspect split Hyprland configuration (Lua and related `.conf` files)
- View live Hyprland runtime options from `hyprctl`
- Monitor CPU, GPU, memory, temperature, network, processes, and audio
- Tail logs, manage systemd services, and review system information
- Search across the active tab, copy values, and open config files for editing

## Split Hyprland configuration

Hyprland is **not** configured in a single `hyprland.conf` here. Settings are split across multiple **Lua** modules under `~/.config/hypr/config/`, with the main entry point at `~/.config/hypr/hyprland.lua`. Related tools (Hypridle, Hyprlock, Hyprpaper) keep their own `.conf` files in `~/.config/hypr/`.

Typical layout:

| File | Topics |
|------|--------|
| `keybindings.lua` | Keybinds and mouse bindings |
| `environment-variables.lua` | `exec-once`, environment variables |
| `monitors.lua` | Monitor and workspace layout |
| `input.lua` | Keyboard, mouse, touchpad |
| `look-and-feel.lua` | Gaps, borders, animations, decoration |
| `windows-and-workspaces.lua` | Window rules, layer rules, workspaces |
| `my-programs.lua` | Default apps (`terminal`, `fileManager`, etc.) |
| `autostarts.lua` | Startup commands |
| `permissions.lua` | Window permission rules |
| `misc.lua` | Miscellaneous options |

## How the inspector uses the split config

- **Config Files** tab — Primary file browser. Pick any registered config from the dropdown to view it with syntax highlighting (`bat`), filter lines with global search, copy the full file, or press **Ctrl+E** / **Edit** to open it in `$TERMINAL` with `nano`.
- **Key Bindings** and **Environment** tabs — Read `keybindings.lua` and `environment-variables.lua` directly and show parsed tables (easier to scan than raw source). See [Custom description comments](#custom-description-comments) below.
- **Runtime Options** tab — Shows values Hyprland is running with now via `hyprctl getoption` (useful after editing; reload Hyprland to apply file changes).

The file list is defined in `widgets/HyprConfigInsp.qml` (`configFileEntries`). Add an entry there if you create a new config module.

## Custom description comments

In `keybindings.lua` and `environment-variables.lua`, inline comments use the `--#` prefix to attach a **human-readable description** on the same line as the config entry. The inspector parses these and surfaces them in the **Key Bindings** and **Environment** tabs — they are not Hyprland syntax; they are a local convention for documentation.

```lua
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal)) --# Opens the default terminal
hl.env("TERMINAL", terminal)                         --# Default terminal for keybinds and CLI tools
```

| File | What `--#` becomes in the inspector |
|------|-------------------------------------|
| `keybindings.lua` | **Action** column (the bind’s description). Only `hl.bind(...)` lines that include `--#` are listed. |
| `environment-variables.lua` | **Comment** shown under the variable name. Plain `--` comments are also recognized as a fallback. |

Use `--#` to keep Hyprland directives on the left and your notes on the right. Commented-out binds (`--hl.bind(...)`) are ignored. If you adopt this layout in your own config, match the parser expectations in `widgets/HyprConfigInsp.qml` (`parseKeybinds`, `parseEnvVars`).

## New to split configs?

If you are used to one monolithic `hyprland.conf`, think of `hyprland.lua` as a thin loader and each file in `config/` as a chapter (bindings, monitors, input, etc.). Edit the file that matches what you want to change, then reload Hyprland (`hyprctl reload` or your usual method). Use the **Config Files** tab to jump between modules without hunting paths in a file manager.

## Key features

- **14 tabs** covering config, metrics, logs, and services
- **Global search** (`Ctrl+F`) filters the active tab
- **Syntax-highlighted** config file viewer (bat-backed)
- **Live polling** for metric tabs while the inspector is open and visible (stops when closed or minimized)
- **Per-tab refresh** and **Refresh All** (`Ctrl+R`) for on-demand data
- **Edit in terminal** (`Ctrl+E`) opens the current config file in `$TERMINAL` with `nano`
- **Copy** buttons and click-to-copy on many values
- **Resizable** window with themed Catppuccin-style UI from `Config.qml`

## Tabs

| Tab | Description |
|-----|-------------|
| **Key Bindings** | Parsed `hl.bind` entries from `keybindings.lua` (key + `--#` description as action). The control strip **Keybinds** panel can edit chord/category/description; this tab stays read-only browse. |
| **Environment** | Parsed `hl.env` entries from `environment-variables.lua` (variable, value, `--#` comment) |
| **Runtime Options** | Live Hyprland options via `hyprctl getoption`, grouped by category with wiki links |
| **Config Files** | Browse all split `config/*.lua` modules plus Hypridle/Hyprlock/Hyprpaper configs; syntax highlighting, search, copy, and edit |
| **CPU** | CPU usage gauge, history sparkline, load averages, and top CPU processes |
| **GPU** | NVIDIA utilization, VRAM, and temperature via `nvidia-smi`. Missing `nvidia-smi` shows N/A. Intel and AMD GPUs are not read. |
| **Memory** | System memory and swap usage with history and breakdown |
| **Temperature** | CPU and GPU temperature monitoring with history |
| **Network** | Interfaces, routing, DNS, latency, firewall, active connections, per-process bandwidth, and live traffic graphs |
| **Processes** | Process list with CPU/memory usage, PR/NI columns, sort, filter, and signal controls |
| **Audio** | PipeWire/PulseAudio sinks, sources, ports, volumes, defaults, active apps; tools (Refresh / pw-top / Restart audio) + echo cancel. Same `AudioMonitorView` as the control-bar **Audio** panel. |
| **Logs** | Tail Hyprland log, user/system journal, kernel, and common service logs |
| **Services** | systemd user and system units with status filters and start/stop/restart controls |
| **System Info** | `fastfetch` hardware/OS summary, Service Documentation links, and click-to-copy fields |

## Launch

**IPC (works from scripts, keybinds, or other Quickshell widgets):**

```bash
qs ipc call hyprConfigInsp toggle
```

**Hyprland keybind** (in `~/.config/hypr/config/keybindings.lua`):

```
SUPER + SLASH   →   qs ipc call hyprConfigInsp toggle
```

The inspector is registered in `shell.qml` as `hyprConfigInsp`. Run `qs ipc show` to list available IPC targets.

## Recommended window rule

Add this to `~/.config/hypr/config/windows-and-workspaces.lua` (or your window-rules module) so the inspector opens centered and floating at a comfortable default size. Adjust `size` to taste — the window remains user-resizable.

```lua
-- Hyprland Config Inspector
hl.window_rule({
    name     = "Hyprland Config Inspector",
    match    = { title = "^(Hyprland Config Inspector)$" },
    float    = true,
    center   = true,
    fullscreen = false,
    immediate  = false,
    pin  = false,
    size   = { 1231, 1029 },
})
```

The rule matches the window title set in `widgets/HyprConfigInsp.qml`. If you change the title there, update `match` accordingly.

## Keyboard shortcuts

Shortcuts apply while the inspector window is focused (search field captures typing when active).

| Shortcut | Action |
|----------|--------|
| `Escape` | Close search or close the inspector |
| `Ctrl+F` | Focus global search |
| `Ctrl+R` | Refresh all data for the current context |
| `Ctrl+E` | Edit the current config file in a terminal (`nano`) |
| `Tab` / `Shift+Tab` | Next / previous tab |
| `PgUp` / `PgDown` | Page scroll in the active tab |
| `↑` / `↓` | Line scroll in the active tab |

## Important notes

**Config paths** — See [Split Hyprland configuration](#split-hyprland-configuration) above. Paths are hard-coded in `widgets/HyprConfigInsp.qml`; change `configDir`, `hyprDir`, or `configFileEntries` if your install differs.

**`--#` descriptions** — Key Bindings and Environment tabs depend on the `--#` comment convention in `keybindings.lua` and `environment-variables.lua`. Entries without `--#` (for binds) or without a recognized comment (for env) may not appear as expected in those parsed views.

**Background polling** — `SysMonService` polls only while the inspector is open *and* not minimized. Closing or hiding the window stops metric polling to reduce idle CPU use.

**Network tab (privileged data)** — Routing, latency tests, firewall rules, and the full connection table are loaded on demand when you open the Network tab or press **Refresh** in those sections. Live interface stats, DNS, public IP, and socket counts still update from the fast poller. Some firewall or connection details may require elevated permissions on certain systems.

**Services tab** — User-scoped units use `systemctl --user`. System-scoped start/stop/restart may prompt for polkit authentication depending on your policy.

**Logs tab** — System journal and kernel sources may show limited output without appropriate permissions. Hyprland’s session log is read from `/run/user/<uid>/hypr/`.

**System Info** — Collected via `fastfetch --logo none` when the tab is opened. Includes links to System76 Thelio Mira R4 documentation.

**Terminal** — Edit and Network **Open Terminal** actions use the `$TERMINAL` environment variable (set in Hyprland from `my-programs.lua`; defaults to `kitty`).

---
