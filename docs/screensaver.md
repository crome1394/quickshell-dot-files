# Screensaver

Idle fullscreen saver. It does **not** use compositor DPMS (that blanks the CRTC and can drop DisplayPort / DSC on an Odyssey G9). Super+L starts it immediately. Click, move, or Esc dismisses it.

Options → Screensaver chooses the picture: **Video** (the mpv loop) or a text style (**Night watch**, **Rain**, **Orbital**, **Warp**, **Pyro**, **Scanner**). Text styles need no video file. The choice is `mode` and `style` in `screensaver.conf`. Missing `mode` means video, so an old config keeps playing the file. **Clock** hides the center time, date, and night line when it is off (`clock=0`). Warp has speed, density, and streak, each 1–10.

Prefs: `~/.config/hypr/screensaver.conf` (written by Options → Screensaver). Apply writes that file, creates `~/.config/hypr/hypridle.conf` when it is missing, and starts hypridle. The listener is the block marked `SCREENSAVER_IDLE`. hypridle reads the file only at start, so Apply restarts it. There is no DPMS listener. Player: `scripts/screensaver.sh` → `~/.local/bin/screensaver.sh`.

Mouse / click / Esc dismiss lives in **git**, not `~/.config/mpv` (that tree is empty after a reinstall). Source files:

| Git | Installed copy |
|-----|----------------|
| `scripts/screensaver.sh` | `~/.local/bin/screensaver.sh` |
| `scripts/screensaver-config.sh` | `~/.local/bin/screensaver-config.sh` |
| `scripts/screensaver-text.py` | `~/.local/share/screensaver/screensaver-text.py` |
| `scripts/screensaver-mpv/input.conf` | `~/.local/share/screensaver/input.conf` |
| `scripts/screensaver-mpv/quit-on-input.lua` | `~/.local/share/screensaver/quit-on-input.lua` |

After clone or pull:

```bash
~/.config/quickshell/scripts/install-screensaver-helpers.sh
```

The player looks in the git tree first, then `~/.local/share/screensaver`. Super+L / hypridle call `~/.local/bin`, so copy the helpers or they stay on the last install.

Text mode opens fullscreen kitty (class `hypr-screensaver`) on the Python script. The active-window pill skips that class by default. Settings → Options → **Active Window** edits the skip list. Kitty does not idle-inhibit a fullscreen window. The script quits on a key, a click, or a pointer move after one second, and the shell restores monitor brightness when that process exits. Video mode is unchanged: fullscreen mpv, same title, same dismiss files.

## Idle vs video

Browser tabs (YouTube, X, Facebook, Rumble, …) often set Wayland/D-Bus **idle-inhibit** without going fullscreen. Hypridle is set to **ignore** those inhibitors so the timeout still fires.

`screensaver-config.sh idle-ok` then:

1. Exits failure if auto-start is off.
2. Exits success if **Always start after idle** is on (`ignore_inhibit=1`).
3. Otherwise refuses only when a mapped client is in **real fullscreen** (not the saver itself).

So a YouTube tab does not block the saver; a fullscreen movie does, unless Always start is on.

## DDC dim / exit brightness

The G9 has no `/sys/class/backlight`. Optional dim uses `ddcutil` VCP 10 (one get, then one set — NVIDIA DP AUX can drop DDC if hammered).

| Option | Conf keys | Behavior |
|--------|-----------|----------|
| **Dim on start** | `dim_enable`, `dim_level` | Capture current %, then set `dim_level` |
| **Brightness on exit** | `restore_enable`, `restore_level` | On: set `restore_level`. Off after a dim: restore the captured value |

Needs `ddcutil` on PATH and **DDC/CI** enabled in the monitor OSD. If DDC fails, the saver still runs; dim is skipped (`~/.cache/screensaver-ddc.log`).

## Apply

Options → Screensaver → **Apply** writes `screensaver.conf`, creates `hypridle.conf` if it is missing, and restarts hypridle so the new delay is loaded. Run `scripts/install-screensaver-helpers.sh` after pulling so hypridle and Super+L keep using the helpers (player + mouse-dismiss lua).

## Dismiss

Fullscreen mpv can swallow pointer events, so hypridle `on-resume` is not enough. The lua script quits after the pointer moves more than 8px (1s grace so the first warp does not dismiss). Clicks, wheel, Esc, q, Space, Enter also quit. `--stop-screensaver=no` still lets hypridle stop the saver if the compositor sees the input.
