#!/usr/bin/env bash
set -euo pipefail
IMAGE="${1:?Provide image name as first argument}"
# Classroom version: image package must be PUBLIC in GHCR for anonymous docker pull.
case "$IMAGE" in ghcr.io/*:*) ;; *) echo "Invalid image reference" >&2; exit 1;; esac
NAME="${CONTAINER_NAME:-cloud-tasks-api}"
VOLUME="${DATA_VOLUME:-cloud-tasks-data}"
PORT="${HOST_PORT:-80}"

start() {
  docker run -d --name "$NAME" --restart unless-stopped -p "$PORT:8000" -v "$VOLUME:/data" -e DB_PATH=/data/tasks.db "$1"
}

healthy() {
  for i in $(seq 1 20); do
    if curl --fail --silent "http://127.0.0.1:$PORT/health" >/dev/null; then
      return 0
    fi
    sleep 2
  done
  return 1
}

OLD="$(docker inspect --format '{{.Config.Image}}' "$NAME" 2>/dev/null || true)"
docker volume create "$VOLUME" >/dev/null
if [ "${SKIP_PULL:-0}" != 1 ]; then
  docker pull "$IMAGE"
fi
# Make sure that port 80 is not occupied by a host web server.
docker rm -f "$NAME" >/dev/null 2>&1 || true
if start "$IMAGE" && healthy; then
  echo "Deploy succeeded: $IMAGE"
  exit 0
fi

echo "Deploy falhou, voltando para a versao anterior: $OLD"
docker logs "$NAME" >&2 || true
docker rm -f "$NAME" >/dev/null 2>&1 || true
if [ -n "$OLD" ] && [ "$OLD" != "$IMAGE" ]; then
  start "$OLD" && healthy && echo "Rollback ok: $OLD"
fi
exit 1
