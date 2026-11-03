#!/usr/bin/env bash
# wallpaper-list-json.sh — list images in a directory as JSON for SettingsPanel
# Usage: wallpaper-list-json.sh [directory]
set -euo pipefail

DIR="${1:-$HOME/Pictures/wallpapers}"
DIR="${DIR/#\~/$HOME}"

python3 - "$DIR" <<'PY'
import json, os, sys
from pathlib import Path

root = Path(sys.argv[1]).expanduser()
exts = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".jxl"}

def dims(path: Path):
    w = h = 0
    try:
        from PIL import Image
        with Image.open(path) as im:
            w, h = im.size
            return w, h
    except Exception:
        pass
    # Fallback: identify(1)
    try:
        import subprocess
        out = subprocess.check_output(
            ["identify", "-format", "%w %h", str(path)],
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=5,
        ).strip()
        parts = out.split()
        if len(parts) >= 2:
            return int(parts[0]), int(parts[1])
    except Exception:
        pass
    return 0, 0

items = []
if root.is_dir():
    files = [p for p in root.iterdir() if p.is_file() and p.suffix.lower() in exts]
    files.sort(key=lambda p: p.name.lower())
    for p in files:
        w, h = dims(p)
        try:
            size = p.stat().st_size
        except OSError:
            size = 0
        items.append({
            "path": str(p.resolve()),
            "name": p.name,
            "width": w,
            "height": h,
            "size": size,
            "url": "file://" + str(p.resolve()),
        })

print(json.dumps({
    "dir": str(root.resolve()) if root.exists() else str(root),
    "count": len(items),
    "images": items,
}, ensure_ascii=False))
PY
