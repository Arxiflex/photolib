# Developer commands; run `just` to list them. A fresh clone starts with `just bootstrap`.
set dotenv-load
set dotenv-path := "tools/dev/.env"

default:
    @just --list

# One-time setup: secrets, dev stack, Caddy certificate, seed data and git hooks
bootstrap:
    bash tools/dev/bootstrap.sh

# The quality gate, the same command CI runs
test:
    bash tools/check.sh

# Run photolibd against the dev stack, with the settings from tools/dev/.env
run-server *args:
    cargo run --manifest-path server/Cargo.toml --bin photolibd -- {{args}}

# Run the app, for example `just run-app -d linux`
run-app *args:
    cd app && flutter run {{args}}

# Load the seed users, libraries and media into the running stack
seed:
    python3 tools/dev/seed.py

# Stop the dev stack and keep its data
down:
    docker compose -f tools/dev/compose.yaml down

# Stop the dev stack and delete its data; `just bootstrap` brings it back
reset:
    docker compose -f tools/dev/compose.yaml down --volumes
