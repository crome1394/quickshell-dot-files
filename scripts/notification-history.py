#!/usr/bin/env python3
"""notification-history.py — persisted notification history for Quickshell.

Watches dbus-monitor for org.freedesktop.Notifications.Notify calls so the
bar can show every notification with expand / copy / dismiss (SwayNC owns
the on-screen daemon; this file is the history panel source of truth).

Persisted at ~/.local/state/quickshell/notification-history.json (survives reboot).

Commands:
  watch           Stream JSON lines as notifications arrive (default).
  list            Print the history array once as JSON and exit.
  clear           Wipe history and print [].
  dismiss <id>    Remove one item by id, print the remaining array, exit.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

MAX_ITEMS = 80
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state")) / "quickshell"
STATE_FILE = STATE_DIR / "notification-history.json"


def load_history() -> list:
    try:
        if STATE_FILE.is_file():
            data = json.loads(STATE_FILE.read_text(encoding="utf-8"))
            if isinstance(data, list):
                return data[-MAX_ITEMS:]
    except Exception:
        pass
    return []


def save_history(items: list) -> None:
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        STATE_FILE.write_text(json.dumps(items[-MAX_ITEMS:], ensure_ascii=False), encoding="utf-8")
    except Exception:
        pass


def emit(obj) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def make_entry(app_name, summary, body, app_icon="", urgency=1) -> dict:
    now = time.time()
    return {
        "id": f"{int(now * 1000)}-{os.getpid()}",
        "ts": int(now),
        "app": str(app_name or "Notification"),
        "summary": str(summary or ""),
        "body": str(body or ""),
        "icon": str(app_icon or ""),
        "urgency": int(urgency) if urgency is not None else 1,
        "expanded": False,
    }


def cmd_list() -> int:
    emit(load_history())
    return 0


def cmd_clear() -> int:
    save_history([])
    emit([])
    return 0


def cmd_dismiss(item_id: str) -> int:
    want = str(item_id or "").strip()
    history = load_history()
    if want:
        history = [x for x in history if str(x.get("id", "")) != want]
        save_history(history)
    emit(history)
    return 0


def unquote_dbus_string(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        s = s[1:-1]
    # dbus-monitor escapes
    s = s.replace('\\"', '"').replace("\\n", "\n").replace("\\t", "\t").replace("\\\\", "\\")
    return s


def parse_notify_block(lines: list[str]) -> dict | None:
    """Parse a dbus-monitor Notify method_call block into an entry."""
    # Expect sequential string args: app, (uint32 skipped), icon, summary, body
    strings: list[str] = []
    urgency = 1
    for ln in lines:
        m = re.match(r'^\s*string\s+"(.*)"\s*$', ln)
        if m:
            # incomplete multi-line strings are rare; dbus-monitor uses single line usually
            strings.append(unquote_dbus_string('"' + m.group(1) + '"'))
            continue
        # multi-line form: string "foo
        m2 = re.match(r'^\s*string\s+(".*)$', ln)
        if m2 and not ln.rstrip().endswith('"'):
            # start of multi-line — join later; skip for simplicity
            strings.append(unquote_dbus_string(m2.group(1) + '"'))
            continue
        if "urgency" in ln:
            # next lines may hold byte N
            pass
        m3 = re.search(r"byte\s+(\d+)", ln)
        if m3 and "urgency" in "\n".join(lines):
            try:
                urgency = int(m3.group(1))
            except Exception:
                pass

    # Notify args: app_name, replaces_id(uint32), app_icon, summary, body, ...
    # After filtering only strings we get [app, icon, summary, body, ...] roughly
    # But replaces_id is uint32 so strings are: app, icon, summary, body (+ maybe more)
    if len(strings) < 3:
        return None
    app = strings[0] if len(strings) > 0 else "Notification"
    icon = strings[1] if len(strings) > 1 else ""
    summary = strings[2] if len(strings) > 2 else ""
    body = strings[3] if len(strings) > 3 else ""
    # If icon looked like a title (empty icon path often ""), still fine
    return make_entry(app, summary, body, icon, urgency)


def cmd_watch() -> int:
    history = load_history()
    emit({"type": "snapshot", "items": history})

    cmd = [
        "dbus-monitor",
        "--session",
        "type='method_call',interface='org.freedesktop.Notifications',member='Notify'",
    ]
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
        )
    except Exception as e:
        emit({"type": "error", "message": f"dbus-monitor failed: {e}"})
        return 1

    block: list[str] = []
    in_notify = False

    def flush_block() -> None:
        nonlocal history, block, in_notify
        if not block:
            in_notify = False
            return
        entry = parse_notify_block(block)
        block = []
        in_notify = False
        if not entry:
            return
        # Skip empty noise
        if not (entry.get("summary") or entry.get("body") or entry.get("app")):
            return
        # Reload so dismiss/clear from the panel is not overwritten by this process.
        history = load_history()
        history.append(entry)
        if len(history) > MAX_ITEMS:
            history = history[-MAX_ITEMS:]
        save_history(history)
        emit({"type": "add", "item": entry, "count": len(history)})

    try:
        assert proc.stdout is not None
        for raw in proc.stdout:
            line = raw.rstrip("\n")
            if "member=Notify" in line and "method call" in line:
                if in_notify:
                    flush_block()
                block = [line]
                in_notify = True
                continue
            if in_notify:
                # Next top-level message ends the previous Notify
                if line.startswith("method ") or line.startswith("signal "):
                    flush_block()
                    if "member=Notify" in line and "method call" in line:
                        block = [line]
                        in_notify = True
                    continue
                block.append(line)
                # Notify ends with expire_timeout int32 at the root arg indent
                if re.match(r"^\s{3}int32\s+", line):
                    flush_block()
                    continue
                if len(block) > 200:
                    flush_block()
        # EOF
        if in_notify:
            flush_block()
    except KeyboardInterrupt:
        if in_notify:
            flush_block()
    finally:
        try:
            proc.terminate()
        except Exception:
            pass
    return 0


def main(argv: list[str]) -> int:
    cmd = (argv[1] if len(argv) > 1 else "watch").strip().lower()
    if cmd in ("list", "--list", "-l"):
        return cmd_list()
    if cmd in ("clear", "--clear"):
        return cmd_clear()
    if cmd in ("dismiss", "--dismiss", "remove", "--remove"):
        if len(argv) < 3:
            print(f"usage: {argv[0]} dismiss <id>", file=sys.stderr)
            return 2
        return cmd_dismiss(argv[2])
    if cmd in ("watch", "--watch", "-w", "listen"):
        return cmd_watch()
    print(f"usage: {argv[0]} [watch|list|clear|dismiss <id>]", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
