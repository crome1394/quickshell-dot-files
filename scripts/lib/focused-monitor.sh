#!/usr/bin/env bash
# Print the focused Hyprland output, or the first output if none is focused.
detect_focused_monitor() {
  local name
  command -v hyprctl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  name="$(hyprctl monitors -j 2>/dev/null | jq -r '([.[] | select(.focused == true)][0].name) // (.[0].name) // empty')"
  [[ -n "$name" && "$name" != "null" ]] || return 1
  printf '%s\n' "$name"
}
