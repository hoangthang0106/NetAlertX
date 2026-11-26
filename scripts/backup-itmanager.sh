#!/usr/bin/env bash
# IT-MANAGER volume snapshot; run on the Docker host with docker CLI.
set -Eeuo pipefail
BACKUP_DIR="${1:-/opt/it-manager/backups}"
mkdir -p "$BACKUP_DIR"
BACKUP_DIR="$(cd "$BACKUP_DIR" && pwd -P)"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
command -v docker >/dev/null || { echo "docker CLI missing" >&2; exit 1; }
get_volume() {
  docker inspect --format "{{range .Mounts}}{{if eq .Destination \"$2\"}}{{.Name}}{{end}}{{end}}" "$1"
}
NETALERTX_VOL="$(get_volume netalertx /data)"
PROMETHEUS_VOL="$(get_volume itmanager-prometheus /prometheus)"
GRAFANA_VOL="$(get_volume itmanager-grafana /var/lib/grafana)"
for vol in "$NETALERTX_VOL" "$PROMETHEUS_VOL" "$GRAFANA_VOL"; do
  [[ -n "$vol" ]] || { echo "Missing named volume" >&2; exit 1; }
  docker volume inspect "$vol" >/dev/null
done
RUNNING=()
resume() {
  for name in "${RUNNING[@]}"; do
    docker start "$name" >/dev/null || echo "Failed to restart $name" >&2
  done
}
trap resume EXIT
for name in netalertx itmanager-prometheus itmanager-grafana; do
  if [[ "$(docker inspect -f '{{.State.Running}}' "$name")" == true ]]; then
    docker stop "$name" >/dev/null
    RUNNING+=("$name")
  fi
done
save_volume() {
  local vol="$1" label="$2"
  echo "Backup $label: $vol"
  docker run --rm -v "$vol:/source:ro" -v "$BACKUP_DIR:/backup" alpine:3.21 \
    tar -czf "/backup/${RUN_ID}-${label}.tar.gz" -C /source .
}
save_volume "$NETALERTX_VOL" netalertx-data
save_volume "$PROMETHEUS_VOL" prometheus-history
save_volume "$GRAFANA_VOL" grafana-data
echo "Backup complete: $BACKUP_DIR"
