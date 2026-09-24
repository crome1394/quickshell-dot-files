# Changelog

Notable changes for people upgrading this config. Day-to-day usage is in [README.md](README.md) and [docs/](docs/).

## 2026-09 — Audio top-align, all display modes, layout previews

- Audio: Input Devices align to the top of the column; Refresh / pw-top / Restart audio sit on the panel bottom-right.
- Display chips list every resolution at every supported refresh rate.
- Position: Classic vs Dual are monitor mockups; select then **Apply**.

## 2026-09 — Control tabs fill the window; actions bottom-right

- Every control-bar tab fills the Hyprland window. Footer actions (Refresh, Reset, NVIDIA, Apply, …) sit at the **bottom right**.
- Display lists available resolutions in the remaining space.

## 2026-09 — Control bar fills the window; stepper arrows grouped

- Opening the control strip starts on **Position**. The panel fills the window so the tab bar stays at the bottom (Hyprland owns the size).
- Slider **‹ ›** buttons sit together after the track, then the typed value.

## 2026-09 — Floating control bar + full-width Thresholds

- Control strip is a movable Hyprland **FloatingWindow** (title **Bar control**), like the inspector. Drag the top strip; Esc / ✕ close. Does not dismiss on outside click.
- Themes → **Thresholds** uses the full panel until you click a swatch; the color picker then opens on the right.

## 2026-09 — Slider steppers + even dock hover

- Control-bar numeric sliders (Dock, Position, Options, Wallpaper, Themes opacity/fonts, Screensaver, thresholds, widget width) use **‹ ›** plus a typed field (`OptValueSlider`).
- Hover between Quick Launch / tray / workspace icons no longer tracks the scaled hit-box, so neighbors magnify evenly.

## 2026-09 — Docs catch-up

- README covers Dock, Quick Launch dots, per-metric stats colors, **Save setup**, and screensaver (idle mpv, no DPMS).
- New [docs/screensaver.md](docs/screensaver.md). Control-bar / Config tokens match the current Options and Themes panels.

## 2026-09 — Screensaver DDC dim / exit brightness

- Options → Screensaver **Dim on start** (0–100%) uses `ddcutil` VCP 10 (G9 has no sysfs backlight; not DPMS). Captures the current level first.
- **Brightness on exit**: on = set that %; off = restore the captured level after a dim. Needs `ddcutil`. One get/set per transition.

## 2026-09 — Screensaver ignores tab video; fullscreen still blocks

- Browser tabs playing YouTube / X / Facebook / Rumble no longer hold off the idle screensaver (`ignore_wayland/dbus/systemd_inhibit` in hypridle; `idle-ok` only refuses **fullscreen** windows).
- Options → Screensaver **Always start after idle** starts the saver even during fullscreen video. Apply to save.

## 2026-09 — Widgets panel Top / Bottom sections

- **Widgets** lists dual-layout pills in **Top bar** and **Bottom bar** cards (classic: Left / Center / Right). Empty sections stay visible so you can move a widget in with T/B.

## 2026-09 — Per-metric stats colors, running-dot color, saved setups

- **Themes → Theming:** **Running app dot** (`qlRunningDot`, default vivid cyan `#00F5FF`). Same swatch on **Options → Dock**.
- **Themes → Thresholds:** CPU / Memory / GPU each have their own load ramp (AMD-red, cyan, NVIDIA-green defaults). Shared % cutoffs stay one set.
- **Themes → Presets:** **Save setup** stores colors + layout (bars, widget order, dock, pins) under `profiles/`. **Your setups** to apply or remove.

## 2026-09 — Quick Launch running dot

- Running apps show a Mac-dock-style **dot** on the pill’s bottom edge instead of a dash plus workspace-chip fill. Icons stay center-aligned with the rest of the bar; focused is the same size dot, brighter.

## 2026-09 — Dock hover on all icons + last-icon unstick

- Options → **Dock → Apply to**: **Quick Launch** or **All icons** (default). Magnify/jump apply to launcher, tray, workspaces, FreshRSS, net/BT chips, bell, kill, inspector, config, and power. CPU/Memory/GPU and the volume meter stay still.
- Quick Launch no longer leaves the last icon magnified after the pointer leaves the pill (hover is gated on the unscaled row).

## 2026-09 — GNOME overlay standard offset

- Overlay masks use the **non-DST** offset (`min(January, July)`), matching `cc-timezone-map.c`. Sydney (AEST +10) no longer lights UTC+11 Siberia.

## 2026-09 — GNOME timezone overlays

- Region map uses GNOME Initial Setup assets (`bg.png` + `timezone_*.png`) and the same Miller projection (`cc-timezone-map.c`: 81°N–59°S, −6° longitude shift). Hover/click highlight is the official offset mask, not a city Voronoi.

