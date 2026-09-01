#!/usr/bin/env bash
# wallpaper-delete.sh — delete a wallpaper file inside the wallpaper directory
# Usage: wallpaper-delete.sh <directory> <basename>
# Prints JSON: { "ok": true, "path": "...", "name": "...", "deleted": true }
set -euo pipefail

DIR="${1:-}"
NAME="${2:-}"

if [[ -z "$DIR" || -z "$NAME" ]]; then
  echo '{"ok":false,"error":"usage: wallpaper-delete.sh <dir> <name>"}'
  exit 1
fi

python3 - "$DIR" "$NAME" <<'PY'
import json, sys
from pathlib import Path

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".jxl"}

def fail(msg, code=1):
    print(json.dumps({"ok": False, "error": msg}, ensure_ascii=False))
    sys.exit(code)

dir_arg, name = sys.argv[1], sys.argv[2]
root = Path(dir_arg).expanduser().resolve()
if not root.is_dir():
    fail("directory not found")

base = Path(name).name
if not base or base in (".", "..") or "/" in name or "\\" in name:
    fail("invalid name")

src = (root / base).resolve()
if src.parent != root or not src.is_file():
    fail("file not found in wallpaper folder")
if src.suffix.lower() not in IMAGE_EXTS:
    fail("not an image file")

src.unlink()
print(json.dumps({
    "ok": True,
    "path": str(src),
    "name": src.name,
    "deleted": True,
}, ensure_ascii=False))
PY
