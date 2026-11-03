#!/usr/bin/env bash
# theme-io.sh — list / export / import / delete bar color themes (JSON)
# Usage:
#   theme-io.sh list
#   theme-io.sh export <name>          # JSON on stdin → themes/<name>.json
#   theme-io.sh import <name-or-path>  # print theme JSON to stdout
#   theme-io.sh delete <name-or-path>  # remove a user-saved theme file
#   theme-io.sh path <name>            # print absolute path for a named theme
set -euo pipefail

QS_ROOT="${QUICKSHELL_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/quickshell}"
THEMES_DIR="${QS_THEMES_DIR:-$QS_ROOT/themes}"
mkdir -p "$THEMES_DIR"

sanitize_name() {
  local n="${1:-}"
  n="$(echo "$n" | tr -cd 'A-Za-z0-9._ -' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  n="${n// /_}"
  if [[ -z "$n" ]]; then
    n="theme"
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
    python3 - "$THEMES_DIR" <<'PY'
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
    raw_name="${2:-theme}"
    name="$(sanitize_name "$raw_name")"
    dest="$THEMES_DIR/${name}.json"
    body="$(cat)"
    if [[ -z "${body//[[:space:]]/}" ]]; then
      echo "empty theme JSON" >&2
      exit 1
    fi
    printf '%s' "$body" | python3 -c '
import json, sys
dest = sys.argv[1]
raw_name = sys.argv[2]
body = sys.stdin.read()
try:
    data = json.loads(body)
except Exception as e:
    print("invalid json: %s" % e, file=sys.stderr)
    sys.exit(1)
if not isinstance(data, dict):
    print("theme root must be an object", file=sys.stderr)
    sys.exit(1)
if not data.get("name"):
    data["name"] = raw_name
data["version"] = int(data.get("version") or 1)
if "colors" not in data or not isinstance(data.get("colors"), dict):
    print("theme missing colors object", file=sys.stderr)
    sys.exit(1)
with open(dest, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(dest)
' "$dest" "$raw_name"
    ;;
  import)
    target="${2:-}"
    if [[ -z "$target" ]]; then
      echo "usage: theme-io.sh import <name-or-path>" >&2
      exit 1
    fi
    if [[ -f "$target" ]]; then
      path="$target"
    else
      name="$(sanitize_name "$target")"
      path="$THEMES_DIR/${name}.json"
    fi
    if [[ ! -f "$path" ]]; then
      echo "theme not found: $path" >&2
      exit 1
    fi
    cat "$path"
    ;;
  delete)
    target="${2:-}"
    if [[ -z "$target" ]]; then
      echo "usage: theme-io.sh delete <name-or-path>" >&2
      exit 1
    fi
    delete_direct_child "$THEMES_DIR" "$target" "theme"
    ;;
  path)
    name="$(sanitize_name "${2:-theme}")"
    echo "$THEMES_DIR/${name}.json"
    ;;
  *)
    echo "usage: theme-io.sh list|export <name>|import <name-or-path>|delete <name-or-path>|path <name>" >&2
    exit 1
    ;;
esac
