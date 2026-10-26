#!/usr/bin/env bash
# tools/macos/bundle_vips.py puts Homebrew's libvips, its dependencies and its HEIF and JPEG XL modules into the built
# macOS app (ADR-0394): it walks the non-system dependencies per architecture, rewrites install names to
# @loader_path, drops RPATHs, joins the slices with lipo and signs libraries, then the app. Xcode's tools are stubbed
# (they exist only on a Mac); every stub and every run has a hard timeout, as a test that hangs holds the gate for
# minutes.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
cd "$REPO_ROOT" || exit 1

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
BIN=$TMP/bin WORLD=$TMP/world
mkdir -p "$BIN" "$WORLD/deps" "$WORLD/rpaths"
export WORLD LOG=$TMP/calls.log

# The stubs read a table per file name: deps/<name> (one install name per line, the library's own id first, @P@ for the
# Homebrew prefix the file came from, written on the file's first line) and rpaths/<name>.
cat >"$BIN/otool" <<'STUB'
#!/bin/bash
file=$2 name=$(basename "$2") prefix=$(head -n 1 "$2")
echo "$file:"
if [[ $1 == -D ]]; then
  [[ $name != vips-* && -f $WORLD/deps/$name ]] && sed "s|@P@|$prefix|" "$WORLD/deps/$name" | head -n 1
elif [[ $1 == -L ]]; then
  [[ -f $WORLD/deps/$name ]] && sed "s|@P@|$prefix|; s|^|\t|; s|\$| (compatibility version 1.0.0)|" "$WORLD/deps/$name"
else
  [[ -f $WORLD/rpaths/$name ]] && sed "s|^|          cmd LC_RPATH\n      cmdsize 32\n         path |; s|\$| (offset 12)|" "$WORLD/rpaths/$name"
