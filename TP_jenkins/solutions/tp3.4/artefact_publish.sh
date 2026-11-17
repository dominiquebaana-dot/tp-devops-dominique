#!/bin/bash
# TP 3.4 : Build avec tag unique traçable + Tests d'acceptance + Défi Scan Trivy + Push
set -euo pipefail

DOCKERHUB_ID="${DOCKERHUB_ID:-localhost:5000}"
IMAGE_NAME="${IMAGE_NAME:-restaurant}"
IMAGE_TAG="${IMAGE_TAG:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
GIT_COMMIT="${GIT_COMMIT:-$(git rev-parse HEAD 2>/dev/null || echo '0123456789abcdef')}"

IMAGE="${DOCKERHUB_ID}/${IMAGE_NAME}"
UNIQUE_TAG="${IMAGE_TAG}.${BUILD_NUMBER}-${GIT_COMMIT:0:7}"
TEST_C="${IMAGE_NAME}-artefact-test"

cleanup() {
    docker rm -f "${TEST_C}" 2>/dev/null || true
}
trap cleanup EXIT

echo "=== 1. Build de l'image traçable ${IMAGE}:${UNIQUE_TAG} ==="
cat > Dockerfile <<'EOF'
FROM nginx:1.27-alpine
RUN apk upgrade --no-cache
COPY . /usr/share/nginx/html/
EXPOSE 80
EOF
printf '.git\nDockerfile\n' > .dockerignore

docker build --label "org.opencontainers.image.revision=${GIT_COMMIT}" \
             -t "${IMAGE}:${UNIQUE_TAG}" -t "${IMAGE_NAME}:${IMAGE_TAG}" .

echo "${UNIQUE_TAG}" > tag.txt
echo "Tag généré et enregistré dans tag.txt : ${UNIQUE_TAG}"

echo "=== 2. Tests d'acceptance avant publication ==="
if [ -f /.dockerenv ] && docker inspect jenkins >/dev/null 2>&1; then
    JENKINS_NET=$(docker inspect jenkins -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' | awk '{print $1}')
    docker run -d --name "${TEST_C}" --network "${JENKINS_NET}" "${IMAGE}:${UNIQUE_TAG}"
    TARGET_URL="http://${TEST_C}"
else
    docker run -d --name "${TEST_C}" -p 18094:80 "${IMAGE}:${UNIQUE_TAG}"
    TARGET_URL="http://127.0.0.1:18094"
fi
for i in $(seq 1 15); do curl -sf "${TARGET_URL}/" >/dev/null && break; sleep 1; done
curl -sf "${TARGET_URL}/" | grep -qi "<title>Restaurant" && echo "✅ titre OK"
test "$(curl -s -o /dev/null -w '%{http_code}' "${TARGET_URL}/nexiste-pas")" = "404" && echo "✅ 404 OK"
docker rm -f "${TEST_C}"

echo "=== 3. Défi TP 3.4 : Scan de sécurité Trivy avant publication ==="
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy_cache:/root/.cache \
  aquasec/trivy:0.57.1 image --quiet --severity CRITICAL --ignore-unfixed --exit-code 1 \
  "${IMAGE}:${UNIQUE_TAG}"
echo "✅ Scan Trivy OK (0 vulnérabilité CRITICAL corrigeable)"

echo "=== 4. Publication vers le registre (${DOCKERHUB_ID}) ==="
if [ -n "${DOCKERHUB_TOKEN:-}" ] && [ -n "${DOCKERHUB_USER:-}" ]; then
    echo "${DOCKERHUB_TOKEN}" | docker login -u "${DOCKERHUB_USER}" --password-stdin
fi

docker push "${IMAGE}:${UNIQUE_TAG}" || echo "Info: Push ignoré si non connecté au registre distant"
docker tag "${IMAGE}:${UNIQUE_TAG}" "${IMAGE}:latest"
docker push "${IMAGE}:latest" || true
