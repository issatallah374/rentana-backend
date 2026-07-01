#!/usr/bin/env bash
set -euo pipefail

apt update
apt upgrade -y
apt install -y git curl wget unzip nano ufw nginx certbot python3-certbot-nginx openjdk-21-jdk postgresql postgresql-contrib

id -u rentana >/dev/null 2>&1 || adduser --system --group --home /opt/rentana rentana
mkdir -p /opt/rentana /etc/rentana
chown -R rentana:rentana /opt/rentana
chmod 750 /etc/rentana

ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw --force enable
ufw status
