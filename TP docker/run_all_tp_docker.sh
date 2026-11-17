#!/bin/bash
# ==============================================================================
# SCRIPT MAÎTRE TOUT-EN-UN : INSTALLATION + EXÉCUTION DE TOUS LES TPs DOCKER
# (TP 2.2 à TP 2.10) - 100% Déportable d'un PC à un autre (Ubuntu / WSL2 / VM)
# ==============================================================================
# Usage :
#   bash "TP docker/run_all_tp_docker.sh"          # Exécute tout (TP 2.2 -> 2.10)
#   bash "TP docker/run_all_tp_docker.sh" 2.8      # Exécute uniquement le TP 2.8
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOLUTIONS_DIR="$SCRIPT_DIR/solutions"
APP_DIR="$ROOT_DIR/app-fil-rouge"
LOG_FILE="$SCRIPT_DIR/logs_execution_tp_docker.txt"
TARGET_TP="${1:-all}"

if [ "${_DOCKER_TP_INIT:-0}" = "0" ]; then
    find "$SCRIPT_DIR" "$APP_DIR" -type f \( -name "*.sh" -o -name "*.env*" -o -name "Dockerfile*" -o -name "*.yml" -o -name "*.conf" -o -name "*.py" -o -name "*.json" -o -name "*.md" \) -exec sed -i 's/\r$//' {} + 2>/dev/null || true
    chmod +x "$SOLUTIONS_DIR"/*/*.sh "$APP_DIR"/deploy/*.sh 2>/dev/null || true
fi

exec > >(tee "$LOG_FILE") 2>&1

echo "=============================================================================="
echo " DÉMARRAGE DU PARCOURS AUTOMATISÉ TP DOCKER ($(date))"
echo " Dossier racine : $ROOT_DIR"
echo " Fichier de traces : $LOG_FILE"
echo "=============================================================================="

# ------------------------------------------------------------------------------
# ÉTAPE PRÉLIMINAIRE : VÉRIFICATION & INSTALLATION AUTOMATIQUE DE DOCKER
# ------------------------------------------------------------------------------
ensure_docker_installed() {
    echo ""
    echo ">>> [VÉRIFICATION SYSTÈME] Contrôle de Docker Engine et Docker Compose..."
    if ! command -v docker >/dev/null 2>&1 || ! docker --version >/dev/null 2>&1; then
        echo "Docker n'est pas installé. Installation automatique en cours..."
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl gnupg lsb-release git
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL "https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg" | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
        sudo chmod 0644 /etc/apt/keyrings/docker.asc
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
          | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo systemctl enable --now docker 2>/dev/null || sudo service docker start 2>/dev/null || true
        sudo usermod -aG docker "$USER" || true
    fi

    if ! docker info >/dev/null 2>&1; then
        sudo systemctl start docker 2>/dev/null || sudo service docker start 2>/dev/null || true
        if [ "$(id -u)" -ne 0 ] && ! docker info >/dev/null 2>&1; then
            if getent group docker | grep -qw "$USER" && [ "${_DOCKER_TP_SG:-0}" = "0" ]; then
                export _DOCKER_TP_INIT=1
                export _DOCKER_TP_SG=1
                exec sg docker -c "bash \"$0\" \"$TARGET_TP\""
            fi
        fi
    fi

    docker --version
    docker compose version
}

ensure_webapp_image() {
    if ! docker image inspect legeni-webapp:1.0.0 >/dev/null 2>&1; then
        cd "$APP_DIR"
        docker build --build-arg APP_VERSION=1.0.0 -t legeni-webapp:1.0.0 .
    fi
}

# ------------------------------------------------------------------------------
# TP 2.2 : Installation, Cycle de vie & Stack Odoo
# ------------------------------------------------------------------------------
run_tp2_2() {
    echo ""
    echo "=============================================================================="
    echo " TP 2.2 : CYCLE DE VIE D'UN CONTENEUR & PREMIÈRE STACK COMPOSE"
    echo "=============================================================================="
    docker run --rm hello-world | sed -n '1,15p'

    docker rm -f web 2>/dev/null || true
    docker run -d --name web -p 8081:80 nginx:1.27-alpine
    until curl -sf http://localhost:8081 >/dev/null; do sleep 1; done
    curl -s http://localhost:8081 | sed -n '1,5p'
    docker inspect web --format 'Status={{.State.Status}} IP={{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'
    docker rm -f web

    echo "--- Validation et test de persistance Compose Odoo + PostgreSQL ---"
    docker compose -f "$SOLUTIONS_DIR/tp2.2/odoo-compose/compose.yml" config >/dev/null
    echo "compose.yml Odoo valide !"
    docker compose -f "$SOLUTIONS_DIR/tp2.2/odoo-compose/compose.yml" down -v 2>/dev/null || true
    docker compose -f "$SOLUTIONS_DIR/tp2.2/odoo-compose/compose.yml" up -d
    sleep 5
    docker compose -f "$SOLUTIONS_DIR/tp2.2/odoo-compose/compose.yml" ps
    docker compose -f "$SOLUTIONS_DIR/tp2.2/odoo-compose/compose.yml" down
    docker compose -f "$SOLUTIONS_DIR/tp2.2/odoo-compose/compose.yml" up -d
    docker compose -f "$SOLUTIONS_DIR/tp2.2/odoo-compose/compose.yml" ps
    docker compose -f "$SOLUTIONS_DIR/tp2.2/odoo-compose/compose.yml" down -v

    echo "--- Exécution du Défi TP 2.2 (Redis cache) ---"
    bash "$SOLUTIONS_DIR/tp2.2/defi_tp22.sh"
}

# ------------------------------------------------------------------------------
# TP 2.3 : Dockerfile, Image, Couches & Site Restaurant
# ------------------------------------------------------------------------------
run_tp2_3() {
    echo ""
    echo "=============================================================================="
    echo " TP 2.3 : DOCKERFILE (v1, v2, v3) & COUCHES D'IMAGES"
    echo "=============================================================================="
    cd "$SOLUTIONS_DIR/tp2.3"
    docker build -f Dockerfile -t legeni_static_website:v1 .
    docker build -f Dockerfile.v2 -t legeni_static_website:v2 .
    docker build -f Dockerfile.v3 --build-arg VERSION=v3 -t legeni_static_website:v3 .

    echo "--- Comparaison des tailles d'images (v1 vs v2 vs v3) ---"
    docker images legeni_static_website

    echo "--- Test du Défi TP 2.3 (injection dynamique de la version v3) ---"
    docker rm -f v3 2>/dev/null || true
    docker run -d --name v3 -p 8093:80 legeni_static_website:v3
    until curl -sf http://localhost:8093 >/dev/null; do sleep 1; done
    curl -s http://localhost:8093 | grep "Version :" || true
    docker rm -f v3
}

# ------------------------------------------------------------------------------
# TP 2.4 : Réseaux Bridge, Volumes Anonymes & Nommés, PostgreSQL persistant
# ------------------------------------------------------------------------------
run_tp2_4() {
    echo ""
    echo "=============================================================================="
    echo " TP 2.4 : RÉSEAUX BRIDGE, VOLUMES & PERSISTANCE POSTGRESQL"
    echo "=============================================================================="
    bash "$SOLUTIONS_DIR/tp2.4/tp24_reseaux_volumes.sh"
}

# ------------------------------------------------------------------------------
# TP 2.5 : Variables ARG/ENV, ENTRYPOINT/CMD, PID 1 & Signaux
# ------------------------------------------------------------------------------
run_tp2_5() {
    echo ""
    echo "=============================================================================="
    echo " TP 2.5 : CONFIGURATION PAR L'ENVIRONNEMENT, PID 1 & ENTRYPOINT"
    echo "=============================================================================="
    cd "$APP_DIR"
    docker build -t legeni-webapp:1.0.0 --build-arg APP_VERSION=1.0.0 .

    docker rm -f dev prod staging 2>/dev/null || true
    docker run -d --name dev  -p 5001:5000 legeni-webapp:1.0.0
    docker run -d --name prod -p 5002:5000 -e APP_ENV=prod -e APP_COLOR='#d1242f' legeni-webapp:1.0.0
    docker run -d --name staging -p 5003:5000 --env-file "$SOLUTIONS_DIR/tp2.5/staging.env" legeni-webapp:1.0.0
    until curl -sf http://localhost:5001/health >/dev/null && curl -sf http://localhost:5002/health >/dev/null && curl -sf http://localhost:5003/health >/dev/null; do sleep 1; done
    echo "Réponse dev     : $(curl -s http://localhost:5001/api/info)"
    echo "Réponse prod    : $(curl -s http://localhost:5002/api/info)"
    echo "Réponse staging : $(curl -s http://localhost:5003/api/info)"
    docker rm -f dev prod staging

    cd "$SOLUTIONS_DIR/tp2.5"
    docker build -f Dockerfile.args --build-arg BUILD_VERSION=2.0 -t demo:args .
    docker run --rm demo:args
    docker run --rm -e APP_MESSAGE="Salut" demo:args

    docker build -f Dockerfile.cmd   -t demo:cmd .
    docker build -f Dockerfile.entry -t demo:entry .
    docker run --rm demo:entry "mon argument"

    docker build -f Dockerfile.shell -t demo:shell .
    docker run -d --name shell_pid demo:shell
    sleep 1
    echo "Arrêt demo:shell (forme shell -> SIGKILL ~10s) :"
    time docker stop shell_pid
    docker rm -f shell_pid

    docker build -f Dockerfile.exec -t demo:exec .
    docker run -d --name exec demo:exec
    sleep 1
    echo "Arrêt demo:exec (forme exec -> SIGTERM ~1s) :"
    time docker stop exec
    docker logs exec
    docker rm -f exec

    docker build -f Dockerfile.nginx -t demo:entrypoint .
    docker run -d --name ep -p 8095:80 -e APP_ENV=staging demo:entrypoint
    until curl -sf http://localhost:8095 >/dev/null; do sleep 1; done
    curl -s http://localhost:8095
    docker rm -f ep

    echo "--- Défi TP 2.5 : Image demo:wait (attente active de disponibilité réseau) ---"
    docker build -f Dockerfile.wait -t demo:wait .
    docker network rm tp25 2>/dev/null || true
    docker network create tp25
    docker rm -f redis_tp25 2>/dev/null || true
    (sleep 3 && docker run -d --name redis_tp25 --network tp25 redis:7.4-alpine >/dev/null) &
    BG_PID=$!
    docker run --rm --network tp25 -e WAIT_HOST=redis_tp25 -e WAIT_PORT=6379 demo:wait echo "Redis est prêt !"
    wait "$BG_PID" || true
    docker rm -f redis_tp25 && docker network rm tp25
    docker rmi demo:args demo:cmd demo:entry demo:shell demo:exec demo:entrypoint demo:wait 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# TP 2.6 : Dockerfile avancé (Multi-stage, Tests dans le build, Non-root, Healthcheck)
# ------------------------------------------------------------------------------
run_tp2_6() {
    echo ""
    echo "=============================================================================="
    echo " TP 2.6 : DOCKERFILE AVANCÉ, MULTI-STAGE, NON-ROOT & HEALTHCHECK"
    echo "=============================================================================="
    cd "$APP_DIR"
    echo "--- Exécution de la cible 'test' (flake8 + pytest) & comparaison de tailles ---"
    docker build --target test -t legeni-webapp:test .
    docker build --build-arg APP_VERSION=1.0.0 -t legeni-webapp:1.0.0 .
    docker images legeni-webapp

    echo "--- Expérience .dockerignore (réduction du contexte de 200 Mo -> quelques Ko) ---"
    TMP_CTX="/tmp/tp26_ctx_ignore"
    rm -rf "$TMP_CTX" && cp -r "$APP_DIR" "$TMP_CTX"
    dd if=/dev/zero of="$TMP_CTX/gros_fichier.bin" bs=1M count=50 status=none
    docker build --no-cache -t legeni-webapp:ctx-before "$TMP_CTX" 2>&1 | grep -i "transferring context" || true
    echo "gros_fichier.bin" >> "$TMP_CTX/.dockerignore"
    docker build --no-cache -t legeni-webapp:ctx-after "$TMP_CTX" 2>&1 | grep -i "transferring context" || true
    docker rmi legeni-webapp:ctx-before legeni-webapp:ctx-after 2>/dev/null || true

    echo "--- Test volontairement cassé (--target test doit échouer) ---"
    sed -i 's/status="ok"/status="ko"/' "$TMP_CTX/app.py"
    if docker build --target test "$TMP_CTX" >/dev/null 2>&1; then
        echo "❌ ERREUR : le build --target test aurait dû échouer !"
        exit 1
    else
        echo "✅ OK : --target test a bien bloqué le build sur test cassé."
    fi
    rm -rf "$TMP_CTX"

    echo "--- Vérification de l'utilisateur non-root ---"
    docker run --rm legeni-webapp:1.0.0 id

    echo "--- Vérification du HEALTHCHECK ---"
    docker rm -f webapp 2>/dev/null || true
    docker run -d --name webapp -p 5000:5000 legeni-webapp:1.0.0
    for i in $(seq 1 20); do
        STATUS=$(docker inspect -f '{{.State.Health.Status}}' webapp 2>/dev/null || echo "starting")
        [ "$STATUS" = "healthy" ] && break
        sleep 2
    done
    docker ps --filter name=webapp
    docker rm -f webapp

    echo "--- Comparaison restaurant:ubuntu vs restaurant:alpine (single-stage) vs Défi multistage ---"
    docker build -f "$SOLUTIONS_DIR/tp2.3/Dockerfile" -t restaurant:ubuntu "$SOLUTIONS_DIR/tp2.3"
    docker history restaurant:ubuntu
    TMP_REST="/tmp/tp26_restaurant_ctx"
    rm -rf "$TMP_REST" && mkdir -p "$TMP_REST"
    git clone --depth 1 https://github.com/Legeni07/restaurant.git "$TMP_REST/restaurant"
    cp "$SOLUTIONS_DIR/tp2.6/Dockerfile.alpine" "$TMP_REST/"
    docker build -f "$TMP_REST/Dockerfile.alpine" -t restaurant:alpine "$TMP_REST"
    rm -rf "$TMP_REST"

    cd "$SOLUTIONS_DIR/tp2.6"
    docker build -f Dockerfile.multistage -t restaurant:multistage .
    docker images restaurant
    docker rm -f restaurant_ms 2>/dev/null || true
    docker run -d --name restaurant_ms restaurant:multistage
    for i in $(seq 1 20); do
        STATUS=$(docker inspect -f '{{.State.Health.Status}}' restaurant_ms 2>/dev/null || echo "starting")
        [ "$STATUS" = "healthy" ] && break
        sleep 2
    done
    docker ps --filter name=restaurant_ms
    docker rm -f restaurant_ms
}

# ------------------------------------------------------------------------------
# TP 2.7 : Réseaux et Stockage en profondeur
# ------------------------------------------------------------------------------
run_tp2_7() {
    echo ""
    echo "=============================================================================="
    echo " TP 2.7 : ISOLATION 3-TIERS, TMPFS & SAUVEGARDE/RESTAURATION DE VOLUME"
    echo "=============================================================================="
    bash "$SOLUTIONS_DIR/tp2.7/tp27_reseaux_stockage.sh"
}

# ------------------------------------------------------------------------------
# TP 2.8 : Docker Compose multi-services, Scaling & Panne Redis
# ------------------------------------------------------------------------------
run_tp2_8() {
    echo ""
    echo "=============================================================================="
    echo " TP 2.8 : DOCKER COMPOSE MULTI-SERVICES, SCALING & TOLÉRANCE AUX PANNES"
    echo "=============================================================================="
    cd "$SOLUTIONS_DIR/tp2.8"
    docker compose down -v 2>/dev/null || true
    docker compose up -d --build --wait
    docker compose ps

    echo "--- Scaling du service web à 3 réplicas et répartition de charge ---"
    docker compose up -d --scale web=3 --wait
    for i in $(seq 6); do
        curl -s http://localhost:8090/api/info
        echo ""
    done

    echo "--- Vérification de la persistance Redis après docker compose down / up -d ---"
    curl -s http://localhost:8090/ | grep -oE "Nombre de visites.*" || true
    docker compose down
    docker compose up -d --wait
    curl -s http://localhost:8090/ | grep -oE "Nombre de visites.*" || true

    echo "--- Simulation de panne Redis (/ready -> 503 vs /health -> 200) ---"
    docker compose stop redis
    echo "Code /ready  (attendu 503) : $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8090/ready)"
    echo "Code /health (attendu 200) : $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8090/health)"
    docker compose start redis
    sleep 2
    docker compose down -v

    echo "--- Exécution réelle du Défi TP 2.8 (WordPress + MariaDB Compose sur :8000) ---"
    docker compose -f "$SOLUTIONS_DIR/tp2.8/wordpress/compose.yml" config >/dev/null
    docker compose -f "$SOLUTIONS_DIR/tp2.8/wordpress/compose.yml" down -v 2>/dev/null || true
    docker compose -f "$SOLUTIONS_DIR/tp2.8/wordpress/compose.yml" up -d --wait
    for i in $(seq 1 20); do
        WP_CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8000/wp-admin/install.php || echo "000")
        [ "$WP_CODE" = "200" ] || [ "$WP_CODE" = "302" ] && break
        sleep 2
    done
    echo "Code HTTP WordPress Compose (:8000) : $WP_CODE"
    docker compose -f "$SOLUTIONS_DIR/tp2.8/wordpress/compose.yml" down -v
}

# ------------------------------------------------------------------------------
# TP 2.9 : Registre privé, Tags, Scan Trivy & Lint Hadolint
# ------------------------------------------------------------------------------
run_tp2_9() {
    echo ""
    echo "=============================================================================="
    echo " TP 2.9 : REGISTRE PRIVÉ, STRATÉGIE DE TAGS, TRIVY & HADOLINT"
    echo "=============================================================================="
    docker rm -f registry 2>/dev/null || true
    docker run -d --name registry -p 5000:5000 -v registry_data:/var/lib/registry registry:3
    until curl -sf http://localhost:5000/v2/ >/dev/null; do sleep 1; done

    echo "--- Lint Hadolint sur app-fil-rouge/Dockerfile et Dockerfile.restaurant.clean ---"
    docker run --rm -i hadolint/hadolint:v2.12.0 < "$APP_DIR/Dockerfile" && echo "Hadolint app-fil-rouge OK (0 erreur) !"
    docker run --rm -i hadolint/hadolint:v2.12.0 < "$SOLUTIONS_DIR/tp2.9/Dockerfile.restaurant.clean" && echo "Hadolint restaurant.clean OK (0 avertissement DL3008/DL3009) !"

    echo "--- Exécution du Défi TP 2.9 (release.sh vers le registre local localhost:5000) ---"
    DOCKERHUB_ID="localhost:5000" bash "$SOLUTIONS_DIR/tp2.9/release.sh" "1.0.0"

    echo "--- Vérification du catalogue et test pull depuis zéro du registre privé ---"
    curl -s http://localhost:5000/v2/_catalog ; echo ""
    curl -s http://localhost:5000/v2/legeni-webapp/tags/list ; echo ""
    docker rmi localhost:5000/legeni-webapp:1.0.0
    docker pull localhost:5000/legeni-webapp:1.0.0
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy_cache:/root/.cache \
      aquasec/trivy:0.57.1 image --severity HIGH,CRITICAL --ignore-unfixed localhost:5000/legeni-webapp:1.0.0 | tail -n 15

    docker rm -f registry && docker volume rm registry_data 2>/dev/null || true
}

# ------------------------------------------------------------------------------
# TP 2.10 : Exploitation, Limites de ressources, Restart policies & 5 Pannes
# ------------------------------------------------------------------------------
run_tp2_10() {
    echo ""
    echo "=============================================================================="
    echo " TP 2.10 : EXPLOITATION, LIMITES CPU/RAM & RÉSOLUTION DES 5 PANNES"
    echo "=============================================================================="
    ensure_webapp_image

    echo "--- Test OOMKilled (limite mémoire 32m) ---"
    docker rm -f oom 2>/dev/null || true
    docker run --name oom --memory 32m python:3.12-slim python -c "x = bytearray(200*1024*1024)" || true
    docker inspect -f 'ExitCode={{.State.ExitCode}} OOMKilled={{.State.OOMKilled}}' oom
    docker rm -f oom

    echo "--- Résolution automatisée des 5 pannes (Partie B) ---"
    bash "$SOLUTIONS_DIR/tp2.10/depannage_5_pannes.sh"
}

# ------------------------------------------------------------------------------
# ORCHESTRATION PRINCIPALE
# ------------------------------------------------------------------------------
ensure_docker_installed

case "$TARGET_TP" in
    2.2) run_tp2_2 ;;
    2.3) run_tp2_3 ;;
    2.4) run_tp2_4 ;;
    2.5) run_tp2_5 ;;
    2.6) run_tp2_6 ;;
    2.7) run_tp2_7 ;;
    2.8) run_tp2_8 ;;
    2.9) run_tp2_9 ;;
    2.10) run_tp2_10 ;;
    all)
        run_tp2_2
        run_tp2_3
        run_tp2_4
        run_tp2_5
        run_tp2_6
        run_tp2_7
        run_tp2_8
        run_tp2_9
        run_tp2_10
        ;;
    *)
        echo "Usage: $0 [all|2.2|2.3|2.4|2.5|2.6|2.7|2.8|2.9|2.10]"
        exit 1
        ;;
esac

echo ""
echo "=============================================================================="
echo " TOUS LES TPs DOCKER DEMANDÉS SONT TERMINÉS AVEC SUCCÈS !"
echo " Les traces complètes sont disponibles dans : $LOG_FILE"
echo " Le compte-rendu complet est dans : $SCRIPT_DIR/COMPTE_RENDU_TP_DOCKER.md"
echo "=============================================================================="
