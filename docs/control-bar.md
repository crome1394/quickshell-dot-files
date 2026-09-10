<!-- Extracted from README for reference. See ../README.md for overview. -->

# Bar control strip (`BarControlBar.qml`)

Open via the **Config menu** gear or **right-click empty bar chrome**. Toolbar on the **bottom**; content expands above and resizes to fit. Close a panel with the **✕** (top-right) or Esc. Wheel-scroll the body on Display, Wallpaper, Widgets, Options, Themes, Launch, Autostart. **MIME**, Services, Audio, and Keybinds use a fixed tall panel with internal scrolling. Refresh / reset / reload actions sit at the **bottom** of each panel.

| Panel | What it does |
|-------|----------------|
| **Position** | Layout **Classic** (one bar, L/C/R) or **Dual** (top + bottom, centered) · classic edge top/bottom · **Gap from edge** (0–48px) · **Flush windows to bar** · **Bar size** (80–140%) → `state/bar-layout.json` |
| **Display** | Monitor resolution / refresh / bit depth + adapter stats from `hyprctl` (see Display subsection) |
| **Wallpaper** | hyprpaper thumbs (tiles fill the panel; **Tile size** slider / Ctrl+wheel), apply, rename, delete, pick folder, add images (button or drag-and-drop) |
| **Widgets** | **A–Z list**; each row is three columns: **✓/✕ + full name** · **L C R** (classic) or **T B** (dual) · **↑ ↓**; width slider 80–180%. Names use flexible width (Notifications, Hypr Inspector, etc. not clipped). Net·BT·Audio is one pill. **Add |** inserts a movable divider. **Reset layout** / **Reset sizes** (reset matches the active layout mode) |
| **Options** | Behavior prefs (not layout) — table below |
| **Themes** | Live colors/opacity, text roles, **Fonts** (UI·Mono·Main·Secondary·Bar + sizes), thresholds, liquid presets (see Themes subsection) |
| **Launch** | Quick Launch pins (installed apps or custom) |
| **Autostart** | XDG `~/.config/autostart` (see Autostart subsection) |
| **MIME** | Preferred applications / file-type defaults (see MIME subsection) |
| **Services** | systemd user/system units — filter, select, **Start / Stop / Restart** (reuses Inspector `ServicesView`) |
| **Audio** | Sound manager: overview (summary / streams / levels), dual device columns + profiles, echo cancel; **pw-top** / **Restart audio** (reuses Inspector `AudioMonitorView`) |
| **Keybinds** | Browse `keybindings.lua` by category; **edit key chord, category, description** (not the action) |
| **Region & Clock** | Tabs: **Region** (default, clickable timezone map) · **Clock** (format presets + custom). **Apply region** closes the panel first so a password prompt is not covered. |

## MIME panel (Preferred applications)

Set which program opens a given file type or link scheme. Opens from the control-strip **MIME** tab (after Autostart). UI: `components/MimeAppsView.qml`. Scripts: `scripts/mime-catalog-json.sh`, `mime-apps-json.sh`, `mime-file-probe.sh`, `mime-set-default.sh` (app picker reuses `desktop-apps-json.sh`).

Dual-pane layout fills the panel height; lists scroll inside each pane.

| Control | Behavior |
|---------|----------|
| **File types \| Applications** | **File types:** pick a type → apps that can open it. **Applications:** pick an app → file types linked to it (from `.desktop` `MimeType=` plus your associations). |
| **★ Default opener** | The app that runs when you open that kind of file. Other listed apps *can* open it, but are not currently the default. |
| **What opens this file?** | Paste a path → **Look up** detects the type (`xdg-mime query filetype`) and selects it. |
| **Associate app…** | (File types) Pick any installed app and make it the default opener — works even if the app doesn’t advertise that type (e.g. VSCodium + Markdown). |
| **+ Add type** | (Applications) Link another file type to this app and set it as the default opener. |
| **Use as default** | Make the selected listed app the default opener (double-click a row, or Enter when the apps list is focused). |
| **Clear default** | Removes your saved default under user `mimeapps.list` `[Default Applications]` only. |
| **Keyboard (File types)** | ↑/↓ (or j/k) type list · → / Enter focus apps · Enter set default · **A** associate · ← / Esc back · Page Up/Down · Home/End. |
| **Search / filters** | Name, extension, app name. Chips: **All** · **Files** · **Links** (`x-scheme-handler/*`) · **Has default** (explicit `mimeapps.list` entry). |
| **Reload** | Re-read catalog after external changes. |

