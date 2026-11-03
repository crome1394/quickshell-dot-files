#!/usr/bin/env bash
# monitor-mode.sh — list / status / apply Hyprland monitor modes for Quickshell
#
# Usage:
#   monitor-mode.sh status-json
#   monitor-mode.sh list-json
#   monitor-mode.sh apply <mode> [bitdepth]
#
# mode examples: 5120x1440@239.76  |  3840x1080@239.97Hz
# bitdepth: 8 or 10 (default 10)
# scale is always 1.0; position 0x0
#
# Env:
#   HYPR_MONITOR               optional output; empty uses the focused output
#   HYPR_MONITOR_BITDEPTH=10   (default for apply when omitted)
set -euo pipefail

# Empty selects the focused output inside monitor_json (then the first).
MONITOR="${HYPR_MONITOR:-}"
DEFAULT_BITDEPTH="${HYPR_MONITOR_BITDEPTH:-10}"
POSITION="0x0"
SCALE="1"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_jq() {
  command -v jq >/dev/null 2>&1 || die "jq is required"
}

normalize_mode() {
  # WxH@rate only. The string is interpolated into hyprctl eval and monitors.lua.
  local m="${1// /}"
  m="${m%Hz}"
  m="${m%hz}"
  if [[ ! "$m" =~ ^[0-9]+x[0-9]+@[0-9]+([.][0-9]+)?$ ]]; then
    printf ''
    return 0
  fi
  printf '%s' "$m"
}

bitdepth_from_format() {
  local fmt="$1"
  if [[ "$fmt" == *2101010* ]]; then
    printf '10'
  else
    printf '8'
  fi
}

# Select monitor JSON object from hyprctl monitors -j
monitor_json() {
  need_jq
  local all
  all="$(hyprctl monitors -j 2>/dev/null)" || die "hyprctl monitors -j failed"
  [[ -n "$all" && "$all" != "null" ]] || die "no monitors from hyprctl"

  # Prefer exact name, then focused, then first
  printf '%s' "$all" | jq -c --arg n "$MONITOR" '
    (map(select(.name == $n)) | .[0])
    // (map(select(.focused == true)) | .[0])
    // .[0]
    // empty
  '
}

# DRM card / connector for a Hyprland output name (cardN-<output>).
drm_adapter_info() {
  local out_name="$1"
  local link card conn path
  # Prefer the sysfs connector whose status is connected and name matches
  for path in /sys/class/drm/card*-"${out_name}"; do
    [[ -e "$path" ]] || continue
    if [[ -f "$path/status" ]] && [[ "$(cat "$path/status" 2>/dev/null)" == "connected" ]]; then
      conn="$(basename "$path")"
      card="${conn%%-*}"
      # Resolve PCI device for this card
      local vendor device pci driver
      vendor="$(cat "/sys/class/drm/${card}/device/vendor" 2>/dev/null || true)"
      device="$(cat "/sys/class/drm/${card}/device/device" 2>/dev/null || true)"
      pci="$(basename "$(readlink -f "/sys/class/drm/${card}/device" 2>/dev/null)" 2>/dev/null || true)"
      driver="$(basename "$(readlink -f "/sys/class/drm/${card}/device/driver" 2>/dev/null)" 2>/dev/null || true)"
      jq -nc \
        --arg connector "$conn" \
        --arg card "$card" \
        --arg pci "$pci" \
        --arg driver "$driver" \
        --arg vendor "$vendor" \
        --arg device "$device" \
        '{connector:$connector, card:$card, pci:$pci, driver:$driver, vendor:$vendor, device:$device}'
      return 0
    fi
  done
  printf '%s' '{}'
}

