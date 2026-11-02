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
BOOT_ID_FILE = STATE_DIR / "notification-boot-id"
KERNEL_BOOT_ID = Path("/proc/sys/kernel/random/boot_id")
LAYOUT_FILE = Path.home() / ".config/quickshell/state/bar-layout.json"


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


def make_entry(app_name, summary, body, app_icon="", urgency=1, image="") -> dict:
    now = time.time()
    return {
        "id": f"{int(now * 1000)}-{os.getpid()}",
        "ts": int(now),
        "app": str(app_name or "Notification"),
        "summary": str(summary or ""),
        "body": str(body or ""),
        "icon": str(app_icon or ""),
        "image": str(image or ""),
        "urgency": int(urgency) if urgency is not None else 1,
        "expanded": False,
    }


def cmd_list() -> int:
    emit(prepare_history(load_history()))
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


_IMAGE_SUFFIXES = (".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp")
_IMAGE_KEYS = {"image-path", "image_path"}


def _dbus_string(raw_inside: str) -> str:
    return unquote_dbus_string('"' + raw_inside + '"')


def _unescape_dbus(raw: str) -> str:
    # Same order as unquote_dbus_string. Do not strip: a body can start or end
    # with a newline that dbus-monitor printed as a real line break.
    return (
        raw.replace('\\"', '"')
        .replace("\\n", "\n")
        .replace("\\t", "\t")
        .replace("\\\\", "\\")
    )


# dbus-monitor prints a string as: string "<bytes>"
# A real newline in the value is a real line break. Quotes inside the value
# are not escaped. The closing quote is the last character, and the next line
# is the next typed value (array, int32, string, ...).
_DBUS_VALUE = re.compile(
    r"^\s*(?:string |array |dict |variant |uint\d+ |int\d+ |byte |boolean |"
    r"double |objpath |signature |\]|\)|method |signal )"
)


def dbus_strings(lines: list[str]) -> tuple[list[tuple[int, str]], bool]:
    """Top-to-bottom strings in a dbus-monitor block.

    A string may span lines. The bool is true when the block ends inside one.
    """
    found: list[tuple[int, str]] = []
    i = 0
    open_string = False
    while i < len(lines):
        match = re.match(r'^(\s*)string "(.*)$', lines[i])
        if not match:
            i += 1
            continue
        indent = len(match.group(1))
        chunk = match.group(2)
        i += 1
        while True:
            nxt = lines[i] if i < len(lines) else ""
            if chunk.endswith('"') and (i >= len(lines) or _DBUS_VALUE.match(nxt)):
                chunk = chunk[:-1]
                found.append((indent, _unescape_dbus(chunk)))
                break
            if i >= len(lines) or nxt.startswith("method ") or nxt.startswith("signal "):
                found.append((indent, _unescape_dbus(chunk)))
                open_string = True
                break
            chunk += "\n" + nxt
            i += 1
        if open_string:
            break
    return found, open_string


def _clean_image_path(value: str) -> str:
    path = str(value or "").strip()
    if path.startswith("file://"):
        path = path[7:]
    return path


def _is_local_image(value: str) -> bool:
    path = _clean_image_path(value).lower().split("?", 1)[0]
    return path.startswith("/") and path.endswith(_IMAGE_SUFFIXES)


_BODY_PATH = re.compile(
    r"(/[^\s'\"<>]+?\.(?:png|jpg|jpeg|webp|gif|bmp))",
    re.IGNORECASE,
)
_NAME_STAMP = re.compile(r"screenshot-(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})-(\d{2})")
_SHOT_CACHE: dict = {"at": 0.0, "files": []}


def _existing_image(value: str) -> str:
    path = _clean_image_path(value)
    if _is_local_image(path) and Path(path).is_file():
        return path
    return ""


def _screenshot_dirs() -> list[Path]:
    found: list[Path] = []
    seen: set[str] = set()
    candidates: list[Path] = []
    for key in ("SCREENSHOT_DIR", "OMARCHY_SCREENSHOT_DIR"):
        raw = os.environ.get(key, "").strip()
        if raw:
            candidates.append(Path(raw))
    layout = Path.home() / ".config" / "quickshell" / "state" / "bar-layout.json"
    try:
        if layout.is_file():
            data = json.loads(layout.read_text(encoding="utf-8"))
            raw = str(data.get("screenshotDir") or "").strip()
            if raw:
                candidates.append(Path(raw))
    except Exception:
        pass
    pics = Path(os.environ.get("XDG_PICTURES_DIR", str(Path.home() / "Pictures")))
    candidates.append(pics / "screenshots")
    for cand in candidates:
        key = str(cand)
        if key in seen:
            continue
        seen.add(key)
        if cand.is_dir():
            found.append(cand)
    return found


def _screenshot_files() -> list[tuple[float, str]]:
    now = time.time()
    cached = _SHOT_CACHE.get("files") or []
    if cached and now - float(_SHOT_CACHE.get("at") or 0) < 5:
        return cached
    files: list[tuple[float, str]] = []
    for folder in _screenshot_dirs():
        try:
            entries = list(folder.iterdir())
        except Exception:
            continue
        for path in entries:
            if not path.is_file() or not _is_local_image(str(path)):
                continue
            try:
                files.append((path.stat().st_mtime, str(path)))
            except Exception:
                pass
    _SHOT_CACHE["at"] = now
    _SHOT_CACHE["files"] = files
    return files