Writes go only to `~/.config/mimeapps.list` (via `xdg-mime default` for set/associate; surgical edit for clear). No `update-mime-database` and no system package edits.

## Wallpaper panel

Thumbnail grid for the current wallpaper folder (`hyprpaper` apply). Tiles use a preferred width from **Tile size**, then stretch so each row fills the panel.

| Control | Behavior |
|---------|----------|
| Click thumb | Apply via `scripts/wallpaper-apply.sh` |
| Hover **✎** / right-click **Rename…** | Rename the file in-folder (keeps extension if omitted) |
| Hover **✕** / right-click **Delete…** | Confirm, then delete only that image in the wallpaper folder |
| **Tile size** | 100–260px preferred width; **Ctrl+wheel** on the grid also changes it (`wallpaperTileSize` in `bar-layout.json`) |
| **Add wallpapers…** | zenity picker; copies into the folder |
| Drag-and-drop | Image files, or a folder of images (top-level only), copied in (suffix if the name exists). The Wallpaper tab stays open for the drop (file-manager drags start as an outside click, which would otherwise dismiss the popup). Close with the **Wallpaper** tab, bar chrome, or Esc. |
| **Change folder…** / **Open folder** | Pick or reveal the wallpaper directory |

Scripts: `wallpaper-list-json.sh`, `wallpaper-apply.sh`, `wallpaper-add.sh`, `wallpaper-rename.sh`, `wallpaper-delete.sh`, `wallpaper-pick-dir.sh`.

## Display panel

Runtime mode switcher for the focused (or configured) Hyprland monitor. Modes come live from `hyprctl monitors -j` → `availableModes` via `scripts/monitor-mode.sh` — not a hardcoded list.

Layout (top → bottom): status · adapter · **Resolution | Refresh | Bit depth** row · Apply.

| Control | Behavior |
|---------|----------|
| **Indicator** | Current resolution, refresh, bit depth, make/model/serial, connector + format + scale, physical size, position |
| **NVIDIA** | Button with Nerd Font `md-nvidia` glyph + label; opens `nvidia-settings` |
| **Adapter** | DRM connector + NVIDIA name/driver; util, temp, P-state, power, VRAM, clocks. Mini GPU/VRAM bars. |
| **Resolution** | Stepped block slider over `WxH` in the selected refresh **family**, sorted **width then height descending** |
| **Refresh rate** | Dropdown of **exact** rates for the selected resolution only (hyprctl). Changing rate refilters the resolution list by Hz **family** (e.g. 239.76 / 239.90 / 239.97 → ~240) |
| **Bit depth** | Dropdown: **8-bit** / **10-bit** (pending until Apply) |
| **Apply** | Commits pending mode + bitdepth at **scale 1.0** |

**Linked filtering**

- Pick a **resolution** → refresh dropdown lists only rates hyprctl reports for that `WxH`.
- Pick a **refresh rate** → resolution slider lists only `WxH` values that advertise a rate in the same family (~60 / ~75 / ~120 / ~240).
- Moving the slider snaps the pending rate to that panel’s exact EDID value in the same family so Apply always uses a real mode string.

**Polling / resources**

- GPU/status soft-poll runs **only** while the Display panel is open (default **3s**).
- Poll **pauses** while dragging the resolution slider; no background work when Display is closed.
- Selection changes do **not** bump global layout ticks (keeps the slider responsive).

Pending changes do **not** take effect until **Apply**. Apply:

1. Runs `hyprctl eval` for the live mode (`scripts/monitor-mode.sh apply`).
2. **Rewrites** `~/.config/hypr/config/monitors.lua` so the mode survives reboot / reload (backup: `monitors.lua.bak-qs`).

Related CLI (outside this repo, on PATH): `hypr-resolution` — rofi menu over the same EDID modes (default 10-bit, scale 1).

## Region & Clock panel

Toolbar button **Region & Clock**. Two tabs (MIME-style chips); **Region** is the default when you open the panel. UI: `components/TimezoneMapView.qml`. Script: `scripts/timezone-control.sh`. Map land: `assets/world-land.json` (Natural Earth 110m, public domain, simplified).

