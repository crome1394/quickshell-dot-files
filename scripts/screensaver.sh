#!/usr/bin/env bash
# Idle screensaver: fullscreen mpv, no DPMS, no lock.
# mpv must not idle-inhibit (--stop-screensaver=no) or hypridle will
# never see mouse/keyboard and on-resume will not fire.
# Optional DDC brightness (G9 has no sysfs backlight): dim on start,
# set or restore on stop. Prefs in ~/.config/hypr/screensaver.conf.

set -uo pipefail

CONF="${HOME}/.config/hypr/screensaver.conf"
VIDEO="${SCREENSAVER_VIDEO:-$HOME/Videos/screensaver/g9-screen-saver.mp4}"
PID_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/screensaver-mpv.pid"
SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/screensaver-mpv.sock"
PREV_BRIGHT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/screensaver-ddc-prev"
DDC_LOG="${HOME}/.cache/screensaver-ddc.log"

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
    # Isolated mpv: own input.conf so clicks/ESC quit instead of leaving
    # fullscreen. --stop-screensaver=no lets hypridle see mouse on idle.
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
        --input-cursor=yes \
        --cursor-autohide=always \
        --input-conf="${HOME}/.config/mpv/screensaver-input.conf" \
        --script="${HOME}/.config/mpv/scripts-screensaver/quit-on-input.lua" \
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
