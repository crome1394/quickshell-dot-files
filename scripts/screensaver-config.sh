#!/usr/bin/env bash
# screensaver-config.sh — get/set idle screensaver prefs for the control bar.
# Does not enable DPMS. Super+L and hypridle both call start/stop here.
set -euo pipefail

CONF="${HOME}/.config/hypr/screensaver.conf"
HYPRIDLE="${HOME}/.config/hypr/hypridle.conf"
DEFAULT_VIDEO="${HOME}/Videos/screensaver/g9-screen-saver.mp4"
DEFAULT_SCRIPT="${HOME}/.local/bin/screensaver.sh"
SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"

BEGIN="# === SCREENSAVER_IDLE ==="
END="# === SCREENSAVER_IDLE_END ==="

expand_path() {
    local p="${1:-}"
    p="${p/#\~/$HOME}"
    printf '%s' "$p"
}

read_conf() {
    ENABLED=1
    TIMEOUT_SEC=600
    VIDEO="$DEFAULT_VIDEO"
    SCRIPT="$DEFAULT_SCRIPT"
    [[ -f "$CONF" ]] || return 0
    local line key val
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        key="${line%%=*}"
        val="${line#*=}"
        key="${key// /}"
        case "$key" in
            enabled) ENABLED="$val" ;;
            timeout_sec) TIMEOUT_SEC="$val" ;;
            video) VIDEO="$val" ;;
            script) SCRIPT="$val" ;;
        esac
    done <"$CONF"
    VIDEO="$(expand_path "$VIDEO")"
    SCRIPT="$(expand_path "$SCRIPT")"
}

json_escape() {
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()[:-1] if False else sys.argv[1]))' "$1"
}

emit_json() {
    read_conf
    local video_ok=0 script_ok=0
    [[ -f "$VIDEO" ]] && video_ok=1
    [[ -x "$SCRIPT" ]] && script_ok=1
    python3 - "$ENABLED" "$TIMEOUT_SEC" "$VIDEO" "$SCRIPT" "$video_ok" "$script_ok" <<'PY'
import json, sys
enabled, timeout, video, script, vok, sok = sys.argv[1:7]
try:
    t = int(timeout)
except ValueError:
    t = 600
try:
    en = int(enabled)
except ValueError:
    en = 1
print(json.dumps({
    "ok": True,
    "enabled": bool(en),
    "timeout_sec": t,
    "timeout_min": max(1, int(round(t / 60.0))) if t >= 30 else 1,
    "video": video,
    "script": script,
    "video_ok": bool(int(vok)),
    "script_ok": bool(int(sok)),
}))
PY
}

write_conf() {
    mkdir -p "$(dirname "$CONF")"
    local tmp
    tmp="$(mktemp "${CONF}.XXXXXX")"
    cat >"$tmp" <<EOF
# Managed by Quickshell Options → Screensaver. Do not put secrets here.
enabled=${ENABLED}
timeout_sec=${TIMEOUT_SEC}
video=${VIDEO}
script=${SCRIPT}
EOF
    mv -f "$tmp" "$CONF"
}

patch_hypridle() {
    [[ -f "$HYPRIDLE" ]] || return 0
    python3 - "$HYPRIDLE" "$BEGIN" "$END" "$TIMEOUT_SEC" "$SELF" <<'PY'
import pathlib, sys
path, begin, end, timeout, self = sys.argv[1:6]
try:
    t = int(timeout)
except ValueError:
    t = 600
t = max(30, min(86400, t))
text = pathlib.Path(path).read_text()
block = (
    f"{begin}\n"
    "listener {\n"
    f"    timeout = {t}\n"
    f"    on-timeout = {self} start\n"
    f"    on-resume = {self} stop\n"
    f"    condition_cmd = {self} idle-ok\n"
    "}\n"
    f"{end}\n"
)
i = text.find(begin)
j = text.find(end)
if i >= 0 and j > i:
    j = j + len(end)
    if j < len(text) and text[j] == "\n":
        j += 1
    new = text[:i] + block + text[j:]
else:
    if text and not text.endswith("\n"):
        text += "\n"
    new = text + "\n" + block
if new != text:
    bak = path + ".bak-screensaver"
    pathlib.Path(bak).write_text(pathlib.Path(path).read_text())
    pathlib.Path(path).write_text(new)
    print("patched")
else:
    print("unchanged")
PY
}

