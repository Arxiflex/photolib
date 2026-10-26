#!/usr/bin/env python3
"""Checks that every third-party npm package of a package.json is under a licence on the allow-list.

    tools/node_licenses.py <package-dir> [<deny.toml>]

The list is `licenses.allow` of deny.toml (ADR-0013), the one cargo-deny and tools/dart_licenses.py use. The licence
of a package is the SPDX expression its package-lock.json entry records: `OR` needs one allowed side, `AND` both, and
a package without one fails. Linked packages are first-party. Exit status: 0 all allowed, 1 a package is not allowed,
2 usage error.
"""
import json
import re
import sys
import tomllib
from pathlib import Path

DEFAULT_CONFIG = Path(__file__).resolve().parent.parent / "deny.toml"


def permitted(expression, allowed):
    tokens = re.findall(r"[()]|[^\s()]+", expression)

    def either(at):  # OR binds looser than AND
        value, at = both(at)
        while at < len(tokens) and tokens[at] == "OR":
            right, at = both(at + 1)
            value = value or right
        return value, at

    def both(at):
        value, at = term(at)
        while at < len(tokens) and tokens[at] == "AND":
            right, at = term(at + 1)
            value = value and right
        return value, at

    def term(at):
        if tokens[at] == "(":
            value, at = either(at + 1)
            if tokens[at] != ")":
                raise IndexError
            return value, at + 1
        if tokens[at] in ("AND", "OR", ")"):
            raise IndexError
        if at + 2 < len(tokens) and tokens[at + 1] == "WITH":
            return " ".join(tokens[at:at + 3]) in allowed, at + 3
        return tokens[at] in allowed, at + 1

    try:
        value, at = either(0)
    except IndexError:
        return False
    return value and at == len(tokens)


def main(args):
    if len(args) not in (1, 2):
        print(__doc__, file=sys.stderr)
        return 2
    allowed = set(tomllib.loads(Path(args[1] if len(args) == 2 else DEFAULT_CONFIG).read_text())["licenses"]["allow"])
    lock = Path(args[0]) / "package-lock.json"
    if not lock.is_file():
        print(f"node_licenses: {lock} not found; run 'npm install' first", file=sys.stderr)
        return 1
    packages = {path: entry for path, entry in json.loads(lock.read_text())["packages"].items()
                if path.startswith("node_modules/") or "/node_modules/" in path}
    problems = []
    for path, entry in sorted(packages.items()):
        name, licence = path.rsplit("node_modules/", 1)[1], entry.get("license")
        if entry.get("link"):
            continue
        if not isinstance(licence, str):
            problems.append(f"{name}: package-lock.json records no licence")
        elif not permitted(licence, allowed):
            problems.append(f"{name}: '{licence}' is not on the allow-list")
    for problem in problems:
        print(f"node_licenses: {args[0]}: {problem}", file=sys.stderr)
    if not problems:
        print(f"node_licenses: {args[0]}: {len(packages)} third-party packages, all on the allow-list")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
