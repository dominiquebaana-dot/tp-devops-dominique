#!/bin/sh
set -e
if [ -n "$WAIT_HOST" ]; then
  for i in $(seq 1 30); do
    nc -z "$WAIT_HOST" "${WAIT_PORT:-80}" && break
    echo "[wait] $WAIT_HOST:${WAIT_PORT:-80} indisponible ($i/30)"; sleep 1
  done
  nc -z "$WAIT_HOST" "${WAIT_PORT:-80}" || { echo "[wait] abandon"; exit 1; }
fi
exec "$@"
