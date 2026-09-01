#!/usr/bin/env bash
# wallpaper-add.sh — copy image files into the wallpaper directory
# Usage:
#   wallpaper-add.sh [target-directory]                 # zenity file picker
#   wallpaper-add.sh [target-directory] <file-or-dir…>  # copy given files (dirs: top-level images)
# Prints JSON: { "dir": "...", "added": ["path", ...], "count": N, "skipped": N }
set -euo pipefail

DIR="${1:-$HOME/Pictures/wallpapers}"
DIR="${DIR/#\~/$HOME}"
shift || true
mkdir -p "$DIR"

python3 - "$DIR" "$@" <<'PY'
import json, os, shutil, subprocess, sys
from pathlib import Path

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".jxl"}

dest_dir = Path(sys.argv[1]).expanduser()
dest_dir.mkdir(parents=True, exist_ok=True)
given = [Path(a) for a in sys.argv[2:] if a]

def unique_dest(directory: Path, name: str) -> Path:
    dest = directory / name
    if not dest.exists():
        return dest
    stem, ext = Path(name).stem, Path(name).suffix
    n = 2
    while True:
        cand = directory / f"{stem}-{n}{ext}"
        if not cand.exists():
            return cand
        n += 1

def collect(paths):
    out = []
    seen = set()
    for p in paths:
        try:
            p = p.expanduser()
        except Exception:
            continue
        if p.is_file():
            if p.suffix.lower() in IMAGE_EXTS:
                rp = str(p.resolve()) if p.exists() else str(p)
                if rp not in seen:
                    seen.add(rp)
                    out.append(p)
        elif p.is_dir():
            try:
                kids = sorted(p.iterdir(), key=lambda x: x.name.lower())
            except OSError:
                continue
            for kid in kids:
                if kid.is_file() and kid.suffix.lower() in IMAGE_EXTS:
                    rp = str(kid.resolve()) if kid.exists() else str(kid)
                    if rp not in seen:
                        seen.add(rp)
                        out.append(kid)
    return out

sources = list(given)
if not sources:
    if not shutil.which("zenity"):
        print(json.dumps({"error": "zenity not found", "dir": str(dest_dir.resolve()), "added": [], "count": 0, "skipped": 0}, ensure_ascii=False))
        sys.exit(1)
    try:
        proc = subprocess.run(
            [
                "zenity", "--file-selection", "--multiple", f"--separator=\n",
                "--title=Add wallpapers",
                "--file-filter=Images | *.jpg *.jpeg *.png *.webp *.gif *.bmp *.jxl *.JPG *.JPEG *.PNG *.WEBP",
                "--file-filter=All files | *",
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        picked = [ln.strip() for ln in (proc.stdout or "").splitlines() if ln.strip()]
        sources = [Path(p) for p in picked]
    except Exception:
        sources = []

files = collect(sources)
added = []
skipped = 0
for src in files:
    if not src.is_file():
        skipped += 1
        continue
    dest = unique_dest(dest_dir, src.name)
    try:
        shutil.copy2(src, dest)
        added.append(str(dest.resolve()))
    except OSError:
        skipped += 1

print(json.dumps({
    "dir": str(dest_dir.resolve()),
    "added": added,
    "count": len(added),
    "skipped": skipped,
}, ensure_ascii=False))
PY