## 2026-09 — Region map zone alignment

- Hover/click highlight follows the **city's UTC offset**, not the ocean pixel under the cursor (Los Angeles no longer lights random Pacific blobs).
- Raster v2: far ocean uses longitude bands; land stays city-based so west-coast PST covers California.

## 2026-09 — Region map selected zone

- Current timezone (e.g. America/New_York) and a clicked city now keep the green band after hover ends. Highlight is sampled from the same raster as mouseover, including ocean.

## 2026-09 — Region map hover highlight

- **Region & Clock:** hovering a timezone lights the whole offset band including ocean (GNOME Date & Time style). Example: hover San Francisco → Pacific band. Repaint only when the hovered band changes.

## 2026-09 — Hover height, clock font, widget dividers

- Hover chips on Clock / Network / Bluetooth / Audio match workspace pill height.
- Tighter gap between bar widgets (`widgetSpacing` 8px).
- **Region & Clock → Clock:** face font family + size (independent of Themes → Bar widget text).
- **Widgets:** **Add |** inserts a movable `|` divider (up to 8) to split widget groups.

## 2026-09 — Control-bar hover without an extra click

- Opening the config strip re-arms Hyprland focus grab after the popup maps, so toolbar/panel hover works immediately.

## 2026-09 — Tooltip placement + region map paint

- Bar hover tips sit **above or below** the pill (by bar edge) and are click-through, so they no longer cover the icon.
- Options → **Tooltips**: delay (0–3000 ms) and per-widget side (Auto / T / B / L / R).
- Region map highlight repaints as soon as the panel opens (no extra click).

## 2026-09 — Region map timezone bands

- **Region & Clock:** the world map stretches to fill the panel, includes Antarctica, tints land by timezone, and highlights the whole offset band when you click a city (GNOME Date & Time style).

## 2026-09 — Control-bar scrollbar gutter

- Wallpaper, Widgets, Options, Launch, and Autostart leave a 22px lane for the body scrollbar so thumbs and row controls are no longer under the bar.

## 2026-09 — Last octet toggle + flush windows to bar

- **Network pill:** Options → **Last octet on bar** (`showNetworkLastOctet`, default on). Turn it off to hide the last IPv4 octet (full IP still wins when enabled). Combines with **Device name on bar**.
- **Position** and **Options → Bar / UI:** **Flush windows to bar** (`flushWindowsToBar`) shrinks the exclusive zone by Hyprland `gaps_out` so tiled windows sit against the bar. IPC: `setFlushWindowsToBar`.

## 2026-09 — Network device name on bar

- **Network pill:** Options → **Device name on bar** shows the adapter name (`enp10s0`, `wlan0`) next to the IP (`showNetworkDeviceName` in `bar-layout.json`). Combines with **Full IP on bar**.

## 2026-09 — Bar edge gap + bar size

- Control strip **Position** and **Options → Bar / UI**: **Gap from edge** (0–48 px) and **Bar size** (80–140%). Dual applies the gap to both bars. Persisted in `bar-layout.json`.
- IPC: `setBarEdgeMargin` / `setBarSizeScale`.

## 2026-09 — Dual centered bars

- Control strip **Position** can switch **Classic** (one bar, L/C/R) and **Dual** (top + bottom, centered). Each mode stores its own widget order in `bar-layout.json`.
- Dual default: top = Clock, Workspaces, Tray, Notifications, Power; bottom = Sys Stats, Launcher, Quick Launch, FreshRSS, Config, Net·BT·Audio (sound stays in that combined pill).
- **Widgets** panel uses **T/B** zone buttons in Dual (same show/hide, reorder, width % as Classic). **Reset layout** restores the default for the active mode.
- IPC: `setBarLayoutMode classic|dual` / `toggleBarLayoutMode`. Classic remains the default so existing layouts keep working.

## 2026-09 — Clock region map + custom format

- Control-strip button is **Region & Clock**, with MIME-style **Region** / **Clock** tabs (Region is the default).
- **Region:** clickable world map (installer-style) from `zone1970.tab`, city search, **Apply region**. Apply closes the panel first so a polkit password prompt is not covered.
- **Clock:** format presets unchanged; a **Custom** field accepts any `Qt.formatDateTime` string (preview live, **Set** / Enter to save). Still persisted in `bar-layout.json`.

## 2026-09 — Notification history panel

