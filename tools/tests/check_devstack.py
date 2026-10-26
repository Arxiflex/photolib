#!/usr/bin/env python3
"""Check the dev stack with Docker Compose's config command; no daemon needed."""
import json
import os
import re
import subprocess
import tempfile
import tomllib

from checklib import ROOT, check, finish, read

DEV = os.path.join(ROOT, "tools", "dev")
SETTINGS = {
    "POSTGRES_PASSWORD": "pg-secret",
    "GARAGE_RPC_SECRET": "rpc-secret",
    "AWS_ACCESS_KEY_ID": "GKaccess",
    "AWS_SECRET_ACCESS_KEY": "s3-secret",
    "S3_BUCKET": "bucket-from-env",
}


def compose(env_lines):
    """`docker compose config` of the dev stack with exactly these settings; returns (exit code, stdout, stderr)."""
    with tempfile.NamedTemporaryFile("w", suffix=".env") as env_file:
        env_file.write("".join(f"{line}\n" for line in env_lines))
        env_file.flush()
        run = subprocess.run(
            ["docker", "compose", "--env-file", env_file.name, "-f", os.path.join(DEV, "compose.yaml"), "config", "--format", "json"],
            capture_output=True, text=True, check=False,
        )
    return run.returncode, run.stdout, run.stderr


def published(service):
    return {(port.get("host_ip"), int(port["published"]), port["target"]) for port in service.get("ports", [])}


def mounts(service):
    return {volume["target"]: volume for volume in service.get("volumes", [])}


def check_compose():
    status, _, err = compose([])
    check(status != 0 and "just bootstrap" in err, "the stack refuses to start without generated secrets and points at `just bootstrap`")
    status, out, err = compose([f"{key}={value}" for key, value in SETTINGS.items()])
    if not check(status == 0, f"the compose file is valid ({err.strip()})"):
        return
    services = json.loads(out)["services"]
    check(set(services) == {"postgres", "garage", "caddy"}, "the stack runs PostgreSQL, the S3 store and Caddy")
    postgres, garage, caddy = services["postgres"], services["garage"], services["caddy"]

    check(re.fullmatch(r"postgres:18(\.\d+)?(-[a-z]+)?", postgres["image"]) is not None, "PostgreSQL is version 18")
    check(re.fullmatch(r"dxflrs/garage:v2\.\d+\.\d+", garage["image"]) is not None, "the S3-compatible store is Garage 2.x, pinned")
    tested = re.search(r"^VERSION=(\S+)$", read("tools/garage.sh"), re.M)
    check(tested is not None and garage["image"] == f"dxflrs/garage:{tested[1]}", "the storage tests run the Garage release of the stack (tools/garage.sh)")
    check(re.fullmatch(r"caddy:2(\.\d+)*", caddy["image"]) is not None, "the proxy is Caddy 2")

    check(published(postgres) == {("127.0.0.1", 5432, 5432)}, "PostgreSQL is published on loopback only")
    check(published(garage) == {("127.0.0.1", 3900, 3900)}, "the S3 API is published on loopback only")
    check(published(caddy) == {("127.0.0.1", 8443, 443)}, "Caddy is published on loopback port 8443")

    check(postgres["environment"]["POSTGRES_PASSWORD"] == "pg-secret", "the PostgreSQL password comes from the settings")
    check("/var/lib/postgresql" in mounts(postgres) and mounts(postgres)["/var/lib/postgresql"]["type"] == "volume", "PostgreSQL data lives on a named volume at the PostgreSQL 18 path")

    command = garage["command"]
    check(command[:2] == ["/garage", "server"] and "--single-node" in command and "--default-bucket" in command, "Garage starts as a single node that creates its default bucket")
    env = garage["environment"]
    check(
        (env["GARAGE_DEFAULT_ACCESS_KEY"], env["GARAGE_DEFAULT_SECRET_KEY"], env["GARAGE_DEFAULT_BUCKET"], env["GARAGE_RPC_SECRET"])
        == ("GKaccess", "s3-secret", "bucket-from-env", "rpc-secret"),
        "Garage credentials, bucket and RPC secret come from the settings",
    )
    garage_mounts = mounts(garage)
    check(garage_mounts["/etc/garage.toml"]["read_only"] and garage_mounts["/var/lib/garage/meta"]["type"] == "volume" and garage_mounts["/var/lib/garage/data"]["type"] == "volume", "Garage reads its config and keeps metadata and data on named volumes")

    check(mounts(caddy)["/etc/caddy/Caddyfile"]["read_only"], "Caddy reads the Caddyfile")
    check(mounts(caddy)["/data"]["type"] == "volume", "Caddy keeps its local CA on a named volume, so trust survives restarts")
    hosts = caddy["extra_hosts"]  # a mapping or a list of host=address, depending on the compose version
    check(hosts in ({"host.docker.internal": "host-gateway"}, ["host.docker.internal=host-gateway"]), "Caddy can reach the server running on the host")

    for name, service in services.items():
        check("test" in service.get("healthcheck", {}), f"{name} has a healthcheck, so `up --wait` waits for it")


def check_garage_config():
    config = tomllib.loads(read(os.path.join(DEV, "garage.toml")))
    check(config["replication_factor"] == 1, "Garage runs without replication")
    check(config["s3_api"]["s3_region"] == "garage", "the S3 region is garage")
    check("rpc_secret" not in config and "admin" not in config, "no secret is committed in the Garage config")
    check(config["metadata_dir"] == "/var/lib/garage/meta" and config["data_dir"] == "/var/lib/garage/data", "Garage paths match the compose volumes")


def check_caddyfile():
    text = read(os.path.join(DEV, "Caddyfile"))
    check(re.search(r"^photolib\.localhost \{$", text, re.M), "Caddy serves photolib.localhost")
    check(re.search(r"^\s*tls internal$", text, re.M), "Caddy uses its local CA (tls internal)")
    check(re.search(r"^\s*reverse_proxy host\.docker\.internal:8080$", text, re.M), "Caddy proxies to the server on port 8080")
    check(re.search(r"^\s*auto_https disable_redirects$", text, re.M), "Caddy does not redirect to a port that is not published")


def check_hygiene():
    for name in ("compose.yaml", "garage.toml", "Caddyfile"):
        check(not re.search(r"[0-9a-f]{32}", read(os.path.join(DEV, name))), f"tools/dev/{name} holds no secret-looking value")
    for path in ("tools/dev/.env", "tools/dev/caddy-root.crt"):
        ignored = subprocess.run(["git", "check-ignore", "-q", "--no-index", path], cwd=ROOT, check=False).returncode == 0
        check(ignored, f"{path} is git-ignored")


present = [check(os.path.isfile(os.path.join(DEV, name)), f"tools/dev/{name} exists") for name in ("compose.yaml", "garage.toml", "Caddyfile")]
if all(present):
    check_compose()
    check_garage_config()
    check_caddyfile()
    check_hygiene()

finish()
