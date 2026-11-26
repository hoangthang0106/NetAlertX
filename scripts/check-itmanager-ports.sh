#!/usr/bin/env bash
# IT-MANAGER read-only port preflight; run on the EXACT Docker/Portainer target host.
# Exit status 0 => no matching TCP LISTEN socket at snapshot time (NOT a reservation).
# Exit status 1 => likely collision. Does not stop, install, or modify anything.
set -Eeuo pipefail
command -v ss >/dev/null || { echo "ERROR: ss/iproute2 unavailable; cannot verify live listening ports" >&2; exit 2; }
LAN_IP="${1:-${LAN_IP:-}}"
API_PORT="${NETALERTX_API_PORT:-18900}"
if ! [[ "$API_PORT" =~ ^[0-9]+$ ]] || (( API_PORT < 1 || API_PORT > 65535 )); then echo "Invalid NETALERTX_API_PORT" >&2; exit 2; fi
echo "IT-MANAGER port check | host=$(hostname) | date=$(date -Is)"
echo "LAN_IP=${LAN_IP:-not specified; checking all IP bindings conservatively}"
echo "Scope: this Linux host only; another Proxmox VM/LXC or NAS needs its own check."
if [[ -n "$LAN_IP" ]] && command -v ip >/dev/null; then
  if ! ip -4 -o addr show | grep -Fq " $LAN_IP/"; then
    echo "ERROR: LAN_IP $LAN_IP does not appear on any IPv4 interface of this host." >&2; exit 2
  fi
fi
fail=0
check_tcp() {
  local name="$1" port="$2" bind="$3" all matching
  # Extract exact numerical LISTEN port from ss. Do NOT use remote TCP connect
  # to guess an unused Docker host port.
  all="$(ss -H -lnt | awk -v p=":$port" '$4 ~ (p "$") {print}')"
  if [[ -z "$all" ]]; then
    printf 'FREE* %-22s TCP/%-5s intended=%s\n' "$name" "$port" "$bind"
    return
  fi
  # If a specific bind IP was provided, allow sockets on OTHER specific IPs,
  # but treat 0.0.0.0, * and IPv6 wildcard as conflicts (conservative).
  if [[ -n "$LAN_IP" ]]; then
    matching="$(printf '%s\n' "$all" | awk -v port="$port" -v intended="$bind" '
      { a=$4; sub(":" port "$", "", a);
        if (a=="*" || a=="0.0.0.0" || a=="[::]" || a=="::" ||
            a==intended || a=="[" intended "]") print
      }')"
  else
    matching="$all"
  fi
  if [[ -n "$matching" ]]; then
    printf 'BUSY  %-22s TCP/%-5s intended=%s\n' "$name" "$port" "$bind"
    printf '%s\n' "$matching" | sed 's/^/    LISTENER /'
    fail=1
  else
    printf 'FREE* %-22s TCP/%-5s intended=%s (other-IP listener exists)\n' "$name" "$port" "$bind"
  fi
}
check_tcp 'NetAlertX Web' 18897 "${LAN_IP:-any}"
check_tcp 'NetAlertX GraphQL/API' "$API_PORT" any
check_tcp 'Grafana Web' 18899 "${LAN_IP:-any}"
check_tcp 'Prometheus local' 19090 127.0.0.1
check_tcp 'Socket proxy local' 2375 127.0.0.1
echo
echo "Reserved by the Social Analyzer fork: TCP/18898 (do not assign NetAlertX API here)."
echo "Listening snapshot (TCP ports 18889-18910, 19090, 2375):"
ss -H -lnt | awk '
 { p=$4; sub(/^.*:/,"",p);
   if (p ~ /^[0-9]+$/ && ((p>=18889 && p<=18910) || p==19090 || p==2375)) print
 }' || true
if command -v docker >/dev/null; then
  echo
  echo 'Running Docker published ports (same host only):'
  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || echo 'Docker CLI not accessible: verify Portainer Containers independently.'
fi
echo
if (( fail )); then
 echo 'RESULT: PORT CONFLICT - DO NOT DEPLOY until a target IP/port is changed and rechecked.'
 exit 1
fi
echo 'RESULT: NO COLLISION DETECTED at this instant on this host (not proof of future availability).'