def _looks_like_capture(entry: dict) -> bool:
    app = str(entry.get("app") or "").lower()
    summary = str(entry.get("summary") or "").lower()
    if app in ("screenshot", "satty", "swappy", "grim"):
        return True
    return "screenshot" in app or "screenshot" in summary


def resolve_image(entry: dict) -> str:
    """Prefer a file that is still on disk.

    Screenshot toasts often store a temp path, or no path at all. The saved
    PNG is either named in the body or sits in the screenshot folder with
    almost the same timestamp.
    """
    current = _existing_image(str(entry.get("image") or ""))
    if current:
        return current
    icon = _existing_image(str(entry.get("icon") or ""))
    if icon:
        return icon
    for text in (entry.get("body"), entry.get("summary")):
        for match in _BODY_PATH.findall(str(text or "")):
            found = _existing_image(match)
            if found:
                return found
    if not _looks_like_capture(entry):
        return ""
    try:
        stamp = float(entry.get("ts") or 0)
    except Exception:
        stamp = 0
    if stamp <= 0:
        return ""
    # Filename clock survives a later edit that changes the file's mtime.
    named = ""
    named_dt = 3.0
    best = ""
    best_dt = 8.0
    for mtime, path in _screenshot_files():
        delta = abs(mtime - stamp)
        if delta < best_dt:
            best_dt = delta
            best = path
        match = _NAME_STAMP.search(Path(path).name)
        if not match:
            continue
        try:
            named_at = time.mktime(time.strptime(
                f"{match.group(1)} {match.group(2)}:{match.group(3)}:{match.group(4)}",
                "%Y-%m-%d %H:%M:%S",
            ))
        except Exception:
            continue
        name_delta = abs(named_at - stamp)
        if name_delta < named_dt:
            named_dt = name_delta
            named = path
    return named or best


def prepare_history(items: list) -> list:
    changed = False
    for it in items:
        if not isinstance(it, dict):
            continue
        resolved = resolve_image(it)
        if resolved != str(it.get("image") or ""):
            it["image"] = resolved
            changed = True
    if changed:
        save_history(items)
    return items


def parse_notify_block(lines: list[str]) -> dict | None:
    """Parse a dbus-monitor Notify method_call block into an entry.

    Top-level strings (3-space indent) are app, app_icon, summary, body.
    A body with a newline spans dbus-monitor lines; those lines stay one string.
    Screenshot paths arrive as an image-path hint, not as app_icon.
    Action labels and hint keys are nested, so they are not positional.
    """
    image = ""
    urgency = 1
    pairs, _open = dbus_strings(lines)
    top = [val for indent, val in pairs if indent <= 3]
    for i, ln in enumerate(lines):
        m = re.match(r'^(\s*)string\s+"(.*)"\s*$', ln)
        if not m:
            continue
        val = _dbus_string(m.group(2))
        if val in _IMAGE_KEYS:
            for nxt in lines[i + 1 : i + 4]:
                vm = re.search(r'string\s+"(.*)"\s*$', nxt)
                if not vm:
                    continue
                candidate = _dbus_string(vm.group(1))
                if _is_local_image(candidate):
                    image = _clean_image_path(candidate)
                break
        if val == "urgency":
            for nxt in lines[i : i + 3]:
                bm = re.search(r"byte\s+(\d+)", nxt)
                if not bm:
                    continue
                try:
                    urgency = int(bm.group(1))
                except Exception:
                    pass
                break

    # Notify args: app_name, replaces_id(uint32), app_icon, summary, body, ...
    if len(top) < 3:
        return None
    app = top[0] if top else "Notification"
    icon = top[1] if len(top) > 1 else ""
    summary = top[2] if len(top) > 2 else ""
    body = top[3] if len(top) > 3 else ""
    if not image and _is_local_image(icon):
        image = _clean_image_path(icon)
    entry = make_entry(app, summary, body, icon, urgency, image)
    entry["image"] = resolve_image(entry) or image
    return entry


def kernel_boot_id() -> str:
    try:
        return KERNEL_BOOT_ID.read_text(encoding="utf-8").strip()
    except Exception:
        return ""


def clear_on_boot_enabled() -> bool:
    try:
        data = json.loads(LAYOUT_FILE.read_text(encoding="utf-8"))
    except Exception:
        return False
    return bool(isinstance(data, dict) and data.get("notificationClearOnBoot"))


def apply_boot_clear(history: list) -> list:
    """Drop saved history once per boot when Options asks for it.

    The boot id is recorded on every start, including when the option is off,
    so turning it on takes effect at the next boot. A shell reload in the same
    boot keeps the list.
    """
    current = kernel_boot_id()
    previous = ""
    try:
        if BOOT_ID_FILE.is_file():
            previous = BOOT_ID_FILE.read_text(encoding="utf-8").strip()
    except Exception:
        previous = ""
    if current:
        try:
            STATE_DIR.mkdir(parents=True, exist_ok=True)
            BOOT_ID_FILE.write_text(current + "\n", encoding="utf-8")
        except Exception:
            pass
    if clear_on_boot_enabled() and previous and current and previous != current:
        save_history([])
        return []
    return history


def cmd_watch() -> int:
    history = apply_boot_clear(prepare_history(load_history()))
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
        history = prepare_history(load_history())
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
                # Avatar bytes follow the body. Flush once the text is in hand
                # so a large image-data array is not stored line by line.
                # Keep reading while a quoted body is still open.
                _open = False
                if len(block) > 200:
                    _open = dbus_strings(block)[1]
                if len(block) > 4000 or (len(block) > 200 and not _open):
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
