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

# Delete only a direct child of the real directory. A symlink there is
# removed as a link. ".." and any path outside the directory are refused.
delete_direct_child() {
  local dir="$1" target="$2" what="$3"
  local real base parent parent_real victim
  real="$(readlink -f -- "$dir" 2>/dev/null || true)"
  if [[ -z "$real" || ! -d "$real" ]]; then
    echo "refusing to delete: cannot resolve $what dir" >&2
    exit 1
  fi
  case "$target" in
    ..|../*|*/..|*/../*)
      echo "refusing to delete outside $what dir: $target" >&2
      exit 1
      ;;
  esac
  if [[ "$target" != */* && ! -e "$target" && ! -L "$target" ]]; then
    base="$(sanitize_name "$target")"
    victim="$real/${base}.json"
  else
    parent="$(dirname -- "$target")"
    base="$(basename -- "$target")"
    case "$base" in
      ""|.|..)
        echo "refusing to delete outside $what dir: $target" >&2
        exit 1
        ;;
    esac
    parent_real="$(readlink -f -- "$parent" 2>/dev/null || true)"
    if [[ -z "$parent_real" || "$parent_real" != "$real" ]]; then
      echo "refusing to delete outside $what dir: $target" >&2
      exit 1
    fi
    victim="$real/$base"
  fi
  if [[ "$(dirname -- "$victim")" != "$real" ]]; then
    echo "refusing to delete outside $what dir: $target" >&2
    exit 1
  fi
  if [[ ! -e "$victim" && ! -L "$victim" ]]; then
    echo "$what not found: $victim" >&2
    exit 1
  fi
  # rm of a symlink removes the link, not the file it names.
  rm -f -- "$victim"
  echo "deleted $victim"
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
    delete_direct_child "$PROFILES_DIR" "$target" "setup"
    ;;
  *)
    echo "usage: profile-io.sh list|export <name>|import <name-or-path>|delete <name-or-path>" >&2
    exit 1
    ;;
esac
