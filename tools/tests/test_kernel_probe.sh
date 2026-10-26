#!/usr/bin/env bash
# The APK check of tools/kernel/probe.sh, with flutter stubbed to build a synthetic APK: every ABI's kernel is found
# wherever the listing holds it (photolib-design#595: grep -q ended the listing early and failed under pipefail).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
require_tool unzip
sandbox_tools bash dirname mktemp rm unzip python3 mkdir cp
TMP=$(mktemp -d)
SANDBOXES+=("$TMP")
mkdir "$TMP/bin" "$TMP/artifacts"

# apk <name> <abi...>: each ABI's kernel (a header with a 16 KB-aligned LOAD segment) first, then 3,000 assets.
python3 - "$TMP" <<'PY'
import struct, sys, zipfile
tmp = sys.argv[1]
elf = struct.pack("<4sBBBx8xHHIQQQIHHHHHH", b"\x7fELF", 2, 1, 1, 3, 0xB7, 1, 0, 64, 0, 0, 64, 56, 1, 0, 0, 0) + \
    struct.pack("<IIQQQQQQ", 1, 5, 0, 0, 0, 0, 0, 0x4000)

def apk(name, *abis):
    with zipfile.ZipFile(f"{tmp}/{name}", "w", zipfile.ZIP_DEFLATED) as z:
        for abi in abis:
            z.writestr(f"lib/{abi}/libphotolib_kernel_ffi.so", elf)
        for i in range(3000):
            z.writestr(f"assets/flutter_assets/packages/probe/asset_{i:05}.bin", b"")

apk("all.apk", "arm64-v8a", "armeabi-v7a", "x86_64")
apk("no-x64.apk", "arm64-v8a", "armeabi-v7a")
PY
cat >"$TMP/bin/flutter" <<'STUB'
#!/bin/bash
case $1 in
  create) mkdir -p "${@: -1}" ;;
  build) mkdir -p build/app/outputs/flutter-apk && cp "$PROBE_APK" build/app/outputs/flutter-apk/app-release.apk ;;
esac
STUB
chmod +x "$TMP/bin/flutter"

probe() { PROBE_APK=$TMP/$1 PATH="$TMP/bin:$BASE_BIN" capture bash "$REPO_ROOT/tools/kernel/probe.sh" "$TMP/artifacts" apk; }

probe all.apk
expect_result "finds every ABI's kernel listed before 3,000 other entries" 0
probe no-x64.apk
expect_result "fails naming the ABI whose kernel the APK lacks" 1 "probe.sh: no x86_64 kernel"

finish
