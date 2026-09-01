#!/usr/bin/env bash
# wallpaper-rename.sh — rename a wallpaper file inside the wallpaper directory
# Usage: wallpaper-rename.sh <directory> <old-basename> <new-basename>
# Prints JSON: { "ok": true, "from": "...", "to": "...", "path": "...", "name": "..." }
set -euo pipefail

DIR="${1:-}"
OLD_NAME="${2:-}"
NEW_NAME="${3:-}"

if [[ -z "$DIR" || -z "$OLD_NAME" || -z "$NEW_NAME" ]]; then
  echo '{"ok":false,"error":"usage: wallpaper-rename.sh <dir> <old-name> <new-name>"}'
  exit 1
fi

python3 - "$DIR" "$OLD_NAME" "$NEW_NAME" <<'PY'
import json, sys
from pathlib import Path

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".jxl"}

def fail(msg, code=1):
    print(json.dumps({"ok": False, "error": msg}, ensure_ascii=False))
    sys.exit(code)

dir_arg, old_name, new_name = sys.argv[1], sys.argv[2], sys.argv[3]
root = Path(dir_arg).expanduser().resolve()
if not root.is_dir():
    fail("directory not found")

old_base = Path(old_name).name
new_base = Path(new_name).name
if not old_base or old_base in (".", "..") or old_base != old_name.replace("\\", "/").split("/")[-1]:
    fail("invalid original name")
if not new_base or new_base in (".", "..") or "/" in new_name or "\\" in new_name:
    fail("invalid new name")
if new_base.startswith("."):
    fail("name cannot start with a dot")

src = (root / old_base).resolve()
if src.parent != root or not src.is_file():
    fail("file not found in wallpaper folder")
if src.suffix.lower() not in IMAGE_EXTS:
    fail("not an image file")

if not Path(new_base).suffix:
    new_base = new_base + src.suffix

dest = (root / new_base).resolve()
if dest.parent != root:
    fail("invalid new name")
if dest.suffix.lower() not in IMAGE_EXTS:
    fail("new name must keep an image extension")
if dest == src:
    print(json.dumps({
        "ok": True,
        "from": str(src),
        "to": str(dest),
        "path": str(dest),
        "name": dest.name,
        "unchanged": True,
    }, ensure_ascii=False))
    sys.exit(0)
if dest.exists():
    fail("a file with that name already exists")

src.rename(dest)
print(json.dumps({
    "ok": True,
    "from": str(src),
    "to": str(dest),
    "path": str(dest),
    "name": dest.name,
}, ensure_ascii=False))
PY
