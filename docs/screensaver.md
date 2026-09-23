# Screensaver

Idle fullscreen **mpv** loop. It does **not** use compositor DPMS (that blanks the CRTC and can drop DisplayPort / DSC on an Odyssey G9). Super+L starts it immediately. Click, move, or Esc dismisses it.

Prefs: `~/.config/hypr/screensaver.conf` (written by Options → Screensaver). Hypridle listener is patched by `scripts/screensaver-config.sh` (also installed as `~/.local/bin/screensaver-config.sh`). Player: `scripts/screensaver.sh` → `~/.local/bin/screensaver.sh`.

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

Options → Screensaver → **Apply** writes `screensaver.conf` and reloads hypridle. Copy `scripts/screensaver-config.sh` and `scripts/screensaver.sh` to `~/.local/bin/` after pulling so hypridle and Super+L keep using the helpers.
