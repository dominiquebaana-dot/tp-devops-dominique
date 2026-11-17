#!/bin/bash
# TP 3.3 : Script complet du Job "test-acceptance" + Solution du Défi (Temps moyen < 500 ms)
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-restaurant}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
TEST="${IMAGE_NAME}-test"

cat > Dockerfile <<'EOF'
FROM nginx:alpine
COPY . /usr/share/nginx/html/
EXPOSE 80
EOF
printf '.git\nDockerfile\n' > .dockerignore
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .

docker rm -f "${TEST}" 2>/dev/null || true

# Si le script s'exécute à l'intérieur du conteneur Jenkins, on attache au réseau de Jenkins.
# S'il s'exécute directement sur l'hôte, on publie le port localement.
if [ -f /.dockerenv ] && docker inspect jenkins >/dev/null 2>&1; then
    JENKINS_NET=$(docker inspect jenkins -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' | awk '{print $1}')
    docker run -d --name "${TEST}" --network "${JENKINS_NET}" "${IMAGE_NAME}:${IMAGE_TAG}"
    TARGET_URL="http://${TEST}"
else
    docker run -d --name "${TEST}" -p 18093:80 "${IMAGE_NAME}:${IMAGE_TAG}"
    TARGET_URL="http://127.0.0.1:18093"
fi

# Attendre que nginx accepte les connexions (au plus 15 s)
for i in $(seq 1 15); do curl -sf "${TARGET_URL}/" >/dev/null && break; sleep 1; done

echo "=== 1. Vérification du titre de la page d'accueil ==="
curl -sf "${TARGET_URL}/" | grep -qi "<title>Restaurant" && echo "✅ titre OK"

echo "=== 2. Vérification d'une ressource statique ==="
curl -sf -o /dev/null -w "%{http_code} %{content_type}\n" "${TARGET_URL}/1.jpg" || true

echo "=== 3. Vérification du code 404 sur une page inexistante ==="
test "$(curl -s -o /dev/null -w '%{http_code}' "${TARGET_URL}/nexiste-pas")" = "404" && echo "✅ 404 OK"

echo "=== 4. Défi TP 3.3 : Test de performance (moyenne de 10 requêtes < 500 ms) ==="
TEMPS=$(for i in $(seq 1 10); do curl -s -o /dev/null -w '%{time_total}\n' "${TARGET_URL}/"; done)
MOY=$(echo "$TEMPS" | awk '{s+=$1} END {printf "%.3f", s/NR}')
echo "Temps moyen : ${MOY} s"
awk -v m="$MOY" 'BEGIN { exit !(m < 0.5) }' && echo "✅ Performance OK (< 0.5s)" || { echo "❌ trop lent"; docker rm -f "${TEST}"; exit 1; }

docker rm -f "${TEST}"
