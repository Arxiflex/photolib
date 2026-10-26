#!/bin/sh
# One-command quickstart: setup.sh <domain> [base path such as /photos] writes .env from .env.example with the user
# running it (or sudo's), a new database password and the domain, makes the directories compose.yaml mounts and starts
# Photolib. It never overwrites an .env.
set -eu
cd "$(dirname "$0")"
domain=${1:?usage: setup.sh <domain> [base path such as /photos]}
if [ -e .env ]; then
  echo "setup.sh: .env exists; nothing changed" >&2
  exit 1
fi
puid=${PUID:-${SUDO_UID:-$(id -u)}} pgid=${PGID:-${SUDO_GID:-$(id -g)}}
mkdir -p data keys postgres caddy/data caddy/config
if [ "$(id -u)" = 0 ]; then chown -R "$puid:$pgid" data keys postgres caddy; fi
password=$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')
(umask 077 && sed -e "s|^PHOTOLIB_DOMAIN=.*|PHOTOLIB_DOMAIN=$domain|" -e "s|^PHOTOLIB_BASE_PATH=.*|PHOTOLIB_BASE_PATH=${2:-}|" \
  -e "s|^PUID=.*|PUID=$puid|" -e "s|^PGID=.*|PGID=$pgid|" -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$password|" \
  .env.example >.env)
docker compose up -d
echo "Open https://$domain${2:-}/ and create the first administrator with the setup_token that"
echo "'docker compose logs photolibd' shows (docs/admin/users.md)."
