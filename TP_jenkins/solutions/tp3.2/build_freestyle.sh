#!/bin/bash
# TP 3.2 : Script du Job Freestyle "build" + Solution du Défi (PORT et NETTOYER)
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-restaurant}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
GIT_COMMIT="${GIT_COMMIT:-local00}"
WORKSPACE="${WORKSPACE:-$(pwd)}"
PORT="${PORT:-8092}"
NETTOYER="${NETTOYER:-true}"

echo "== Build n°${BUILD_NUMBER} du commit ${GIT_COMMIT:0:7} dans ${WORKSPACE}"

cat > Dockerfile <<'EOF'
FROM nginx:1.27-alpine
LABEL maintainer="Legeni"
COPY . /usr/share/nginx/html/
EXPOSE 80
EOF
printf '.git\nDockerfile\n' > .dockerignore

docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" -t "${IMAGE_NAME}:build-${BUILD_NUMBER}" .
docker images "${IMAGE_NAME}"

# Relancer le conteneur de manière idempotente
docker rm -f legeni_website 2>/dev/null || true
docker run --name legeni_website -d -p "${PORT}:80" "${IMAGE_NAME}:${IMAGE_TAG}"
docker ps --filter name=legeni_website

# Défi TP 3.2 : Supprimer les images restaurant:build-* sauf les 3 plus récentes
if [ "${NETTOYER}" = "true" ]; then
  echo "== Nettoyage des anciennes images build-* (conservation des 3 plus récentes) =="
  docker images "${IMAGE_NAME}" --format '{{.Tag}}' | grep '^build-' | sort -t- -k2 -n -r | tail -n +4 \
    | xargs -r -I{} docker rmi "${IMAGE_NAME}:{}"
fi
