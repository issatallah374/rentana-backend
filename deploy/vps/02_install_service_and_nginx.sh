#!/usr/bin/env bash
set -euo pipefail

BACKEND_DIR="${1:-/opt/rentana/backend}"
if [ ! -f "$BACKEND_DIR/build/libs/app.jar" ]; then
  echo "app.jar not found at $BACKEND_DIR/build/libs/app.jar"
  echo "Run: cd $BACKEND_DIR && ./gradlew clean build -x test"
  exit 1
fi

install -m 640 -o root -g rentana deploy/vps/rentana-backend.env.template /etc/rentana/rentana-backend.env.example || true
cp deploy/vps/rentana-backend.service /etc/systemd/system/rentana-backend.service
cp deploy/vps/nginx-rentana.conf /etc/nginx/sites-available/rentana
ln -sf /etc/nginx/sites-available/rentana /etc/nginx/sites-enabled/rentana
rm -f /etc/nginx/sites-enabled/default

chown -R rentana:rentana /opt/rentana
nginx -t
systemctl daemon-reload
systemctl enable rentana-backend
systemctl restart rentana-backend
systemctl reload nginx

echo "✅ Service and Nginx installed. Check: systemctl status rentana-backend --no-pager"
