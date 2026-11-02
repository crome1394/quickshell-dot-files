#!/usr/bin/env bash
# capture-screenshot-pick-dir.sh — zenity directory picker for screenshot output
# Prints an absolute path on stdout, empty if cancelled.
set -euo pipefail

START="${1:-$HOME/Pictures}"
START="${START/#\~/$HOME}"

if ! command -v zenity >/dev/null 2>&1; then
  echo ""
  exit 1
fi

out="$(zenity --file-selection --directory \
  --title="Screenshot folder" \
  --filename="${START%/}/" 2>/dev/null || true)"

if [[ -n "${out:-}" && -d "$out" ]]; then
  readlink -f "$out" 2>/dev/null || echo "$out"
else
  echo ""
fi
