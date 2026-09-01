#!/usr/bin/env bash
# timezone-control.sh — list / status / set the system timezone for the Clock panel
#
# Usage:
#   timezone-control.sh status-json
#   timezone-control.sh list-json
#   timezone-control.sh land-json
#   timezone-control.sh preview <Area/City>
#   timezone-control.sh set <Area/City>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

python3 - "$ROOT_DIR" "$@" <<'PY'
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(sys.argv[1])
ZONE_TAB = Path("/usr/share/zoneinfo/zone1970.tab")
ZONEINFO = Path("/usr/share/zoneinfo")
LAND_FILE = ROOT / "assets" / "world-land.json"
TZ_RE = re.compile(r"^[A-Za-z0-9/_+\-]+$")
COORD_RE = re.compile(
    r"^([+-])(\d{2})(\d{2})(\d{2})?([+-])(\d{3})(\d{2})(\d{2})?$"
)


def emit(obj) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def die(msg: str, code: int = 1) -> None:
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(code)


def parse_iso6709(s: str) -> tuple[float, float] | None:
    m = COORD_RE.match(s.strip())
    if not m:
        return None
    slat, dlat, mlat, slatsec, slon, dlon, mlon, slonsec = m.groups()

    def dms(sign: str, deg: str, minutes: str, seconds: str | None) -> float:
        val = int(deg) + int(minutes) / 60.0
        if seconds:
            val += int(seconds) / 3600.0
        return val if sign == "+" else -val

    return dms(slat, dlat, mlat, slatsec), dms(slon, dlon, mlon, slonsec)


def pretty_city(tz_id: str) -> str:
    city = tz_id.split("/")[-1].replace("_", " ")
    return city


def pretty_region(tz_id: str) -> str:
    parts = tz_id.split("/")
    if len(parts) >= 2:
        return parts[0].replace("_", " ")
    return "Other"


def load_zones() -> list[dict]:
    rows: list[dict] = []
    if not ZONE_TAB.is_file():
        return rows
    text = ZONE_TAB.read_text(encoding="utf-8", errors="replace")
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        cols = line.split("\t")
        if len(cols) < 3:
            continue
        coords = parse_iso6709(cols[1])
        if not coords:
            continue
        tz_id = cols[2].strip()
        if not tz_id:
            continue
        comment = cols[3].strip() if len(cols) > 3 else ""
        lat, lon = coords
        rows.append(
            {
                "id": tz_id,
                "region": pretty_region(tz_id),
                "city": pretty_city(tz_id),
                "comment": comment,
                "lat": round(lat, 4),
                "lon": round(lon, 4),
                "countries": [c for c in cols[0].split(",") if c],
            }
        )
    rows.sort(key=lambda z: (z["region"], z["city"], z["id"]))
    return rows


def valid_zone(tz_id: str) -> bool:
    if not TZ_RE.match(tz_id):
        return False
    path = ZONEINFO / tz_id
    return path.is_file() or path.is_dir()


def current_timezone() -> str:
    try:
        out = subprocess.check_output(
            ["timedatectl", "show", "-p", "Timezone", "--value"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        if out:
            return out
    except Exception:
        pass
    try:
        link = Path("/etc/localtime")
        if link.is_symlink():
            resolved = os.path.realpath(link)
            marker = "/zoneinfo/"
            i = resolved.find(marker)
            if i >= 0:
                return resolved[i + len(marker) :]
    except Exception:
        pass
    return time.tzname[0] if time.tzname else ""


def preview_zone(tz_id: str) -> dict:
    env = os.environ.copy()
    env["TZ"] = tz_id
    local = time.strftime("%a %Y-%m-%d %H:%M", time.localtime())
    # Use the target zone for display
    old = os.environ.get("TZ")
    os.environ["TZ"] = tz_id
    time.tzset()
    try:
        now = time.localtime()
        local = time.strftime("%a %H:%M", now)
        abbr = time.strftime("%Z", now)
        off = time.strftime("%z", now)
    finally:
        if old is None:
            os.environ.pop("TZ", None)
        else:
            os.environ["TZ"] = old
        time.tzset()
    hours = 0.0
    try:
        sign = 1 if off[0] != "-" else -1
        hours = sign * (int(off[1:3]) + int(off[3:5]) / 60.0)
    except Exception:
        pass
    return {
        "timezone": tz_id,
        "local": local,
        "abbr": abbr,
        "offset": off,
        "offsetHours": hours,
    }


def cmd_status() -> int:
    tz = current_timezone()
    info = preview_zone(tz) if tz else {
        "timezone": "",
        "local": "",
        "abbr": "",
        "offset": "",
        "offsetHours": 0,
    }
    emit(info)
    return 0


def cmd_list() -> int:
    emit(load_zones())
    return 0


def cmd_land() -> int:
    if not LAND_FILE.is_file():
        emit({"projection": "equirectangular", "rings": []})
        return 0
    try:
        data = json.loads(LAND_FILE.read_text(encoding="utf-8"))
    except Exception as e:
        die(f"land map: {e}")
    emit(data)
    return 0


def cmd_preview(tz_id: str) -> int:
    if not valid_zone(tz_id):
        die(f"unknown timezone: {tz_id}")
    emit(preview_zone(tz_id))
    return 0


def run_set(tz_id: str) -> subprocess.CompletedProcess:
    # Prefer the session call; polkit may prompt via pkexec if needed.
    r = subprocess.run(
        ["timedatectl", "set-timezone", tz_id],
        text=True,
        capture_output=True,
    )
    if r.returncode == 0:
        return r
    if os.environ.get("QS_TZ_NO_PKEXEC") == "1":
        return r
    pk = subprocess.run(
        ["pkexec", "timedatectl", "set-timezone", tz_id],
        text=True,
        capture_output=True,
    )
    return pk


def cmd_set(tz_id: str) -> int:
    if not valid_zone(tz_id):
        die(f"unknown timezone: {tz_id}")
    r = run_set(tz_id)
    if r.returncode != 0:
        err = (r.stderr or r.stdout or "set-timezone failed").strip()
        die(err.splitlines()[-1][:200], r.returncode)
    emit(preview_zone(tz_id))
    return 0


def main(argv: list[str]) -> int:
    cmd = (argv[2] if len(argv) > 2 else "status-json").strip().lower()
    if cmd in ("status", "status-json"):
        return cmd_status()
    if cmd in ("list", "list-json"):
        return cmd_list()
    if cmd in ("land", "land-json"):
        return cmd_land()
    if cmd in ("preview",):
        if len(argv) < 4:
            die("usage: timezone-control.sh preview <Area/City>")
        return cmd_preview(argv[3])
    if cmd in ("set", "set-timezone"):
        if len(argv) < 4:
            die("usage: timezone-control.sh set <Area/City>")
        return cmd_set(argv[3])
    print(
        f"usage: {Path(argv[0]).name} [status-json|list-json|land-json|preview <tz>|set <tz>]",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY
