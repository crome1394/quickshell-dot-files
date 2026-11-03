#!/usr/bin/env python3
"""Point SwayNC toasts at a screen corner and set how long they stay.

Usage: swaync-corner.py topLeft|topRight|bottomLeft|bottomRight [SECONDS]

Writes positionX and positionY in ~/.config/swaync/config.json. When SECONDS
is given, it also writes the normal-priority "timeout" (0 keeps a toast up
until it is closed). Reloads SwayNC only when a value changes. A bottom
corner stacks new toasts upward. A top corner stacks them downward. The
control center follows the same position because its own position keys are
left unset.
"""

import re
import subprocess
import sys
from pathlib import Path

CORNERS = {
    "topLeft": ("left", "top"),
    "topRight": ("right", "top"),
    "bottomLeft": ("left", "bottom"),
    "bottomRight": ("right", "bottom"),
}


def replace_value(text, key, value):
    pattern = re.compile(rf'("{re.escape(key)}"\s*:\s*")([^"]*)(")')
    match = pattern.search(text)
    if not match:
        raise SystemExit(f"{key} not found in swaync config")
    if match.group(2) == value:
        return text, False
    start, end = match.span(2)
    return text[:start] + value + text[end:], True


def replace_int(text, key, value):
    # Match the exact key so "timeout" does not change "timeout-low".
    pattern = re.compile(rf'("{re.escape(key)}"\s*:\s*)(-?\d+)')
    match = pattern.search(text)
    if not match:
        raise SystemExit(f"{key} not found in swaync config")
    if match.group(2) == str(value):
        return text, False
    start, end = match.span(2)
    return text[:start] + str(value) + text[end:], True


def main():
    corner = sys.argv[1] if len(sys.argv) > 1 else ""
    if corner not in CORNERS:
        names = ", ".join(CORNERS)
        raise SystemExit(f"usage: swaync-corner.py {names} [SECONDS]")

    timeout = None
    if len(sys.argv) > 2:
        try:
            timeout = int(sys.argv[2])
        except ValueError:
            raise SystemExit("timeout must be a whole number of seconds")
        if timeout < 0 or timeout > 60:
            raise SystemExit("timeout must be from 0 to 60")

    position_x, position_y = CORNERS[corner]
    path = Path.home() / ".config" / "swaync" / "config.json"
    text = path.read_text()
    text, changed_x = replace_value(text, "positionX", position_x)
    text, changed_y = replace_value(text, "positionY", position_y)
    changed_t = False
    if timeout is not None:
        text, changed_t = replace_int(text, "timeout", timeout)
    if not changed_x and not changed_y and not changed_t:
        return 0

    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(text)
    tmp.replace(path)

    subprocess.run(["swaync-client", "-R", "-sw"], check=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
