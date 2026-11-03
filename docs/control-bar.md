<!-- Extracted from README for reference. See ../README.md for overview. -->

# Settings (`widgets/settings/SettingsPanel.qml`)

Open via the **Config Menu Icon** gear or **right-click empty bar chrome**. Closing Settings with **Super+C** or Hyprland’s window ✕ used to leave it unable to open again; the gear icon clears that and maps the window. The in-panel ✕ and Esc still close it. It is a movable Hyprland window (title **Settings**); it opens on **Position**. Drag the top strip; close with **✕** or Esc. The tab bar stays at the **bottom** of the window. Each tab fills the window; footer actions (Refresh, Apply, Reset, …) sit **bottom-right**. Numeric sliders are track + **‹ ›** + a typed field. Hyprland window rule should match `title = "^(Settings)$"` and `class = ^(org.quickshell)$`; size and placement are compositor-owned.

| Panel | What it does |
|-------|----------------|
| **Position** | Monitor mockups: **Classic** (one bar) or **Dual** (top + bottom). Select, then **Apply**. Classic also has edge top/bottom. Dual adds **Left bar** and **Right bar** (both off until shown), each with span and alignment. **Gap from edge**, **Flush windows to bar**, **Bar size**. |
| **Display** | Current mode, adapter/GPU, resolution slider, chips for **every res × refresh rate**, bit depth, Apply. NVIDIA Settings + Refresh bottom-right. |
| **Wallpaper** | hyprpaper thumbs (tiles fill the panel; **Tile size** slider / Ctrl+wheel), apply, rename, delete, pick folder, add images (button or drag-and-drop) |
| **Widgets** | Dual layout: **Top bar**, **Bottom bar**, **Left bar**, and **Right bar** (classic: Left / Center / Right). Order inside a section is along that bar. Each row: **✓/✕ + full name** · zone chips · **↑ ↓**; width slider 80–180%. **Other** holds **Active Window** (show/hide and the four corners). Bluetooth · Audio is one pill. Network is its own pill. **Add |** inserts a movable divider. **Reset layout** / **Reset sizes** (reset matches the active layout mode) |
| **Options** | Behavior prefs (not layout) — **tabs** per section (table below); only the active tab scrolls |
| **Themes** | Live colors/opacity, text roles, **Fonts**, per-metric thresholds, liquid presets; **Save as preset** (colors) and **Save setup** (colors + layout) — see Themes subsection |
| **App Launcher** | Application Launcher pins (installed apps or custom) |
| **Autostart** | XDG `~/.config/autostart` (see Autostart subsection) |
| **MIME** | Preferred applications / file-type defaults (see MIME subsection) |
| **Services** | systemd user/system units — filter, select, **Start / Stop / Restart** (reuses Inspector `ServicesView`) |
| **Audio** | Sound manager: overview, dual device columns (inputs top-aligned), echo cancel. **Refresh** / **pw-top** / **Restart audio** bottom-right. |
| **Keybinds** | Browse `keybindings.lua` by category; edit key chord, category, description (not the action). **Refresh** / **Reload Hypr** bottom-right. |
| **Region & Clock** | Tabs: **Region** (default, clickable timezone map) · **Clock** (format presets + custom). **Apply region** closes the panel first so a password prompt is not covered. |

## MIME panel (Preferred applications)

Set which program opens a given file type or link scheme. Opens from the control-strip **MIME** tab (after Autostart). UI: `components/MimeAppsTab.qml`. Scripts: `scripts/mime-catalog-json.sh`, `mime-apps-json.sh`, `mime-file-probe.sh`, `mime-set-default.sh` (app picker reuses `desktop-apps-json.sh`).

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

Layout (top → bottom): status · adapter · **Resolution | Refresh | Bit depth** row · Apply · chip grid of **every res × refresh rate** · NVIDIA + Refresh (bottom-right).

| Control | Behavior |
|---------|----------|
| **Indicator** | Current resolution, refresh, bit depth, make/model/serial, connector + format + scale, physical size, position |
| **NVIDIA** | Button with Nerd Font `md-nvidia` glyph + label; opens `nvidia-settings` (footer, bottom-right) |
| **Adapter** | DRM connector + NVIDIA name/driver; util, temp, P-state, power, VRAM, clocks. Mini GPU/VRAM bars. |
| **Resolution** | Stepped slider over `WxH` in the selected refresh **family**, plus chips for **all** `WxH · Hz` modes from hyprctl |
| **Refresh rate** | Dropdown of **exact** rates for the selected resolution only (hyprctl). Changing rate refilters the **slider** list by Hz **family** (e.g. 239.76 / 239.90 / 239.97 → ~240); chips stay unfiltered |
| **Bit depth** | Dropdown: **8-bit** / **10-bit** (pending until Apply) |
| **Apply** | Commits pending mode + bitdepth at **scale 1.0**, with `cm = "srgb"` so 10-bit does not switch the monitor to wide/BT2020 |

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
2. **Rewrites** `~/.config/hypr/config/monitors.lua` so the mode survives reboot / reload (backup: `monitors.lua.bak-qs`). The written monitor block sets `cm = "srgb"`.

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

