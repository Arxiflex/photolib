#!/usr/bin/env bash
# The kernel's cross-build (tools/kernel/build.py): each target name builds kernel/ffi for its Rust target, Android
# links with the NDK's clang for 16 KB pages, and prebuilt.json pins the SHA-256 of every library in the output, each
# within ADR-0004's 3 MB budget; ADR-0026 records the choices as Accepted.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
cd "$REPO_ROOT" || exit 1

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/sdk/ndk/9.1.0" "$TMP/sdk/ndk/28.2.1" "$TMP/sdk/ndk/28.10.0"

# Stub cargo: logs its Rust target and linker settings, writes a library holding the Rust target's name and
# reports it as cargo does (on Windows the import library comes first).
cat >"$TMP/bin/cargo" <<'STUB'
#!/bin/bash
while [[ $# -gt 0 ]]; do [[ $1 == --target ]] && triple=$2; shift; done
echo "cargo $triple $(env | grep -E "^CARGO_TARGET_\w+_(LINKER|RUSTFLAGS)=" | sort | tr '\n' ' ')@$PWD" >>"$STUB_LOG"
[[ $triple == "$STUB_FAIL" ]] && exit 101
case $triple in
  *windows*) files=(photolib_kernel_ffi.dll.lib photolib_kernel_ffi.dll) ;;
  *apple*) files=(libphotolib_kernel_ffi.dylib) ;;
  *) files=(libphotolib_kernel_ffi.so) ;;
esac
dir=$STUB_TARGET/$triple/release
mkdir -p "$dir"
names=()
for file in "${files[@]}"; do
  [[ $file == *.lib ]] && echo import library >"$dir/$file" || printf '%s' "$triple" >"$dir/$file"
  names+=("\"$dir/$file\"")
done
echo '{"reason":"compiler-artifact","target":{"name":"photolib_kernel"},"filenames":["x.rlib"]}'
echo "{\"reason\":\"compiler-artifact\",\"target\":{\"name\":\"photolib_kernel_ffi\"},\"filenames\":[$(IFS=,; echo "${names[*]}")]}"
STUB
printf '#!/bin/bash\necho "rustup $*" >>"$STUB_LOG"\n' >"$TMP/bin/rustup"
chmod +x "$TMP/bin/cargo" "$TMP/bin/rustup"
export STUB_LOG=$TMP/calls.log STUB_TARGET=$TMP/target STUB_FAIL=none ANDROID_HOME=$TMP/sdk
unset ANDROID_NDK_HOME
# The stub logs only what build.py sets, not the caller's linker (the agents' gate links with mold).
for var in $(compgen -e); do [[ $var != CARGO_TARGET_* ]] || unset "$var"; done

# build <args...>: output in $OUT, status in $STATUS, calls in $CALLS.
build() {
  : >"$STUB_LOG"
  OUT=$(PATH="$TMP/bin:$PATH" python3 tools/kernel/build.py "$@" 2>&1)
  STATUS=$?
  CALLS=$(cat "$STUB_LOG")
}

# pins <dir>: "name=sha256" per pinned library, then "release=<url>".
pins() {
  python3 -c 'import json, sys; m = json.load(open(sys.argv[1] + "/prebuilt.json"))
for k, v in sorted(m["sha256"].items()): print(f"{k}={v}")
print("release=" + str(m.get("release")))' "$1"
}

ALL=(android-arm64 android-arm android-x64 ios-arm64 ios-sim-arm64 ios-sim-x64 macos-arm64 macos-x64 windows-x64
  linux-x64 linux-arm64)
TRIPLES=(aarch64-linux-android armv7-linux-androideabi x86_64-linux-android aarch64-apple-ios aarch64-apple-ios-sim
  x86_64-apple-ios aarch64-apple-darwin x86_64-apple-darwin x86_64-pc-windows-msvc x86_64-unknown-linux-gnu
  aarch64-unknown-linux-gnu)

