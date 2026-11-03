#!/usr/bin/env bash
# On-demand network detail collector (public IP, DNS).
# Privileged data (routing, latency, firewall, connections) lives in
# network-privileged-poller.sh and is refreshed manually from the Network tab.
set -u pipefail

NOW=$(date +%s)

# ---------- Public IP (short external lookup) ----------
public_ip=""
public_ip_error=""
for url in "https://api.ipify.org" "https://ifconfig.me/ip"; do
    if command -v curl >/dev/null 2>&1; then
        public_ip=$(curl -fsS --max-time 2 "$url" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "$public_ip" && "$public_ip" =~ ^[0-9a-fA-F:.]+$ ]]; then
            break
        fi
        public_ip=""
    fi
done
[[ -z "$public_ip" ]] && public_ip_error="lookup failed or offline"

# ---------- DNS resolution + cache ----------
dns_servers_json='[]'
dns_current=""
dns_link=""
dns_domain=""
dns_cache_json='{"cache_size":0,"cache_hits":0,"cache_misses":0,"transactions":0}'
if command -v resolvectl >/dev/null 2>&1; then
    dns_servers=()
    while IFS= read -r line; do
        case "$line" in
            Link\ *' ('*')')
                cur_link="${line#Link * (}"
                cur_link="${cur_link%)}"
                ;;
            *"Current DNS Server:"*)
                dns_current="${line#*Current DNS Server: }"
                dns_current="${dns_current%%#*}"
                dns_link="${cur_link:-}"
                ;;
            *"DNS Domain:"*)
                dns_domain="${line#*DNS Domain: }"
                ;;
            # Fallback DNS Servers matches here on purpose. resolvectl
            # prints that label, and those servers belong in this list.
            *"DNS Servers:"*)
                rest="${line#*DNS Servers: }"
                while read -r srv; do
                    srv="${srv%%#*}"
                    [[ -n "$srv" ]] && dns_servers+=("$srv")
                done < <(tr ' ' '\n' <<<"$rest")
                ;;
        esac
    done < <(resolvectl status 2>/dev/null || true)
    while read -r ip; do
        [[ -n "$ip" ]] && dns_servers+=("$ip")
    done < <(resolvectl status 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | awk '!seen[$0]++')
    if ((${#dns_servers[@]} > 0)); then
        dns_servers_json=$(printf '%s\n' "${dns_servers[@]}" | awk '!seen[$0]++' | head -16 \
            | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')
    fi
    stats_out=$(resolvectl statistics 2>/dev/null || true)
    if [[ -n "$stats_out" ]]; then
        cache_size=$(sed -n 's/^[[:space:]]*Current Cache Size:[[:space:]]*\([0-9]*\).*/\1/p' <<<"$stats_out" | head -1)
        cache_hits=$(sed -n 's/^[[:space:]]*Cache Hits:[[:space:]]*\([0-9]*\).*/\1/p' <<<"$stats_out" | head -1)
        cache_misses=$(sed -n 's/^[[:space:]]*Cache Misses:[[:space:]]*\([0-9]*\).*/\1/p' <<<"$stats_out" | head -1)
        transactions=$(sed -n 's/^[[:space:]]*Total Transactions:[[:space:]]*\([0-9]*\).*/\1/p' <<<"$stats_out" | head -1)
        dns_cache_json=$(jq -cn \
            --argjson cache_size "${cache_size:-0}" \
            --argjson cache_hits "${cache_hits:-0}" \
            --argjson cache_misses "${cache_misses:-0}" \
            --argjson transactions "${transactions:-0}" \
            '{cache_size: $cache_size, cache_hits: $cache_hits, cache_misses: $cache_misses, transactions: $transactions}')
    fi
fi
if [[ -z "$dns_servers_json" || "$dns_servers_json" == "[]" ]]; then
    dns_servers_json=$(grep -E '^nameserver ' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | head -16 \
        | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')
fi

dns_json=$(jq -cn \
    --argjson servers "$dns_servers_json" \
    --arg current "${dns_current:-}" \
    --arg link "${dns_link:-}" \
    --arg domain "${dns_domain:-}" \
    --argjson cache "$dns_cache_json" \
    '{servers: $servers, current: $current, link: $link, domain: $domain, cache: $cache}')

jq -cn \
    --argjson ts "$NOW" \
    --arg public_ip "$public_ip" \
    --arg public_ip_error "$public_ip_error" \
    --argjson dns "$dns_json" \
    '{
        timestamp: $ts,
        public_ip: $public_ip,
        public_ip_error: $public_ip_error,
        dns: $dns
    }'