#!/usr/bin/env bash
# Coverage-guided fuzzing of the kernel on the build machine, outside the gate (ADR-0036):
#
#   bash tools/kernel/fuzz.sh [seconds per target, default 3600]
#
# Runs each libFuzzer target of kernel/fuzz in turn, on one core at the lowest priority with its memory capped, from a
# corpus kept in the tools cache and seeded from testdata/corpus and the kernel's vectors. Each crash, out-of-memory or
# timeout is minimized into testdata/fuzz/<target>/, which kernel/tests/fuzz.rs replays in the gate, and printed as
# `found: <path>`; the script then exits 1. Needs rustup (it installs nightly), cargo and a C++ compiler for libFuzzer;
# cargo-fuzz is installed once into the cache.
set -euo pipefail

seconds=${1:-3600}
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
fuzz=$root/kernel/fuzz
cache=${PHOTOLIB_TOOLS_CACHE:-${TMPDIR:-/tmp}/photolib-tools-$(id -u)}
work=$cache/kernel-fuzz
version=0.13.2
if [[ $(cargo fuzz --version 2>/dev/null) != "cargo-fuzz $version" ]]; then
  tool=$cache/cargo-fuzz-$version
  [[ -x $tool/bin/cargo-fuzz ]] || cargo install cargo-fuzz --version "$version" --locked --root "$tool" >&2
  export PATH=$tool/bin:$PATH
fi
rustup toolchain install nightly --profile minimal >&2
export CARGO_TARGET_DIR=$work/target

# No sanitizer: the kernel has no unsafe code, and without one the address-space limit below works. Overflow checks
# stay on, as in the gate.
nice -n 19 cargo +nightly fuzz build --fuzz-dir "$fuzz" --sanitizer none --debug-assertions >&2
rm -rf "$work/seeds"
nice -n 19 cargo +nightly run --quiet --release --manifest-path "$fuzz/Cargo.toml" --example seeds -- "$work/seeds"
bin=$work/target/$(rustc +nightly -vV | sed -n 's/^host: //p')/release

# One process, so one core, at the lowest priority; libFuzzer fails an input past 1 GiB resident or 10 s, and nothing
# maps past 4 GiB.
run() {
  (ulimit -v $((4 << 20)) && exec nice -n 19 "$@" -rss_limit_mb=1024 -timeout=10) >&2
}

found=0
for target in $(cargo +nightly fuzz list --fuzz-dir "$fuzz"); do
  artifacts=$work/artifacts/$target
  mkdir -p "$work/corpus/$target" "$artifacts"
  run "$bin/$target" -max_total_time="$seconds" -artifact_prefix="$artifacts/" "$work/corpus/$target" \
    "$work/seeds/$target" || true
  for artifact in "$artifacts"/*; do
    [[ -f $artifact ]] || continue
    minimized=$work/minimized
    rm -f "$minimized"
    run "$bin/$target" -minimize_crash=1 -max_total_time=300 -exact_artifact_path="$minimized" "$artifact" || true
    [[ -s $minimized ]] || cp "$artifact" "$minimized"
    kind=${artifact##*/}
    out=testdata/fuzz/$target/${kind%%-*}-$(sha256sum "$minimized" | cut -c1-16)
    mkdir -p "$root/testdata/fuzz/$target"
    mv "$minimized" "$root/$out"
    rm "$artifact"
    echo "found: $out"
    found=1
  done
done
exit "$found"
