#!/usr/bin/env bash
# Idle screensaver: fullscreen mpv, no DPMS, no lock.
# mpv must not idle-inhibit (--stop-screensaver=no) or hypridle will
# never see mouse/keyboard and on-resume will not fire.
# Optional DDC brightness (G9 has no sysfs backlight): dim on start,
# set or restore on stop. Prefs in ~/.config/hypr/screensaver.conf.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${HOME}/.config/hypr/screensaver.conf"
VIDEO="${SCREENSAVER_VIDEO:-$HOME/Videos/screensaver/g9-screen-saver.mp4}"
PID_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/screensaver-mpv.pid"
SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/screensaver-mpv.sock"
PREV_BRIGHT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/screensaver-ddc-prev"
DDC_LOG="${HOME}/.cache/screensaver-ddc.log"
RUNTIME_MPV="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/screensaver-mpv"

# Mouse/key dismiss files. Prefer the git tree, then the copied share dir.
# Never ~/.config/mpv — that tree is wiped on an mpv/user reinstall.
mpv_dismiss_src() {
    local d
    for d in \
        "${HOME}/.config/quickshell/scripts/screensaver-mpv" \
        "${HOME}/.local/share/screensaver" \
        "${SCRIPT_DIR}/screensaver-mpv"
    do
        if [[ -f "$d/input.conf" && -f "$d/quit-on-input.lua" ]]; then
            printf '%s' "$d"
            return 0
        fi
    done
    return 1
}

write_bundled_dismiss() {
    # Last resort if only screensaver.sh was copied (keep in sync with
    # scripts/screensaver-mpv/).
    mkdir -p "$RUNTIME_MPV"
    cat >"$RUNTIME_MPV/input.conf" <<'EOF'
# Bundled fallback — prefer scripts/screensaver-mpv/input.conf in git.
MBTN_LEFT quit
MBTN_RIGHT quit
MBTN_MID quit
MBTN_BACK quit
MBTN_FORWARD quit
WHEEL_UP quit
WHEEL_DOWN quit
WHEEL_LEFT quit
WHEEL_RIGHT quit
ESC quit
q quit
SPACE quit
ENTER quit
EOF
    cat >"$RUNTIME_MPV/quit-on-input.lua" <<'EOF'
-- Bundled fallback — prefer scripts/screensaver-mpv/quit-on-input.lua in git.
local grace = true
local origin = nil

local function quit()
    mp.command("quit")
end

mp.add_timeout(1.0, function()
    grace = false
end)

mp.observe_property("mouse-pos", "native", function(_, pos)
    if grace or not pos then
        return
    end
    if not origin then
        origin = pos
        return
    end
    local dx = math.abs((pos.x or 0) - (origin.x or 0))
    local dy = math.abs((pos.y or 0) - (origin.y or 0))
    if dx > 8 or dy > 8 then
        quit()
    end
end)

local keys = {
    "MBTN_LEFT", "MBTN_RIGHT", "MBTN_MID", "MBTN_BACK", "MBTN_FORWARD",
    "WHEEL_UP", "WHEEL_DOWN", "WHEEL_LEFT", "WHEEL_RIGHT",
    "ESC", "q", "SPACE", "ENTER", "ANY_UNICODE",
}
for _, key in ipairs(keys) do
    mp.add_forced_key_binding(key, "ss-quit-" .. key, quit)
end
EOF
}

stage_mpv_dismiss() {
    mkdir -p "$RUNTIME_MPV"
    local src
    src="$(mpv_dismiss_src || true)"
    if [[ -n "$src" ]]; then
        cp -f "$src/input.conf" "$RUNTIME_MPV/input.conf"
        cp -f "$src/quit-on-input.lua" "$RUNTIME_MPV/quit-on-input.lua"
        return 0
    fi
    echo "screensaver: mpv dismiss files missing; using bundled fallback (run scripts/install-screensaver-helpers.sh)" >&2
    write_bundled_dismiss
}

DIM_ENABLE=0
DIM_LEVEL=10
RESTORE_ENABLE=0
RESTORE_LEVEL=80

read_conf() {
    [[ -f "$CONF" ]] || return 0
    local line key val
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        key="${line%%=*}"
        val="${line#*=}"
        key="${key// /}"
        case "$key" in
            video)
                if [[ -z "${SCREENSAVER_VIDEO:-}" ]]; then
                    val="${val/#\~/$HOME}"
                    [[ -n "$val" ]] && VIDEO="$val"
                fi
                ;;
            dim_enable) DIM_ENABLE="$val" ;;
            dim_level) DIM_LEVEL="$val" ;;
            restore_enable) RESTORE_ENABLE="$val" ;;
            restore_level) RESTORE_LEVEL="$val" ;;
        esac
    done <"$CONF"
    case "$DIM_ENABLE" in 1|true|yes|on) DIM_ENABLE=1 ;; *) DIM_ENABLE=0 ;; esac
    case "$RESTORE_ENABLE" in 1|true|yes|on) RESTORE_ENABLE=1 ;; *) RESTORE_ENABLE=0 ;; esac
    [[ "$DIM_LEVEL" =~ ^[0-9]+$ ]] || DIM_LEVEL=10
    [[ "$RESTORE_LEVEL" =~ ^[0-9]+$ ]] || RESTORE_LEVEL=80
    if (( DIM_LEVEL > 100 )); then DIM_LEVEL=100; fi
    if (( RESTORE_LEVEL > 100 )); then RESTORE_LEVEL=100; fi
}

