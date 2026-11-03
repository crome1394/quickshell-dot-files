# Changelog

Notable changes for people upgrading this config. Day-to-day usage is in [README.md](README.md) and [docs/](docs/).

## 2026-11 — Paths, app menu, and missing tools

- Config and script paths use the home directory. The focused monitor is detected instead of a fixed output name. CPU temperature follows the `k10temp` sensor. Extra disk mounts stay empty unless `SYSMON_EXTRA_MOUNTS` is set. Mounted NVMe partitions are still listed.
- The default Application Menu command is `scripts/app-drawer.sh`. It tries rofi, then wofi, then fuzzel, and shows an error if none of them is installed. A saved custom command still wins.
- Without `nvidia-smi`, GPU and VRAM show N/A. Intel and AMD GPUs are not read.
- Bluetooth · Audio is one pill. Network is its own pill. `scripts/window-at-point.sh` is a manual helper and is not called by the bar.
- Hyprland, hyprpaper, hypridle, screensaver, and FreshRSS writes go through a temporary file in the target directory. A symlink stays a symlink, and the real file is replaced.
- FreshRSS does not call a built-in server when its env file is missing.
- The bottom bar and the side bars no longer log an exclusive-zone binding loop.

## 2026-11 — Workspace overview

- **Super+Tab** toggles a fullscreen workspace overview on the focused monitor (`qs ipc call overview toggle`). **Super+Shift+Tab** is desktop layout (`overview desktop`). **Super+Ctrl+Tab** is every workspace on that monitor (`overview all`). `next` and `prev` step the strip.
- While it is open, that monitor takes the keyboard. **Tab** / **Shift+Tab** move between cards, arrows select a window, **Enter** focuses it, **D** closes it, **A** toggles all workspaces, a bare **Shift** flips desktop layout, **1–9** and **0** pick a strip card, and **Esc** closes. Drag a window onto a card to move it.
- Closing focuses the workspace you were viewing. Clicking a window focuses that window and skips that step.
- Settings → Options → **Overview**. Layout is **Rows**, **Grid**, or **Natural**. The strip can sit on any edge. Live previews are on until you turn them off. Saved in `state/bar-layout.json` (`ov*` keys) after the first change. See [docs/overview.md](docs/overview.md).
- The special strip card is the name from Options → **Workspaces**. Any other Hyprland special stays off the strip. **Show the special workspace** is off until you turn it on.

## 2026-11 — Notification popup corner

- Settings → Options → **Notifications** has **Popup corner**: top left, top right, bottom left, bottom right. The choice is saved in `bar-layout.json` (`notificationCorner`) and written to SwayNC `positionX` / `positionY`.
- Bottom corners stack a new toast at the bottom and move older ones upward. Top corners stack downward.
- The default is **bottom right**. IPC: `qs ipc call shell setNotificationCorner bottomRight`.
- **Message timeout** is how long a normal toast stays, from 0 to 60 seconds. 0 keeps it up until you close it. Saved as `notificationTimeout` and written to SwayNC `timeout`. IPC: `qs ipc call shell setNotificationTimeout 8`.

## 2026-11 — Network panel

- The bar network control is `widgets/network/`. Settings → Widgets → **Network** shows or hides it. IPC: `setShowNetworkPanel` / `toggleShowNetworkPanel`, and `networkPanel` `showPopup` / `hidePopup` / `togglePopup` / `setWifi` / `toggleWifi`.
- The old network pill, its `networkPill` IPC, the traffic-graph switch, and the nm-applet login autostart switch are removed. The combined pill is Bluetooth · Audio.
- Options → **Network** keeps **Full IP on bar**, **Last octet on bar**, and **Device name on bar**.
- Removed the unused `cachyos-linux.svg` from the repo root. The inspector still asks fastfetch for its own cachyos logo.

## 2026-11 — Transparency, edge bars, text saver, and the stats popups are gone