| Control | Behavior |
|---------|----------|
| **Region tab** | GNOME Date & Time map (`assets/gnome-tz/`: Miller projection, `timezone_<offset>.png` overlays). Hover/click lights the official offset region. City search sits below the map; the city list filters as you type. |
| **Apply region** | Closes the control strip first (so a polkit password prompt is not covered), then runs `timedatectl set-timezone` (pkexec if the session call is denied). |
| **Clock tab** | Format presets (Full / Date / Time / Short / 12h / US) plus a **Custom** `Qt.formatDateTime` field. **Clock face font** (family + size). Preview updates as you type; **Set** or Enter saves to `bar-layout.json`. |

The bar clock itself still uses local time, so after a successful region apply it follows the new timezone automatically.

## Options panel

| Section | Controls | Persistence |
|---------|----------|-------------|
| **Bar / UI** | UI scale auto/manual · **Gap from edge** · **Flush windows to bar** · **Bar size** · **Tooltips** (delay + per-widget T/B/L/R) · Config menu icon on bar · **Color presets section** (show/hide presets on Colors) | `bar-layout.json` |
| **Workspaces** | Magic pill · only-active · min pills · startup workspace · close magic on start | `bar-layout.json` |
| **Audio** | Show AEC section · show Summary / device profiles / Level meters · keep Summary / Active streams expanded (AEC on/off is only in the Audio panel) | visibility/expand → `bar-layout.json` |
| **Network** | nm-applet sticky login autostart · traffic graph on/off · **Full IP on bar** · **Last octet on bar** · **Device name on bar** | XDG / `bar-layout.json` |
| **Bluetooth** | Blueman sticky login autostart | XDG / applet control |
| **System stats** | Show CPU / Memory / GPU · **bar** util graphs · **menu** util graphs · metrics live updates | `bar-layout.json` |
| **FreshRSS** | Filters expanded on open · HTTPS/HTTP · host · user · API password · **Test** / **Save server** | filters → `bar-layout.json`; credentials → `~/.config/freshrss-quickshell/freshrss.env` (never git) |

Editable text fields use a slightly lifted background so they read as inputs. Toggle/number columns share a fixed right-hand control slot for alignment.

## Themes panel

Non-coder theme editor for the bar and all widgets. Open **Themes** on the control-bar toolbar.

### Layout

Title and sub-tabs (**Theming** · **Thresholds** · **Presets**) stay fixed at the top; the body scrolls underneath.

| Tab | Contents |
|-----|----------|
| **Theming** | Collapsible **Colors** · **Text** · **Special / Effects** (left) and **Opacity** (right). **Main text** = menu headers; **Secondary text** = menu body; **Bar widget text** = face labels on the bar |
| **Thresholds** | Output/input volume + Sys Stats load/temperature (left); color picker (right) |
| **Fonts** | Two columns: **typeface** left · **size %** right. Rows: **UI**, **Monospace**, **Main**, **Secondary**, **Bar widget**. Preview shows all five |
| **Presets** | Liquid glass family (mint/violet/rose/amber/ice/aurora) + solid/soft/nordic/… — hide from **Options → Color presets section** |

Color picker opens on the **right**. **Undo** reverts theme steps. Fonts, colors, and thresholds save to `state/theme-colors.json`.

### Controls

| Control | What it does |
|---------|----------------|
| **Colors** swatches | Bar background, widget background, menu background, border, accent, warning/pink, hover glow, **active button** (selected control-bar tab), **active workspace** (selected workspace pill), top edge shine |
| **Opacity** sliders | Alpha for glass fills, borders, hover, active button, active workspace, top edge shine |
| **Text** swatches | **Main** (headers) · **Secondary** (body) · **Bar widget text** (bar face) · button/workspace labels |
| **Built-in presets** | Liquid glass + liquid variants, Solid dark, Soft grey, Nordic, Ember, Ocean, Lavender, Forest — **cannot be removed** |
| **Your presets** | Click to apply; **×** removes a custom preset only |
| **Save as preset** | Stores the current look under a name in `~/.config/quickshell/themes/` |
| **Load file** | Optional path to any theme `.json` |
| **Reset** | Restores factory Liquid glass defaults |

### What maps to what

Each Colors swatch writes **only** its Theme key (strict isolation). Shared looks use the **same** key on purpose (e.g. every inactive toolbar tab uses `buttonBg`).

