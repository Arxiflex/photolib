#!/usr/bin/env python3
"""Writes a CycloneDX 1.6 SBOM of a release to stdout: every third-party package its lock files pin.

    tools/sbom.py <name> <version> <lock file>...

Lock files are Cargo.lock, pubspec.lock and package-lock.json. Each component has its package URL and the hash its lock
file pins; workspace, path, SDK and linked packages are first-party or toolchain, not components. SOURCE_DATE_EPOCH
dates the document, so that a release's SBOM is reproducible. Exit status 2: not a lock file, or a package from
anything but crates.io, pub.dev or the npm registry, which these package URLs would misname.
"""
import base64
import json
import os
import re
import sys
import time
import tomllib
import uuid
from pathlib import Path


def default_registry(name, source, *registries):
    if not source.startswith(registries):
        print(f"sbom.py: {name} comes from {source}: only crates.io, pub.dev and the npm registry have package URLs here",
              file=sys.stderr)
        sys.exit(2)


def component(ecosystem, name, version, algorithm=None, digest=None):
    namespace, _, name = name.rpartition("/")
    purl = f"pkg:{ecosystem}/{namespace.replace('@', '%40') + '/' if namespace else ''}{name}@{version}"
    entry = {"type": "library", "bom-ref": purl, "name": name, "version": version, "purl": purl}
    if namespace:
        entry["group"] = namespace
    if digest:
        entry["hashes"] = [{"alg": algorithm, "content": digest}]
    return entry


def cargo(text):
    for package in tomllib.loads(text).get("package", []):
        if "source" in package:
            default_registry(package["name"], package["source"], "registry+https://github.com/rust-lang/crates.io-index",
                             "sparse+https://index.crates.io/")
            yield component("cargo", package["name"], package["version"], "SHA-256", package.get("checksum"))


def pub(text):
    for name, body in re.findall(r"^  (\S+):\n((?:    .*\n)+)", text + "\n", re.M):
        field = dict(re.findall(r"^ +(\w+): \"?([^\"\n]*)\"?$", body, re.M))
        if field.get("source") not in ("sdk", "path"):
            default_registry(name, f"{field.get('source')} {field.get('url', '')}", "hosted https://pub.dev")
            yield component("pub", name, field["version"], "SHA-256", field["sha256"])


def npm(text):
    for path, package in json.loads(text)["packages"].items():
        if "node_modules/" in path and not package.get("link"):
            default_registry(path, package.get("resolved", "https://registry.npmjs.org/"), "https://registry.npmjs.org/")
            algorithm, _, digest = package.get("integrity", "").partition("-")
            digest = digest and base64.b64decode(digest).hex()
            yield component("npm", path.rpartition("node_modules/")[2], package["version"],
                            algorithm.upper().replace("SHA", "SHA-"), digest)


READERS = {"Cargo.lock": cargo, "pubspec.lock": pub, "package-lock.json": npm}


def main(args):
    unknown = [lock for lock in args[2:] if Path(lock).name not in READERS]
    if len(args) < 3 or unknown:
        print(f"sbom.py: not a lock file: {' '.join(unknown)}\n{__doc__}", file=sys.stderr)
        return 2
    name, version = args[:2]
    components = {c["bom-ref"]: c for lock in args[2:] for c in READERS[Path(lock).name](Path(lock).read_text())}
    refs = sorted(components)
    epoch = int(os.environ.get("SOURCE_DATE_EPOCH", time.time()))
    bom = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "serialNumber": f"urn:uuid:{uuid.uuid5(uuid.NAMESPACE_URL, ' '.join([name, version, *refs]))}",
        "version": 1,
        "metadata": {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(epoch)),
            "component": {"type": "application", "bom-ref": f"pkg:generic/{name}@{version}", "name": name,
                          "version": version, "licenses": [{"license": {"id": "AGPL-3.0-only"}}]},
        },
        "components": [components[ref] for ref in refs],
    }
    json.dump(bom, sys.stdout, indent=1)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