- **Transparency** is a bar pill. Click opens **Apps** and **Satty**, each 5–100%. 100% is solid. Fullscreen windows and the Settings window stay solid. Until **Apps** is moved, the Hyprland window rules you already have stay. Satty does not follow Apps. State is `~/.config/hypr/opacity.state`. Generated rules are `~/.config/hypr/opacity.lua`. IPC: `setShowOpacityPill` / `toggleShowOpacityPill`.
- **Active Window** is a corner overlay, not a widget in a bar zone. It shows the focused window’s icon, class, and title, and it hides when that label is empty. Widgets → **Other** picks the corner (top left by default). The layer sits above a fullscreen window. Steam games show the game title and the Steam icon.
- Settings → Options → **Active Window** hides the pill for a class, app id, or title. `*` is a wildcard. The list starts with `hypr-screensaver`. **Add class** and **Add title** use the window that is focused now. IPC: `setShowActiveWindowPill`, `setActiveWindowCorner`, `addActiveWindowExclude`, `removeActiveWindowExclude`.
- Dual mode can show a **left bar** and a **right bar**. Both start off. Options → **Bar** turns each one on, sets whether it spans the screen, and sets alignment. On a side bar, **Left** is the top of the screen. Widget faces rotate 90° clockwise. Popups stay upright and open beside that bar. Widgets lists **Left bar** and **Right bar** once the bar is on.
- The screensaver can be **Video** or a text style: **Night watch**, **Rain**, **Orbital**, **Warp**, **Pyro**, **Scanner**. Text mode needs no video file. **Clock** hides the center time when it is off. See [docs/screensaver.md](docs/screensaver.md).
- Display **Apply** writes `cm = "srgb"` into `monitors.lua`. Hyprland `auto` on 10-bit maps to wide/BT2020 and fringes Quickshell icons.
- Removed the Sys Stats **metrics popups**: sparklines, process lists, pin-to-desktop, **Show graphs**, and the live-update pause. CPU and Memory open `btop`. GPU and VRAM open `nvtop`. Options → **Stats** picks the terminal and which mouse button launches it. The other button does nothing. **Bar util graphs** still toggles the mini bars on the pill. The `sysStatsPill` live-update IPC commands are gone, and `showStatMenuGraphs` no longer controls anything.

## 2026-10 — Notification history window

- `qs ipc call notificationBell toggleHistory` opens or closes the history window. `showHistory` and `hideHistory` do one direction.
- Settings → Options → **Notifications** has **Keep messages expanded** (off until you turn it on) and **Stagger row colors** (on until you turn it off).
- The history window takes the keyboard: **→** expands the selected row, **←** collapses it, **a** expand all, **c** collapse all, **d** Do Not Disturb, **Del** removes the selected row, **Ctrl+C** copies it, **Ctrl+Del** clears the list. **↑↓** move the selection.
- With stagger on, rows alternate a modest shade. The selected row uses the accent either way.
- The bell badge counts rows in the history list. An empty list shows no number. SwayNC's own count can stay above zero after those notifications leave the list.
- The history window keeps its key hint and buttons on the bottom edge.
- Settings → Options → **Notifications** can clear the history on the next boot, and can hide the number on the bell.

## 2026-10 — Notification message text

- Expanding a history row shows the message. Telegram bodies that contain a line break are kept whole. Rows saved before this change have no message text to show.

## 2026-10 — Tailscale node switches

- The Tailscale panel can turn on Accept Routes, Accept DNS, Shields Up, Allow LAN access, Advertise as Exit Node, and stateful filtering.
- Advertise routes takes a subnet list, then Apply. Clear removes them. Offered exit nodes and routes still need approval in the Tailscale admin console.

## 2026-10 — Notification images, audio columns, edge popups

- The notification history panel is 15% wider. Click a row to expand it. An expanded screenshot shows a small thumbnail beside the full text. Copy puts the image on the clipboard when the row has one, and the text otherwise.
- Themes → Thresholds → **Audio** places **Input volume** to the right of **Output volume**.
- Popups for widgets on a side bar open beside that bar. A right-bar pill opens to its left; a left-bar pill opens to its right.
- SwayNC toasts use the same cerulean card, silver frame, and accent as SwayOSD. They stay at the top-right.

## 2026-10 — Tailscale pill, threshold columns, ScreenShots

- Themes → Thresholds → **System Stats** places **Temperature Thresholds** to the right of **Load Thresholds**.
- Options → **ScreenShots** is the capture-folder tab.
- **Tailscale** is a bar pill. Left click opens machines (copy IP, name, or DNS, exit node, Taildrop send). Right click runs `tailscale up` or `down`. Move it from Settings → Widgets.

## 2026-10 — Settings window and workspace columns

- The control window is titled **Settings**. Hyprland floats it and keeps it opaque when `title = "^(Settings)$"` and the class is `org.quickshell`.
- Options → **Workspaces** has two sections. **Workspace Options** is two columns: special pill, only-active, and show numbers on the left; default count, startup workspace, and close special on startup on the right.
- **Workspaces** lists the special row and the numbered rows in two columns. The left column takes one more card when the count is odd, so the columns differ by at most one. The label-color picker still opens on the right.

## 2026-10 — VRAM on the stats pill

- The Sys Stats pill now shows **CPU | Memory | GPU | VRAM**. VRAM is GPU memory used (percent + GiB).
- Themes → **Thresholds** has a separate **VRAM load** color ramp (GPU-green by default).
- Options → **Stats** has a **Show VRAM** switch, saved with the other stats options.
- The **Menu util graphs** toggle left Options → **Stats** with this change. The popups it controlled were removed later. See the 2026-11 entry above.
- The bar pill polls every 2 seconds.

## 2026-10 — Control bar menu stays down, autostart commands are editable

- The control-bar tabs stay on the bottom edge when a page is closed. They pack from the left, and the close button stays at the right.
- Autostart → **Edit** changes an entry’s `Exec=` path. The rest of the desktop file is left as it is.

## 2026-09 — Light presets stay readable