| UI label | Theme key | Affects |
|----------|-----------|---------|
| Button background | `buttonBg` | Inactive control-bar toolbar tabs and action chips |
| Bar background | `glassBg` | Main bar chrome fill |
| Border | `glassBorder` | Main bar outer rim |
| Widget / pill fill | `glassPillBg` / `pillBg` | Bar widget pills only (not toolbar buttons) |
| Pill border | `pillBorder` | Pill rims (independent of bar border) |
| Menu background / border | `glassPopupBg` / `glassPopupBorder` | Popups and control-bar panels |
| Active button | `controlActiveBg` | Selected control-bar toolbar tab fill |
| Active workspace | `wsActiveBg` | Selected workspace pill fill on the bar |
| Button text | `buttonText` | Inactive control-bar tab labels |
| Active button text | `buttonTextActive` | Active / hovered control-bar tab labels |
| Icon color | `audioSpeakerIcon` (+ mic) | Speaker / mic unicode icons |
| Active workspace text | `wsActiveText` | Number/icon on the active workspace |
| Workspace text | `wsInactiveText` | Number/icon on inactive workspaces |
| Volume levels | `audioSpeakerTier1`–`4` + thresholds | Volume bars on the bar and in Audio panels |
| Sys Stats load | `statUtilTier1`–`4` + thresholds | CPU / Memory / GPU util bars and % text |
| Sys Stats temperature | `statTempCool` / `Warm` / `Hot` + °C cutoffs | CPU / GPU temperature labels |

**Thresholds** tab: volume and Sys Stats each have three cutoffs and four tier swatches (low → peak). Speaker and mic share the volume ramp. Temperature has warm/hot °C cutoffs and three colors.

Changes apply **live** across the bar and widgets, and the active look is stored in `state/theme-colors.json` (survives `qs` restart). Layout prefs (including **Color presets section** visibility) stay in `bar-layout.json` — resetting colors does not move widgets.

Theme JSON shape:

```json
{
  "name": "My teal glass",
  "version": 1,
  "colors": {
    "glassBg": { "hex": "#0A0F1A", "alpha": 0.58 },
    "accent": { "hex": "#00F0E0", "alpha": 1.0 },
    "wsActiveBg": { "hex": "#00D9CC", "alpha": 0.28 },
    "buttonText": { "hex": "#A8B4C8", "alpha": 1.0 }
  }
}
```

Script helper: `scripts/theme-io.sh` (`list` / `export` / `import`). Advanced tokens (volume tiers, inspector semantics) stay in `Config.qml`.

## XDG Autostart panel

Session user apps only (not Hyprland core). Scripts: `autostart-list-json.sh`, `autostart-set.sh`, `autostart-add.sh`, `autostart-run.sh`, `xdg-autostart-run.sh`. Failures log to `~/.local/state/quickshell/autostart-run.log`.

### How entries are created

| Source | Behavior |
|--------|----------|
| **Installed app** (picker / `--desktop-id` / `--desktop-file`) | **Copy** the real `.desktop` from `/usr/share/applications` (or other XDG apps dirs) into `~/.config/autostart/`. Preserves the app’s `Exec=`, `TryExec=`, icons, and other keys. Only forces `Hidden=false`, `X-GNOME-Autostart-enabled=true`, and `X-systemd-skip=true`. |
| **Manual** (`--name` + `--exec`) | Synthesize a minimal entry with the given command. |

Do **not** rewrite `Exec=` to `gtk-launch …`. That breaks apps with `DBusActivatable=true` (e.g. Telegram): `gtk-launch` can exit 0 without starting the process. The working system file has a real command (`Exec=Telegram -- %U`); the autostart copy must keep that.

### How entries are run

`autostart-run.sh` (and the login helper) always run the entry’s **`Exec=`** line with FreeDesktop field codes (`%U`, `%f`, …) stripped. It does not call `gtk-launch`.

Login helper in Hyprland `autostarts.lua`:

```lua
hl.exec_cmd("/home/crome/.config/quickshell/scripts/xdg-autostart-run.sh")
```

`X-systemd-skip=true` tells the systemd user xdg-autostart generator to ignore these files so only this helper starts them (avoids double-start / D-Bus activation quirks).

### Repair a broken entry

