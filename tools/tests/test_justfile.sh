#!/usr/bin/env bash
# The justfile gives every developer the same short commands: bootstrap, test, run-server, run-app (plus seed, down
# and reset for the dev stack). The recipes are thin wrappers; the real work lives in tools/dev and tools/check.sh.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_file justfile
JUSTFILE="$REPO_ROOT/justfile"
[[ -f "$JUSTFILE" ]] || { finish; exit; }

# recipe_body <name>: the indented command lines of a recipe, trimmed.
recipe_body() {
  awk -v name="$1" '
    $0 ~ "^" name "( .*)?:" { inside = 1; next }
    inside && /^[ ]+/ { sub(/^[ ]+/, ""); print; next }
    inside && !/^[ ]*$/ { inside = 0 }
  ' "$JUSTFILE"
}

expect_recipe() {
  local name=$1 expected=$2 body
  body=$(recipe_body "$name")
  if [[ "$body" == "$expected" ]]; then ok "recipe $name runs: ${expected//$'\n'/ ; }"; else
    fail "recipe $name: expected
$expected
got
$body"
  fi
}

expect_recipe bootstrap "bash tools/dev/bootstrap.sh"
expect_recipe test "bash tools/check.sh"
expect_recipe run-server 'cargo run --manifest-path server/Cargo.toml --bin photolibd -- {{args}}'
expect_recipe run-app 'cd app && flutter run {{args}}'
expect_recipe seed "python3 tools/dev/seed.py"
expect_recipe down "docker compose -f tools/dev/compose.yaml down"
expect_recipe reset "docker compose -f tools/dev/compose.yaml down --volumes"

assert_matches justfile '^set dotenv-load' "loads the environment for run-server"
assert_matches justfile '^set dotenv-path := "tools/dev/\.env"' "reads the generated tools/dev/.env"
assert_matches justfile '^run-(server|app) \*args:' "run recipes pass extra arguments through"

if command -v just >/dev/null 2>&1; then
  listed=$(cd "$REPO_ROOT" && just --list 2>&1)
  for name in bootstrap test run-server run-app seed down reset; do
    if grep -Eq "^ +$name( |\$)" <<<"$listed"; then ok "just lists $name"; else fail "just --list does not show $name"; fi
  done
  if (cd "$REPO_ROOT" && just --dry-run run-server api >/dev/null 2>&1); then ok "just parses run-server arguments"; else fail "just --dry-run run-server failed"; fi
else
  echo "skip: 'just' is not on PATH, so the justfile was only checked structurally"
fi

finish
