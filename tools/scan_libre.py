#!/usr/bin/env python3
"""Proprietary-dependency scan for the libre (F-Droid) Android flavour.

    scan_libre.py <file>...

Each file is a dependency listing (`gradlew :app:dependencies`, pubspec.lock) or a built `.apk`, whose entry names and
dex files are searched. Fails (exit 1) on Google Play Services, Firebase, ML Kit, Play Core and Billing, Huawei
services and the Flutter plugins that wrap them. Exit 2 on a usage error or an unreadable file.
"""
import re
import sys
import zipfile

JVM = (rb"com[./]google[./]android[./](?:gms|play)\b|com[./]google[./](?:firebase|mlkit)\b"
       rb"|com[./]android[./]billingclient\b|com[./]huawei[./]hms\b")
DART = rb"^\s*(?:firebase_\w+|google_mlkit_\w+|google_maps_flutter\w*|google_sign_in\w*|in_app_purchase_android):"
PROPRIETARY = re.compile(rb"(?:%s)|(?:%s)" % (JVM, DART), re.MULTILINE)


def hits(data):
    return sorted({m.group().strip().decode() for m in PROPRIETARY.finditer(data)})


def scan(path):
    if not path.endswith(".apk"):
        with open(path, "rb") as f:
            return hits(f.read())
    with zipfile.ZipFile(path) as apk:
        names = "\n".join(apk.namelist()).encode()
        dex = b"\n".join(apk.read(n) for n in apk.namelist() if n.endswith(".dex"))
    return hits(names + b"\n" + dex)


def die(message):
    print(f"scan_libre.py: {message}", file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        die("usage: scan_libre.py <dependency listing or apk>...")
    failed = False
    for path in sys.argv[1:]:
        try:
            found = scan(path)
        except (OSError, zipfile.BadZipFile) as error:
            die(f"cannot read {path}: {error}")
        for name in found:
            print(f"{path}: proprietary component {name}", file=sys.stderr)
        failed = failed or bool(found)
    sys.exit(1 if failed else 0)
