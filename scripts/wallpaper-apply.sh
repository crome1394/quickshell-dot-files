#!/usr/bin/env bash
# wallpaper-apply.sh — set wallpaper via hyprpaper (immediate) + persist hyprpaper.conf
# Usage: wallpaper-apply.sh <image-path> [monitor]
set -euo pipefail

PATH_IMG="${1:-}"
MONITOR="${2:-${HYPR_WALLPAPER_MONITOR:-DP-1}}"
FIT="${HYPR_WALLPAPER_FIT:-cover}"
CONF="${HYPR_WALLPAPER_CONF:-$HOME/.config/hypr/hyprpaper.conf}"

if [[ -z "$PATH_IMG" || ! -f "$PATH_IMG" ]]; then
  echo "error: file not found: $PATH_IMG" >&2
  exit 1
fi

# Absolute path
PATH_IMG="$(readlink -f "$PATH_IMG" 2>/dev/null || realpath "$PATH_IMG" 2>/dev/null || echo "$PATH_IMG")"

# The path is written literally. Reject a newline so it cannot break the conf.
case "$PATH_IMG" in
  *$'\n'*|*$'\r'*) echo "error: path contains a newline" >&2; exit 1 ;;
esac
[[ "$MONITOR" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "error: refusing monitor name" >&2; exit 1; }
[[ "$FIT" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "error: refusing fit mode" >&2; exit 1; }

# Apply now (hyprpaper IPC)
if ! hyprctl hyprpaper wallpaper "${MONITOR},${PATH_IMG},${FIT}" >/dev/null 2>&1; then
  # Older syntax without fit mode
  if ! hyprctl hyprpaper wallpaper "${MONITOR},${PATH_IMG}" >/dev/null 2>&1; then
    echo "error: hyprctl hyprpaper wallpaper failed" >&2
    exit 1
  fi
fi

# Persist for next hyprpaper start (rewrite minimal conf, keep splash/ipc if present)
splash=false
ipc=true
if [[ -f "$CONF" ]]; then
  grep -q '^splash' "$CONF" && splash="$(grep -E '^splash\s*=' "$CONF" | head -1 | cut -d= -f2- | tr -d '[:space:]' || echo false)"
  grep -q '^ipc' "$CONF" && ipc="$(grep -E '^ipc\s*=' "$CONF" | head -1 | cut -d= -f2- | tr -d '[:space:]' || echo true)"
fi

case "$splash" in
  true|false) ;;
  *) splash=false ;;
esac
case "$ipc" in
  true|false) ;;
  *) ipc=true ;;
esac

# Follow a symlink and replace the real file. mktemp stays in that
# file's directory so mv is atomic and the link itself is left alone.
if [[ -L "$CONF" ]]; then
  dest="$(readlink -f -- "$CONF")"
else
  dest="$CONF"
fi
mkdir -p "$(dirname "$dest")"
tmp="$(mktemp "${dest}.XXXXXX")"
{
  printf '# Managed by quickshell wallpaper-apply.sh — last applied %s\n' "$(date -Iseconds)"
  printf 'preload = %s\n' "$PATH_IMG"
  printf 'wallpaper = %s,%s\n' "$MONITOR" "$PATH_IMG"
  printf 'splash = %s\n' "$splash"
  printf 'ipc = %s\n' "$ipc"
  printf '\n'
  printf 'wallpaper {\n'
  printf '\tmonitor = %s\n' "$MONITOR"
  printf '\tpath = %s\n' "$PATH_IMG"
  printf '\tfit_mode = %s\n' "$FIT"
  printf '}\n'
} > "$tmp"
mv -f "$tmp" "$dest"

# State for the control bar
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr-wallpaper"
mkdir -p "$STATE_DIR"
printf '%s\n' "$PATH_IMG" >"$STATE_DIR/current"
printf '%s\n' "$MONITOR" >"$STATE_DIR/monitor"

echo "ok ${MONITOR} ${PATH_IMG}"