# NVIDIA GPU live stats (first GPU). Empty object if nvidia-smi missing.
nvidia_stats_json() {
  if ! command -v nvidia-smi >/dev/null 2>&1; then
    printf '%s' '{"available":false}'
    return 0
  fi
  local raw name driver
  raw="$(nvidia-smi --query-gpu=\
name,driver_version,pci.bus_id,\
memory.total,memory.used,memory.free,\
utilization.gpu,utilization.memory,\
temperature.gpu,power.draw,power.limit,pstate,\
clocks.current.graphics,clocks.current.memory \
--format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d '\r' || true)"
  if [[ -z "${raw// /}" ]]; then
    printf '%s' '{"available":false}'
    return 0
  fi
  # CSV fields may have spaces after commas
  IFS=',' read -r name driver pci_bus \
    mem_total mem_used mem_free \
    util_gpu util_mem \
    temp power power_limit pstate \
    clock_gfx clock_mem <<<"$raw"

  trim() { local s="${1:-}"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

  name="$(trim "$name")"
  driver="$(trim "$driver")"
  pci_bus="$(trim "$pci_bus")"
  mem_total="$(trim "$mem_total")"
  mem_used="$(trim "$mem_used")"
  mem_free="$(trim "$mem_free")"
  util_gpu="$(trim "$util_gpu")"
  util_mem="$(trim "$util_mem")"
  temp="$(trim "$temp")"
  power="$(trim "$power")"
  power_limit="$(trim "$power_limit")"
  pstate="$(trim "$pstate")"
  clock_gfx="$(trim "$clock_gfx")"
  clock_mem="$(trim "$clock_mem")"

  jq -nc \
    --argjson available true \
    --arg name "$name" \
    --arg driver "$driver" \
    --arg pciBus "$pci_bus" \
    --argjson memTotalMiB "${mem_total:-0}" \
    --argjson memUsedMiB "${mem_used:-0}" \
    --argjson memFreeMiB "${mem_free:-0}" \
    --argjson utilGpu "${util_gpu:-0}" \
    --argjson utilMem "${util_mem:-0}" \
    --argjson tempC "${temp:-0}" \
    --argjson powerW "${power:-0}" \
    --argjson powerLimitW "${power_limit:-0}" \
    --arg pstate "$pstate" \
    --argjson clockGfxMHz "${clock_gfx:-0}" \
    --argjson clockMemMHz "${clock_mem:-0}" \
    '{
      available: $available,
      name: $name,
      driver: $driver,
      pciBus: $pciBus,
      memTotalMiB: $memTotalMiB,
      memUsedMiB: $memUsedMiB,
      memFreeMiB: $memFreeMiB,
      utilGpu: $utilGpu,
      utilMem: $utilMem,
      tempC: $tempC,
      powerW: $powerW,
      powerLimitW: $powerLimitW,
      pstate: $pstate,
      clockGfxMHz: $clockGfxMHz,
      clockMemMHz: $clockMemMHz
    }' 2>/dev/null || printf '%s' '{"available":false}'
}

