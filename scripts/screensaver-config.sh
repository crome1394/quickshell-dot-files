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

norm_bool() {
    case "${1:-}" in
        1|true|yes|on) echo 1 ;;
        *) echo 0 ;;
    esac
}

norm_mode() {
    case "${1:-}" in
        text) echo text ;;
        *) echo video ;;
    esac
}

norm_style() {
    case "${1:-}" in
        rain|orbital|night|warp|pyro|scanner) echo "$1" ;;
        *) echo night ;;
    esac
}

clamp_1_10() {
    local n="${1:-5}"
    if ! [[ "$n" =~ ^[0-9]+$ ]]; then
        n=5
    fi
    if (( n < 1 )); then n=1; fi
    if (( n > 10 )); then n=10; fi
    printf '%s' "$n"
}

# A blank script field means the built-in player. Apply must not wipe it.
use_default_script_if_empty() {
    if [[ -z "${SCRIPT:-}" ]]; then
        SCRIPT="$DEFAULT_SCRIPT"
    fi
}

read_conf() {
    ENABLED=1
    TIMEOUT_SEC=600
    VIDEO="$DEFAULT_VIDEO"
    SCRIPT="$DEFAULT_SCRIPT"
    MODE=video
    STYLE=night
    CLOCK=1
    WARP_SPEED=4
    WARP_DENSITY=5
    WARP_STREAK=6
    IGNORE_INHIBIT=0
    DIM_ENABLE=0
    DIM_LEVEL=10
    RESTORE_ENABLE=0
    RESTORE_LEVEL=80
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
            mode) MODE="$val" ;;
            style) STYLE="$val" ;;
            clock) CLOCK="$val" ;;
            warp_speed) WARP_SPEED="$val" ;;
            warp_density) WARP_DENSITY="$val" ;;
            warp_streak) WARP_STREAK="$val" ;;
            ignore_inhibit) IGNORE_INHIBIT="$val" ;;
            dim_enable) DIM_ENABLE="$val" ;;
            dim_level) DIM_LEVEL="$val" ;;
            restore_enable) RESTORE_ENABLE="$val" ;;
            restore_level) RESTORE_LEVEL="$val" ;;
        esac
    done <"$CONF"
    VIDEO="$(expand_path "$VIDEO")"
    SCRIPT="$(expand_path "$SCRIPT")"
    use_default_script_if_empty
    ENABLED="$(norm_bool "$ENABLED")"
    MODE="$(norm_mode "$MODE")"
    STYLE="$(norm_style "$STYLE")"
    CLOCK="$(norm_bool "$CLOCK")"
    WARP_SPEED="$(clamp_1_10 "$WARP_SPEED")"
    WARP_DENSITY="$(clamp_1_10 "$WARP_DENSITY")"
    WARP_STREAK="$(clamp_1_10 "$WARP_STREAK")"
    IGNORE_INHIBIT="$(norm_bool "$IGNORE_INHIBIT")"
    DIM_ENABLE="$(norm_bool "$DIM_ENABLE")"
    RESTORE_ENABLE="$(norm_bool "$RESTORE_ENABLE")"
    DIM_LEVEL="$(clamp_pct "$DIM_LEVEL")"
    RESTORE_LEVEL="$(clamp_pct "$RESTORE_LEVEL")"
}

clamp_pct() {
    local n="${1:-0}"
    [[ "$n" =~ ^[0-9]+$ ]] || n=0
    if (( n > 100 )); then n=100; fi
    printf '%s' "$n"
}

json_escape() {
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()[:-1] if False else sys.argv[1]))' "$1"
}