- **History is the panel:** left-click the bell for history (every notification is captured via D-Bus `Notify` and kept in `~/.local/state/quickshell/notification-history.json`). SwayNC’s control center is no longer in the UI.
- History footer: **Expand all / Collapse all**, **DND**, **Clear list**. Top-right **✕** closes the panel. Right-click the bell still toggles DND.
- Per-item **✕** removes one saved notification (history is persisted across reboot). Expand and copy are unchanged.

## 2026-09 — Sticky control-bar headers + widget close ✕

- Wallpaper / Widgets / Options / Launch / Autostart / Display pin title + controls (like Themes and Audio); only the body scrolls.
- Bluetooth: **Power off/on** is visible at the bottom of the menu; hint is “Right-click pill to toggle on/off bluetooth”.
- Network, Bluetooth, and Audio Controls popups have a top-right **✕**.

## 2026-09 — Control bar focus, close ✕, footer actions

- **Keyboard search** works again in Autostart / MIME / Keybinds / Launch / Audio / Services (Hyprland focus grab stays armed; close with ✕ or Esc).
- Control-bar panels: **✕** top-right; “click outside to close” hint removed.
- Header actions moved to the **bottom** of each panel: Display (NVIDIA + Refresh), Wallpaper, Widgets, Options, Themes (Reset), Launch, Autostart, MIME (Reload).
- Bluetooth popup: **Power off** at the bottom; applet toggle removed (sticky autostart stays in Options).
- Audio Controls: **pw-top** and **Restart audio** at the bottom (same in the control-bar Audio tools).

## 2026-09 — Control bar scroll + Network popup

- **Scroll:** Widgets, Options, Themes, Launch, Audio, and Keybinds wheel-scroll again. A wallpaper DropArea had `enabled: false` on other tabs, which disabled the whole panel tree (Wallpaper was unaffected because that DropArea was on).
- **Network pill:** Options → **Full IP on bar** shows the complete IPv4 address instead of the last octet (`showNetworkFullIp` in `bar-layout.json`).
- **Network popup:** per-adapter **Enable** (undo `disconnect` without toggling Auto), **WiFi on/off** on WiFi cards, **Wired on/off** on ethernet cards. Header **WiFi / Net / Applet** toggles removed (nm-applet login autostart stays under Options). **↻ IP** / **↻ DNS** moved to the bottom next to **All off** (disconnect every adapter + WiFi radio off).

## 2026-09 — Wallpaper panel

- **Wallpaper** (control strip → **Wallpaper**):
  - Thumbnails stretch to fill the panel width (no empty column on the right).
  - **Tile size** slider (100–260px, persisted in `bar-layout.json`); **Ctrl+wheel** on the grid also resizes.
  - Hover **✎ / ✕** or right-click a thumb to **Rename…** / **Delete…** (delete asks for confirmation). Rename of the current wallpaper re-applies it.
  - Drag-and-drop image files (or a folder of images) onto the panel to copy them in; **Add wallpapers…** still uses the file picker.
  - The panel **stays open** while dragging from a file manager (outside-click dismiss is skipped on this tab so the drop can land). Click **Wallpaper** again, the bar chrome, or Esc to close.
  - Scripts: `wallpaper-add.sh` accepts extra file args; `wallpaper-rename.sh` / `wallpaper-delete.sh` only touch image files inside the wallpaper folder.

## 2026-08 — Theme system, fonts, polish

- **Themes** (control strip → **Themes**): live color/opacity editor, undo, thresholds (volume + sysstats), **Fonts** tab, presets.
  - Text roles: **Main** (menu headers), **Secondary** (menu body), **Bar widget text** (face on the bar) — isolated colors.
  - **Fonts**: UI / Mono / Main / Secondary / Bar — each with typeface + size % (two-column layout); preview lists all five.
  - Liquid presets: Liquid glass, mint, violet, rose, amber, ice, aurora (+ solid/soft/nordic/ember/ocean/lavender/forest).
  - Persist: `state/theme-colors.json`; named presets under `themes/`.
- **Display**: Apply writes `~/.config/hypr/config/monitors.lua` so resolution/refresh/bit-depth survive reboot.
- **Sys Stats / Network Options**: independent toggles for bar util graphs vs menu graphs; network traffic sparkline optional.
- **Notifications**: left-click history panel (expand all, per-item copy / dismiss, DND, Clear list); right-click DND. History via `scripts/notification-history.py`.
- **Hover**: content-chip accent rim (not whole multi-item pills); Net/BT/Audio sections when embedded.
- **MIME / control panels**: secondary body greys track Themes → Secondary text.
- **Stability**: fixed QML type-coercion warnings (`NetworkMonitorView` bools/ints, `ClockPill` grid spacing, `ServicesView` row selection).

## 2026-08 — Control bar & FreshRSS

