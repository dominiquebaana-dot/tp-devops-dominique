#!/bin/bash
# Défi TP 2.9 : Script de release automatisé (Test -> Build -> Scan Trivy -> Push)
set -euo pipefail

VERSION=${1:-1.0.0}
REGISTRY=${DOCKERHUB_ID:-localhost:5000}
IMAGE="${REGISTRY}/legeni-webapp"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../../../app-fil-rouge" && pwd)"
cd "$APP_DIR"

SHA="sha-$(git rev-parse --short HEAD 2>/dev/null || echo 'local')"

echo "=== 1. Exécution des tests unitaires et du linter (cible test) ==="
docker build --target test -t legeni-webapp:test .

echo "=== 2. Build de l'image de production ($IMAGE:$VERSION et $IMAGE:$SHA) ==="
docker build --build-arg APP_VERSION="$VERSION" -t "$IMAGE:$VERSION" -t "$IMAGE:$SHA" .

echo "=== 3. Scan de sécurité Trivy (Quality Gate : échec si CRITICAL corrigeable) ==="
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy_cache:/root/.cache \
  aquasec/trivy:0.57.1 image --severity CRITICAL --ignore-unfixed --exit-code 1 "$IMAGE:$VERSION"

echo "=== 4. Publication vers le registre ($REGISTRY) ==="
docker push "$IMAGE:$VERSION"
docker push "$IMAGE:$SHA"

echo "Release $VERSION ($SHA) publiée avec succès !"
