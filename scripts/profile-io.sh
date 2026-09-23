#!/usr/bin/env bash
# profile-io.sh — save / load full bar setups (theme colors + layout)
# Usage:
#   profile-io.sh list
#   profile-io.sh export <name>
#   profile-io.sh import <name-or-path>
#   profile-io.sh delete <name-or-path>
set -euo pipefail

QS_ROOT="${QUICKSHELL_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/quickshell}"
PROFILES_DIR="${QS_PROFILES_DIR:-$QS_ROOT/profiles}"
STATE_DIR="${QS_STATE_DIR:-$QS_ROOT/state}"
mkdir -p "$PROFILES_DIR"

sanitize_name() {
  local n="${1:-}"
  n="$(echo "$n" | tr -cd 'A-Za-z0-9._ -' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  n="${n// /_}"
  if [[ -z "$n" ]]; then
    n="setup"
  fi
  echo "$n"
}

cmd="${1:-}"
case "$cmd" in
  list)
    python3 - "$PROFILES_DIR" <<'PY'
import json, os, sys
d = sys.argv[1]
out = []
if os.path.isdir(d):
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".json"):
            continue
        path = os.path.join(d, fn)
        name = fn[:-5]
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict) and data.get("name"):
                name = str(data["name"])
        except Exception:
            pass
        out.append({"id": fn[:-5], "name": name, "path": path})
print(json.dumps(out))
PY
    ;;
  export)
    raw_name="${2:-setup}"
    name="$(sanitize_name "$raw_name")"
    dest="$PROFILES_DIR/${name}.json"
    python3 - "$dest" "$raw_name" "$STATE_DIR/theme-colors.json" "$STATE_DIR/bar-layout.json" <<'PY'
import json, os, sys
dest, raw_name, theme_path, layout_path = sys.argv[1:5]
theme = {}
if os.path.isfile(theme_path):
    with open(theme_path, "r", encoding="utf-8") as f:
        wrap = json.load(f)
    if isinstance(wrap, dict) and wrap.get("themeJson"):
        try:
            theme = json.loads(wrap["themeJson"])
        except Exception:
            theme = wrap
    elif isinstance(wrap, dict) and "colors" in wrap:
        theme = wrap
layout = {}
if os.path.isfile(layout_path):
    with open(layout_path, "r", encoding="utf-8") as f:
        layout = json.load(f)
if not isinstance(theme, dict):
    theme = {}
if not isinstance(layout, dict):
    layout = {}
data = {
    "name": raw_name,
    "version": 1,
    "kind": "setup",
    "theme": theme,
    "layout": layout,
}
os.makedirs(os.path.dirname(dest), exist_ok=True)
with open(dest, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(dest)
PY
    ;;
  import)
    target="${2:-}"
    if [[ -z "$target" ]]; then
      echo "usage: profile-io.sh import <name-or-path>" >&2
      exit 1
    fi
    if [[ -f "$target" ]]; then
      path="$target"
    else
      name="$(sanitize_name "$target")"
      path="$PROFILES_DIR/${name}.json"
    fi
    if [[ ! -f "$path" ]]; then
      echo "setup not found: $path" >&2
      exit 1
    fi
    cat "$path"
    ;;
  delete)
    target="${2:-}"
    if [[ -z "$target" ]]; then
      echo "usage: profile-io.sh delete <name-or-path>" >&2
      exit 1
    fi
    if [[ -f "$target" ]]; then
      path="$target"
    else
      name="$(sanitize_name "$target")"
      path="$PROFILES_DIR/${name}.json"
    fi
    case "$path" in
      "$PROFILES_DIR"/*) ;;
      *)
        echo "refusing to delete outside profiles dir: $path" >&2
        exit 1
        ;;
    esac
    if [[ ! -f "$path" ]]; then
      echo "setup not found: $path" >&2
      exit 1
    fi
    rm -f -- "$path"
    echo "deleted $path"
    ;;
  *)
    echo "usage: profile-io.sh list|export <name>|import <name-or-path>|delete <name-or-path>" >&2
    exit 1
    ;;
esac
