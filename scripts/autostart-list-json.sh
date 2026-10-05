#!/usr/bin/env bash
# autostart-list-json.sh — list ~/.config/autostart entries as JSON
set -euo pipefail

DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
mkdir -p "$DIR"

python3 - "$DIR" <<'PY'
import json, os, re, sys
from pathlib import Path

root = Path(sys.argv[1]).expanduser()
icon_roots = [
    Path.home() / ".local/share/icons",
    Path("/usr/share/icons"),
    Path("/usr/share/pixmaps"),
]

def resolve_icon(name: str) -> str:
    if not name:
        return ""
    p = Path(name)
    if p.is_file():
        return str(p)
    if name.startswith("/") and p.suffix:
        return name
    for base in icon_roots:
        if not base.is_dir():
            continue
        if base.name == "pixmaps":
            for ext in (".svg", ".png", ".xpm"):
                f = base / f"{name}{ext}"
                if f.is_file():
                    return str(f)
            continue
        for pattern in (f"**/apps/{name}.svg", f"**/apps/{name}.png", f"**/{name}.svg", f"**/{name}.png"):
            for hit in base.glob(pattern):
                if hit.is_file():
                    return str(hit)
    return ""

def parse_desktop(path: Path):
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return None
    data = {}
    in_entry = False
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("["):
            in_entry = s == "[Desktop Entry]"
            continue
        if not in_entry or not s or s.startswith("#") or "=" not in s:
            continue
        k, v = s.split("=", 1)
        data.setdefault(k.strip(), v.strip())
    if data.get("Type", "Application") not in ("Application", ""):
        return None
    name = data.get("Name") or path.stem
    exec_line = data.get("Exec") or ""
    exec_clean = re.sub(r"\s+%[a-zA-Z@]", "", exec_line).strip()
    icon = data.get("Icon") or ""
    hidden = data.get("Hidden", "").lower() in ("true", "1")
    # X-GNOME-Autostart-enabled=false means disabled even if present
    gnome_en = data.get("X-GNOME-Autostart-enabled", "true").lower()
    enabled = (not hidden) and gnome_en not in ("false", "0", "no")
    return {
        "id": path.name,
        "name": name,
        "exec": exec_clean,
        "execRaw": exec_line,
        "iconName": icon,
        "icon": resolve_icon(icon),
        "enabled": enabled,
        "hidden": hidden,
        "path": str(path.resolve()),
        "delay": int(data.get("X-GNOME-Autostart-Delay") or 0) if str(data.get("X-GNOME-Autostart-Delay") or "").isdigit() else 0,
    }

entries = []
if root.is_dir():
    for p in sorted(root.glob("*.desktop"), key=lambda x: x.name.lower()):
        e = parse_desktop(p)
        if e:
            entries.append(e)

print(json.dumps({"dir": str(root.resolve()), "count": len(entries), "entries": entries}, ensure_ascii=False))
PY
