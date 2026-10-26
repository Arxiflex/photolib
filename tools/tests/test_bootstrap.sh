#!/usr/bin/env bash
# Bootstrap against tool stubs; the real stack needs a container runtime.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPT="$REPO_ROOT/tools/dev/bootstrap.sh"
sandbox_tools bash env dirname basename mkdir cat rm mv head tr od chmod

bootstrap_sandbox() {
  new_sandbox tools/dev/bootstrap.sh "$@"
  ENV_FILE="$SANDBOX/tools/dev/.env"
}

# run_bootstrap: run the sandbox copy from an unrelated directory; output in $OUT, status in $STATUS.
run_bootstrap() {
  OUT=$(cd "$SANDBOX/stubs" && PATH="$SANDBOX/stubs:$BASE_BIN" bash "$SANDBOX/tools/dev/bootstrap.sh" 2>&1)
  STATUS=$?
}

[[ -f "$SCRIPT" ]] || fail "tools/dev/bootstrap.sh does not exist"

COMPOSE="docker compose -f tools/dev/compose.yaml"
EXPECTED="$COMPOSE up -d --wait --wait-timeout 180 @
$COMPOSE cp caddy:/data/caddy/pki/authorities/local/root.crt tools/dev/caddy-root.crt @
python3 tools/dev/seed.py @
pre-commit install @"

# --- a fresh clone
bootstrap_sandbox docker python3 pre-commit
run_bootstrap
expect_result "bootstrap succeeds with every tool present" 0
expect_calls "runs compose up, the CA export, the seed loader and pre-commit in order from the root" "$EXPECTED"

if [[ -f "$ENV_FILE" ]]; then
  ok "creates tools/dev/.env"
  [[ "$(stat -c %a "$ENV_FILE")" == 600 ]] && ok ".env is readable by its owner only" || fail ".env mode is not 600"
  for pattern in \
    'POSTGRES_PASSWORD=[0-9a-f]{32}' \
    'GARAGE_RPC_SECRET=[0-9a-f]{64}' \
    'AWS_ACCESS_KEY_ID=GK[0-9a-f]{32}' \
    'AWS_SECRET_ACCESS_KEY=[0-9a-f]{64}' \
    'AWS_ENDPOINT_URL=http://localhost:3900' \
    'AWS_REGION=garage' \
    'S3_BUCKET=photolib-dev'; do
    if grep -Eq "^$pattern\$" "$ENV_FILE"; then ok ".env has ${pattern%%=*}"; else fail ".env lacks a line matching ^$pattern\$"; fi
  done
  password=$(sed -n 's/^POSTGRES_PASSWORD=//p' "$ENV_FILE")
  if grep -Fxq "DATABASE_URL=postgres://photolib:$password@localhost:5432/photolib" "$ENV_FILE"; then
    ok ".env DATABASE_URL uses the generated password"
  else
    fail ".env DATABASE_URL does not match the generated password"
  fi
  if [[ "$(grep -c . "$ENV_FILE")" -eq 8 ]]; then ok ".env has no unexpected lines"; else fail ".env line count is not 8"; fi
else
  fail "tools/dev/.env was not created"
fi

for hint in "just run-server" "just run-app" "caddy-root.crt" "https://photolib.localhost:8443"; do
  if [[ "$OUT" == *"$hint"* ]]; then ok "prints the next step: $hint"; else fail "output does not mention '$hint'"; fi
done

# --- a second run keeps the secrets, so existing volumes keep working
first=$(cat "$ENV_FILE" 2>/dev/null)
run_bootstrap
if [[ $STATUS -eq 0 && "$(cat "$ENV_FILE")" == "$first" ]]; then ok "a second run keeps the same .env"; else fail "a second run changed .env or failed"; fi

# --- two clones get different secrets
bootstrap_sandbox docker python3 pre-commit
run_bootstrap
if [[ "$(cat "$ENV_FILE")" != "$first" ]]; then ok "a different clone gets different secrets"; else fail "two clones generated identical secrets"; fi

# --- a missing tool fails before anything is changed
for missing in docker python3 pre-commit; do
  stubs=()
  for tool in docker python3 pre-commit; do [[ $tool != "$missing" ]] && stubs+=("$tool"); done
  bootstrap_sandbox "${stubs[@]}"
  run_bootstrap
  if [[ $STATUS -ne 0 && "$OUT" == *"$missing"* ]]; then ok "missing $missing fails and names it"; else fail "missing $missing: exit $STATUS, output: $OUT"; fi
  if [[ ! -e "$ENV_FILE" && -z "$(calls)" ]]; then ok "missing $missing changes nothing"; else fail "missing $missing still changed things"; fi
done

# --- a failing step stops the run
bootstrap_sandbox docker python3 pre-commit
FAIL_ON="$COMPOSE up -d --wait --wait-timeout 180" run_bootstrap
if [[ $STATUS -ne 0 && "$(calls)" != *seed.py* ]]; then ok "a failing compose up stops before seeding"; else fail "bootstrap went on after compose up failed"; fi

bootstrap_sandbox docker python3 pre-commit
FAIL_ON="python3 tools/dev/seed.py" run_bootstrap
if [[ $STATUS -ne 0 && "$(calls)" != *pre-commit* ]]; then ok "a failing seed load stops before the hooks"; else fail "bootstrap went on after the seed load failed"; fi

finish
