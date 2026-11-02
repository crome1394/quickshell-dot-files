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
RESTORED_FLAG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/screensaver-ddc-restored"
DDC_LOG="${HOME}/.cache/screensaver-ddc.log"
TEXT_LOG="${HOME}/.cache/screensaver-text.log"
RUNTIME_MPV="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/screensaver-mpv"
MODE=video
STYLE=night

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

# Prefer the git tree, then the installed copy, then beside this script.
text_py() {
    local d
    for d in \
        "${HOME}/.config/quickshell/scripts/screensaver-text.py" \
        "${HOME}/.local/share/screensaver/screensaver-text.py" \
        "${SCRIPT_DIR}/screensaver-text.py"
    do
        if [[ -f "$d" ]]; then
            printf '%s' "$d"
            return 0
        fi
    done
    return 1
}

DIM_ENABLE=0
DIM_LEVEL=10
RESTORE_ENABLE=0
RESTORE_LEVEL=80

read_conf() {
    MODE=video
    STYLE=night
    CLOCK=1
    WARP_SPEED=4
    WARP_DENSITY=5
    WARP_STREAK=6
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
            mode)
                case "$val" in
                    text) MODE=text ;;
                    *) MODE=video ;;
                esac
                ;;
            style)
                case "$val" in
                    rain|orbital|night|warp|pyro|scanner) STYLE="$val" ;;
                    *) STYLE=night ;;
                esac
                ;;
            clock)
                case "$val" in
                    1|true|yes|on) CLOCK=1 ;;
                    *) CLOCK=0 ;;
                esac
                ;;
            warp_speed) WARP_SPEED="$val" ;;
            warp_density) WARP_DENSITY="$val" ;;
            warp_streak) WARP_STREAK="$val" ;;
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
    rm -f "$RESTORED_FLAG"
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

# The text saver restores from its own exit and hypridle stop can race.
# One DDC write per 2s. Video stop still runs this, just not twice at once.
brightness_on_stop() {
    local lock="${RESTORED_FLAG}.lock"
    mkdir -p "$(dirname "$RESTORED_FLAG")"
    {
        flock 9
        if [[ -f "$RESTORED_FLAG" ]]; then
            local now age
            now="$(date +%s)"
            age=$(( now - $(stat -c %Y "$RESTORED_FLAG" 2>/dev/null || echo 0) ))
            if (( age < 2 )); then
                return 0
            fi
        fi
        : >"$RESTORED_FLAG"
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
    } 9>>"$lock"
}

is_running() {
    local pid
    [[ -f "$PID_FILE" ]] || return 1
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

TEXT_CLEANED=0
text_exit() {
    [[ "$TEXT_CLEANED" == "1" ]] && return 0
    TEXT_CLEANED=1
    pkill -TERM -P $$ 2>/dev/null || true
    sleep 0.05
    pkill -KILL -P $$ 2>/dev/null || true
    rm -f "$PID_FILE" "$SOCK"
    brightness_on_stop
}

# Session leader. Kitty stays in this process group so stop can signal it.
# Brightness is restored when kitty exits, including a pointer dismiss.
text_child() {
    trap text_exit EXIT INT TERM
    echo $$ >"$PID_FILE"
    local py="${SCREENSAVER_TEXT_PY:-}"
    local style="${SCREENSAVER_TEXT_STYLE:-night}"
    local clock="${SCREENSAVER_TEXT_CLOCK:-1}"
    local warp_speed="${SCREENSAVER_TEXT_WARP_SPEED:-4}"
    local warp_density="${SCREENSAVER_TEXT_WARP_DENSITY:-5}"
    local warp_streak="${SCREENSAVER_TEXT_WARP_STREAK:-6}"
    case "$style" in
        rain|orbital|night|warp|pyro|scanner) ;;
        *) style=night ;;
    esac
    case "$clock" in
        0|false|no|off) clock=0 ;;
        *) clock=1 ;;
    esac
    if [[ ! -f "$py" ]]; then
        echo "screensaver: missing text script: ${py:-<unset>}" >&2
        exit 1
    fi
    echo "$(date -Iseconds) text style=$style" >&2
    kitty \
        --class hypr-screensaver \
        --title hypr-screensaver \
        --start-as fullscreen \
        -o 'font_family=JetBrainsMono Nerd Font Mono' \
        -o font_size=18 \
        -o background=#0a0e16 \
        -o foreground=#f0f4fc \
        -o cursor=#0a0e16 \
        -o cursor_blink_interval=0 \
        -o mouse_hide_wait=0 \
        -o confirm_os_window_close=0 \
        -o remember_window_size=no \
        -o hide_window_decorations=yes \
        -o enable_audio_bell=no \
        -o window_padding_width=0 \
        -- python3 "$py" --style "$style" --clock "$clock" \
            --warp-speed "$warp_speed" --warp-density "$warp_density" \
            --warp-streak "$warp_streak"
}

start_text() {
    local py
    py="$(text_py || true)"
    if [[ -z "$py" ]]; then
        echo "screensaver: missing screensaver-text.py" >&2
        exit 1
    fi
    if ! command -v kitty >/dev/null 2>&1; then
        echo "screensaver: kitty not on PATH" >&2
        exit 1
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        echo "screensaver: python3 not on PATH" >&2
        exit 1
    fi
    brightness_on_start
    mkdir -p "$(dirname "$TEXT_LOG")"
    SCREENSAVER_TEXT_CHILD=1 \
    SCREENSAVER_TEXT_PY="$py" \
    SCREENSAVER_TEXT_STYLE="$STYLE" \
    SCREENSAVER_TEXT_CLOCK="$CLOCK" \
    SCREENSAVER_TEXT_WARP_SPEED="$WARP_SPEED" \
    SCREENSAVER_TEXT_WARP_DENSITY="$WARP_DENSITY" \
    SCREENSAVER_TEXT_WARP_STREAK="$WARP_STREAK" \
        setsid "$0" start >>"$TEXT_LOG" 2>&1 &
    local pid=$!
    echo "$pid" >"$PID_FILE"
    sleep 0.45
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "screensaver: text saver exited immediately (see $TEXT_LOG)" >&2
        brightness_on_stop
        rm -f "$PID_FILE"
        exit 1
    fi
}

start() {
    if [[ -n "${SCREENSAVER_TEXT_CHILD:-}" ]]; then
        text_child
        exit 0
    fi
    read_conf
    if pidof hyprlock >/dev/null 2>&1; then
        exit 0
    fi
    if is_running; then
        exit 0
    fi
    if [[ "$MODE" == "text" ]]; then
        start_text
        return 0
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
    local text_mode=0
    if [[ -S "$SOCK" ]]; then
        printf '%s\n' '{ "command": ["quit"] }' | socat - "$SOCK" >/dev/null 2>&1 || true
        sleep 0.15
    else
        text_mode=1
    fi
    if is_running; then
        local pid i tries
        pid="$(cat "$PID_FILE")"
        kill -TERM -- "-$pid" 2>/dev/null || true
        kill -TERM "$pid" 2>/dev/null || true
        # Text exit runs one DDC set. Give it time before KILL.
        tries=8
        [[ "$text_mode" == "1" ]] && tries=70
        for (( i=0; i<tries; i++ )); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$pid" 2>/dev/null; then
            kill -KILL -- "-$pid" 2>/dev/null || true
            kill -KILL "$pid" 2>/dev/null || true
        fi
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