fi
exit 0
STUB
cat >"$BIN/lipo" <<'STUB'
#!/bin/bash
if [[ $1 == -archs ]]; then cat "$WORLD/archs"; exit 0; fi
echo "lipo $*" >>"$LOG"
out=${@: -1}
files=("${@:2:$#-3}")
cat "${files[@]}" >"$out"
STUB
cat >"$BIN/install_name_tool" <<'STUB'
#!/bin/bash
echo "install_name_tool $*" >>"$LOG"
STUB
cat >"$BIN/codesign" <<'STUB'
#!/bin/bash
echo "codesign $*" >>"$LOG"
[[ $* == *--verify* && -f $WORLD/verify-fails ]] && exit 1
exit 0
STUB
chmod +x "$BIN"/*

# world <arch...>: an app of the architectures and a Homebrew tree per architecture (arm64: brew-arm64, x86_64: brew-x64).
world() {
  rm -rf "$TMP/app" "$TMP/brew-arm64" "$TMP/brew-x64" "$WORLD"/deps/* "$WORLD"/rpaths/*
  mkdir -p "$TMP/app/Contents/MacOS" "$TMP/app/Contents/Frameworks"
  echo executable >"$TMP/app/Contents/MacOS/photolib"
  echo "$*" >"$WORLD/archs"
  local arch dir
  for arch in "$@"; do
    dir=$TMP/brew-${arch/x86_64/x64}
    mkdir -p "$dir/lib/vips-modules-8.18" "$dir/opt/glib/lib" "$dir/opt/libheif/lib" "$dir/opt/libjxl/lib"
    printf '%s\n%s libvips\n' "$dir" "$arch" >"$dir/lib/libvips.42.8.dylib"
    ln -s libvips.42.8.dylib "$dir/lib/libvips.42.dylib"
    printf '%s\n%s glib\n' "$dir" "$arch" >"$dir/opt/glib/lib/libglib-2.0.0.dylib"
    printf '%s\n%s heif\n' "$dir" "$arch" >"$dir/opt/libheif/lib/libheif.1.dylib"
    printf '%s\n%s de265\n' "$dir" "$arch" >"$dir/opt/libheif/lib/libde265.0.dylib"
    printf '%s\n%s jxl\n' "$dir" "$arch" >"$dir/opt/libjxl/lib/libjxl.0.11.dylib"
    printf '%s\n%s module-heif\n' "$dir" "$arch" >"$dir/lib/vips-modules-8.18/vips-heif.dylib"
    printf '%s\n%s module-jxl\n' "$dir" "$arch" >"$dir/lib/vips-modules-8.18/vips-jxl.so"
  done
  # Homebrew links absolute opt paths; libheif finds its sibling through an @rpath.
  printf '%s\n' '@P@/lib/libvips.42.dylib' '@P@/opt/glib/lib/libglib-2.0.0.dylib' /usr/lib/libSystem.B.dylib \
    /System/Library/Frameworks/CoreFoundation.framework/CoreFoundation >"$WORLD/deps/libvips.42.8.dylib"
  cp "$WORLD/deps/libvips.42.8.dylib" "$WORLD/deps/libvips.42.dylib"
  printf '%s\n' '@P@/opt/glib/lib/libglib-2.0.0.dylib' /usr/lib/libSystem.B.dylib >"$WORLD/deps/libglib-2.0.0.dylib"
  printf '%s\n' '@P@/opt/libheif/lib/libheif.1.dylib' '@P@/opt/glib/lib/libglib-2.0.0.dylib' >"$WORLD/deps/vips-heif.dylib"
  printf '%s\n' '@P@/opt/libjxl/lib/libjxl.0.11.dylib' '@P@/opt/glib/lib/libglib-2.0.0.dylib' >"$WORLD/deps/vips-jxl.so"
  printf '%s\n' '@P@/opt/libheif/lib/libheif.1.dylib' '@rpath/libde265.0.dylib' /usr/lib/libc++.1.dylib \
    >"$WORLD/deps/libheif.1.dylib"
  echo '@loader_path/' >"$WORLD/rpaths/libheif.1.dylib"
  printf '%s\n' '@P@/opt/libjxl/lib/libjxl.0.11.dylib' >"$WORLD/deps/libjxl.0.11.dylib"
  : >"$WORLD/deps/libde265.0.dylib"
  rm -f "$WORLD/verify-fails"
}

OPTIONS=()
# bundle: runs the script with the stubs first on PATH; output in $OUT, status in $STATUS, tool calls in $CALLS.
bundle() {
  : >"$LOG"
  OUT=$(PATH="$BIN:$PATH" timeout 60 python3 tools/macos/bundle_vips.py "$TMP/app" app/macos/Runner/Release.entitlements \
    --prefix "arm64=$TMP/brew-arm64" --prefix "x86_64=$TMP/brew-x64" "${OPTIONS[@]}" 2>&1)
  STATUS=$?
  CALLS=$(<"$LOG")
}
F=$TMP/app/Contents/Frameworks

world arm64 x86_64
bundle
[[ $STATUS -eq 0 ]] && ok "bundles a universal app" || fail "universal: exit $STATUS $OUT"
listing=$(cd "$F" && find . -type f | LC_ALL=C sort | tr '\n' ' ')
expected="./libde265.0.dylib ./libglib-2.0.0.dylib ./libheif.1.dylib ./libjxl.0.11.dylib ./libvips.42.dylib ./vips-modules/vips-heif.dylib ./vips-modules/vips-jxl.so "
[[ $listing == "$expected" ]] && ok "copies libvips, every non-system dependency (rpath ones too) and the HEIF and JXL modules" ||
  fail "Frameworks hold: $listing"
[[ $(<"$F/libglib-2.0.0.dylib") == *"arm64 glib"*"x86_64 glib"* ]] && ok "joins each library's slices with lipo" ||
  fail "libglib is $(<"$F/libglib-2.0.0.dylib")"
[[ $CALLS != *libSystem*lipo* && $listing != *libSystem* && $listing != *CoreFoundation* ]] &&
  ok "leaves system libraries alone" || fail "system libraries bundled: $listing"

edit=$(grep '^install_name_tool' <<<"$CALLS")
for arch in brew-arm64 brew-x64; do
  grep -q -- "-id @loader_path/libvips.42.dylib -change $TMP/$arch/opt/glib/lib/libglib-2.0.0.dylib @loader_path/libglib-2.0.0.dylib .*libvips.42.dylib\$" <<<"$edit" &&
    ok "$arch: libvips takes @loader_path names" || fail "$arch: libvips edit missing in: $edit"
  grep -q -- "-change $TMP/$arch/opt/libheif/lib/libheif.1.dylib @loader_path/../libheif.1.dylib .*vips-heif.dylib\$" <<<"$edit" &&
    ok "$arch: a module reaches its libraries one folder up" || fail "$arch: module edit missing in: $edit"
done
grep -q -- "-change @rpath/libde265.0.dylib @loader_path/libde265.0.dylib -delete_rpath @loader_path/ .*libheif.1.dylib\$" <<<"$edit" &&
  ok "an @rpath reference is resolved beside its library and the RPATH removed" || fail "rpath edit missing in: $edit"
[[ $edit != *"-change /usr/lib"* && $edit != *"-change /System"* ]] && ok "system references are not rewritten" ||
  fail "system references rewritten: $edit"
[[ $(grep -c "^lipo -create" <<<"$CALLS") -eq 7 ]] && ok "7 files joined" || fail "lipo calls: $(grep -c '^lipo -create' <<<"$CALLS")"

signs=$(grep '^codesign' <<<"$CALLS" | sed "s|$TMP/||")
first_lib=$(grep -n 'vips-modules' <<<"$signs" | head -1 | cut -d: -f1)
app_line=$(grep -n -- '--entitlements' <<<"$signs" | cut -d: -f1)
last_lib=$(grep -n 'Frameworks/lib' <<<"$signs" | tail -1 | cut -d: -f1)
[[ $first_lib -lt $last_lib && $last_lib -lt $app_line && $(grep -c -- '--sign -' <<<"$signs") -eq 8 ]] &&
  ok "signs ad hoc each module, each library, then the app" || fail "signing order: $signs"
[[ $signs == *"--entitlements"*"Release.entitlements app"* && $signs == *"--verify --deep --strict app" ]] &&
  ok "signs the app with Release.entitlements and verifies it last" || fail "app signing: $signs"
[[ $signs != *"--options runtime"* ]] && ok "no hardened runtime on the ad hoc build (package.sh signs for release)" ||
  fail "ad hoc signing uses the runtime: $signs"

# (the staging folders are random names)
same() { sed -E 's|/[^ ]*/tmp[a-z0-9_]+/||g' <<<"$1"; }
cp -r "$F" "$TMP/first" && first_calls=$(same "$CALLS")
bundle
[[ $STATUS -eq 0 && $(same "$CALLS") == "$first_calls" ]] && diff -r "$F" "$TMP/first" >/dev/null &&
  ok "running again changes nothing" || fail "second run differs: exit $STATUS"

