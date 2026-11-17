#!/bin/bash
# ==============================================================================
# SCRIPT MAÎTRE TOUT-EN-UN : INSTALLATION + EXÉCUTION DE TOUS LES TPs JENKINS
# (TP 3.1 à TP 3.8) - 100% Déportable d'un PC à un autre
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOLUTIONS_DIR="$SCRIPT_DIR/solutions"
APP_DIR="$ROOT_DIR/app-fil-rouge"
JENKINS_DOCKER_DIR="$SCRIPT_DIR/jenkins-docker"
LOG_FILE="$SCRIPT_DIR/logs_execution_tp_jenkins.txt"

find "$SCRIPT_DIR" "$APP_DIR" -type f \( -name "*.sh" -o -name "Jenkinsfile*" -o -name "Dockerfile*" -o -name "*.yml" -o -name "*.txt" -o -name "*.py" -o -name "*.json" -o -name "*.md" \) -exec sed -i 's/\r$//' {} + 2>/dev/null || true
chmod +x "$SOLUTIONS_DIR"/*/*.sh "$APP_DIR/deploy/smoke-test.sh" 2>/dev/null || true

cleanup_tp_jenkins() {
    docker rm -f registry legeni_website restaurant-test restaurant-prod 2>/dev/null || true
}
trap cleanup_tp_jenkins EXIT

exec > >(tee "$LOG_FILE") 2>&1

echo "=============================================================================="
echo " DÉMARRAGE DU PARCOURS AUTOMATISÉ TP JENKINS ($(date))"
echo "=============================================================================="

# ------------------------------------------------------------------------------
# TP 3.1 : Construction et démarrage de l'image Jenkins personnalisée
# ------------------------------------------------------------------------------
echo ""
echo "=== [TP 3.1] Configuration du DOCKER_GID, build et démarrage de Jenkins ==="
cd "$JENKINS_DOCKER_DIR"
DOCKER_GID=$(stat -c %g /var/run/docker.sock 2>/dev/null || echo "999")
echo "DOCKER_GID=${DOCKER_GID}" > .env
cat .env

docker compose up -d --build
echo "Attente que Jenkins réponde sur http://localhost:8080 (jusqu'à 120s)..."
JENKINS_OK=0
for i in $(seq 1 60); do
    if curl -sf http://localhost:8080/login >/dev/null 2>&1; then
        JENKINS_OK=1
        break
    fi
    sleep 2
done
if [ "$JENKINS_OK" -ne 1 ]; then
    echo "❌ ERREUR : Jenkins n'a pas répondu sur http://localhost:8080 après 120s"
    docker compose logs jenkins 2>&1 || true
    exit 1
fi

echo "--- Vérification des outils à l'intérieur du conteneur Jenkins ---"
docker exec jenkins docker version --format 'Docker serveur : {{.Server.Version}}'
docker exec jenkins docker compose version
docker exec jenkins kubectl version --client
docker exec jenkins ansible --version | sed -n '1p'
docker exec jenkins id

if docker exec jenkins test -f /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null; then
    echo "Mot de passe initial Jenkins (http://localhost:8080) :"
    docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
fi

# ------------------------------------------------------------------------------
# TP 3.2, 3.3, 3.4 : Exécution automatisée des scripts de Build, Acceptance & Artefact
# ------------------------------------------------------------------------------
echo ""
echo "=== [TP 3.2 / 3.3 / 3.4] Exécution des scripts de Build, Test d'acceptance et Artefact ==="
WORK_RESTAURANT="/tmp/tp_jenkins_restaurant"
rm -rf "$WORK_RESTAURANT"
git clone --depth 1 https://github.com/Legeni07/restaurant.git "$WORK_RESTAURANT"
cd "$WORK_RESTAURANT"

echo "--- Exécution TP 3.2 (build_freestyle.sh + Défi) ---"
PORT=8092 NETTOYER=true bash "$SOLUTIONS_DIR/tp3.2/build_freestyle.sh"
docker rm -f legeni_website 2>/dev/null || true

echo "--- Exécution TP 3.3 (test_acceptance.sh + Défi performance < 500ms) ---"
bash "$SOLUTIONS_DIR/tp3.3/test_acceptance.sh"

echo "--- Exécution TP 3.4 (artefact_publish.sh + Défi Trivy) ---"
docker rm -f registry 2>/dev/null || true
docker run -d --name registry -p 5000:5000 registry:3
echo "Attente de disponibilité du registre local (max 30s)..."
REG_OK=0
for i in $(seq 1 30); do
    if curl -sf http://localhost:5000/v2/ >/dev/null 2>&1; then
        REG_OK=1
        break
    fi
    sleep 1
done
if [ "$REG_OK" -ne 1 ]; then
    echo "❌ ERREUR : Le registre local n'a pas répondu dans les 30s"
    docker logs registry 2>&1 || true
    exit 1
fi
DOCKERHUB_ID="localhost:5000" bash "$SOLUTIONS_DIR/tp3.4/artefact_publish.sh"
echo "--- Exécution TP 3.4 Étape 9 (chaînage deploy -> restaurant-prod sur :8099) ---"
DOCKERHUB_ID="localhost:5000" bash "$SOLUTIONS_DIR/tp3.4/deploy_freestyle.sh"
docker rm -f restaurant-prod
docker rm -f registry
rm -rf "$WORK_RESTAURANT"

# ------------------------------------------------------------------------------
# TP 3.5, 3.6, 3.7, 3.8 : Validation de bout en bout des étapes du Pipeline CI/CD
# ------------------------------------------------------------------------------
echo ""
echo "=== [TP 3.5 à 3.8] Exécution des étapes Qualité, Build, Déploiement Staging/Prod & Rollback ==="
cd "$APP_DIR"
export VERSION="1.0.1"
export IMAGE="legeni-webapp"

echo "--- 1. Contrôles qualité (Tests unitaires + Couverture >= 80% + Flake8 + Hadolint + Gitleaks) ---"
docker build --target test -t legeni-webapp:test .
docker run --rm -v "$APP_DIR:/app" -w /app python:3.12-slim sh -c \
  "pip install -q -r requirements.txt -r requirements-dev.txt && pytest -q --cov=app --cov-fail-under=80"
docker run --rm -i hadolint/hadolint:v2.12.0 < Dockerfile
docker run --rm -v "$APP_DIR:/src:ro" --entrypoint="" zricethezav/gitleaks:v8.21.2 \
  gitleaks detect --source /src --no-git --exit-code 1 && echo "✅ Gitleaks : 0 secret détecté"

echo "--- 2. Build & Scan Trivy de l'image applicative ($IMAGE:$VERSION) ---"
docker build --build-arg APP_VERSION="$VERSION" -t "$IMAGE:$VERSION" .
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy_cache:/root/.cache \
  aquasec/trivy:0.57.1 image --quiet --severity CRITICAL --ignore-unfixed --exit-code 1 "$IMAGE:$VERSION"
echo "✅ Trivy legeni-webapp:$VERSION OK (0 CRITICAL)"

echo "--- 3. Déploiement automatique en Staging (port 8081) + Smoke Test ---"
REDIS_PASSWORD="secret-staging" IMAGE_REF="$IMAGE:$VERSION" APP_ENV="staging" APP_COLOR="#bf8700" PORT=8081 \
    docker compose -f deploy/docker-compose.deploy.yml -p legeni-staging up -d --wait
bash ./deploy/smoke-test.sh legeni-staging "$VERSION"

echo "--- 4. Déploiement en Production (port 8082) + Smoke Test + Test Rollback ---"
REDIS_PASSWORD="secret-prod" IMAGE_REF="$IMAGE:$VERSION" APP_ENV="prod" APP_COLOR="#2da44e" PORT=8082 \
    docker compose -f deploy/docker-compose.deploy.yml -p legeni-prod up -d --wait
bash ./deploy/smoke-test.sh legeni-prod "$VERSION"

set +e
bash ./deploy/smoke-test.sh legeni-prod "9.9.9-bad"
BAD_RC=$?
set -e
echo "Échec smoke test volontaire détecté (code=$BAD_RC) -> Rollback vers $VERSION :"
REDIS_PASSWORD="secret-prod" IMAGE_REF="$IMAGE:$VERSION" APP_ENV="prod" APP_COLOR="#2da44e" PORT=8082 \
    docker compose -f deploy/docker-compose.deploy.yml -p legeni-prod up -d --wait
bash ./deploy/smoke-test.sh legeni-prod "$VERSION"

echo "--- 5. Nettoyage des stacks de test Staging & Prod ---"
REDIS_PASSWORD=dummy IMAGE_REF=dummy docker compose -f deploy/docker-compose.deploy.yml -p legeni-staging down -v
REDIS_PASSWORD=dummy IMAGE_REF=dummy docker compose -f deploy/docker-compose.deploy.yml -p legeni-prod down -v

echo ""
echo "=============================================================================="
echo " TOUS LES TPs JENKINS SONT CONFIGURÉS ET VÉRIFIÉS AVEC SUCCÈS !"
echo " Interface Jenkins active sur : http://localhost:8080"
echo " Compte-rendu complet : $SCRIPT_DIR/COMPTE_RENDU_TP_JENKINS.md"
echo "=============================================================================="
