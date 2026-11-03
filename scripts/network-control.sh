#!/usr/bin/env bash
# NetworkManager helpers for the Quickshell network panel.
# Emits JSON on stdout for status; other actions print {"ok":true|false,...}.
set -euo pipefail

ACTION="${1:-}"
ARG1="${2:-}"
ARG2="${3:-}"

usage() {
    cat >&2 <<'EOF'
usage: network-control.sh status
       network-control.sh networking on|off|toggle
       network-control.sh wifi on|off|toggle
       network-control.sh radio all on|off
       network-control.sh wifi-rescan
       network-control.sh wifi-hidden <ssid> [password]
       network-control.sh device disconnect <iface>
       network-control.sh device connect <iface>
       network-control.sh connection up <uuid|name>
       network-control.sh connection down <uuid|name>
       network-control.sh connection delete <uuid|name>
       network-control.sh refresh-ip [iface]
       network-control.sh refresh-dns [iface]
EOF
}

RATE_STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/quickshell-network"
RATE_STATE_FILE="${RATE_STATE_DIR}/rates.state"

json_esc() {
    local s="${1:-}"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    printf '%s' "$s"
}

ok_json() {
    local msg="${1:-}"
    if [[ -n "$msg" ]]; then
        printf '{"ok":true,"message":"%s"}\n' "$(json_esc "$msg")"
    else
        printf '{"ok":true}\n'
    fi
}

err_json() {
    local msg="${1:-error}"
    printf '{"ok":false,"error":"%s"}\n' "$(json_esc "$msg")"
    return 1
}

need_nmcli() {
    command -v nmcli >/dev/null 2>&1 || { err_json "nmcli not found"; exit 1; }
}