world arm64 x86_64
rm -rf "$TMP/brew-x64"
bundle
[[ $STATUS -eq 0 && $OUT == *"WARNING: no Homebrew libvips for x86_64"*"arch -x86_64"* && $OUT == *"no libvips for x86_64"* ]] &&
  ok "an architecture without Homebrew's libvips is warned about by name, and the other is bundled" ||
  fail "one slice: exit $STATUS $OUT"
[[ $(<"$F/libglib-2.0.0.dylib") == *"arm64 glib" && $CALLS != *lipo\ -create* ]] &&
  ok "that app's libraries are the one slice" || fail "thin libglib: $(<"$F/libglib-2.0.0.dylib")"

world arm64 x86_64
rm -rf "$TMP/brew-arm64" "$TMP/brew-x64"
bundle
[[ $STATUS -ne 0 && $OUT == *"brew install vips"* && $CALLS != *codesign* ]] &&
  ok "without Homebrew's libvips it fails, saying brew install vips, and signs nothing" || fail "no libvips: $STATUS $OUT"

OPTIONS=(--optional)
bundle
[[ $STATUS -eq 0 && $OUT == *"WARNING"*"brew install vips"* && $CALLS != *codesign* ]] &&
  ok "--optional (debug builds) only warns when there is no libvips" || fail "optional: $STATUS $OUT"
OPTIONS=()

world arm64 x86_64
rm "$TMP/brew-arm64/opt/glib/lib/libglib-2.0.0.dylib"
bundle
[[ $STATUS -ne 0 && $OUT == *"libglib-2.0.0.dylib was not found"* && $CALLS != *codesign* ]] &&
  ok "a dependency that is missing fails the build by name" || fail "missing dependency: $STATUS $OUT"

world arm64
touch "$WORLD/verify-fails"
bundle
[[ $STATUS -ne 0 && $OUT == *"--verify"* ]] && ok "a signature that does not verify fails the build" || fail "verify: $STATUS $OUT"

mkdir -p "$TMP/empty"
OUT=$(PATH="$BIN:$PATH" timeout 60 python3 tools/macos/bundle_vips.py "$TMP/empty" x 2>&1)
[[ $? -ne 0 && $OUT == *"is not a built app"* ]] && ok "refuses a folder that is no app" || fail "not an app: $OUT"

# --- the Xcode project runs it after Flutter has embedded its frameworks (a pbxproj cannot be built here)
PBX=app/macos/Runner.xcodeproj/project.pbxproj
verdict=$(timeout 30 python3 -I - "$PBX" <<'PY'
import re, sys

text = open(sys.argv[1], encoding="utf-8").read()
plain = re.sub(r'"(?:[^"\\]|\\.)*"', '""', text)
print("balanced" if plain.count("{") == plain.count("}") and plain.count("(") == plain.count(")") else "unbalanced")
ids = re.findall(r"^\t\t([0-9A-F]{24}) /\* Bundle libvips \*/ = \{", text, re.MULTILINE)
runner = re.search(r"/\* Runner \*/ = \{\s*isa = PBXNativeTarget;.*?buildPhases = \((.*?)\);", text, re.DOTALL)
names = re.findall(r"/\* (.+?) \*/", runner.group(1))
print(len(ids) == 1 and ids[0] in runner.group(1), names[-2:])
print("tools/macos/bundle_vips.py" in text)
PY
)
[[ $verdict == "balanced"$'\n'"True ['ShellScript', 'Bundle libvips']"$'\n'"True" ]] &&
  ok "$PBX: Runner runs 'Bundle libvips' last, after Flutter embeds its frameworks, in a well-formed project" ||
  fail "$PBX: $verdict"

finish
