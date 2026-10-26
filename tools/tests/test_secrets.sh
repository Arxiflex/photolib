#!/usr/bin/env bash
# Secret scan: gitleaks with .gitleaks.toml over the history of HEAD, so the gate catches a flagged string before a
# merge. gitleaks comes from PATH, else the image pinned here (Renovate keeps it current) through docker.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

if command -v gitleaks >/dev/null 2>&1; then
  GITLEAKS=(gitleaks)
elif docker info >/dev/null 2>&1; then
  GITLEAKS=(docker run --rm --user "$(id -u):$(id -g)" -v "$REPO_ROOT:/repo" -w /repo zricethezav/gitleaks:v8.30.1)
else
  echo "FAIL: the secret scan needs gitleaks on PATH or a running docker daemon" >&2
  exit 1
fi

if "${GITLEAKS[@]}" git --config .gitleaks.toml --log-opts="--full-history HEAD" --redact --verbose --no-banner .; then
  ok "gitleaks finds no secret in the history of HEAD"
else
  fail "gitleaks flags the findings above: remove the secret, or allowlist a test value in .gitleaks.toml"
fi

finish