ddc_log() {
    mkdir -p "$(dirname "$DDC_LOG")"
    printf '%s %s\n' "$(date -Iseconds)" "$*" >>"$DDC_LOG"
}

# One get/set only — NVIDIA DP AUX can drop DDC if hammered.
ddc_get() {
    command -v ddcutil >/dev/null 2>&1 || return 1
    local out n
    out="$(timeout 6 ddcutil --brief getvcp 10 2>/dev/null || true)"
    n="$(printf '%s\n' "$out" | awk '/^VCP / { print $4; exit }')"
    if [[ -z "$n" ]]; then
        out="$(timeout 6 ddcutil getvcp 10 2>/dev/null || true)"
        n="$(printf '%s\n' "$out" | awk -F'=' '/current value/ {
            gsub(/[^0-9]/, "", $2)
            print $2 + 0
            exit
        }')"
    fi
    [[ "$n" =~ ^[0-9]+$ ]] || return 1
    if (( n > 100 )); then n=100; fi
    printf '%s' "$n"
}

ddc_set() {
    local v="$1"
    command -v ddcutil >/dev/null 2>&1 || { ddc_log "ddcutil missing; skip set $v"; return 1; }
    [[ "$v" =~ ^[0-9]+$ ]] || return 1
    (( v > 100 )) && v=100
    if timeout 6 ddcutil setvcp 10 "$v" >/dev/null 2>&1; then
        ddc_log "setvcp 10 -> $v"
        return 0
    fi
    ddc_log "setvcp 10 $v failed"
    return 1
}

brightness_on_start() {
    read_conf
    [[ "$DIM_ENABLE" == "1" ]] || return 0
    local cur
    cur="$(ddc_get || true)"
    if [[ -n "$cur" ]]; then
        printf '%s\n' "$cur" >"$PREV_BRIGHT"
        ddc_log "captured brightness $cur"
    else
        ddc_log "could not read brightness (is ddcutil installed and DDC/CI on?)"
        rm -f "$PREV_BRIGHT"
    fi
    ddc_set "$DIM_LEVEL" || true
}

brightness_on_stop() {
    read_conf
    if [[ "$RESTORE_ENABLE" == "1" ]]; then
        ddc_set "$RESTORE_LEVEL" || true
        rm -f "$PREV_BRIGHT"
        return 0
    fi
    if [[ "$DIM_ENABLE" == "1" && -f "$PREV_BRIGHT" ]]; then
        local prev
        prev="$(tr -cd '0-9' <"$PREV_BRIGHT")"
        [[ -n "$prev" ]] && ddc_set "$prev" || true
    fi
    rm -f "$PREV_BRIGHT"
}

is_running() {
    local pid
    [[ -f "$PID_FILE" ]] || return 1
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

start() {
    read_conf
    if pidof hyprlock >/dev/null 2>&1; then
        exit 0
    fi
    if is_running; then
        exit 0
    fi
    if [[ ! -f "$VIDEO" ]]; then
        echo "screensaver: missing $VIDEO" >&2
        exit 1
    fi

    brightness_on_start

    rm -f "$SOCK"
    stage_mpv_dismiss
    # Isolated mpv: own input.conf + lua so mouse/keys quit. Files live in
    # git (scripts/screensaver-mpv/), not ~/.config/mpv. --stop-screensaver=no
    # lets hypridle see activity; lua still quits if the compositor does not.
    mpv --no-config \
        --fullscreen --ontop --no-border --keep-open=no \
        --title=hypr-screensaver \
        --loop-file=inf --no-audio --no-osc --osd-level=0 \
        --hwdec=no --gpu-api=opengl --vo=gpu \
        --scale=bilinear --cscale=bilinear --dither-depth=no --deband=no \
        --video-sync=audio --framedrop=vo --cache=no \
        --panscan=1.0 --speed=0.75 \
        --stop-screensaver=no \
        --force-window=immediate \
        --input-default-bindings=no \
        --input-builtin-bindings=no \
        --input-cursor=yes \
        --cursor-autohide=always \
        --input-conf="${RUNTIME_MPV}/input.conf" \
        --script="${RUNTIME_MPV}/quit-on-input.lua" \
        --input-ipc-server="$SOCK" \
        --really-quiet \
        -- "$VIDEO" &
    echo $! >"$PID_FILE"
}

stop() {
    if [[ -S "$SOCK" ]]; then
        printf '%s\n' '{ "command": ["quit"] }' | socat - "$SOCK" >/dev/null 2>&1 || true
        sleep 0.15
    fi
    if is_running; then
        kill "$(cat "$PID_FILE")" 2>/dev/null || true
        sleep 0.1
        kill -KILL "$(cat "$PID_FILE")" 2>/dev/null || true
    fi
    rm -f "$PID_FILE" "$SOCK"
    brightness_on_stop
}

case "${1:-}" in
    start) start ;;
    stop)  stop ;;
    *)
        echo "usage: $0 start|stop" >&2
        exit 2
        ;;
esac
