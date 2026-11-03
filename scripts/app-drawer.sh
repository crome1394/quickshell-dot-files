#!/usr/bin/env bash
# Application menu. Tries rofi, then wofi, then fuzzel.
# A saved launcherCommand overrides this script.
set -u

if command -v rofi >/dev/null 2>&1; then
  exec rofi -show drun
fi
if command -v wofi >/dev/null 2>&1; then
  exec wofi --show drun
fi
if command -v fuzzel >/dev/null 2>&1; then
  exec fuzzel
fi

msg="No application menu found. Install rofi, wofi, or fuzzel."
if command -v notify-send >/dev/null 2>&1; then
  notify-send "Application menu" "$msg"
elif command -v zenity >/dev/null 2>&1; then
  zenity --error --title="Application menu" --text="$msg"
elif command -v hyprctl >/dev/null 2>&1; then
  hyprctl notify -1 5000 "rgb(ff0000)" "$msg" >/dev/null 2>&1 || true
fi
printf '%s\n' "$msg" >&2
exit 1