Sticky chips under the title: **Bar** · **App Menu** · **Tooltips** · **Workspaces** · **Overview** · **Audio** · **Network** · **Bluetooth** · **Notifications** · **Stats** · **Dock** · **Active Window** · **Screensaver** · **ScreenShots** · **FreshRSS**. Position (Classic / Dual, edge, span, and size) lives on **Bar**. One section is shown at a time. A chip hides while its widget is off on the Widgets tab; the saved settings stay. **Bar**, **Overview**, **Tooltips** (the delay), **Screensaver**, **ScreenShots**, and **Notifications** stay. **Dock** hides only when every icon pill is off. The same switch hides the **App Launcher** and **Audio** tabs, the **Clock** format tab (Region stays), that widget's tooltip row, and the audio or stats blocks under Themes → Thresholds.

| Section | Controls | Persistence |
|---------|----------|-------------|
| **Bar / UI** | UI scale auto/manual · **Gap from edge** · **Flush windows to bar** · **Bar size** · top and bottom span, size, and alignment · **Left bar** / **Right bar** (show, span, alignment; left means the top of the screen) · Config menu icon on bar · **Color presets section** (show/hide presets on Colors) | `bar-layout.json` |
| **App Menu** | Pill icon (empty = 3×3 grid) · size 14–36 px · command the pill runs. Stock drawer toggles; any other command starts on each press | `bar-layout.json` |
| **Tooltips** | Delay · per-widget side (auto / above / below / left / right) | `bar-layout.json` |
| **Workspaces** | **Workspace Options** (two columns): special pill · only-active · show numbers · **default** count · startup workspace · close special on startup. **Workspaces** (two columns, counts differ by at most one): special row and numbered rows. Per row: **#** (typing a number another row owns swaps them; Hyprland is not renamed) · **symbol** (≤3 chars, ✕ clears — an empty symbol shows no glyph on the pill) · **label** (✕ clears) · **font** with search, **B** / **I** · **size** · **label color** swatch (picker opens to the right of the columns; right-click clears). **Add workspace** / **Apply** / **Undo** sit in the footer left of **Refresh** | `bar-layout.json` |
| **Overview** | **Layout** (Rows / Grid / Natural). Two columns: **Workspace strip** (edge, height, width, card length), **Previews** (margins, live captures, strip thumbnails, backdrop dim, blur the desktop, workspace numbers), **Workspaces** (dynamic, empty, special, All card), **Input** (pointer, wheel, click to close). **Motion** is open/close, slide, and the drop flight. **Super+Tab** toggles it. Full table: [overview.md](overview.md) | `bar-layout.json` (`ov*` keys, after the first change) |
| **Audio** | Show AEC section · show Summary / device profiles / Level meters · keep Summary / Active streams expanded (AEC on/off is only in the Audio panel) | visibility/expand → `bar-layout.json` |
| **Network** | **Full IP on bar** · **Last octet on bar** · **Device name on bar** | `bar-layout.json` |
| **Bluetooth** | Blueman sticky login autostart | XDG / applet control |
| **Notifications** | **Popup corner** — top left, top right, bottom left, or bottom right. A bottom corner stacks new toasts upward; a top corner stacks them downward. The SwayNC panel uses the same corner. **Message timeout** is 0–60 seconds for a normal toast. 0 keeps it up until you close it. **Keep messages expanded** — the history list opens with every message expanded, and new ones stay expanded. Collapse all still closes them until the next open. **Stagger row colors** alternates a modest shade; the selected row still uses the accent when it is off. **Clear history at boot** empties the list on the next startup. **Show counter** is the number on the bell. Keys: **→** expand the selected row, **←** collapse it, **a** expand all, **c** collapse all, **d** DND, **Del** remove the selected row, **Ctrl+C** copy, **Ctrl+Del** clear. Toggle the window with `qs ipc call notificationBell toggleHistory`. | `bar-layout.json` (`notificationCorner`, `notificationTimeout`, `notificationAutoExpand`, `notificationStaggerRows`, `notificationClearOnBoot`, `notificationShowCount`) and `~/.config/swaync/config.json` |
| **System stats** | Show CPU / Memory / GPU / VRAM · **Bar util graphs** (mini bars on the pill) · terminal · which mouse button opens `btop` / `nvtop`. The metrics popups are gone | `bar-layout.json` |
| **Dock** | Apply to **Application Launcher** or **All icons** · Off / Magnify / Jump / Both · magnify amount · neighbor spread · jump height. Stats and volume meters stay still. | `bar-layout.json` |
| **Active Window** | Hide the pill for a class, app id, or title. **Add class** / **Add title** use the focused window. `*` is a wildcard; the rest must match exactly. The corner stays on Widgets. The list starts with `hypr-screensaver`. | `bar-layout.json` (`activeWindowExcludesJson`) |
| **Screensaver** | **Video** or a text style (Night watch, Rain, Orbital, Warp, Pyro, Scanner) · **Clock** · warp speed / density / streak · auto-start · **Always start after idle** · idle minutes · **Dim on start** (DDC %, G9) · **Brightness on exit** · video path (hidden in text mode) · **script** · **Browse** / **Preview** / **Apply**. Tab video does not block; fullscreen does unless Always start is on. | `~/.config/hypr/screensaver.conf` + hypridle listener (no DPMS) |
| **ScreenShots** | Default folder for saved captures · **Browse** (zenity) · **Open** · **Default** (clears to `~/Pictures`) · **Apply**. Read by `~/.local/bin/capture-screenshot`; the `SCREENSHOT_DIR` env var still overrides it. The completion toast opens the capture in satty; **Super + Alt + ,** edits the latest shot. | `bar-layout.json` (`screenshotDir`) |
| **FreshRSS** | Filters expanded on open · HTTPS/HTTP · host · user · API password · **Test** / **Save server** | filters → `bar-layout.json`; credentials → `~/.config/freshrss-quickshell/freshrss.env` (never git) |

