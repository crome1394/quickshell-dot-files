<!-- Extracted from README for reference. See ../README.md for overview. -->

# Configuration (`Config.qml`)

`Config.qml` is the single source of truth for bar visuals, widget visibility defaults, and workspace behavior. `shell.qml` re-exports theme properties on the root `bar` object (e.g. `bar.accent`, `bar.wsMinimumShown`). The inspector loads a local `Config` instance for overlay-specific tokens.

Edit `Config.qml` to change:

- Colors, fonts (UI / mono / Main / Secondary / Bar roles + scales), spacing, radii, icons
- **Theme editor API** (`themeUiRows`, `themeEditableKeys`, `getThemeColor` / `setThemeColor`, font role setters) — control strip **Themes** panel
- Bar position and size (`barPosition`, `barLayoutMode` classic/dual, `barHeight`, `barEdgeMargin`, `flushWindowsToBar`)
- Bar pill visibility defaults (`showLauncherPill`, `showAudioPill`, etc.) and launcher command (`launcherCommand`)
- **Quick Launch** apps (`quickLaunchApps`)
- **Notification bell** daemon commands (`notification*`)
- **Power menu** session commands (`power*Command`, `powerMenuActions`)
- **Kill Target** pill (`killTargetIcon`, `showKillTargetPill`, etc.)
- Workspace pill count, active-only mode, magic pill default, startup focus, and workspace colors (search **WORKSPACES**; IPC: `setWsMinimumShown`, `setWsShowOnlyActive`, `setWsStartupWorkspace`, `setWsStartupCloseMagic`)
- System Stats pill and metrics popups (search **SYS STATS PILL** and `popupStats*`)
- Inspector sizing and semantic colors (search `insp*` properties)
- Wallpaper folder / apply scripts / default tile size (search **Wallpaper**; runtime folder and tile size persist in `state/bar-layout.json`)
- Clock format presets (`clockFormatPresets`) and timezone helper (`timezoneControlScript`)

Day-to-day color tweaks belong in the control strip **Colors** panel (persisted to `state/theme-colors.json`); only edit `Config.qml` for factory defaults or tokens not exposed in the UI.

Every property in `Config.qml` has an inline or section comment explaining what it does and which widget uses it. Search for the section headers in the file (e.g. **POWER MENU**, **NOTIFICATION BELL**, **WIDGET VISIBILITY**).

The file is named `Config.qml` (capital **C**) because QML requires that naming for reliable type registration across subdirectories.

# System Stats pill (`Config.qml`)

Search for **SYS STATS PILL** for the compact bar widget (CPU | Memory | GPU), and **popupStats** for the large right-click dropdowns.

**Bar pill size** — snug to content by default. Raise these only if you want more room:

| Property | What it does | Default |
|----------|--------------|---------|
| `statPillPaddingH` | Left/right padding inside the border. Raise first if text feels flush to the glass. | `10` |
| `statPillSpacing` | Gap between columns (divider centered in the slot) | `8` |
| `statGaugeWidth` | Width of the util bar in each column | `56` |
| `statPillSectionWidth` | Optional minimum column width (`0` = hug content) | `0` |
| `statPillWidth` | Optional preferred pill width (`0` = fit content; larger values add side space with content centered) | `0` |

**Bar pill colors** — utilization bar tiers (`statUtilTier1`–`4`, `statUtilThreshold1`–`3`) and CPU/GPU temperature label colors (`statTempCool` / `Warm` / `Hot`, `statTempWarmAt` / `HotAt`).

**Metrics popups** (right-click a section) — each section has its own size and screen position:

| Prefix | Section |
|--------|---------|
| `popupStatsCpu*` | CPU (left) |
| `popupStatsMem*` | Memory (middle) |
| `popupStatsGpu*` | GPU (right) |

- `*Width` / `*Height` — popup panel size in pixels
- `*AnchorX` — `0` = align to left of section, `0.5` = center, `1` = right
- `*AnchorWholePill` — `true` = anchor to the full pill instead of that section
- `*OffsetX` / `*OffsetY` — nudge popup left/right or up/down in pixels
- `*BarGap` — distance between the bar and the popup

**Live updates** — `popupStatsLiveUpdates` sets whether charts refresh while a popup is open. `popupStatsPersistPause: true` saves Pause/Resume choices to `state/popup-stats.json`.