build --out "$TMP/all" "${ALL[@]}"
[[ $STATUS -eq 0 ]] && ok "builds every native target" || fail "building every target: exit $STATUS $OUT"
mapped=1
for i in "${!ALL[@]}"; do
  library=libphotolib_kernel_ffi.so
  [[ ${ALL[i]} == windows-* ]] && library=photolib_kernel_ffi.dll
  [[ ${ALL[i]} == ios-* || ${ALL[i]} == macos-* ]] && library=libphotolib_kernel_ffi.dylib
  file="$TMP/all/${ALL[i]}-$library"
  [[ -f $file && $(cat "$file") == "${TRIPLES[i]}" ]] || { mapped=0; fail "${ALL[i]} is not ${TRIPLES[i]} in $file"; }
  [[ $CALLS == *"rustup target add ${TRIPLES[i]}"* ]] || { mapped=0; fail "${TRIPLES[i]} is not installed first"; }
done
[[ $mapped -eq 1 ]] && ok "each target is its Rust target's library, named <target>-<library>"
[[ $(find "$TMP/all" -type f | wc -l) -eq 12 ]] && ok "the output holds the libraries and prebuilt.json only" ||
  fail "unexpected output: $(ls "$TMP/all")"
[[ $CALLS == *"@$REPO_ROOT/kernel"* && $CALLS != *"@$REPO_ROOT "* ]] && ok "cargo builds the kernel workspace" ||
  fail "cargo did not run in kernel/: $CALLS"

pinned=$(pins "$TMP/all")
expected=$(cd "$TMP/all" && for f in *-*; do echo "$f=$(sha256sum "$f" | cut -d' ' -f1)"; done | LC_ALL=C sort; echo release=None)
[[ $pinned == "$expected" ]] && ok "prebuilt.json pins the SHA-256 of every library, and no release" ||
  fail "prebuilt.json: got $pinned, want $expected"

ndk="$TMP/sdk/ndk/28.10.0/toolchains/llvm/prebuilt/linux-x86_64/bin"
line=$(grep '^cargo armv7-linux-androideabi ' <<<"$CALLS")
[[ $line == *"CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER=$ndk/armv7a-linux-androideabi24-clang "* ]] &&
  ok "Android links with the newest NDK's clang for API 24" || fail "Android linker: $line"
[[ $line == *"CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_RUSTFLAGS=-C link-arg=-Wl,-z,max-page-size=16384 "* ]] &&
  ok "Android libraries are linked for 16 KB pages" || fail "Android link flags: $line"
line=$(grep '^cargo x86_64-unknown-linux-gnu ' <<<"$CALLS")
[[ $line != *CARGO_TARGET_* ]] && ok "other targets use cargo's own linker settings" || fail "Linux build: $line"

ANDROID_NDK_HOME="$TMP/sdk/ndk/9.1.0" build --out "$TMP/ndk" android-x64
[[ $CALLS == *"LINKER=$TMP/sdk/ndk/9.1.0/toolchains"* ]] && ok "ANDROID_NDK_HOME chooses the NDK" ||
  fail "ANDROID_NDK_HOME ignored: $CALLS"
ANDROID_HOME=$TMP/none build --out "$TMP/nondk" android-x64
[[ $STATUS -ne 0 && $OUT == *"Android NDK"* ]] && ok "fails without an Android NDK" || fail "no NDK: exit $STATUS $OUT"

mkdir "$TMP/merged" && cp "$TMP/all"/linux-* "$TMP/all"/ios-arm64-* "$TMP/merged/"
build --out "$TMP/merged" --release https://example.org/kernel-v1/
[[ $STATUS -eq 0 && $CALLS != *cargo* ]] && ok "no target only writes prebuilt.json" || fail "no target: $STATUS $CALLS"
[[ $(pins "$TMP/merged") == *"ios-arm64-libphotolib_kernel_ffi.dylib="*"linux-arm64-"*"linux-x64-"*"release=https://example.org/kernel-v1/" ]] &&
  ok "pins the libraries already in the output, with the release they are published in" ||
  fail "merged prebuilt.json: $(pins "$TMP/merged")"

mkdir "$TMP/size" && head -c 3000000 /dev/zero >"$TMP/size/android-arm64-libphotolib_kernel_ffi.so"
build --out "$TMP/size"
[[ $STATUS -eq 0 && $OUT == *"android-arm64-libphotolib_kernel_ffi.so: 3000000 bytes, budget 3000000"* ]] &&
  ok "a library of 3 MB is within ADR-0004's budget, and its size is shown" || fail "3 MB: exit $STATUS $OUT"