emit_json() {
    read_conf
    local video_ok=0 script_ok=0
    [[ -f "$VIDEO" ]] && video_ok=1
    [[ -x "$SCRIPT" ]] && script_ok=1
    python3 - "$ENABLED" "$TIMEOUT_SEC" "$VIDEO" "$SCRIPT" "$video_ok" "$script_ok" "$IGNORE_INHIBIT" \
        "$DIM_ENABLE" "$DIM_LEVEL" "$RESTORE_ENABLE" "$RESTORE_LEVEL" "$MODE" "$STYLE" \
        "$CLOCK" "$WARP_SPEED" "$WARP_DENSITY" "$WARP_STREAK" <<'PY'
import json, sys
(enabled, timeout, video, script, vok, sok, ign, dim_on, dim_lv, rest_on, rest_lv,
 mode, style, clock, warp_speed, warp_density, warp_streak) = sys.argv[1:18]
try:
    t = int(timeout)
except ValueError:
    t = 600
try:
    en = int(enabled)
except ValueError:
    en = 1
def b(x):
    try:
        return bool(int(x))
    except ValueError:
        return False
def pct(x, default):
    try:
        n = int(x)
    except ValueError:
        n = default
    return max(0, min(100, n))
if mode not in ("video", "text"):
    mode = "video"
if style not in ("night", "rain", "orbital", "warp", "pyro", "scanner"):
    style = "night"
def unit(x, default):
    try:
        n = int(x)
    except ValueError:
        n = default
    return max(1, min(10, n))
print(json.dumps({
    "ok": True,
    "enabled": bool(en),
    "timeout_sec": t,
    "timeout_min": max(1, int(round(t / 60.0))) if t >= 30 else 1,
    "video": video,
    "script": script,
    "mode": mode,
    "style": style,
    "clock": b(clock),
    "warp_speed": unit(warp_speed, 4),
    "warp_density": unit(warp_density, 5),
    "warp_streak": unit(warp_streak, 6),
    "video_ok": bool(int(vok)),
    "script_ok": bool(int(sok)),
    "ignore_inhibit": b(ign),
    "dim_enable": b(dim_on),
    "dim_level": pct(dim_lv, 10),
    "restore_enable": b(rest_on),
    "restore_level": pct(rest_lv, 80),
    "ddcutil_ok": bool(__import__("shutil").which("ddcutil")),
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
mode=${MODE}
style=${STYLE}
clock=${CLOCK}
warp_speed=${WARP_SPEED}
warp_density=${WARP_DENSITY}
warp_streak=${WARP_STREAK}
ignore_inhibit=${IGNORE_INHIBIT}
dim_enable=${DIM_ENABLE}
dim_level=${DIM_LEVEL}
restore_enable=${RESTORE_ENABLE}
restore_level=${RESTORE_LEVEL}
EOF
    mv -f "$tmp" "$CONF"
}

write_hypridle_if_missing() {
    [[ -f "$HYPRIDLE" ]] && return 0
    mkdir -p "$(dirname "$HYPRIDLE")"
    cat >"$HYPRIDLE" <<EOF
general {
    ignore_dbus_inhibit = true
    ignore_systemd_inhibit = true
    ignore_wayland_inhibit = true
}

${BEGIN}
listener {
    timeout = ${TIMEOUT_SEC}
    on-timeout = ${SELF} start
    on-resume = ${SELF} stop
    condition_cmd = ${SELF} idle-ok
}
${END}
EOF
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
import re
# Tab video (YouTube/X/etc.) uses Wayland/D-Bus idle inhibit. Ignore those so
# hypridle still reaches timeout; idle-ok decides fullscreen vs always-start.
for key in ("ignore_dbus_inhibit", "ignore_systemd_inhibit", "ignore_wayland_inhibit"):
    new2, nsub = re.subn(rf"(?m)^(\s*{key}\s*=\s*)\S+", r"\1true", new)
    if nsub:
        new = new2
if new != text:
    bak = path + ".bak-screensaver"
    pathlib.Path(bak).write_text(pathlib.Path(path).read_text())
    pathlib.Path(path).write_text(new)
    print("patched", file=sys.stderr)
else:
    print("unchanged", file=sys.stderr)
PY
}

# True if a mapped client is in real fullscreen (not the screensaver itself).
fullscreen_client_blocks() {
    hyprctl clients -j 2>/dev/null | python3 -c '
import json, sys
try:
    clients = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if not isinstance(clients, list):
    sys.exit(1)

def is_real_fullscreen(c):
    if c.get("fullscreenClient"):
        return True
    fs = c.get("fullscreen")
    if fs is True:
        return True
    try:
        return int(fs) >= 2
    except (TypeError, ValueError):
        return False

for c in clients:
    if not c or not c.get("mapped", True):
        continue
    if c.get("hidden"):
        continue
    title = str(c.get("title") or "")
    if title == "hypr-screensaver":
        continue
    if is_real_fullscreen(c):
        sys.exit(0)
sys.exit(1)
'
}

# hypridle reads its config once at start and does not reload on SIGHUP.
# Restart it so a new "Start after" value is the one that actually fires.
reload_hypridle() {
    local log="${HOME}/.cache/hypridle.log"
    local i
    mkdir -p "$(dirname "$log")"
    if pgrep -x hypridle >/dev/null 2>&1; then
        pkill -TERM -x hypridle 2>/dev/null || true
        for i in 1 2 3 4 5 6 7 8 9 10; do
            pgrep -x hypridle >/dev/null 2>&1 || break
            sleep 0.1
        done
        if pgrep -x hypridle >/dev/null 2>&1; then
            pkill -KILL -x hypridle 2>/dev/null || true
            sleep 0.1
        fi
    fi
    if [[ "$ENABLED" == "1" ]]; then
        setsid hypridle >>"$log" 2>&1 &
        sleep 0.4
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
            --mode)
                MODE="$2"; shift 2 ;;
            --style)
                STYLE="$2"; shift 2 ;;
            --clock)
                CLOCK="$2"; shift 2 ;;
            --warp-speed)
                WARP_SPEED="$2"; shift 2 ;;
            --warp-density)
                WARP_DENSITY="$2"; shift 2 ;;
            --warp-streak)
                WARP_STREAK="$2"; shift 2 ;;
            --ignore-inhibit)
                IGNORE_INHIBIT="$2"; shift 2 ;;
            --dim-enable)
                DIM_ENABLE="$2"; shift 2 ;;
            --dim-level)
                DIM_LEVEL="$2"; shift 2 ;;
            --restore-enable)
                RESTORE_ENABLE="$2"; shift 2 ;;
            --restore-level)
                RESTORE_LEVEL="$2"; shift 2 ;;
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
    use_default_script_if_empty
    MODE="$(norm_mode "$MODE")"
    STYLE="$(norm_style "$STYLE")"
    CLOCK="$(norm_bool "$CLOCK")"
    WARP_SPEED="$(clamp_1_10 "$WARP_SPEED")"
    WARP_DENSITY="$(clamp_1_10 "$WARP_DENSITY")"
    WARP_STREAK="$(clamp_1_10 "$WARP_STREAK")"
    IGNORE_INHIBIT="$(norm_bool "$IGNORE_INHIBIT")"
    DIM_ENABLE="$(norm_bool "$DIM_ENABLE")"
    RESTORE_ENABLE="$(norm_bool "$RESTORE_ENABLE")"
    DIM_LEVEL="$(clamp_pct "$DIM_LEVEL")"
    RESTORE_LEVEL="$(clamp_pct "$RESTORE_LEVEL")"
    write_conf
    if [[ ! -f "$HYPRIDLE" ]]; then
        write_hypridle_if_missing
    else
        patch_hypridle
    fi
    reload_hypridle
    emit_json
}

cmd_idle_ok() {
    read_conf
    [[ "$ENABLED" == "1" ]] || exit 1
    # Override: start after idle even if a site is playing video or is fullscreen.
    [[ "$IGNORE_INHIBIT" == "1" ]] && exit 0
    # Tab players (YouTube, X, Facebook, Rumble, …) set idle-inhibit without
    # fullscreen; those are ignored in hypridle. Real fullscreen still blocks.
    if fullscreen_client_blocks; then
        exit 1
    fi
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
