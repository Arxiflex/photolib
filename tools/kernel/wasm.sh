#!/usr/bin/env bash
# Builds the kernel for the web: bash tools/kernel/wasm.sh <out-dir>. Writes kernel/wasm as one single-threaded ES
# module, photolib_kernel_wasm.js with its .wasm and TypeScript types, for Flutter web and the viewer, and beside it
# photolib_kernel_guard.js (kernel/wasm/guard.js), which catches its traps; fails when they exceed the budget that
# budget.mjs checks. Needs rustup, cargo and node. The wasm-bindgen CLI must be the version in kernel/Cargo.lock: the
# one on PATH, else installed once into a per-user cache, as tools/buf.sh does.
set -euo pipefail

out=${1:?usage: wasm.sh <out-dir>}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
manifest=$here/../../kernel/Cargo.toml
version=$(sed -n '/^name = "wasm-bindgen"$/{n;s/^version = "\(.*\)"$/\1/p;}' "${manifest%.toml}.lock")

bindgen=wasm-bindgen
if [[ $(wasm-bindgen --version 2>/dev/null) != "wasm-bindgen $version" ]]; then
  root=${PHOTOLIB_TOOLS_CACHE:-${TMPDIR:-/tmp}/photolib-tools-$(id -u)}/wasm-bindgen-$version
  bindgen=$root/bin/wasm-bindgen
  [[ -x $bindgen ]] || cargo install wasm-bindgen-cli --version "$version" --locked --root "$root" >&2
fi

rustup target add wasm32-unknown-unknown >&2
# SIMD speeds ChaCha20-Poly1305 up by a tenth; every browser Flutter's web build supports has it.
CARGO_TARGET_WASM32_UNKNOWN_UNKNOWN_RUSTFLAGS="-C target-feature=+simd128" \
  cargo build --locked --manifest-path "$manifest" -p photolib-kernel-wasm --release --target wasm32-unknown-unknown
target=$(cargo metadata --manifest-path "$manifest" --format-version 1 --no-deps |
  node -p 'JSON.parse(require("fs").readFileSync(0)).target_directory')
"$bindgen" --target web --out-dir "$out" "$target/wasm32-unknown-unknown/release/photolib_kernel_wasm.wasm"
cp "$here/../../kernel/wasm/guard.js" "$out/photolib_kernel_guard.js"
node "$here/budget.mjs" "$out/photolib_kernel_wasm.js" "$out/photolib_kernel_wasm_bg.wasm" "$out/photolib_kernel_guard.js"
