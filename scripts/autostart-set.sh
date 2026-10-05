#!/usr/bin/env bash
# autostart-set.sh — enable|disable|remove|exec an XDG autostart entry
# Usage:
#   autostart-set.sh enable  Flameshot.desktop
#   autostart-set.sh disable Flameshot.desktop
#   autostart-set.sh remove  Flameshot.desktop
#   autostart-set.sh exec    Flameshot.desktop "/usr/bin/app --flag"
# exec rewrites Exec= inside [Desktop Entry] and leaves every other key alone.
set -euo pipefail

ACTION="${1:-}"
ID="${2:-}"
EXEC_VALUE="${3:-}"
DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"

if [[ -z "$ACTION" || -z "$ID" ]]; then
  echo "usage: $0 enable|disable|remove <file.desktop>" >&2
  echo "       $0 exec <file.desktop> \"command\"" >&2
  exit 1
fi

# Safety: only touch basename inside autostart dir
ID="$(basename "$ID")"
[[ "$ID" == *.desktop ]] || ID="${ID}.desktop"
PATH_FILE="$DIR/$ID"

if [[ ! -f "$PATH_FILE" ]]; then
  echo "error: not found: $PATH_FILE" >&2
  exit 1
fi

# Resolve real path and ensure still under autostart
REAL="$(readlink -f "$PATH_FILE" 2>/dev/null || echo "$PATH_FILE")"
case "$REAL" in
  "$DIR"/*|"$HOME/.config/autostart"/*) ;;
  *)
    echo "error: refusing to touch file outside autostart: $REAL" >&2
    exit 1
    ;;
esac

python3 - "$ACTION" "$REAL" "$EXEC_VALUE" <<'PY'
import sys
from pathlib import Path

action, path = sys.argv[1], Path(sys.argv[2])
exec_value = sys.argv[3] if len(sys.argv) > 3 else ""
text = path.read_text(errors="replace")
lines = text.splitlines(keepends=True)

def set_keys(content: str, pairs: dict) -> str:
    lines = content.splitlines(keepends=True)
    if not lines:
        lines = ["[Desktop Entry]\n"]
    # Ensure Desktop Entry section
    has_entry = any(l.strip() == "[Desktop Entry]" for l in lines)
    if not has_entry:
        lines.insert(0, "[Desktop Entry]\n")

    found = {k: False for k in pairs}
    out = []
    in_entry = False
    for line in lines:
        s = line.strip()
        if s.startswith("["):
            # When leaving Desktop Entry, inject missing keys
            if in_entry:
                for k, v in pairs.items():
                    if not found[k]:
                        out.append(f"{k}={v}\n")
                        found[k] = True
            in_entry = s == "[Desktop Entry]"
            out.append(line)
            continue
        if in_entry and s and not s.startswith("#") and "=" in s:
            k = s.split("=", 1)[0].strip()
            if k in pairs:
                out.append(f"{k}={pairs[k]}\n")
                found[k] = True
                continue
        out.append(line)
    if in_entry:
        for k, v in pairs.items():
            if not found[k]:
                out.append(f"{k}={v}\n")
    return "".join(out)

if action == "remove":
    path.unlink()
    print(f"ok removed {path.name}")
elif action == "enable":
    path.write_text(set_keys(text, {
        "Hidden": "false",
        "X-GNOME-Autostart-enabled": "true",
    }))
    print(f"ok enabled {path.name}")
elif action == "disable":
    path.write_text(set_keys(text, {
        "Hidden": "true",
        "X-GNOME-Autostart-enabled": "false",
    }))
    print(f"ok disabled {path.name}")
elif action == "exec":
    cmd = exec_value.strip()
    if not cmd or "\n" in exec_value or "\r" in exec_value:
        print("error: exec must be a single non-empty line", file=sys.stderr)
        sys.exit(1)
    path.write_text(set_keys(text, {"Exec": cmd}))
    print(f"ok exec {path.name}")
else:
    print(f"error: unknown action {action}", file=sys.stderr)
    sys.exit(1)
PY
