#!/usr/bin/env bash
set -euo pipefail

EMAIL="${1:-}"
if [ -z "$EMAIL" ]; then
  echo "Usage: bash 03_ssl_certbot.sh your-email@example.com"
  exit 1
fi

certbot --nginx -d rentana.online -d www.rentana.online --agree-tos -m "$EMAIL" --redirect --non-interactive
systemctl reload nginx
