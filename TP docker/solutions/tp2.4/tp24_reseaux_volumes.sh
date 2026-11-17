#!/bin/bash
# Script complet d'exécution et de vérification du TP 2.4 (Réseaux, Volumes & Défi 3-tiers)
set -euo pipefail

echo "=== [TP 2.4 - Étape 2] Création du réseau bridge personnalisé mon_reseau ==="
docker rm -f B3_jour B3_soir visiteur pg db web api 2>/dev/null || true
docker network rm mon_reseau backend frontend 2>/dev/null || true
docker volume rm mon_volume_persistant pg_data 2>/dev/null || true

docker network create -d bridge mon_reseau
docker network inspect mon_reseau --format 'Subnet: {{(index .IPAM.Config 0).Subnet}}'

docker run -d --name B3_jour --network mon_reseau alpine:3.20 sleep infinity
docker run -d --name B3_soir --network mon_reseau alpine:3.20 sleep infinity

echo "Test ping DNS entre B3_jour et B3_soir :"
docker exec B3_jour ping -c 2 B3_soir

echo "=== [TP 2.4 - Étape 3] Volume anonyme (temporaire) ==="
docker rm -f B3_jour B3_soir
docker run -d --name B3_jour --network mon_reseau -v /partage alpine:3.20 sleep infinity
docker run -d --name B3_soir --network mon_reseau --volumes-from B3_jour alpine:3.20 sleep infinity

docker exec B3_jour sh -c 'echo "Bonjour du jour" > /partage/fichier.txt'
docker exec B3_soir sh -c 'echo "Bonsoir" >> /partage/fichier.txt'
echo "Contenu lu depuis B3_jour :"
docker exec B3_jour cat /partage/fichier.txt
docker rm -f -v B3_soir B3_jour

echo "=== [TP 2.4 - Étape 4] Volume nommé (persistant) ==="
docker volume create mon_volume_persistant
docker run -d --name B3_jour --network mon_reseau -v mon_volume_persistant:/mnt alpine:3.20 sleep infinity
docker run -d --name B3_soir --network mon_reseau -v mon_volume_persistant:/mnt:ro alpine:3.20 sleep infinity

docker exec B3_jour sh -c 'echo "Bonjour" > /mnt/fichier.txt'
docker rm -f -v B3_jour B3_soir
echo "Lecture après suppression des conteneurs :"
docker run --rm -v mon_volume_persistant:/mnt alpine:3.20 cat /mnt/fichier.txt

echo "=== [TP 2.4 - Étape 5] Base PostgreSQL persistante ==="
docker run -d --name pg --network mon_reseau -e POSTGRES_PASSWORD=secret \
  -v pg_data:/var/lib/postgresql/data postgres:16-alpine
until docker exec pg pg_isready -h 127.0.0.1 -U postgres -q; do sleep 1; done
docker exec pg psql -U postgres -c "CREATE TABLE eleves(nom text); INSERT INTO eleves VALUES ('B3 jour'),('B3 soir');"

docker rm -f pg
docker run -d --name pg --network mon_reseau -e POSTGRES_PASSWORD=secret \
  -v pg_data:/var/lib/postgresql/data postgres:16-alpine
until docker exec pg pg_isready -h 127.0.0.1 -U postgres -q; do sleep 1; done
echo "Vérification des données après recréation du conteneur pg :"
docker exec pg psql -U postgres -c "SELECT * FROM eleves;"

echo "=== [TP 2.4 - Nettoyage] ==="
docker rm -f pg
docker volume rm mon_volume_persistant pg_data
docker network rm mon_reseau

echo "=== [TP 2.4 - Défi] Isolation réseau 3-tiers (frontend / backend) ==="
docker network create backend
docker network create frontend
docker run -d --name db  --network backend  alpine:3.20 sleep infinity
docker run -d --name web --network frontend alpine:3.20 sleep infinity
docker run -d --name api --network backend  alpine:3.20 sleep infinity
docker network connect frontend api

echo "1) web -> api (doit réussir) :"
docker exec web ping -c1 api
echo "2) web -> db (doit échouer car isolé) :"
if docker exec web ping -c1 -W1 db 2>/dev/null; then
  echo "ERREUR : db ne devrait pas être joignable !"
else
  echo "OK : web ne peut pas joindre db directement (isolation validée)."
fi
echo "3) api -> db (doit réussir) :"
docker exec api ping -c1 db

docker rm -f db web api
docker network rm backend frontend
echo "TP 2.4 terminé avec succès."
