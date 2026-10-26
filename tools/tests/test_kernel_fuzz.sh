#!/usr/bin/env bash
# Kernel fuzzing and panics as the owner answered (ADR-0036, photolib-design#328): the gate's fuzzer stays,
# coverage-guided libFuzzer targets run beside it on the build machine and their finds come back as gate cases, and a
# panic fails only its call.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0036-kernel-metadata-reader.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-17\. [^*]*photolib-design#328' \
  "is Accepted with the owner's answers (#328)"
assert_matches docs/adr/README.md '\(0036-kernel-metadata-reader\.md\) \| [^|]* \| Accepted' \
  "the index lists ADR-0036 as Accepted"
assert_patterns assert_prose "$ADR" \
  'takes pieces of a file at their offsets' "ranged reads stay" \
  'opens the file again, or exports it to a temporary file' "a host that reads only forward reopens or exports" \
  '`tools/kernel/fuzz\.sh` runs coverage-guided `cargo fuzz`' "coverage-guided fuzzing runs beside the gate" \
  '`CALL_ERROR_CODE_PANIC` \(kernel\.panic\)' "a panic fails its call with kernel.panic"

FUZZ=kernel/fuzz
assert_matches $FUZZ/Cargo.toml '^\[workspace\]$' "kernel/fuzz is a workspace of its own"
check "the kernel's workspace leaves kernel/fuzz out" bash -c "! grep -qE '^(default-)?members.*fuzz' kernel/Cargo.toml"
targets=$(sed -nE 's/^    \("([a-z_]+)", [a-z_]+\),$/\1/p' $FUZZ/src/lib.rs)
[[ $targets == $'read_metadata\nedit_copy\nedit_recipe\nresolve_capture_time\ncrypto_readers' ]] && ok "the five targets" ||
  fail "targets: $targets"
for target in $targets; do
  assert_matches $FUZZ/Cargo.toml "^name = \"$target\"$" "$target is a cargo-fuzz binary"
  assert_matches "$FUZZ/fuzz_targets/$target.rs" "photolib_kernel_fuzz::$target\(data\)" "$target runs its entry point"
done
assert_matches kernel/tests/fuzz.rs '^#\[path = "\.\./fuzz/src/lib\.rs"\]$' "the gate's fuzzer runs the same targets"

unguarded=$(awk '/extern "C" fn/ { if (open) n++; open = 1 } open && /guard\(|catch_unwind\(/ { open = 0 }
  END { print n + open }' kernel/ffi/src/lib.rs)
[[ $(grep -c 'extern "C" fn' kernel/ffi/src/lib.rs) -eq 9 && $unguarded -eq 0 ]] &&
  ok "every C entry point catches panics" || fail "$unguarded C entry points do not catch panics"

# A run with stub tools and targets whose read_metadata crashes when CRASH is set.
sandbox_tools bash sed sha256sum cut mkdir rm mv cp nice dirname
new_sandbox tools/kernel/fuzz.sh rustup
cat >"$SANDBOX/stubs/cargo" <<STUB
#!/bin/bash
echo "cargo \$*" >>"$SANDBOX/calls.log"
[[ \$* == "fuzz --version" ]] && echo "cargo-fuzz 0.13.2"
[[ \$* == "+nightly fuzz list"* ]] && printf 'read_metadata\ncrypto_readers\n'
exit 0
STUB
printf '#!/bin/bash\necho "host: test-host"\n' >"$SANDBOX/stubs/rustc"
bin=$SANDBOX/cache/kernel-fuzz/target/test-host/release
mkdir -p "$bin"
for target in read_metadata crypto_readers; do
  cat >"$bin/$target" <<STUB
#!/bin/bash
echo "$target \$* (ulimit -v \$(ulimit -v), nice \$(nice))" >>"$SANDBOX/calls.log"
for arg; do
  case \$arg in
    -exact_artifact_path=*) echo minimal >"\${arg#*=}" ;;
    -artifact_prefix=*) [[ $target == read_metadata && -n \${CRASH:-} ]] && echo crashing >"\${arg#*=}crash-1" && exit 1 ;;
  esac
done
exit 0
STUB
done
chmod +x "$SANDBOX"/stubs/* "$bin"/*
fuzz() {
  capture env -i PATH="$SANDBOX/stubs:$BASE_BIN" PHOTOLIB_TOOLS_CACHE="$SANDBOX/cache" "$@" \
    bash "$SANDBOX/tools/kernel/fuzz.sh" 5
}

fuzz
expect_result "a run without finds passes" 0
found=testdata/fuzz/read_metadata/crash-$(echo minimal | sha256sum | cut -c1-16)
fuzz CRASH=1
expect_result "a crash fails the run and is printed" 1 "found: $found"
check "it is minimized into testdata/fuzz" grep -qx minimal "$SANDBOX/$found"
check "its artifact is gone" bash -c "! ls '$SANDBOX'/cache/kernel-fuzz/artifacts/read_metadata/* 2>/dev/null"
check "each target runs on one core at the lowest priority, memory capped" grep -qE \
  "^crypto_readers -max_total_time=5 .* -rss_limit_mb=1024 -timeout=10 \(ulimit -v 4194304, nice 19\)$" \
  "$SANDBOX/calls.log"
check "from its corpus and its seeds" grep -qE "^read_metadata .* $SANDBOX/cache/kernel-fuzz/corpus/read_metadata \
$SANDBOX/cache/kernel-fuzz/seeds/read_metadata -rss_limit_mb" "$SANDBOX/calls.log"
check "the targets are built without a sanitizer, overflow checks on" grep -q \
  "^cargo +nightly fuzz build --fuzz-dir .*/kernel/fuzz --sanitizer none --debug-assertions$" "$SANDBOX/calls.log"

finish
