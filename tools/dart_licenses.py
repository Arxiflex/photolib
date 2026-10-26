#!/usr/bin/env python3
"""Checks that every third-party package of a Dart or Flutter package is under a licence on the allow-list.

    tools/dart_licenses.py <package-dir> [<deny.toml>]

The list is `licenses.allow` of deny.toml (ADR-0013), the one cargo-deny uses. Licences are recognised by their
text in each package's LICENSE file, so a licence the checker does not recognise fails: extend PHRASES when a real
dependency needs it. Needs `.dart_tool/package_config.json` (`flutter pub get`). Packages at relative paths are
first-party. Packages inside the Flutter SDK (`flutterRoot` of package_config.json) are covered by the SDK's own root
LICENSE. Exit status: 0 all allowed, 1 a package is not allowed, 2 usage error.
"""
import json
import sys
import tomllib
from pathlib import Path
from urllib.parse import unquote, urlparse

DEFAULT_CONFIG = Path(__file__).resolve().parent.parent / "deny.toml"
LICENCE_FILES = ("LICENSE", "LICENCE", "COPYING", "UNLICENSE")
PHRASES = {
    "MIT": ("permission is hereby granted, free of charge",),
    "Apache-2.0": ("apache license", "version 2.0"),
    "ISC": ("permission to use, copy, modify, and/or distribute this software for any purpose with or without fee",),
    "Zlib": ("altered source versions must be plainly marked",),
    "MPL-2.0": ("mozilla public license", "version 2.0"),
    "Unlicense": ("free and unencumbered software released into the public domain",),
    "CC0-1.0": ("cc0 1.0 universal",),
}


def detect(text):
    text = " ".join(text.lower().split())
    found = {spdx for spdx, phrases in PHRASES.items() if all(p in text for p in phrases)}
    if "redistribution and use in source and binary forms" in text:
        if "advertising materials" in text:
            found.add("BSD-4-Clause")
        else:
            found.add("BSD-3-Clause" if "endorse or promote" in text else "BSD-2-Clause")
    return found


def licence_text(root):
    files = sorted(f for f in root.iterdir() if f.name.upper().startswith(LICENCE_FILES)) if root.is_dir() else []
    return "\n".join(f.read_text(errors="replace") for f in files if f.is_file())


def main(args):
    if len(args) not in (1, 2):
        print(__doc__, file=sys.stderr)
        return 2
    package_dir = Path(args[0])
    allowed = set(tomllib.loads(Path(args[1] if len(args) == 2 else DEFAULT_CONFIG).read_text())["licenses"]["allow"])
    config = package_dir / ".dart_tool" / "package_config.json"
    if not config.is_file():
        print(f"dart_licenses: {config} not found; run 'flutter pub get' first", file=sys.stderr)
        return 1

    package_config = json.loads(config.read_text())
    flutter_root = package_config.get("flutterRoot")
    sdk = Path(unquote(urlparse(flutter_root).path)) if flutter_root else None
    packages = [(p["name"], Path(unquote(urlparse(p["rootUri"]).path)))
                for p in package_config["packages"] if p["rootUri"].startswith("file:")]
    problems = []
    for name, root in packages:
        if sdk and root.is_relative_to(sdk):
            root = sdk
        text = licence_text(root)
        found = detect(text)
        if not text.strip():
            problems.append(f"{name}: no licence file in {root}")
        elif not found:
            problems.append(f"{name}: licence not recognised, see {root}")
        elif found - allowed:
            problems.append(f"{name}: {', '.join(sorted(found - allowed))} is not on the allow-list")
    for problem in problems:
        print(f"dart_licenses: {package_dir}: {problem}", file=sys.stderr)
    if not problems:
        print(f"dart_licenses: {package_dir}: {len(packages)} third-party packages, all on the allow-list")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