# Sum interface byte counters (skip lo)
iface_byte_totals() {
    local total_rx=0 total_tx=0
    local iface rx tx
    for iface in /sys/class/net/*; do
        iface=$(basename "$iface")
        [[ "$iface" == "lo" ]] && continue
        rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)
        tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)
        [[ "$rx" =~ ^[0-9]+$ ]] || rx=0
        [[ "$tx" =~ ^[0-9]+$ ]] || tx=0
        total_rx=$((total_rx + rx))
        total_tx=$((total_tx + tx))
    done
    printf '%s %s' "$total_rx" "$total_tx"
}

# Compute rx/tx bytes-per-second from previous status call (runtime state file).
compute_rates() {
    local now rx tx prev_ts=0 prev_rx=0 prev_tx=0
    local rx_rate=0 tx_rate=0
    now=$(date +%s%3N 2>/dev/null || echo "$(date +%s)000")
    # Fallback if %3N unsupported
    if [[ ! "$now" =~ ^[0-9]+$ ]]; then
        now=$(($(date +%s) * 1000))
    fi
    read -r rx tx <<<"$(iface_byte_totals)"

    mkdir -p "$RATE_STATE_DIR" 2>/dev/null || true
    if [[ -f "$RATE_STATE_FILE" ]]; then
        # format: ts_ms rx tx
        read -r prev_ts prev_rx prev_tx <"$RATE_STATE_FILE" || true
    fi
    printf '%s %s %s\n' "$now" "$rx" "$tx" >"$RATE_STATE_FILE" 2>/dev/null || true

    if [[ "$prev_ts" =~ ^[0-9]+$ && "$prev_rx" =~ ^[0-9]+$ && "$prev_tx" =~ ^[0-9]+$ ]]; then
        local dt_ms=$((now - prev_ts))
        if (( dt_ms > 200 && dt_ms < 60000 )); then
            local drx=$((rx - prev_rx))
            local dtx=$((tx - prev_tx))
            (( drx < 0 )) && drx=0
            (( dtx < 0 )) && dtx=0
            # bytes/sec
            rx_rate=$(awk -v d="$drx" -v t="$dt_ms" 'BEGIN { printf "%.0f", d * 1000 / t }')
            tx_rate=$(awk -v d="$dtx" -v t="$dt_ms" 'BEGIN { printf "%.0f", d * 1000 / t }')
        fi
    fi
    printf '%s %s %s %s' "$rx_rate" "$tx_rate" "$rx" "$tx"
}

resolve_iface() {
    local want="${1:-}"
    if [[ -n "$want" ]]; then
        printf '%s' "$want"
        return
    fi
    # Prefer first connected non-lo device
    nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null \
        | awk -F: '$1 != "lo" && $2 != "loopback" && $3 ~ /connected/ { print $1; exit }'
}

cmd_refresh_ip() {
    need_nmcli
    local iface
    iface=$(resolve_iface "${1:-}")
    [[ -n "$iface" ]] || { err_json "no interface to reapply"; exit 1; }
    # Reapply connection settings (renews DHCP lease without full disconnect when possible)
    # Quiet stdout so callers only see JSON
    if nmcli device reapply "$iface" >/dev/null 2>&1; then
        ok_json "reapplied $iface"
        return
    fi
    # Fallback: bounce active connection on this iface
    local uuid
    uuid=$(nmcli -t -f GENERAL.CON-UUID device show "$iface" 2>/dev/null | sed -n 's/^GENERAL.CON-UUID://p' | head -1)
    if [[ -n "$uuid" && "$uuid" != "--" ]]; then
        nmcli connection up "$uuid" >/dev/null 2>&1 && ok_json "reactivated $iface" || err_json "refresh IP failed"
        return
    fi
    err_json "refresh IP failed for $iface"
}

cmd_refresh_dns() {
    local iface
    iface=$(resolve_iface "${1:-}")
    local ok=0
    if command -v resolvectl >/dev/null 2>&1; then
        if resolvectl flush-caches 2>/dev/null; then
            ok=1
        fi
        # Reset statistics is harmless; reapply pushes NM DNS into resolved again
        resolvectl reset-statistics 2>/dev/null || true
    fi
    if command -v nmcli >/dev/null 2>&1 && [[ -n "$iface" ]]; then
        # Re-apply connection so DNS servers are re-pushed without full disconnect
        nmcli device reapply "$iface" >/dev/null 2>&1 && ok=1 || true
    fi
    # Optional nscd hosts cache
    if command -v nscd >/dev/null 2>&1; then
        nscd -i hosts 2>/dev/null && ok=1 || true
    fi
    if (( ok )); then
        ok_json "dns refreshed${iface:+ ($iface)}"
    else
        err_json "dns refresh failed"
    fi
}

# Joined access point. Caller declares active_ap_* (bash locals are visible here).
# WIFI.SSID is not a valid `device show` field on this NetworkManager, so the
# SSID, frequency, rate, and signal come from the connection profile and this list.
# --rescan no keeps status from kicking a scan.
load_active_ap() {
    [[ "${active_ap_loaded:-0}" == "1" ]] && return 0
    active_ap_loaded=1
    local line
    line=$(nmcli -t -f IN-USE,SSID,FREQ,RATE,SIGNAL device wifi list --rescan no 2>/dev/null | grep -m1 '^\*' || true)
    [[ -z "$line" ]] && return 0
    # IN-USE is "*". Peel signal, rate, and freq from the right so an SSID
    # that contains an escaped colon (\:) stays intact.
    line="${line#\*:}"
    active_ap_signal="${line##*:}"
    line="${line%:*}"
    active_ap_rate="${line##*:}"
    line="${line%:*}"
    active_ap_freq="${line##*:}"
    line="${line%:*}"
    line="${line//\\:/:}"
    line="${line//\\\\/\\}"
    active_ap_ssid="$line"
    return 0
}

# ---------- status ----------
cmd_status() {
    need_nmcli

    local networking="false"
    local wifi_radio="false"
    local wifi_hw="false"
    local connectivity="unknown"
    local rx_rate=0 tx_rate=0 rx_bytes=0 tx_bytes=0
    read -r rx_rate tx_rate rx_bytes tx_bytes <<<"$(compute_rates)"

    local net_state
    net_state=$(nmcli -t networking 2>/dev/null | head -1 || true)
    [[ "$net_state" == "enabled" ]] && networking="true"

    local radio
    radio=$(nmcli -t -f WIFI,WIFI-HW radio 2>/dev/null | head -1 || true)
    # WIFI:WIFI-HW  e.g. enabled:enabled or disabled:enabled
    local wifi_part="${radio%%:*}"
    local hw_part="${radio#*:}"
    [[ "$wifi_part" == "enabled" ]] && wifi_radio="true"
    [[ "$hw_part" == "enabled" ]] && wifi_hw="true"

    connectivity=$(nmcli -t networking connectivity 2>/dev/null | head -1 || echo "unknown")
    connectivity=$(printf '%s' "$connectivity" | tr '[:upper:]' '[:lower:]')

    # Build device list (skip loopback)
    local devices_json='[]'
    local dev_lines=()
    mapfile -t dev_lines < <(nmcli -t -f DEVICE,TYPE,STATE,CONNECTION,CON-UUID device status 2>/dev/null || true)

    local dev_objs=()
    local line iface dtype state conn uuid
    local active_ap_ssid="" active_ap_freq="" active_ap_rate="" active_ap_signal=""
    local active_ap_loaded=0
    for line in "${dev_lines[@]}"; do
        [[ -z "$line" ]] && continue
        IFS=':' read -r iface dtype state conn uuid <<<"$line"
        [[ -z "$iface" || "$iface" == "lo" || "$dtype" == "loopback" ]] && continue

        # device show for details
        local show
        # GENERAL.MTU is valid. Do not add WIFI.SSID: this NM rejects it and
        # the whole device-show call fails.
        show=$(nmcli -t -f GENERAL.DEVICE,GENERAL.TYPE,GENERAL.STATE,GENERAL.CONNECTION,GENERAL.CON-UUID,GENERAL.HWADDR,GENERAL.NM-MANAGED,GENERAL.MTU,CAPABILITIES.SPEED,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP4.ROUTE,IP6.ADDRESS,IP6.GATEWAY,IP6.DNS device show "$iface" 2>/dev/null || true)

        local mac="" managed="true" speed_mbps=-1
        local -a ip4=() ip6=() dns=() routes4=()
        local gateway4="" gateway6=""
        local dev_rx=0 dev_tx=0
        local mtu="" duplex="" carrier="true" method4=""
        local wifi_ssid="" wifi_freq="" wifi_bitrate="" wifi_signal=""
        if [[ -r "/sys/class/net/$iface/statistics/rx_bytes" ]]; then
            dev_rx=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo 0)
            dev_tx=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo 0)
            [[ "$dev_rx" =~ ^[0-9]+$ ]] || dev_rx=0
            [[ "$dev_tx" =~ ^[0-9]+$ ]] || dev_tx=0
        fi

        while IFS= read -r sline; do
            case "$sline" in
                GENERAL.HWADDR:*)
                    mac="${sline#GENERAL.HWADDR:}"
                    ;;
                GENERAL.NM-MANAGED:*)
                    local m="${sline#GENERAL.NM-MANAGED:}"
                    [[ "$m" == "yes" ]] && managed="true" || managed="false"
                    ;;
                CAPABILITIES.SPEED:*)
                    local sp="${sline#CAPABILITIES.SPEED:}"
                    # "2500 Mb/s" or "unknown"
                    if [[ "$sp" =~ ^([0-9]+) ]]; then
                        speed_mbps="${BASH_REMATCH[1]}"
                    fi
                    ;;
                IP4.ADDRESS*)
                    ip4+=("${sline#*:}")
                    ;;
                IP4.GATEWAY:*)
                    gateway4="${sline#IP4.GATEWAY:}"
                    ;;
                IP4.DNS*)
                    dns+=("${sline#*:}")
                    ;;
                IP4.ROUTE*)
                    routes4+=("${sline#*:}")
                    ;;
                IP6.ADDRESS*)
                    ip6+=("${sline#*:}")
                    ;;
                IP6.GATEWAY:*)
                    gateway6="${sline#IP6.GATEWAY:}"
                    ;;
                IP6.DNS*)
                    dns+=("${sline#*:}")
                    ;;
                GENERAL.MTU:*)
                    mtu="${sline#GENERAL.MTU:}"
                    ;;
                WIRED-PROPERTIES.CARRIER:*)
                    if [[ "${sline#WIRED-PROPERTIES.CARRIER:}" == "on" ]]; then
                        carrier="true"
                    else
                        carrier="false"
                    fi
                    ;;
                WIFI.SSID:*)
                    wifi_ssid="${sline#WIFI.SSID:}"
                    ;;
                WIFI.FREQ:*)
                    wifi_freq="${sline#WIFI.FREQ:}"
                    ;;
                WIFI.BITRATE:*)
                    wifi_bitrate="${sline#WIFI.BITRATE:}"
                    ;;
                WIFI.SIGNAL:*)
                    wifi_signal="${sline#WIFI.SIGNAL:}"
                    ;;
            esac
        done <<<"$show"

        # Link facts NetworkManager does not always fill in (cable, duplex, speed).
        if [[ -r "/sys/class/net/$iface/carrier" ]]; then
            local cs
            cs=$(cat "/sys/class/net/$iface/carrier" 2>/dev/null || true)
            if [[ "$cs" == "0" ]]; then
                carrier="false"
            elif [[ "$cs" == "1" ]]; then
                carrier="true"
            fi
        fi
        if [[ -r "/sys/class/net/$iface/duplex" ]]; then
            duplex=$(cat "/sys/class/net/$iface/duplex" 2>/dev/null || true)
        fi
        if [[ "$speed_mbps" == "-1" && -r "/sys/class/net/$iface/speed" ]]; then
            local sps
            sps=$(cat "/sys/class/net/$iface/speed" 2>/dev/null || true)
            # 65535 is the sysfs "unknown" sentinel on some drivers.
            if [[ "$sps" =~ ^[0-9]+$ && "$sps" != "0" && "$sps" != "65535" ]]; then
                speed_mbps="$sps"
            fi
        fi
        if [[ -z "$mtu" && -r "/sys/class/net/$iface/mtu" ]]; then
            mtu=$(cat "/sys/class/net/$iface/mtu" 2>/dev/null || true)
        fi
        local mtu_num=0
        [[ "$mtu" =~ ^[0-9]+$ ]] && mtu_num="$mtu"

        # Prefer show fields when present
        local g_conn g_uuid g_state g_type
        g_conn=$(printf '%s\n' "$show" | sed -n 's/^GENERAL.CONNECTION://p' | head -1)
        g_uuid=$(printf '%s\n' "$show" | sed -n 's/^GENERAL.CON-UUID://p' | head -1)
        g_state=$(printf '%s\n' "$show" | sed -n 's/^GENERAL.STATE://p' | head -1)
        g_type=$(printf '%s\n' "$show" | sed -n 's/^GENERAL.TYPE://p' | head -1)
        [[ -n "$g_conn" && "$g_conn" != "--" ]] && conn="$g_conn"
        [[ -n "$g_uuid" && "$g_uuid" != "--" ]] && uuid="$g_uuid"
        [[ -n "$g_type" ]] && dtype="$g_type"
        # STATE looks like "100 (connected)" — keep human part when possible
        if [[ -n "$g_state" ]]; then
            if [[ "$g_state" =~ \((.+)\) ]]; then
                state="${BASH_REMATCH[1]}"
            else
                state="$g_state"
            fi
        fi
        # auto = DHCP, manual = static. Looked up after the UUID is finalized.
        if [[ -n "${uuid:-}" && "$uuid" != "--" ]]; then
            method4=$(nmcli -g ipv4.method connection show "$uuid" 2>/dev/null | head -1 || true)
        fi
        # Joined Wi-Fi: profile SSID, plus frequency / rate / signal of the
        # AP that is actually in use. Profile name and SSID are not always the same.
        if [[ "$dtype" == "wifi" || "$dtype" == "802-11-wireless" ]] && [[ "${state,,}" == connected* ]]; then
            load_active_ap
            if [[ -n "${uuid:-}" && "$uuid" != "--" ]]; then
                local prof_ssid
                prof_ssid=$(nmcli -g 802-11-wireless.ssid connection show "$uuid" 2>/dev/null | head -1 || true)
                if [[ -n "$prof_ssid" && "$prof_ssid" != "--" ]]; then
                    wifi_ssid="$prof_ssid"
                fi
            fi
            if [[ -z "$wifi_ssid" && -n "$active_ap_ssid" ]]; then
                if [[ -z "$conn" || "$conn" == "--" || "$conn" == "$active_ap_ssid" ]]; then
                    wifi_ssid="$active_ap_ssid"
                fi
            fi
            if [[ -n "$wifi_ssid" && "$wifi_ssid" == "$active_ap_ssid" ]]; then
                wifi_freq="$active_ap_freq"
                wifi_bitrate="$active_ap_rate"
                wifi_signal="$active_ap_signal"
            fi
        fi

        # JSON arrays via jq if available
        local ip4_json ip6_json dns_json routes_json
        if command -v jq >/dev/null 2>&1; then
            ip4_json=$(printf '%s\n' "${ip4[@]}" | jq -R -s 'split("\n") | map(select(length>0))')
            ip6_json=$(printf '%s\n' "${ip6[@]}" | jq -R -s 'split("\n") | map(select(length>0))')
            dns_json=$(printf '%s\n' "${dns[@]}" | jq -R -s 'split("\n") | map(select(length>0))')
            routes_json=$(printf '%s\n' "${routes4[@]}" | jq -R -s 'split("\n") | map(select(length>0))')
            dev_objs+=("$(jq -nc \
                --arg iface "$iface" \
                --arg type "$dtype" \
                --arg state "$state" \
                --arg connection "${conn:-}" \
                --arg uuid "${uuid:-}" \
                --arg mac "$mac" \
                --argjson managed "$managed" \
                --argjson speed_mbps "$speed_mbps" \
                --argjson ip4 "$ip4_json" \
                --argjson ip6 "$ip6_json" \
                --arg gateway4 "$gateway4" \
                --arg gateway6 "$gateway6" \
                --argjson dns "$dns_json" \
                --argjson routes4 "$routes_json" \
                --argjson rx_bytes "$dev_rx" \
                --argjson tx_bytes "$dev_tx" \
                --arg duplex "$duplex" \
                --argjson carrier "$carrier" \
                --arg method4 "$method4" \
                --argjson mtu "$mtu_num" \
                --arg wifi_ssid "$wifi_ssid" \
                --arg wifi_freq "$wifi_freq" \
                --arg wifi_bitrate "$wifi_bitrate" \
                --arg wifi_signal "$wifi_signal" \
                '{
                    iface: $iface,
                    type: $type,
                    state: $state,
                    connection: $connection,
                    uuid: $uuid,
                    mac: $mac,
                    managed: $managed,
                    speed_mbps: $speed_mbps,
                    ip4: $ip4,
                    ip6: $ip6,
                    gateway4: $gateway4,
                    gateway6: $gateway6,
                    dns: $dns,
                    routes4: $routes4,
                    rx_bytes: $rx_bytes,
                    tx_bytes: $tx_bytes,
                    duplex: $duplex,
                    carrier: $carrier,
                    method4: $method4,
                    mtu: $mtu,
                    wifi_ssid: $wifi_ssid,
                    wifi_freq: $wifi_freq,
                    wifi_bitrate: $wifi_bitrate,
                    wifi_signal: $wifi_signal
                }')")
        else
            # Minimal fallback without jq
            local ip4s="" d
            for d in "${ip4[@]}"; do
                [[ -n "$ip4s" ]] && ip4s+=","
                ip4s+="\"$(json_esc "$d")\""
            done
            dev_objs+=("{\"iface\":\"$(json_esc "$iface")\",\"type\":\"$(json_esc "$dtype")\",\"state\":\"$(json_esc "$state")\",\"connection\":\"$(json_esc "${conn:-}")\",\"uuid\":\"$(json_esc "${uuid:-}")\",\"mac\":\"$(json_esc "$mac")\",\"managed\":$managed,\"speed_mbps\":$speed_mbps,\"ip4\":[${ip4s}],\"ip6\":[],\"gateway4\":\"$(json_esc "$gateway4")\",\"gateway6\":\"$(json_esc "$gateway6")\",\"dns\":[],\"routes4\":[],\"mtu\":$mtu_num,\"wifi_ssid\":\"$(json_esc "$wifi_ssid")\",\"wifi_freq\":\"$(json_esc "$wifi_freq")\",\"wifi_bitrate\":\"$(json_esc "$wifi_bitrate")\",\"wifi_signal\":\"$(json_esc "$wifi_signal")\"}")
        fi
    done

    if command -v jq >/dev/null 2>&1; then
        if ((${#dev_objs[@]} > 0)); then
            devices_json=$(printf '%s\n' "${dev_objs[@]}" | jq -s '.')
        else
            devices_json='[]'
        fi

        # Active connections (non-lo)
        local ac_json
        ac_json=$(nmcli -t -f NAME,UUID,TYPE,DEVICE connection show --active 2>/dev/null \
            | jq -R -s '
                split("\n")
                | map(select(length>0))
                | map(split(":"))
                | map(select(length >= 4 and .[3] != "lo" and .[2] != "loopback"))
                | map({name: .[0], uuid: .[1], type: .[2], device: .[3]})
              ' 2>/dev/null || echo '[]')

        # All saved connection profiles (for dropdown) — skip loopback
        local connections_json
        connections_json=$(nmcli -t -f NAME,UUID,TYPE,DEVICE,ACTIVE connection show 2>/dev/null \
            | jq -R -s '
                split("\n")
                | map(select(length>0))
                | map(split(":"))
                | map(select(length >= 5 and .[2] != "loopback" and .[0] != "lo"))
                | map({
                    name: .[0],
                    uuid: .[1],
                    type: .[2],
                    device: (.[3] // ""),
                    active: (.[4] == "yes")
                  })
                | sort_by([(.active | not), .name])
              ' 2>/dev/null || echo '[]')

        jq -nc \
            --argjson networking "$networking" \
            --argjson wifi_radio "$wifi_radio" \
            --argjson wifi_hw "$wifi_hw" \
            --arg connectivity "$connectivity" \
            --argjson devices "$devices_json" \
            --argjson active_connections "$ac_json" \
            --argjson connections "$connections_json" \
            --argjson rx_rate "${rx_rate:-0}" \
            --argjson tx_rate "${tx_rate:-0}" \
            --argjson rx_bytes "${rx_bytes:-0}" \
            --argjson tx_bytes "${tx_bytes:-0}" \
            --argjson ts "$(date +%s)" \
            '{
                networking: $networking,
                wifi_radio: $wifi_radio,
                wifi_hw: $wifi_hw,
                connectivity: $connectivity,
                devices: $devices,
                active_connections: $active_connections,
                connections: $connections,
                rx_rate: $rx_rate,
                tx_rate: $tx_rate,
                rx_bytes: $rx_bytes,
                tx_bytes: $tx_bytes,
                timestamp: $ts
            }'
    else
        # Extremely minimal without jq. Join first so the device list stays
        # one quoted argument and does not shift the timestamp.
        local devices_csv=""
        if ((${#dev_objs[@]} > 0)); then
            devices_csv="$(IFS=,; echo "${dev_objs[*]}")"
        fi
        printf '{"networking":%s,"wifi_radio":%s,"wifi_hw":%s,"connectivity":"%s","devices":[%s],"active_connections":[],"timestamp":%s}\n' \
            "$networking" "$wifi_radio" "$wifi_hw" "$(json_esc "$connectivity")" \
            "$devices_csv" \
            "$(date +%s)"
    fi
}

# ---------- commands ----------
case "$ACTION" in
    status)
        cmd_status
        ;;
    networking)
        need_nmcli
        case "$ARG1" in
            on)  nmcli networking on  && ok_json "networking on" || err_json "failed to enable networking" ;;
            off) nmcli networking off && ok_json "networking off" || err_json "failed to disable networking" ;;
            toggle)
                if [[ "$(nmcli -t networking 2>/dev/null | head -1)" == "enabled" ]]; then
                    nmcli networking off && ok_json "networking off" || err_json "failed to disable networking"
                else
                    nmcli networking on && ok_json "networking on" || err_json "failed to enable networking"
                fi
                ;;
            *) usage; exit 2 ;;
        esac
        ;;
    wifi)
        need_nmcli
        case "$ARG1" in
            on)  nmcli radio wifi on  && ok_json "wifi on" || err_json "failed to enable wifi" ;;
            off) nmcli radio wifi off && ok_json "wifi off" || err_json "failed to disable wifi" ;;
            toggle)
                wr=$(nmcli -t -f WIFI radio 2>/dev/null | head -1 || true)
                if [[ "$wr" == "enabled" ]]; then
                    nmcli radio wifi off && ok_json "wifi off" || err_json "failed to disable wifi"
                else
                    nmcli radio wifi on && ok_json "wifi on" || err_json "failed to enable wifi"
                fi
                ;;
            *) usage; exit 2 ;;
        esac
        ;;
    device)
        need_nmcli
        case "$ARG1" in
            disconnect)
                [[ -n "$ARG2" ]] || { err_json "iface required"; exit 2; }
                nmcli device disconnect "$ARG2" && ok_json "disconnected $ARG2" || err_json "disconnect failed"
                ;;
            connect)
                [[ -n "$ARG2" ]] || { err_json "iface required"; exit 2; }
                nmcli device connect "$ARG2" && ok_json "connected $ARG2" || err_json "connect failed"
                ;;
            *) usage; exit 2 ;;
        esac
        ;;
    connection)
        need_nmcli
        case "$ARG1" in
            up)
                [[ -n "$ARG2" ]] || { err_json "uuid|name required"; exit 2; }
                nmcli connection up "$ARG2" >/dev/null 2>&1 && ok_json "connection up" || err_json "connection up failed"
                ;;
            down)
                [[ -n "$ARG2" ]] || { err_json "uuid|name required"; exit 2; }
                nmcli connection down "$ARG2" >/dev/null 2>&1 && ok_json "connection down" || err_json "connection down failed"
                ;;
            delete)
                [[ -n "$ARG2" ]] || { err_json "uuid|name required"; exit 2; }
                nmcli connection delete "$ARG2" >/dev/null 2>&1 && ok_json "connection deleted" || err_json "connection delete failed"
                ;;
            *) usage; exit 2 ;;
        esac
        ;;
    radio)
        need_nmcli
        case "$ARG1" in
            all)
                case "$ARG2" in
                    on)  nmcli radio all on  >/dev/null 2>&1 && ok_json "radios on"  || err_json "failed to enable radios" ;;
                    off) nmcli radio all off >/dev/null 2>&1 && ok_json "radios off" || err_json "failed to disable radios" ;;
                    *) usage; exit 2 ;;
                esac
                ;;
            *) usage; exit 2 ;;
        esac
        ;;
    wifi-rescan)
        need_nmcli
        nmcli device wifi rescan >/dev/null 2>&1 && ok_json "scan requested" || err_json "rescan failed"
        ;;
    wifi-hidden)
        need_nmcli
        [[ -n "$ARG1" ]] || { err_json "ssid required"; exit 2; }
        # ARG2 is the whole password (spaces stay inside one argument).
        if [[ -n "$ARG2" ]]; then
            msg=$(nmcli device wifi connect "$ARG1" password "$ARG2" hidden yes 2>&1) \
                && ok_json "connecting" || err_json "${msg:-hidden connect failed}"
        else
            msg=$(nmcli device wifi connect "$ARG1" hidden yes 2>&1) \
                && ok_json "connecting" || err_json "${msg:-hidden connect failed}"
        fi
        ;;
    refresh-ip)
        cmd_refresh_ip "${ARG1:-}"
        ;;
    refresh-dns)
        cmd_refresh_dns "${ARG1:-}"
        ;;
    ""|-h|--help|help)
        usage
        exit 0
        ;;
    *)
        usage
        exit 2
        ;;
esac