Numeric settings that use a slider also have **‹ ›** step buttons and a typed field (`components/OptValueSlider.qml`). Toggle rows still use the right-hand chip.

## Themes panel

Non-coder theme editor for the bar and all widgets. Open **Themes** on the control-bar toolbar.

### Layout

Title and sub-tabs (**Theming** · **Thresholds** · **Presets**) stay fixed at the top; the body scrolls underneath.

| Tab | Contents |
|-----|----------|
| **Theming** | Collapsible **Colors** · **Text** · **Special / Effects** (left) and **Opacity** (right). Includes **Running app dot**. **Main text** = menu headers; **Secondary text** = menu body; **Bar widget text** = face labels on the bar |
| **Thresholds** | Output/input volume; Sys Stats **shared % cutoffs** plus **CPU / Memory / GPU / VRAM** color ramps; temperature. Color picker appears only while a swatch is open. |
| **Fonts** | Two columns: **typeface** left · **size %** right. Rows: **UI**, **Monospace**, **Main**, **Secondary**, **Bar widget**. Preview shows all five |
| **Presets** | **Dark** / **Light**. Dark: liquid family, solid, soft, nordic, ember, ocean, lavender, forest, ink, cocoa, graphite. Light: paper, daylight, mist, blossom, sage, porcelain. Hide the tab from **Options → Color presets section** |

Color picker opens on the **right**. **Undo** reverts theme steps. Fonts, colors, and thresholds save to `state/theme-colors.json`.

### Controls

| Control | What it does |
|---------|----------------|
| **Colors** swatches | Bar background, widget background, menu background, border, accent, warning/pink, hover glow, **active button** (selected control-bar tab), **active workspace** (selected workspace pill), top edge shine |
| **Opacity** sliders | Alpha for glass fills, borders, hover, active button, active workspace, top edge shine |
| **Text** swatches | **Main** (headers) · **Secondary** (body) · **Bar widget text** (bar face) · button/workspace labels |
| **Built-in presets** | Dark and light sets (see Presets tab). **Cannot be removed** |
| **Your presets** | Click to apply; **×** removes a custom preset only (colors/fonts/thresholds) |
| **Save as preset** | Stores the current **colors** under a name in `~/.config/quickshell/themes/` |
| **Save setup** | Stores **colors + layout** (dual/classic bars, widget order, dock, pins, Options) in `~/.config/quickshell/profiles/` |
| **Your setups** | Click to apply the full snapshot; **×** removes it |
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
| Running app dot | `qlRunningDot` | Quick Launch running indicator (also Options → Dock) |
| CPU load | `statCpuTier1`–`4` | CPU util bar and % (AMD-red defaults) |
| Memory load | `statMemTier1`–`4` | Memory util bar and % (cyan defaults) |
| GPU load | `statGpuTier1`–`4` | GPU util bar and % (NVIDIA-green defaults) |
| VRAM load | `statVramTier1`–`4` | VRAM util bar and % (GPU-green defaults) |
| Sys Stats temperature | `statTempCool` / `Warm` / `Hot` + °C cutoffs | CPU / GPU temperature labels |