If an older build left a synthetic file (e.g. `Exec=gtk-launch org.telegram`), re-add from the system desktop file:

```bash
~/.config/quickshell/scripts/autostart-add.sh --desktop-id org.telegram.desktop
# or: remove in the Autostart panel, then add again from the app list
```

Put Telegram/Discord workspace placement in **window rules** (e.g. `special:magic silent`), not in Autostart `exec` workspace options.

## Services panel

Quick recovery for systemd units without opening the full Config Inspector. Embeds `components/ServicesView.qml` (same UI as the Inspector **Services** tab):

- Filter chips: **All / Running / Failed**, plus a text search field
- Table: service name, status, state, loaded-since, description
- Actions on the selected row: **Start**, **Stop**, **Restart**, **Refresh**
- Scripts: `scripts/services-poller.sh`, `scripts/services-control.sh`
- Polls only while the panel is open (`active` binding)
- User units: `systemctl --user`. System units may prompt for polkit (same as [inspector.md](inspector.md))

Full metrics/logs/config browsing remains in the Hyprland Config Inspector (`qs ipc call hyprConfigInsp toggle`).

## Audio panel

Sound manager without opening the full Config Inspector or the bar audio pill. Embeds `components/AudioMonitorView.qml` (same engine as the Inspector **Audio** tab), plus tools from the AudioPill.

Layout (top → bottom):

| Area | Controls |
|------|----------|
| **Tools** | **Refresh** at top; **pw-top** (kitty) and **Restart audio** at the bottom (`audio-control.sh restart-audio`) |
| **Filter** | Text field filters devices and stream names |
| **Overview** (one pill) | **Audio Summary** → **Active streams** → **Levels** (no inter-card dead space) |
| **Devices** | Dual columns: sinks / sources — volume, mute, **Set Default**, **ports**; **Profile** under each column |
| **Echo cancel** | Sticky On/Off at the **bottom** (AEC preference; same scripts as the pill) |

**Overview details**

- **Summary** — default output/input labels, sink/source counts (collapsible; Options: show / keep expanded)
- **Active streams** — real app playback (▶) and recording (● REC); internal **Peak Detect** monitors are filtered out (collapsible; Options: keep expanded)
- **Levels** — Playback + Recording VU meters via name-resolved `PwNodePeakMonitor` (Options: show Level meters)

**Options → Audio** (persisted in `bar-layout.json`)

| Toggle | Effect |
|--------|--------|
| Show echo cancel in audio menu | Show/hide AEC section on **pill popup** and **this panel** (does **not** turn AEC on/off) |
| Show Audio Summary | Hide/show summary block in overview |
| Show device profiles | Profile dropdowns under Output / Input columns |
| Show Level meters | VU meters in overview |
| Keep Audio Summary expanded | Expand summary when the panel opens |
| Keep Active streams expanded | Expand streams when the panel opens |

**Sampling / resources** (idle when closed)

- `active` is true only while the Audio panel is open (and the control strip popup is visible)
- Soft re-poll ~3s **only while open**; peak monitors, profile fetches, and poller processes stop on close (`stopAllWork`)
- Card profiles re-fetch when the default sink/source **changes**, not on every soft-poll
- Scripts: `scripts/audio-poller.sh`, `scripts/audio-control.sh`, `scripts/audio-osd.sh`

The **AudioPill** remains the glance + wheel volume control on the bar; this panel is the multi-device manager. See [audio.md](audio.md) for pill details and the echo-cancel back-out ladder.

## Keybinds panel

Browse and lightly edit Hyprland binds without opening the full Inspector. Source of truth: `~/.config/hypr/config/keybindings.lua`.

- Same **categories** and **descriptions** as the Inspector (`--#Category# description` convention — see [inspector.md](inspector.md))
- Rows show key pills + description; **Edit** opens a form for:
  - **Key** chord (e.g. `SUPER + T`)
  - **Category**
  - **Description**
- The Lua **action / dispatcher** (`hl.dsp.*`, plugins, options tables) is **not** editable here — use Config Files / your editor for that
- Loop / dynamic keys (e.g. workspace `for` loop with `.. key`) are listed as **read-only**
- Scripts: `scripts/keybinds-list-json.sh`, `scripts/keybinds-set.sh`
- **Save** writes the file in place (timestamped `.bak.*` backup first). **Reload Hypr** runs `hyprctl reload` when you want the change live