- **MIME panel** (control strip → **MIME**): Preferred applications / file-type defaults.
  - Dual modes: **File types** (set default opener) and **Applications** (linked types; ★ = default opener).
  - **Associate app…** / **+ Add type** pickers (any installed app, even if it doesn’t advertise the type).
  - Path look-up (“What opens this file?”), search, filters (All / Files / Links / Has default).
  - Keyboard nav on File types (↑↓, → apps, Enter set default, A associate).
  - Dual panes fill the tall panel height; lists scroll internally.
  - Set via `xdg-mime default`; clear only your `~/.config/mimeapps.list` `[Default Applications]` entry.
  - Scripts: `mime-catalog-json.sh`, `mime-apps-json.sh`, `mime-file-probe.sh`, `mime-set-default.sh`; UI: `components/MimeAppsView.qml`.
- **Colors panel** (control strip → **Colors**):
  - Live theme editor: **Colors** + **Opacity** columns, full-width **Text** row (left/right split), optional **Presets** at the bottom.
  - Picker opens on the **opposite** Colors/Opacity column (mouse SV + hue, hex / RGB); compact so the panel Flickable does not steal drag.
  - Editable fills: active control-bar tab (`controlActiveBg`), active workspace pill (`wsActiveBg` + opacity).
  - Editable labels: button text / active button text (toolbar tabs), workspace text / active workspace text (bar pills).
  - Built-in presets (Liquid glass, Solid dark, Soft grey — not removable); **Save as preset** / remove for user themes in `themes/`.
  - Options → **Color presets section** toggles preset UI visibility (`showColorPresets` in `bar-layout.json`).
  - Active look in `state/theme-colors.json`; helper `scripts/theme-io.sh` (list / export / import / delete).
  - Liquid-glass default palette (cool blue-slate glass, vivid teal accent, magenta secondary).
- **Audio panel** (control strip → **Audio**):
  - Multi-device manager via Inspector `AudioMonitorView` (ports, set-default, volume/mute, profiles under Output/Input).
  - Overview pill: **Summary → Active streams → Levels**; tools (**Refresh**, **pw-top**, **Restart audio**); sticky **echo cancel** at bottom.
  - Options: show AEC section / Summary / profiles / Level meters; keep Summary & Active streams expanded. AEC on/off is only in the Audio panel/pill.
  - Idle when closed: no peak sampling, poll, or profile processes (`stopAllWork`). Peak-detect streams filtered from app lists.
  - AudioPill popup scrolls when tall so Echo cancel no longer overlaps the border.
- **Display panel** (control strip → **Display**):
  - Live monitor indicator (res, Hz, bit depth, make/model/serial, scale, physical size).
  - Adapter card (DRM + NVIDIA util/temp/power/VRAM); soft-poll **only while the panel is open**.
  - **NVIDIA** button (Nerd Font icon) → `nvidia-settings`.
  - Resolution block slider + refresh dropdown + bit-depth dropdown; linked by hyprctl modes / Hz families.
  - **Apply** at scale 1.0 via `scripts/monitor-mode.sh` (pending until Apply).
- **SysStats pill layout:** center CPU/Memory/GPU; sections hug content (Memory no longer clips); snug fit with no empty side ballast; single separator slots between visible gauges.
- Control strip: Position, **Display**, Wallpaper, Widgets, Options, **Colors**, Launch, Autostart, **MIME**, **Services**, **Audio**, **Keybinds**, Clock (toolbar on bottom).
- **Keybinds** panel: browse `keybindings.lua` by category; edit key chord / category / description (in-place write + backup; Reload Hypr separate).
- **Services** panel: systemd user/system units with filter + Start/Stop/Restart (reuses Inspector `ServicesView`).
- Widgets panel: A–Z list; row layout ✓/name · L/C/R · ↑↓; horizontal width scale.
- Options: UI scale, workspaces, sticky applets, Sys Stats gauges, FreshRSS server Test/Save.
- FreshRSS secrets moved to `~/.config/freshrss-quickshell/freshrss.env` (outside git).
- **Autostart fix:** add copies the system `.desktop` (keeps real `Exec=`) instead of synthesizing `gtk-launch` entries; run uses `Exec=` only (not `gtk-launch`). Fixes Telegram and other `DBusActivatable` apps that silently failed under `gtk-launch`. Still sets `X-systemd-skip=true`; logs to `~/.local/state/quickshell/autostart-run.log`.
- Config menu bar pill (`controlBar`).

## Earlier

- NWS Radar pill removed from the default bar (code remains under `widgets/RadarPill.qml` / `scripts/radar-fetch.sh` if you re-enable it).
- Combined Network · Bluetooth · Audio connectivity pill option.
- Sticky nm-applet / Blueman autostart controls.
