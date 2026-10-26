#!/usr/bin/env bash
# Generates Rust (buffa messages and connect-rust services for the server, prost for the kernel), Dart (protoc_plugin),
# TypeScript (protobuf-es) and the OpenAPI document of the API from proto/ with the plugin versions pinned below, so
# every machine and CI produce identical files.
#
#   tools/codegen.sh install   build the pinned plugins into the per-user cache, once per pin (cargo, dart, npm, curl)
#   tools/codegen.sh           regenerate the checked-in code in place
#   tools/codegen.sh --check   fail when the checked-in code differs from a fresh generation
#
# The output directories are the `out:` lines of proto/buf.gen.yaml. Bump a pin, regenerate and commit together.
set -euo pipefail

PROST_VERSION=0.5.0
BUFFA_VERSION=0.9.2
CONNECT_RUST_VERSION=0.9.0
DART_PLUGIN_VERSION=25.1.0
ES_VERSION=2.16.0
OPENAPI_VERSION=0.28.0
# The release builds of protoc-gen-connect-openapi and the SHA-256 of each, from the release's checksums.txt.
declare -A OPENAPI_BUILD=([Linux-x86_64]=linux_amd64 [Linux-aarch64]=linux_arm64 [Darwin-x86_64]=darwin_all
  [Darwin-arm64]=darwin_all)
declare -A OPENAPI_SHA256=(
  [linux_amd64]=1bc500494b835efa00487d9685ca8e6f74b5a427bdb6f5a456f3287e5f3b336a
  [linux_arm64]=679816cf64acee93a19c6100f16b5144b5b17e59fa697b8a29cbf73eede5ec80
  [darwin_all]=31d7c1fd7dbacb2f7ec8b870dfe8a5bb4255499d92ed9097501cc972ed549fb5
)

TOOLS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(dirname "$TOOLS")
TEMPLATE=proto/buf.gen.yaml
# Outside the checkout, which may be on a noexec mount where the plugins cannot start.
CACHE=${PHOTOLIB_TOOLS_CACHE:-${TMPDIR:-/tmp}/photolib-tools-$(id -u)}
PLUGINS=$CACHE/codegen
export PUB_CACHE=$PLUGINS/pub

usage() {
  echo "usage: tools/codegen.sh [install | --check]" >&2
  exit 2
}

# install_requires <tool> <why>: fail loudly when a tool needed to build a plugin is missing
install_requires() {
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "'$1' is required to $2 but is not on PATH" >&2
  exit 1
}

PINS="$PROST_VERSION $BUFFA_VERSION $CONNECT_RUST_VERSION $DART_PLUGIN_VERSION $ES_VERSION $OPENAPI_VERSION"
PLUGIN_FILES=(rust/bin/protoc-gen-prost rust/bin/protoc-gen-buffa rust/bin/protoc-gen-buffa-packaging
  rust/bin/protoc-gen-connect-rust pub/bin/protoc-gen-dart node/node_modules/.bin/protoc-gen-es
  openapi/protoc-gen-connect-openapi)

# installed: the pinned plugins are in the cache and each starts (an empty request gets an empty response)
installed() {
  [[ $(cat "$PLUGINS/pins" 2>/dev/null) == "$PINS" ]] || return 1
  local plugin
  for plugin in "${PLUGIN_FILES[@]}"; do
    "$PLUGINS/$plugin" </dev/null >/dev/null 2>&1 || return 1
  done
}

fetch_plugins() {
  cargo install --locked --root "$PLUGINS/rust" protoc-gen-prost --version "$PROST_VERSION" &&
    cargo install --locked --root "$PLUGINS/rust" protoc-gen-buffa --version "$BUFFA_VERSION" &&
    cargo install --locked --root "$PLUGINS/rust" protoc-gen-buffa-packaging --version "$BUFFA_VERSION" &&
    cargo install --locked --root "$PLUGINS/rust" connectrpc-codegen --version "$CONNECT_RUST_VERSION" &&
    dart pub global activate protoc_plugin "$DART_PLUGIN_VERSION" &&
    npm install --prefix "$PLUGINS/node" --ignore-scripts --no-audit --no-fund --loglevel=error \
      "@bufbuild/protoc-gen-es@$ES_VERSION" &&
    bash "$TOOLS/fetch_release.sh" "https://github.com/sudorandom/protoc-gen-connect-openapi/releases/download/\
v$OPENAPI_VERSION/protoc-gen-connect-openapi_${OPENAPI_VERSION}_$1.tar.gz" "${OPENAPI_SHA256[$1]}" \
      "$PLUGINS/openapi" protoc-gen-connect-openapi
}

install_plugins() {
  installed && return 0
  install_requires cargo "build protoc-gen-prost, protoc-gen-buffa and protoc-gen-connect-rust"
  install_requires dart "install protoc_plugin"
  install_requires npm "install protoc-gen-es"
  local build=${OPENAPI_BUILD[$(uname -s)-$(uname -m)]:-} attempt
  if [[ -z $build ]]; then
    echo "protoc-gen-connect-openapi $OPENAPI_VERSION has no release for $(uname -s)-$(uname -m)" >&2
    exit 1
  fi
  # A failed download can leave a plugin that does not start, which cargo then calls installed: start over once.
  for attempt in 1 2; do
    (umask 077 && mkdir -p "$PLUGINS")
    if [[ ! -O $CACHE ]]; then
      echo "$CACHE is owned by another user; set PHOTOLIB_TOOLS_CACHE to a directory you own" >&2
      exit 1
    fi
    fetch_plugins "$build" && echo "$PINS" >"$PLUGINS/pins" && installed && return 0
    rm -rf "$PLUGINS"
  done
  echo "2 installs of the codegen plugins into $PLUGINS failed or do not start (a failed download, or a noexec" \
    "mount?); set PHOTOLIB_TOOLS_CACHE to a directory where programs can run" >&2
  exit 1
}

# out_dirs: the output directories of the template, relative to the repository root, each once
out_dirs() {
  local line
  while IFS= read -r line; do
    [[ $line =~ ^[[:space:]]*out:[[:space:]]*(.+)$ ]] && echo "${BASH_REMATCH[1]}"
  done <"$ROOT/$TEMPLATE" | LC_ALL=C sort -u
}

generate() {
  PATH=$PLUGINS/rust/bin:$PLUGINS/pub/bin:$PLUGINS/node/node_modules/.bin:$PLUGINS/openapi:$PATH
  (cd "$ROOT" && bash "$TOOLS/buf.sh" generate proto --template "$TEMPLATE" "$@")
}

check_current() {
  local scratch out stale=0
  scratch=$(mktemp -d)
  trap 'rm -rf "$scratch"' EXIT
  generate --output "$scratch"
  while IFS= read -r out; do
    if ! diff -rq "$scratch/$out" "$ROOT/$out"; then
      echo "codegen: $out is out of date; run 'bash tools/codegen.sh' and commit the result" >&2
      stale=1
    fi
  done < <(out_dirs)
  exit "$stale"
}

case ${1:-} in
  install) [[ $# -eq 1 ]] || usage; install_plugins ;;
  --check) [[ $# -eq 1 ]] || usage; check_current ;;
  "") generate ;;
  *) usage ;;
esac
