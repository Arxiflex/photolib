#!/usr/bin/env bash
# One-time setup of a fresh clone: secrets, dev stack, Caddy root certificate, seed data and git hooks.
# Safe to run again: an existing tools/dev/.env is kept, so existing database and bucket volumes keep working.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT"

for tool in docker python3 pre-commit; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "bootstrap: '$tool' is not installed; see 'Development environment' in README.md" >&2
    exit 1
  }
done

hex() { head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'; }

ENV_FILE=tools/dev/.env
if [[ -e $ENV_FILE ]]; then
  echo "bootstrap: keeping existing $ENV_FILE"
else
  password=$(hex 16)
  (
    umask 077
    cat >"$ENV_FILE.tmp" <<EOF
POSTGRES_PASSWORD=$password
GARAGE_RPC_SECRET=$(hex 32)
AWS_ACCESS_KEY_ID=GK$(hex 16)
AWS_SECRET_ACCESS_KEY=$(hex 32)
AWS_ENDPOINT_URL=http://localhost:3900
AWS_REGION=garage
S3_BUCKET=photolib-dev
DATABASE_URL=postgres://photolib:$password@localhost:5432/photolib
EOF
  )
  mv "$ENV_FILE.tmp" "$ENV_FILE"
  echo "bootstrap: created $ENV_FILE with random local-only secrets"
fi

COMPOSE=(docker compose -f tools/dev/compose.yaml)
"${COMPOSE[@]}" up -d --wait --wait-timeout 180
"${COMPOSE[@]}" cp caddy:/data/caddy/pki/authorities/local/root.crt tools/dev/caddy-root.crt
python3 tools/dev/seed.py
pre-commit install

cat <<'EOF'

The dev stack is up and loaded with seed data.
  PostgreSQL  localhost:5432 (see DATABASE_URL in tools/dev/.env)
  S3 (Garage) http://localhost:3900, bucket photolib-dev
  Caddy       https://photolib.localhost:8443 (proxies to the server on host port 8080)

Next: just run-server, then just run-app. To trust the local certificate authority, add
tools/dev/caddy-root.crt to your system or browser trust store.
EOF