reload_hypridle() {
    if pgrep -x hypridle >/dev/null 2>&1; then
        pkill -HUP hypridle 2>/dev/null || true
        sleep 0.15
        if ! pgrep -x hypridle >/dev/null 2>&1; then
            hypridle >/dev/null 2>&1 &
        fi
    fi
}

cmd_set() {
    read_conf
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --enabled)
                ENABLED="$2"; shift 2 ;;
            --timeout-sec)
                TIMEOUT_SEC="$2"; shift 2 ;;
            --timeout-min)
                TIMEOUT_SEC=$(( ${2} * 60 )); shift 2 ;;
            --video)
                VIDEO="$(expand_path "$2")"; shift 2 ;;
            --script)
                SCRIPT="$(expand_path "$2")"; shift 2 ;;
            *)
                echo "{\"ok\":false,\"error\":\"unknown arg $1\"}" >&2
                exit 2 ;;
        esac
    done
    case "$ENABLED" in
        1|true|yes|on) ENABLED=1 ;;
        0|false|no|off) ENABLED=0 ;;
        *) ENABLED=1 ;;
    esac
    if ! [[ "$TIMEOUT_SEC" =~ ^[0-9]+$ ]]; then
        TIMEOUT_SEC=600
    fi
    if (( TIMEOUT_SEC < 30 )); then TIMEOUT_SEC=30; fi
    if (( TIMEOUT_SEC > 86400 )); then TIMEOUT_SEC=86400; fi
    VIDEO="$(expand_path "$VIDEO")"
    SCRIPT="$(expand_path "$SCRIPT")"
    write_conf
    patch_hypridle
    reload_hypridle
    emit_json
}

cmd_idle_ok() {
    read_conf
    [[ "$ENABLED" == "1" ]] || exit 1
    exit 0
}

cmd_start() {
    read_conf
    if [[ ! -x "$SCRIPT" ]]; then
        echo "screensaver-config: script not executable: $SCRIPT" >&2
        exit 1
    fi
    exec "$SCRIPT" start
}

cmd_stop() {
    read_conf
    if [[ ! -x "$SCRIPT" ]]; then
        exit 0
    fi
    exec "$SCRIPT" stop
}

cmd_pick_video() {
    read_conf
    local start="$VIDEO"
    [[ -f "$start" ]] || start="${HOME}/Videos/screensaver/"
    [[ -d "$start" ]] || start="$(dirname "$start")/"
    if ! command -v zenity >/dev/null 2>&1; then
        echo ""
        exit 1
    fi
    zenity --file-selection --title="Screensaver video" \
        --filename="$start" \
        --file-filter="Video | *.mp4 *.mkv *.webm *.mov *.avi" \
        --file-filter="All files | *" 2>/dev/null || true
}

cmd_pick_script() {
    read_conf
    local start="$SCRIPT"
    [[ -e "$start" ]] || start="${HOME}/.local/bin/"
    if ! command -v zenity >/dev/null 2>&1; then
        echo ""
        exit 1
    fi
    zenity --file-selection --title="Screensaver script (start|stop)" \
        --filename="$start" 2>/dev/null || true
}

case "${1:-}" in
    get) emit_json ;;
    set) shift; cmd_set "$@" ;;
    idle-ok) cmd_idle_ok ;;
    start) cmd_start ;;
    stop) cmd_stop ;;
    pick-video) cmd_pick_video ;;
    pick-script) cmd_pick_script ;;
    *)
        echo "usage: $0 get|set|start|stop|idle-ok|pick-video|pick-script" >&2
        exit 2
        ;;
esac
