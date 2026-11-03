#!/usr/bin/env bash
# Manual helper. The bar does not call this.
# Resolve the topmost Hyprland client at global layout coordinates.
# Usage: window-at-point.sh <global_x> <global_y> [exclude_pid]
# Emits one JSON line: {pid,class,title,address} or {error:...}

set -euo pipefail

GLOBAL_X="${1:-}"
GLOBAL_Y="${2:-}"
EXCLUDE_PID="${3:-0}"

if [[ -z "$GLOBAL_X" || -z "$GLOBAL_Y" || ! "$GLOBAL_X" =~ ^-?[0-9]+$ || ! "$GLOBAL_Y" =~ ^-?[0-9]+$ ]]; then
    printf '{"error":"usage"}\n'
    exit 2
fi

if ! command -v hyprctl >/dev/null 2>&1; then
    printf '{"error":"hyprctl_missing"}\n'
    exit 3
fi

CLIENTS_JSON="$(hyprctl clients -j 2>/dev/null || echo '[]')"

python3 -c '
import json
import sys

x = int(sys.argv[1])
y = int(sys.argv[2])
exclude_pid = int(sys.argv[3]) if sys.argv[3] else 0
clients = json.loads(sys.argv[4])

hits = []
for client in clients:
    if not client.get("mapped") or not client.get("visible"):
        continue
    pid = int(client.get("pid") or 0)
    if exclude_pid and pid == exclude_pid:
        continue
    at = client.get("at") or [0, 0]
    size = client.get("size") or [0, 0]
    ax, ay = int(at[0]), int(at[1])
    w, h = int(size[0]), int(size[1])
    if ax <= x < ax + w and ay <= y < ay + h:
        hits.append((int(client.get("focusHistoryID") or 0), client))

if not hits:
    print(json.dumps({"error": "no_window"}))
    sys.exit(0)

hits.sort(key=lambda item: item[0], reverse=True)
winner = hits[0][1]
print(json.dumps({
    "pid": int(winner.get("pid") or 0),
    "class": winner.get("class") or "",
    "title": winner.get("title") or "",
    "address": winner.get("address") or "",
}))
' "$GLOBAL_X" "$GLOBAL_Y" "$EXCLUDE_PID" "$CLIENTS_JSON"