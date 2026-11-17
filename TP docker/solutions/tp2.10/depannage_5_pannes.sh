#!/bin/bash
# TP 2.10 - Partie B : Reproduction, diagnostic et résolution automatisée des 5 pannes
set -euo pipefail

echo "=================================================================="
echo "TP 2.10 : DIAGNOSTIC ET RÉSOLUTION DES 5 PANNES"
echo "=================================================================="

# Vérification et construction automatique de legeni-webapp:1.0.0 si absente
if ! docker image inspect legeni-webapp:1.0.0 >/dev/null 2>&1; then
    echo "Image legeni-webapp:1.0.0 absente : construction automatique..."
    APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../app-fil-rouge" && pwd)"
    docker build --build-arg APP_VERSION=1.0.0 -t legeni-webapp:1.0.0 "$APP_DIR"
fi

docker rm -f p1 p2a p2b p3 p4 cache 2>/dev/null || true
docker network rm p4net 2>/dev/null || true

echo ""
echo "--- PANNE 1 : Le conteneur s'arrête tout de suite ---"
docker run -d --name p1 ubuntu:24.04
sleep 1
echo "[Diagnostic] État du conteneur p1 :"
docker ps -a --filter name=p1 --format "table {{.Names}}\t{{.Status}}\t{{.Command}}"
echo "[Cause] bash n'a pas de terminal (TTY) ni de processus maintenu au premier plan."
echo "[Correction] Lancer avec sleep infinity (ou -dit) :"
docker rm -f p1
docker run -d --name p1 ubuntu:24.04 sleep infinity
docker ps --filter name=p1 --format "table {{.Names}}\t{{.Status}}\t{{.Command}}"
docker rm -f p1

echo ""
echo "--- PANNE 2 : Port déjà utilisé sur l'hôte ---"
docker run -d --name p2a -p 8085:80 nginx:1.27-alpine
echo "[Diagnostic] Tentative de lancer p2b sur le même port 8085 :"
if docker run -d --name p2b -p 8085:80 nginx:1.27-alpine 2>&1; then
  echo "Inattendu"
else
  echo "[Cause] Conflit de port hôte 8085 déjà alloué à p2a."
fi
docker rm -f p2b 2>/dev/null || true
echo "[Correction] Publier p2b sur un port hôte libre (ex: 8095:80) :"
docker run -d --name p2b -p 8095:80 nginx:1.27-alpine
docker ps --filter name=p2 --format "table {{.Names}}\t{{.Ports}}"
docker rm -f p2a p2b

echo ""
echo "--- PANNE 3 : L'application ne répond pas depuis le navigateur ---"
docker run -d --name p3 -p 8086:80 legeni-webapp:1.0.0
sleep 2
echo "[Diagnostic] Vérification des ports et logs de p3 :"
curl -sS --max-time 2 http://localhost:8086 2>&1 || true
docker port p3
docker logs p3 | sed -n '1,5p'
echo "[Cause] Gunicorn écoute sur le port 5000 dans le conteneur, or on a mappé le port 80 (-p 8086:80)."
echo "[Correction] Mapper -p 8086:5000 :"
docker rm -f p3
docker run -d --name p3 -p 8086:5000 legeni-webapp:1.0.0
until curl -sf http://localhost:8086/health >/dev/null; do sleep 1; done
curl -s http://localhost:8086/api/info ; echo ""
docker rm -f p3

echo ""
echo "--- PANNE 4 : L'application ne trouve pas Redis (/ready renvoie 503) ---"
docker network create p4net
docker run -d --name cache --network p4net redis:7.4-alpine
docker run -d --name p4 -p 8087:5000 -e REDIS_HOST=redis legeni-webapp:1.0.0
until curl -sf http://localhost:8087/health >/dev/null; do sleep 1; done
echo "[Diagnostic] Code HTTP de /ready :"
curl -s -w " (HTTP %{http_code})\n" http://localhost:8087/ready
echo "[Cause] 1) p4 est sur le bridge par défaut (pas sur p4net). 2) Le conteneur Redis s'appelle 'cache' et non 'redis'."
echo "[Correction] Placer p4 sur --network p4net avec -e REDIS_HOST=cache :"
docker rm -f p4
docker run -d --name p4 --network p4net -p 8087:5000 -e REDIS_HOST=cache legeni-webapp:1.0.0
until curl -sf http://localhost:8087/ready >/dev/null; do sleep 1; done
curl -s -w " (HTTP %{http_code})\n" http://localhost:8087/ready
docker rm -f p4 cache && docker network rm p4net

echo ""
echo "--- PANNE 5 : Permission denied sur un bind mount ---"
rm -rf /tmp/p5 2>/dev/null || sudo rm -rf /tmp/p5 2>/dev/null || true
mkdir -p /tmp/p5 && chmod 755 /tmp/p5
if command -v sudo >/dev/null 2>&1; then
  sudo chown 0:0 /tmp/p5 2>/dev/null || true
fi
echo "[Diagnostic] Tentative d'écriture par appuser (UID 10001) dans /tmp/p5 (propriétaire root 755) :"
docker run --rm -v /tmp/p5:/data legeni-webapp:1.0.0 sh -c 'echo test > /data/f' 2>&1 || true
echo "[Cause] L'image legeni-webapp tourne sous l'utilisateur non-root appuser (UID 10001)."
echo "[Correction] Attribuer les droits UID 10001 au dossier hôte (ou utiliser un volume nommé) :"
if command -v sudo >/dev/null 2>&1; then
  sudo chown 10001:10001 /tmp/p5 || chown 10001:10001 /tmp/p5 2>/dev/null || chmod 777 /tmp/p5
else
  chmod 777 /tmp/p5
fi
docker run --rm -v /tmp/p5:/data legeni-webapp:1.0.0 sh -c 'echo "Écriture réussie par $(id -un)" > /data/f && cat /data/f'
if command -v sudo >/dev/null 2>&1; then
  sudo rm -rf /tmp/p5
else
  rm -rf /tmp/p5
fi

echo ""
echo "=== Les 5 pannes du TP 2.10 ont été diagnostiquées et corrigées avec succès ! ==="
