#!/bin/sh
trap 'echo "SIGTERM reçu : fermeture propre des connexions"; exit 0' TERM
echo "Démarrage (PID $$)"
while true; do sleep 1; done
