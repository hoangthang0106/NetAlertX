#!/usr/bin/env bash
# IT-MANAGER: backup NetAlertX persistent /data named volume.
# Temporarily stop and restart only netalertx (if running); other apps untouched.
set -Eeuo pipefail
BACKUP_DIR="${1:-/opt/it-manager/backups}"
command -v docker >/dev/null || { echo 'docker CLI missing' >&2; exit 2; }
docker inspect netalertx >/dev/null
VOL="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}' netalertx)"
if [ -z "$VOL" ]; then echo 'No named volume mounted at /data; aborting' >&2; exit 2; fi
docker volume inspect "$VOL" >/dev/null
mkdir -p "$BACKUP_DIR"
BACKUP_DIR="$(cd "$BACKUP_DIR" && pwd -P)"
WAS_RUNNING="$(docker inspect --format '{{.State.Running}}' netalertx)"
restart_if_needed() {
  if [ "$WAS_RUNNING" = true ]; then docker start netalertx >/dev/null || echo 'Warning: could not restart netalertx' >&2; fi
}
trap restart_if_needed EXIT
if [ "$WAS_RUNNING" = true ]; then docker stop netalertx >/dev/null; fi
STAMP="$(date +%Y%m%d-%H%M%S)"
docker run --rm -v "$VOL:/source:ro" -v "$BACKUP_DIR:/backup" alpine:3.21 \
  tar -czf "/backup/${STAMP}-netalertx-data.tar.gz" -C /source .
echo "Saved $BACKUP_DIR/${STAMP}-netalertx-data.tar.gz"