status_json() {
  local mon mon_name drm_json gpu_json
  mon="$(monitor_json)"
  [[ -n "$mon" && "$mon" != "null" ]] || die "monitor not found"
  mon_name="$(printf '%s' "$mon" | jq -r '.name // empty')"
  drm_json="$(drm_adapter_info "$mon_name")"
  gpu_json="$(nvidia_stats_json)"

  # lspci human name for the DRM card PCI id when nvidia-smi name empty
  local pci_name=""
  local pci_id
  pci_id="$(printf '%s' "$drm_json" | jq -r '.pci // empty')"
  if [[ -n "$pci_id" ]] && command -v lspci >/dev/null 2>&1; then
    pci_name="$(lspci -s "$pci_id" 2>/dev/null | sed -E 's/^[0-9a-f:.]+\s+([^:]+:\s*)?//' | head -1 || true)"
  fi

  # Note: ${var:-{}} is wrong in bash (appends a literal }); use quoted "{}"
  jq -nc \
    --argjson m "$mon" \
    --argjson drm "${drm_json:-"{}"}" \
    --argjson gpu "${gpu_json:-"{}"}" \
    --arg pciName "$pci_name" '
    ($m.currentFormat // "?") as $fmt
    | (if ($fmt | tostring | test("2101010")) then 10 else 8 end) as $bd
    | {
        name: ($m.name // ""),
        make: ($m.make // ""),
        model: ($m.model // ""),
        serial: ($m.serial // ""),
        description: ($m.description // ""),
        width: ($m.width // 0),
        height: ($m.height // 0),
        refreshRate: ($m.refreshRate // 0),
        scale: ($m.scale // 0),
        format: $fmt,
        bitdepth: $bd,
        mode: (
          (($m.width // 0) | tostring) + "x" + (($m.height // 0) | tostring)
          + "@" + (($m.refreshRate // 0) | tostring)
        ),
        res: ((($m.width // 0) | tostring) + "x" + (($m.height // 0) | tostring)),
        disabled: ($m.disabled // false),
        focused: ($m.focused // false),
        vrr: ($m.vrr // false),
        dpmsStatus: ($m.dpmsStatus // true),
        transform: ($m.transform // 0),
        x: ($m.x // 0),
        y: ($m.y // 0),
        physicalWidth: ($m.physicalWidth // 0),
        physicalHeight: ($m.physicalHeight // 0),
        colorManagementPreset: ($m.colorManagementPreset // ""),
        adapter: {
          connector: ($drm.connector // ""),
          card: ($drm.card // ""),
          pci: ($drm.pci // ""),
          driver: ($drm.driver // ""),
          pciName: $pciName
        },
        gpu: $gpu
      }
  '
}

list_json() {
  local mon
  mon="$(monitor_json)"
  [[ -n "$mon" && "$mon" != "null" ]] || die "monitor not found"

  printf '%s' "$mon" | jq -c '
    def parse_mode:
      # "5120x1440@239.76Hz" -> {res, rate, rateLabel, mode, w, h}
      capture("(?<w>[0-9]+)x(?<h>[0-9]+)@(?<rate>[0-9.]+)Hz?")
      | {
          res: (.w + "x" + .h),
          rate: (.rate | tonumber),
          rateLabel: .rate,
          mode: (.w + "x" + .h + "@" + .rate),
          w: (.w | tonumber),
          h: (.h | tonumber),
          pixels: ((.w | tonumber) * (.h | tonumber))
        };

    (.availableModes // []) as $modes
    | [.name // ""] as $name
    | (
        [$modes[] | select(type == "string") | parse_mode]
        | group_by(.res)
        | map(
            sort_by(-.rate)
            | {
                res: .[0].res,
                w: .[0].w,
                h: .[0].h,
                pixels: .[0].pixels,
                rates: [.[].rate],
                rateLabels: [.[].rateLabel],
                modes: [.[].mode]
              }
          )
        # Width desc, then height desc (so 1440x900 before 1280x1024)
        | sort_by(-.w, -.h)
      ) as $resolutions
    | {
        monitor: ($name[0] // ""),
        count: ($resolutions | length),
        resolutions: $resolutions
      }
  '
}

apply_mode() {
  local mode bitdepth lua out got_fmt got_w got_h got_r
  mode="$(normalize_mode "${1:-}")"
  bitdepth="${2:-$DEFAULT_BITDEPTH}"

  [[ -n "$mode" ]] || die "usage: monitor-mode.sh apply <mode> [bitdepth]"
  [[ "$mode" == *@* ]] || die "mode must look like WxH@rate (got: $mode)"
  case "$bitdepth" in
    8|10) ;;
    *) die "bitdepth must be 8 or 10 (got: $bitdepth)" ;;
  esac

  # Resolve actual monitor name from live state
  local mon_name
  mon_name="$(monitor_json | jq -r '.name // empty')"
  [[ -n "$mon_name" ]] || mon_name="$MONITOR"
  [[ "$mon_name" =~ ^[A-Za-z0-9_.-]+$ ]] || die "refusing monitor name"

  # cm=srgb: Hyprland "auto" maps 10-bit to wide/BT2020, which fringes
  # Quickshell anti-aliased icons. Known-good 10-bit is sRGB primaries.
  lua=$(printf \
    'hl.monitor({ output = "%s", mode = "%s", position = "%s", scale = %s, bitdepth = %s, cm = "srgb" })' \
    "$mon_name" "$mode" "$POSITION" "$SCALE" "$bitdepth")

  if ! out="$(hyprctl eval "$lua" 2>&1)"; then
    die "hyprctl eval failed: $out"
  fi
  if [[ "$out" != "ok" && "$out" != *"ok"* ]]; then
    # Retry without bitdepth as last resort
    lua=$(printf \
      'hl.monitor({ output = "%s", mode = "%s", position = "%s", scale = %s })' \
      "$mon_name" "$mode" "$POSITION" "$SCALE")
    out="$(hyprctl eval "$lua" 2>&1)" || die "hyprctl eval failed: $out"
    if [[ "$out" != "ok" && "$out" != *"ok"* ]]; then
      die "hyprctl eval rejected mode $mode: $out"
    fi
  fi

  # Settle so status / format reflects the new mode
  sleep 0.25

  # Soft-verify format
  if command -v jq >/dev/null 2>&1; then
    got_fmt="$(hyprctl monitors -j 2>/dev/null | jq -r --arg n "$mon_name" \
      '(map(select(.name==$n))|.[0]) // .[0] | .currentFormat // "?"')"
    if [[ "$bitdepth" == "8" && "$got_fmt" == *2101010* ]]; then
      printf 'warning: requested 8-bit but format is still %s\n' "$got_fmt" >&2
    fi
    if [[ "$bitdepth" == "10" && "$got_fmt" == *8888* ]]; then
      printf 'warning: requested 10-bit but format is %s\n' "$got_fmt" >&2
    fi
  fi

  # Persist so the mode survives reboot / hyprctl reload (Hyprland Lua config)
  persist_monitors_lua "$mon_name" "$mode" "$bitdepth" || true

  # Print status for callers
  status_json
}

# Rewrite ~/.config/hypr/config/monitors.lua (or create it) with the applied mode.
# Keeps cm = "srgb" (not auto: 10-bit auto → wide/BT2020, fringes Qt UI) and scale 1.0.
persist_monitors_lua() {
  local mon_name="$1" mode="$2" bitdepth="$3"
  local conf_dir conf bak tmp
  conf_dir="${HYPR_MONITORS_LUA_DIR:-$HOME/.config/hypr/config}"
  conf="${HYPR_MONITORS_LUA:-$conf_dir/monitors.lua}"

  [[ "$mon_name" =~ ^[A-Za-z0-9_.-]+$ ]] || return 1
  [[ "$mode" =~ ^[0-9]+x[0-9]+@[0-9]+([.][0-9]+)?$ ]] || return 1
  [[ "$bitdepth" == "8" || "$bitdepth" == "10" ]] || return 1

  # Follow a symlink and replace the real file. The temp file is created
  # in that file's directory so mv is atomic and the link stays a link.
  if [[ -L "$conf" ]]; then
    conf="$(readlink -f -- "$conf")"
  fi

  mkdir -p "$(dirname "$conf")" 2>/dev/null || return 1

  if [[ -f "$conf" ]]; then
    bak="${conf}.bak-qs"
    cp -f "$conf" "$bak" 2>/dev/null || true
  fi

  # mode is WxH@rate — quote as string for Lua. Write aside, then replace.
  tmp="$(mktemp "${conf}.XXXXXX")"
  cat >"$tmp" <<EOF
-- ━━━━ Monitors ╺━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╸
--
-- Managed by Quickshell Display panel (scripts/monitor-mode.sh).
-- Last applied: $(date -Iseconds 2>/dev/null || date)
-- Manual edits are fine; the next Apply from the bar will rewrite this file.
--
-- See https://wiki.hypr.land/Configuring/Basics/Monitors/

hl.monitor({
    output   = "${mon_name}",
    mode     = "${mode}",
    position = "0x0",
    scale    = 1.0,
    bitdepth = ${bitdepth},
    cm = "srgb",
})
EOF
  mv -f "$tmp" "$conf"
}

usage() {
  cat <<'EOF'
monitor-mode.sh — Hyprland monitor modes for Quickshell SettingsPanel

  monitor-mode.sh status-json
  monitor-mode.sh list-json
  monitor-mode.sh apply <mode> [bitdepth]

  mode:     WxH@rate   e.g. 5120x1440@239.76  (Hz suffix optional)
  bitdepth: 8 or 10    (default 10)
  scale:    always 1.0

Env:
  HYPR_MONITOR           optional output; empty uses the focused output
  HYPR_MONITOR_BITDEPTH=10
EOF
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    status-json|status|--status)
      status_json
      ;;
    list-json|list|--list)
      list_json
      ;;
    apply|set)
      shift
      apply_mode "${1:-}" "${2:-}"
      ;;
    help|-h|--help|"")
      usage
      [[ -n "$cmd" ]] || exit 1
      ;;
    *)
      die "unknown command: $cmd (try: status-json | list-json | apply)"
      ;;
  esac
}

main "$@"