head -c 1 /dev/zero >>"$TMP/size/android-arm64-libphotolib_kernel_ffi.so" && rm "$TMP/size/prebuilt.json"
build --out "$TMP/size"
[[ $STATUS -ne 0 && $OUT == *"over"*"android-arm64-libphotolib_kernel_ffi.so"* && ! -f $TMP/size/prebuilt.json ]] &&
  ok "a library over 3 MB fails and pins nothing" || fail "3 MB + 1 byte: exit $STATUS $OUT"

build --out "$TMP/bad" linux-x64 linux-riscv64
[[ $STATUS -eq 2 && $OUT == *"linux-riscv64"*"android-arm64"* && $CALLS != *cargo* ]] &&
  ok "an unknown target is a usage error that lists the targets" || fail "unknown target: exit $STATUS $OUT"
STUB_FAIL=x86_64-unknown-linux-gnu build --out "$TMP/fail" linux-x64
[[ $STATUS -ne 0 && ! -f $TMP/fail/prebuilt.json ]] && ok "a failed cargo build fails and pins nothing" ||
  fail "failed build: exit $STATUS"

# Cargo is found beyond PATH: the rustup proxy in ~/.cargo/bin, else the pinned toolchain's own bin under
# ~/.rustup/toolchains (a Finder- or hook-started build has no shell profile), and a missing cargo fails with one message.
PY=$(command -v python3)
CHANNEL=$(sed -n 's/^channel = "\(.*\)"$/\1/p' rust-toolchain.toml)
mkdir -p "$TMP/home/.rustup/toolchains/$CHANNEL-aarch64-apple-darwin/bin" "$TMP/empty"
cp "$TMP/bin/cargo" "$TMP/bin/rustup" "$TMP/home/.rustup/toolchains/$CHANNEL-aarch64-apple-darwin/bin/"
: >"$STUB_LOG"
OUT=$(timeout 60 env -u RUSTUP_HOME -u CARGO_HOME HOME="$TMP/home" PATH="$TMP/empty:/usr/bin:/bin" "$PY" tools/kernel/build.py \
  --out "$TMP/toolchain" macos-arm64 2>&1)
STATUS=$?
[[ $STATUS -eq 0 && $(<"$STUB_LOG") == *"cargo aarch64-apple-darwin"* && -f $TMP/toolchain/prebuilt.json ]] &&
  ok "finds cargo in the pinned toolchain under ~/.rustup when PATH has none" || fail "toolchain bin: exit $STATUS $OUT"
OUT=$(timeout 60 env -u RUSTUP_HOME -u CARGO_HOME HOME="$TMP/none" PATH="$TMP/empty:/usr/bin:/bin" "$PY" tools/kernel/build.py \
  --out "$TMP/nocargo" macos-arm64 2>&1)
STATUS=$?
[[ $STATUS -ne 0 && $OUT == *"cargo not found"*"https://rustup.rs"* && ! -f $TMP/nocargo/prebuilt.json ]] &&
  ok "without Rust it fails once, saying how to install it" || fail "no cargo: exit $STATUS $OUT"

# --- ADR-0026 records these decisions as the owner confirmed them (photolib-design#292)
ADR=docs/adr/0026-kernel-prebuilt-libraries.md
assert_patterns assert_prose $ADR \
  '\* \*\*Status\*\*: Accepted — 2026-10-15\. The owner confirmed [^*]*photolib-design#292' \
  "is Accepted, recording the owner's confirmation (#292)" \
  'build hook of `app/packages/photolib_kernel`.{0,200}fails the build unless its SHA-256 is the pinned one' \
  "apps take the kernel through the build hook, checked against the pinned SHA-256" \
  '`kernel-v<version>` tag \(the version of `kernel/ffi/Cargo\.toml`\) publishes the libraries' \
  "libraries are published as release assets of kernel-v<version> tags"
assert_matches docs/adr/README.md '\(0026-kernel-prebuilt-libraries\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0026 as Accepted"

finish