**Thresholds** tab: volume has three cutoffs and four tier swatches (low → peak). Sys Stats keeps **shared % cutoffs** and **separate color ramps** for CPU, Memory, GPU, and VRAM. Temperature has warm/hot °C cutoffs and three colors.

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

Script helper: `scripts/theme-io.sh` (`list` / `export` / `import`). Setups use `scripts/profile-io.sh` the same way. Advanced tokens (volume tiers, inspector semantics) stay in `Config.qml`.

### Importing a preset or a setup

Both import commands take a name already saved in the directory, or a path to a file anywhere else: a download, a USB stick, or a symlink inside `themes/` or `profiles/` that resolves outside that directory.

A file whose canonical path is already inside the directory is printed unchanged. The file is not rewritten, and nothing is dropped.

An outside file is checked, then copied in under a sanitized name (`A-Za-z0-9._-`, spaces become underscores). An existing file or symlink with that name stays in place, and the copy uses a `-2`, `-3`, … suffix. The copy is a regular file, mode 644. Each dropped key is written to the status line as `dropped … (reason)`, followed by `copied …`.

A theme file must be UTF-8 JSON, at most 256 KiB (262144 bytes), and a JSON object. A setup file has the same rules at 1 MiB (1048576 bytes). A known key of the wrong type, a bad hex color, or an alpha outside 0–1 refuses the import. Unknown keys are dropped and named. They do not refuse the import.

An outside setup also drops these layout keys:

| Key | When | Why |
|-----|------|-----|
| `quickLaunchAppsJson` | Always, including an empty value | Each entry can run on click. The whole key is removed. Commands inside it are not blanked one by one. |
| `launcherCommandCustom` | When it is not empty | It runs on click through a shell. An empty value means the default menu and is kept. |
| `statTerminal` | When it is not empty | The Sys Stats buttons launch this terminal. An empty value is kept. |
| `wallpaperDir` | Always | This machine's wallpaper directory. Rename and delete pass it to a script. |
| `wallpaperCurrent` | Always | This machine's current wallpaper path. |
| `screenshotDir` | Always | This machine's screenshot directory. |

A file that already lives in `themes/` or `profiles/` keeps those keys.

## XDG Autostart panel

Session user apps only (not Hyprland core). Scripts: `autostart-list-json.sh`, `autostart-set.sh`, `autostart-add.sh`, `autostart-run.sh`, `xdg-autostart-run.sh`. Failures log to `~/.local/state/quickshell/autostart-run.log`.

### How entries are created

| Source | Behavior |
|--------|----------|
| **Installed app** (picker / `--desktop-id` / `--desktop-file`) | **Copy** the real `.desktop` from `/usr/share/applications` (or other XDG apps dirs) into `~/.config/autostart/`. Preserves the app’s `Exec=`, `TryExec=`, icons, and other keys. Only forces `Hidden=false`, `X-GNOME-Autostart-enabled=true`, and `X-systemd-skip=true`. |
| **Manual** (`--name` + `--exec`) | Synthesize a minimal entry with the given command. |
| **Edit** on an entry | Rewrites that file’s `Exec=` only. Name, icon, and the enable flag stay. The field shows the raw command, including `%U` and other field codes. |

Do **not** rewrite `Exec=` to `gtk-launch …`. That breaks apps with `DBusActivatable=true` (e.g. Telegram): `gtk-launch` can exit 0 without starting the process. The working system file has a real command (`Exec=Telegram -- %U`); the autostart copy must keep that.

To change a command without replacing the file, use **Edit** on the row, or:

```bash
~/.config/quickshell/scripts/autostart-set.sh exec org.telegram.desktop.desktop 'Telegram -- %U'
```

### How entries are run

`autostart-run.sh` (and the login helper) always run the entry’s **`Exec=`** line with FreeDesktop field codes (`%U`, `%f`, …) stripped. It does not call `gtk-launch`.

Login helper in Hyprland `autostarts.lua`:

```lua
hl.exec_cmd("~/.config/quickshell/scripts/xdg-autostart-run.sh")
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
