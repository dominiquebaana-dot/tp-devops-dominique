#!/bin/bash
# Script complet d'exécution du TP 2.7 (Isolation 3-tiers, Bind Mount, tmpfs, Sauvegarde/Restauration)
set -euo pipefail

echo "=== [TP 2.7 - Partie A] Isolation réseau 3-tiers (proxy <-> web <-> redis) ==="
docker rm -f a1 a2 web redis proxy n1 n2 n3 dev secret 2>/dev/null || true
docker network rm front back 2>/dev/null || true

docker network create front
docker network create back
docker run -d --name redis --network back redis:7.4-alpine
docker run -d --name web --network back alpine:3.20 sleep infinity
docker network connect front web
docker run -d --name proxy --network front alpine:3.20 sleep infinity

echo "1) web -> redis (OK) :"
docker exec web ping -c1 redis
echo "2) proxy -> web (OK) :"
docker exec proxy ping -c1 web
echo "3) proxy -> redis (Doit être bloqué) :"
if docker exec proxy ping -c1 -W1 redis 2>/dev/null; then
  echo "ERREUR : proxy ne devrait pas voir redis"
else
  echo "OK : proxy est bien isolé du réseau back (redis inaccessible)"
fi

docker rm -f web redis proxy
docker network rm front back

echo "=== [TP 2.7 - Partie B - Étape 5] Bind mount (mise à jour à chaud & :ro) ==="
SITE_TMP="/tmp/tp27_site"
rm -rf "$SITE_TMP" && mkdir -p "$SITE_TMP"
echo "<h1>Version 1</h1>" > "$SITE_TMP/index.html"
docker run -d --name web_bind -p 8096:80 -v "$SITE_TMP":/usr/share/nginx/html nginx:1.27-alpine
until curl -sf http://localhost:8096 >/dev/null; do sleep 1; done
echo "Bind mount v1 : $(curl -s http://localhost:8096)"
echo "<h1>Version 2 (à chaud)</h1>" > "$SITE_TMP/index.html"
echo "Bind mount v2 : $(curl -s http://localhost:8096)"
docker rm -f web_bind
docker run --rm -v "$SITE_TMP":/usr/share/nginx/html:ro nginx:1.27-alpine sh -c 'touch /usr/share/nginx/html/test.txt 2>&1 || echo "OK : écriture bloquée sur :ro"'
rm -rf "$SITE_TMP"

echo "=== [TP 2.7 - Partie B - Étape 6] Stockage en mémoire vive (tmpfs) ==="
docker run -d --name secret --tmpfs /run/secrets:size=1m alpine:3.20 sleep infinity
docker exec secret sh -c 'echo motdepasse > /run/secrets/token && df -h /run/secrets'
docker restart secret
echo "Contenu de /run/secrets après redémarrage (doit être vide) :"
docker exec secret ls -la /run/secrets
docker rm -f secret

echo "=== [TP 2.7 - Partie B - Étape 7] Sauvegarde et restauration d'un volume Redis ==="
docker volume rm redis_data 2>/dev/null || true
docker volume create redis_data
docker run -d --name redis -v redis_data:/data redis:7.4-alpine redis-server --appendonly yes
sleep 2
docker exec redis redis-cli set cours devops
docker exec redis redis-cli save

BACKUP_TMP="/tmp/tp27_backup"
mkdir -p "$BACKUP_TMP"
docker run --rm -v redis_data:/source:ro -v "$BACKUP_TMP":/backup alpine:3.20 \
  tar czf /backup/redis_data.tar.gz -C /source .
ls -lh "$BACKUP_TMP/redis_data.tar.gz"

echo "Simulation de perte totale du conteneur et du volume :"
docker rm -f redis && docker volume rm redis_data
docker volume create redis_data
docker run --rm -v redis_data:/cible -v "$BACKUP_TMP":/backup alpine:3.20 \
  tar xzf /backup/redis_data.tar.gz -C /cible

docker run -d --name redis -v redis_data:/data redis:7.4-alpine redis-server --appendonly yes
sleep 2
echo "Clé 'cours' après restauration :"
docker exec redis redis-cli get cours

echo "=== [TP 2.7 - Défi] Exécution de backup_volume.sh avec rotation (7 archives max) ==="
SCRIPT_TP27_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROT_TMP="/tmp/tp27_rotation"
rm -rf "$BACKUP_ROT_TMP" && mkdir -p "$BACKUP_ROT_TMP"
for n in $(seq 1 8); do
  BACKUP_DIR="$BACKUP_ROT_TMP" bash "$SCRIPT_TP27_DIR/backup_volume.sh" redis_data >/dev/null
  sleep 1
done
COUNT_ARCH=$(ls -1 "$BACKUP_ROT_TMP"/backup_redis_data_*.tar.gz | wc -l)
echo "Nombre d'archives conservées après 8 sauvegardes (attendu 7) : $COUNT_ARCH"
ls -1 "$BACKUP_ROT_TMP"
rm -rf "$BACKUP_ROT_TMP"

docker rm -f redis && docker volume rm redis_data
rm -rf "$BACKUP_TMP"
echo "TP 2.7 terminé avec succès."