## Notification bell (`Config.qml` + `NotificationBell.qml`)

Search for **NOTIFICATION BELL** in `Config.qml`. Defaults are SwayNC (`swaync-client`). To use another daemon, replace the command lists. `NotificationBell.qml` reads these lists, builds proper argv arrays, and polls internally (same pattern as `SysStatsPill.qml`).

Left-click the bell opens the **history panel** (every notification, expand / copy / per-item ✕, DND, Clear list). Right-click toggles DND. History is persisted by `scripts/notification-history.py` to `~/.local/state/quickshell/notification-history.json` (survives reboot). SwayNC’s control center is not used in the UI.

| Property | SwayNC default | Purpose |
|----------|----------------|---------|
| `notificationSubscribe` | `["swaync-client", "-s", "-sw"]` | Optional live stream for badge / DND updates |
| `notificationTogglePanel` | `["swaync-client", "-t", "-sw"]` | Unused in UI (SwayNC control center) |
| `notificationToggleDnd` | `["swaync-client", "-d", "-sw"]` | History-panel DND button + right-click the bell |
| `notificationClearAll` | `["swaync-client", "-C", "-sw"]` | Also run from history **Clear list** (closes live SwayNC notifications) |
| `notificationSync` | `["…/scripts/notification-sync.sh"]` | Timer poller; prints `{"count":N,"dnd":true\|false}` |
| `notificationSyncIntervalMs` | `2500` | How often the sync script runs |
| `notificationDndAccent` | `#e85d5d` | Pill border, bell, and badge tint when DND is on |

Use `[]` to disable subscribe, sync, or any action. Keep `notificationSync` enabled for reliable badge/DND state; subscribe is optional live updates on top. Config command lists are QML lists — the bell copies them to JS arrays before starting `Io.Process` (do not bind lists directly).

**SwayNC tip:** run only one instance (e.g. `swaync.service` via systemd, not also `hl.exec_cmd("swaync")` in Hyprland autostart). If `notify-send` shows nothing, check DND: `swaync-client -D -sw` — use `swaync-client -df -sw` to turn off.

## Power menu (`Config.qml`)

Search for **POWER MENU**. Each session action has its own command list (or shell string). Use `[]` to hide an action from both the grid and right-click menu.

| Property | Default | Purpose |
|----------|---------|---------|
| `powerLockCommand` | `["hyprlock"]` | Lock screen |
| `powerLogoutCommand` | `["sh", "-c", "…"]` | Log out of Hyprland (stops apps, then `hyprshutdown` or `hl.dsp.exit`) |
| `powerRebootCommand` | `["sh", "-c", "…"]` | Reboot |
| `powerShutdownCommand` | `["sh", "-c", "…"]` | Shutdown |
| `powerBiosCommand` | `["systemctl", "reboot", "--firmware-setup"]` | Firmware setup on next boot |
| `powerMenuActions` | Lock / Logout / … rows | Icons (`iconLock`, etc.), labels, and `action` ids — reorder or rename here |

Logout/reboot/shutdown defaults stop `psd.service` and several user apps before the system action. Edit those pipelines to match your setup.

## Quick Launch (`Config.qml`)

Search for **QUICK LAUNCH**. Edit the `quickLaunchApps` list — one object per icon. Reorder, add, or remove entries; Quickshell reloads automatically.

| Field | Purpose |
|-------|---------|
| `icon` | Path to PNG/SVG image |
| `glyph` | Optional nerd-font character (use instead of `icon` if `icon` is empty) |
| `command` | Launch command as a **list** `["gtk-launch", "firefox"]` (preferred) or shell string `"gtk-launch firefox"`. Use the list form for `gtk-launch` and full paths. |
| `tooltip` | Hover label |

Also tune `quickLaunchIcon` (size), `quickLaunchSpacing`, and `quickLaunchPaddingH`.

## Kill Target pill (`Config.qml`)

Search for **KILL TARGET PILL**. Set `showKillTargetPill: true` to show the bar icon (default is hidden). Tune `killTargetIcon`, `killTargetTooltip`, and `killTargetOverlayDim` (screen dimming while picking). Kills use SIGTERM via `process-control.sh` — only processes owned by your user; root-owned apps are rejected with an error message.

---
