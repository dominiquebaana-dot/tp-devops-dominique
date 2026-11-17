#!/bin/bash
# Défi TP 2.7 : Sauvegarde d'un volume Docker avec rotation des 7 dernières archives
set -euo pipefail

VOLUME=${1:?usage: $0 <nom_volume>}
DEST=${BACKUP_DIR:-$HOME/backups}
mkdir -p "$DEST"

FILE="backup_${VOLUME}_$(date +%Y%m%d_%H%M%S).tar.gz"
docker run --rm -v "${VOLUME}":/source:ro -v "${DEST}":/backup alpine:3.20 \
  tar czf "/backup/${FILE}" -C /source .

# Conserver uniquement les 7 sauvegardes les plus récentes
ls -1t "$DEST"/backup_"${VOLUME}"_*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm --

echo "Sauvegarde réussie : ${DEST}/${FILE}"
