#!/bin/bash
# Solution du Défi TP 2.2 : Conteneur Redis, écriture/lecture clé, inspection IP et suppression
set -euo pipefail

echo "=== [TP 2.2 - Défi] Lancement de Redis (cache) ==="
docker rm -f cache 2>/dev/null || true
docker run -d --name cache redis:7.4-alpine

# Attendre que Redis soit prêt
sleep 2

echo "=== Écriture et lecture de la clé 'cours' ==="
docker exec cache redis-cli SET cours devops
VAL=$(docker exec cache redis-cli GET cours)
echo "Valeur lue : $VAL"

echo "=== Adresse IP du conteneur cache ==="
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' cache

echo "=== Suppression du conteneur en une seule commande ==="
docker rm -f cache
echo "Défi TP 2.2 terminé avec succès."