- Light presets use solid paper fills. The Settings window is no longer a 75% veil, and text fields follow the theme instead of a fixed dark well.

## 2026-09 — Top bar and bottom bar

- Options → **Bar** uses the monitor pictures again. Classic and Dual are those buttons.
- Dual splits into **Top bar** and **Bottom bar**. Each has its own span, size, and widget alignment (left, center, or right).

## 2026-09 — Audio view, bar layout, tooltips

- Options → **Audio**: default pill view is **Speaker**, **Microphone**, or **Both**. It is saved and restored. Right-click still cycles it.
- **Position** is now Options → **Bar**: Classic / Dual, top or bottom, bar size, panel size, and separate **spans the monitor** switches for the bar and the bottom panel.
- Options → **App Menu**: **Apply** saves the icon, size, and command. **Undo** drops unapplied edits, or reverts the last Apply.
- Hover tips use a layer window. The old popup's parent binding loop kept them from opening.

## 2026-09 — Settings follow the widget switches

- Turning a widget off hides its settings and leaves the saved values in place. That covers Options (App Menu, Workspaces, Audio, Network, Bluetooth, Stats, FreshRSS, and Dock when every icon pill is off), the matching tooltip rows, the App Launcher and Audio tabs, the Clock format tab, and the audio/stats theme thresholds. The Widgets switches stay so the pill can be turned back on.

## 2026-09 — Application Menu options and light presets

- Options → **App Menu**: icon (empty keeps the 3×3 grid), size 14–36 px, and the command the pill runs. Saved in `bar-layout.json`. The stock drawer still toggles; any other command starts on each press.
- Themes → **Presets**: **Dark** / **Light**. New dark presets Ink, Cocoa, and Graphite. Light presets Paper, Daylight, Mist, Blossom, Sage, and Porcelain.

## 2026-09 — Autostart app list fills the panel

- Autostart → **Add installed app** uses the open space under the search field. The list still scrolls when there are more apps than fit.

## 2026-09 — Control bar MIME, display, clock, tooltips

- MIME Applications: clicking a linked file type stays on that tab. **Use as default** and **Associate app** act on the selected type. Defaults the File types tab already shows (including HEIF for COSMIC Viewer) appear in the linked list. Category chips (Images, Audio, Video, Text, Documents) can set one wildcard default.
- Autostart lists every installed application without a search.
- Keybind chords use the same modifier colors as the inspector.
- Workspaces: magic pill icon is editable (Apply saves it).
- Display resolution chips are grouped by refresh rate.
- Clock custom format preview sits under the custom field.
- Options → **Tooltips** is its own tab.

## 2026-09 — Theme font steppers; Media and Kill Target removed

- Themes → **Fonts**: **‹ ›** cycle each typeface. **− +** change its size (70–150%).
- **Media** and **Kill Target** are no longer bar widgets. System stat bars stay visible on their own.

## 2026-09 — Workspace font, Apply, Undo

- Options → **Workspaces**: each default pill has its own font (or **Bar font**) and emoji size. The font and size apply to the emoji only; the workspace number stays on the bar font. **‹ ›** step through faces. **− +** change the emoji size. Count, order, label, font, and size stay on the panel until **Apply**. **Undo** drops those edits, or reverts the last Apply.

## 2026-09 — Control bar names, workspace rows, reopen

- Widgets tab: **Application Menu**, **Application Launcher**, **Config Menu Icon**, **System Stat Bars**. The bottom tab **Launch** is **App Launcher**.
- Options → **Workspaces**: default count, per-workspace icon or short text, add, remove, and reorder. Saved in `bar-layout.json`.
- **Super+C** (and Hyprland’s window ✕) no longer leaves Settings unable to open. The in-panel ✕ and the gear icon were already fine.
- The **Application Menu** pill toggles the app drawer: click opens it, click again closes it, and the icon stays lit while it is open.

## 2026-09 — Screensaver mouse dismiss in git

- Mouse / click / Esc dismiss files live in `scripts/screensaver-mpv/` (not `~/.config/mpv`, which a reinstall wipes).
- After clone/pull: `scripts/install-screensaver-helpers.sh` copies the player, config helper, and mpv input/lua.

## 2026-09 — Docs: floating control bar

- README and [docs/control-bar.md](docs/control-bar.md) cover the movable **Settings** window, Position mockups + Apply, Display res×Hz chips, slider steppers, and bottom-right tab actions.

## 2026-09 — Control bar after Hypr inspector

- Opening **Hyprland Config Inspector** first no longer wedges the control strip. Show remaps if the FloatingWindow backing surface was dropped while `visible` stayed true.

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

- Control strip is a movable Hyprland **FloatingWindow** (title **Settings**), like the inspector. Drag the top strip; Esc / ✕ close. Does not dismiss on outside click.
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

- NWS Radar pill removed from the bar (`widgets/RadarPill.qml` and `scripts/radar-fetch.sh` deleted).
- Combined Network · Bluetooth · Audio connectivity pill option.
- Sticky nm-applet / Blueman autostart controls.
