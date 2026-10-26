#!/usr/bin/env bash
# The 16 KB page-size check of Android native libraries (tools/page_size.py): every LOAD segment of an ELF library is
# aligned to at least 16 KB, and an APK stores its uncompressed libraries at 16 KB-aligned offsets.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
cd "$REPO_ROOT" || exit 1

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Fixtures: elf <path> <32|64> <load alignments...> writes a library header with one LOAD segment per alignment and
# a DYNAMIC segment aligned to 8; apk <path> <offset-pad|deflate> <so...> zips them under lib/arm64-v8a/.
python3 - "$TMP" <<'PY'
import struct, sys, zipfile
tmp = sys.argv[1]

def elf(name, bits, *aligns):
    phdrs = [(1, a) for a in aligns] + [(2, 8)]
    if bits == 64:
        head = struct.pack("<4sBBBx8xHHIQQQIHHHHHH", b"\x7fELF", 2, 1, 1, 3, 0xB7, 1, 0, 64, 0, 0, 64, 56,
                           len(phdrs), 0, 0, 0)
        body = b"".join(struct.pack("<IIQQQQQQ", t, 5, 0, 0, 0, 0, 0, a) for t, a in phdrs)
    else:
        head = struct.pack("<4sBBBx8xHHIIIIIHHHHHH", b"\x7fELF", 1, 1, 1, 3, 0x28, 1, 0, 52, 0, 0, 52, 32,
                           len(phdrs), 0, 0, 0)
        body = b"".join(struct.pack("<IIIIIIII", t, 0, 0, 0, 0, 0, 5, a) for t, a in phdrs)
    with open(f"{tmp}/{name}", "wb") as f:
        f.write(head + body)

def apk(name, aligned, compress, *libs):
    with zipfile.ZipFile(f"{tmp}/{name}", "w") as z:
        z.writestr("AndroidManifest.xml", b"x" * 100)
        for lib in libs:
            info = zipfile.ZipInfo(f"lib/arm64-v8a/{lib}")
            info.compress_type = zipfile.ZIP_DEFLATED if compress else zipfile.ZIP_STORED
            start = z.fp.tell() + 30 + len(info.filename) + 4
            pad = (-start) % 16384 + (0 if aligned else 4)
            info.extra = struct.pack("<HH", 0xD935, pad) + bytes(pad)
            z.writestr(info, open(f"{tmp}/{lib}", "rb").read())

elf("good64.so", 64, 0x4000, 0x4000)
elf("big64.so", 64, 0x10000)
elf("bad64.so", 64, 0x4000, 0x1000)
elf("good32.so", 32, 0x4000)
elf("bad32.so", 32, 0x1000)
open(f"{tmp}/text.so", "w").write("not a library\n")
apk("good.apk", True, False, "good64.so", "good32.so")
apk("deflated.apk", False, True, "good64.so")
apk("offset.apk", False, False, "good64.so")
apk("badlib.apk", True, False, "bad64.so")
apk("empty.apk", True, False)
PY

# check <file...>: output in $OUT, status in $STATUS.
check_files() {
  OUT=$(python3 tools/page_size.py "$@" 2>&1)
  STATUS=$?
}

passes() {
  local description=$1
  shift
  check_files "$@"
  [[ $STATUS -eq 0 ]] && ok "accepts $description" || fail "rejects $description: exit $STATUS $OUT"
}

rejects() {
  local description=$1 needle=$2
  shift 2
  check_files "$@"
  [[ $STATUS -eq 1 && $OUT == *"$needle"* ]] && ok "rejects $description" ||
    fail "does not reject $description with '$needle': exit $STATUS $OUT"
}

passes "64-bit libraries aligned to 16 KB and to 64 KB" "$TMP/good64.so" "$TMP/big64.so"
passes "a 32-bit library aligned to 16 KB" "$TMP/good32.so"
rejects "a 64-bit library with one LOAD segment aligned to 4 KB" "bad64.so: LOAD segment aligned to 4096" "$TMP/bad64.so"
rejects "a 32-bit library aligned to 4 KB" "bad32.so: LOAD segment aligned to 4096" "$TMP/bad32.so"
rejects "one bad library among good ones" "bad64.so" "$TMP/good64.so" "$TMP/bad64.so" "$TMP/good32.so"
rejects "a file that is not an ELF library" "text.so: not an ELF file" "$TMP/text.so"
passes "an APK that stores its libraries at 16 KB-aligned offsets" "$TMP/good.apk"
passes "an APK that compresses its libraries, wherever they start" "$TMP/deflated.apk"
rejects "an APK that stores a library at an unaligned offset" \
  "lib/arm64-v8a/good64.so: stored at offset" "$TMP/offset.apk"
rejects "an APK holding a library aligned to 4 KB" "lib/arm64-v8a/bad64.so: LOAD segment aligned to 4096" \
  "$TMP/badlib.apk"
rejects "an APK without native libraries, which proves nothing" "no native libraries" "$TMP/empty.apk"
check_files
[[ $STATUS -eq 2 ]] && ok "no argument is a usage error" || fail "no argument: exit $STATUS, want 2"

finish
