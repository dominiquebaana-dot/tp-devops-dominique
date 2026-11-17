#!/bin/bash
# TP 3.4 Étape 9 : Job Freestyle 'deploy' chaîné après 'artefact' (port 8099)
set -euo pipefail

DOCKERHUB_ID="${DOCKERHUB_ID:-localhost:5000}"
IMAGE_NAME="${IMAGE_NAME:-restaurant}"
PORT="${DEPLOY_PORT:-8099}"

docker rm -f restaurant-prod 2>/dev/null || true
docker run -d --name restaurant-prod -p "${PORT}:80" "${DOCKERHUB_ID}/${IMAGE_NAME}:latest"
for i in $(seq 1 15); do curl -sf "http://127.0.0.1:${PORT}/" >/dev/null && break; sleep 1; done
echo "✅ Site restaurant-prod actif sur http://localhost:${PORT} (HTTP $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:${PORT}/))"
