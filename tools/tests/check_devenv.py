#!/usr/bin/env python3
"""Checks for the developer environment files: .pre-commit-config.yaml and .devcontainer.json."""
import json
import os
import re

import miniyaml
from checklib import ROOT, check, finish, read


def load(path, parse):
    if not check(os.path.isfile(os.path.join(ROOT, path)), f"{path} exists"):
        return None
    try:
        return parse(read(path))
    except ValueError as error:
        check(False, f"{path} parses ({error})")
        return None


def check_pre_commit():
    config = load(".pre-commit-config.yaml", miniyaml.load)
    if config is None:
        return
    repos = config.get("repos", [])
    hooks = {hook["id"]: hook for repo in repos for hook in repo.get("hooks", [])}
    gate, lint = hooks.get("check", {}), hooks.get("commitlint", {})

    check(sorted(config.get("default_install_hook_types", [])) == ["commit-msg", "pre-commit"], "`pre-commit install` sets up the pre-commit and commit-msg hooks")
    check(len(repos) == 1 and repos[0].get("repo") == "local" and set(hooks) == {"check", "commitlint"}, "two local hooks, so no hook repository is downloaded")
    check(gate.get("entry") == "bash tools/check.sh" and gate.get("language") == "system", "the check hook runs the quality gate")
    check(gate.get("pass_filenames") is False and gate.get("always_run") is True, "the gate gets no file list and runs on every commit")
    check(gate.get("stages", ["pre-commit"]) == ["pre-commit"], "the gate runs before the commit")
    check(lint.get("entry") == "bash tools/commitlint.sh --file" and lint.get("language") == "system", "the commitlint hook lints the message file")
    check(lint.get("stages") == ["commit-msg"], "commitlint runs at the commit-msg stage")


def check_devcontainer():
    config = load(".devcontainer.json", json.loads)
    if config is None:
        return
    features = config.get("features", {})
    docker = features.get("ghcr.io/devcontainers/features/docker-in-docker:2")
    command = config.get("postCreateCommand", "")

    check(config.get("image", "").startswith("mcr.microsoft.com/devcontainers/base:trixie"), "the image is the Debian 13 base, which packages just and pre-commit")
    check(isinstance(docker, dict) and docker.get("moby") is False, "Docker-in-Docker installs Docker CE, because Moby has no Debian 13 packages")
    check("ghcr.io/devcontainers/features/rust:1" in features, "the Rust toolchain is installed")
    check("ghcr.io/devcontainers/features/node:1" in features, "Node is installed, so that tools/buf.sh can fetch buf and the gate's proto part runs")
    check("apt-get install" in command and all(package in command for package in ("just", "pre-commit", "python3")), "postCreateCommand installs just, pre-commit and python3")
    check("libvips-dev" in command and "libheif-plugin-libde265" in command,
          "postCreateCommand installs libvips and its HEVC decoder, which photolibd's renderer links and loads")
    check(re.search(r"apt-get install .*\bpostgresql-\d+\b", command) and "create_main_cluster = false" in command,
          "postCreateCommand installs the PostgreSQL programs the database tests need, without a cluster on port 5432")
    check(command.rstrip().endswith("bash tools/dev/bootstrap.sh"), "postCreateCommand ends by bootstrapping the clone")
    check({3900, 5432, 8443} <= set(config.get("forwardPorts", [])), "the S3, PostgreSQL and Caddy ports are forwarded")


check_pre_commit()
check_devcontainer()
finish()
