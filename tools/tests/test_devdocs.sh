#!/usr/bin/env bash
# Developer-environment documentation and the dev-store ADR.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_patterns assert_prose README.md \
  '^# Photolib.*## Development environment' "has a Development environment section" \
  'Docker.*just.*pre-commit.*Python 3' "lists the prerequisites" \
  'just bootstrap' "starts with just bootstrap" \
  'just run-server' "shows how to run the server" \
  'just run-app' "shows how to run the app" \
  'just test' "shows how to run the checks" \
  '\.devcontainer\.json' "mentions the dev container" \
  'https://photolib\.localhost:8443' "gives the Caddy address" \
  'http://localhost:3900' "gives the S3 address" \
  'tools/dev/caddy-root\.crt' "says where the local certificate authority is" \
  'tools/dev/\.env' "explains the generated secrets file" \
  'app shell.*just run-app -d' "says the app shell runs without a server" \
  'app/\.fvmrc' "names the pinned Flutter version file" \
  '0\.0\.0\.0:8080' "says the server must listen on all interfaces for Caddy on Linux"

assert_patterns assert_prose AGENTS.md \
  'just bootstrap' "names the one-time setup" \
  'tools/dev/' "describes the dev stack folder" \
  'tools/dev/\.env.*never committed|never commit.*tools/dev/\.env' "forbids committing the generated .env"
assert_patterns assert_prose tools/README.md \
  'dev/.*compose' "tools/README.md describes the dev stack" \
  'bootstrap\.sh' "tools/README.md names bootstrap.sh" \
  'seed\.py' "tools/README.md names the seed loader"
assert_prose deploy/README.md 'tools/dev/' "deploy/README.md points at the dev stack"
assert_prose docs/adr/README.md '0018-dev-s3-store\.md\) \| [^|]* \| Accepted \(owner deferred' "the ADR index lists the ADR as Accepted"
assert_prose docs/dev/README.md 'just bootstrap' "the developer guide explains the dev environment"

# --- ADR
ADR=docs/adr/0018-dev-s3-store.md
assert_file "$ADR"
assert_patterns assert_prose "$ADR" \
  '^# ADR-0018' "is titled ADR-0018" \
  '\*\*Status\*\*: Accepted .*owner deferred.*photolib-design#264' "is Accepted, recording that the owner deferred (#264)" \
  'Garage.*SeaweedFS|SeaweedFS.*Garage' "weighs Garage against SeaweedFS" \
  'MinIO' "explains why not MinIO" \
  'AGPL' "records the licence consequence"

finish
