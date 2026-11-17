#!/bin/sh
set -e
: "${APP_ENV:?La variable APP_ENV est obligatoire}"
echo "[entrypoint] environnement = $APP_ENV"
echo "<h1>Environnement : $APP_ENV</h1>" > /usr/share/nginx/html/index.html
exec "$@"
