#!/usr/bin/env bash
# Copy screensaver helpers out of this git tree so hypridle / Super+L
# keep working after a reinstall. Run from the repo (or any copy of scripts/).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${HOME}/.local/bin"
SHARE="${HOME}/.local/share/screensaver"

install -d "$BIN" "$SHARE"
install -m755 "$HERE/screensaver.sh" "$BIN/screensaver.sh"
install -m755 "$HERE/screensaver-config.sh" "$BIN/screensaver-config.sh"
install -m755 "$HERE/screensaver-text.py" "$SHARE/screensaver-text.py"
install -m644 "$HERE/screensaver-mpv/input.conf" "$SHARE/input.conf"
install -m644 "$HERE/screensaver-mpv/quit-on-input.lua" "$SHARE/quit-on-input.lua"

printf 'installed:\n  %s\n  %s\n  %s\n  %s\n  %s\n' \
    "$BIN/screensaver.sh" \
    "$BIN/screensaver-config.sh" \
    "$SHARE/screensaver-text.py" \
    "$SHARE/input.conf" \
    "$SHARE/quit-on-input.lua"
