# Changelog

Notable changes for people upgrading this config. Day-to-day usage is in [README.md](README.md) and [docs/](docs/).

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
