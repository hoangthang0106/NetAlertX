#!/usr/bin/env bash
# IT-MANAGER: read-only preflight for ONE published port, 18894:18894.
set -Eeuo pipefail
PORT=18894
command -v ss >/dev/null || { echo 'ERROR: ss (iproute2) not installed' >&2; exit 2; }
echo "Host: $(hostname) | $(date -Is) | required TCP ${PORT}:${PORT}"
LISTENERS="$(ss -H -lnt | awk -v p=":${PORT}" '$4 ~ (p "$") {print}')"
if [ -n "$LISTENERS" ]; then
  echo 'BUSY: TCP/18894 has a listener on this host (inspect before deployment):'
  printf '%s\n' "$LISTENERS"
  if command -v docker >/dev/null; then docker ps --format 'table {{.Names}}\t{{.Ports}}' 2>/dev/null || true; fi
  exit 1
fi
echo 'FREE at this moment: TCP/18894; 18897 is NOT allocated by this stack.'
if command -v docker >/dev/null; then docker ps --format 'table {{.Names}}\t{{.Ports}}' 2>/dev/null || true; fi
