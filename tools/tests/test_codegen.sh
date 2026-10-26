#!/usr/bin/env bash
# Code generation (M0-06): tools/codegen.sh installs the pinned plugins, regenerates Rust, Dart and TypeScript from
# proto/, and checks that the generated code checked into the repository is current.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
mkdir "$SANDBOX/base"
for tool in bash env mkdir chmod cat rm dirname diff sort mktemp uname; do ln -s "$(command -v "$tool")" "$SANDBOX/base/$tool"; done

# The output directories come from the template, the same ones codegen.sh checks; several plugins may share one.
RUST=server/crates/photolib-proto/src/gen
DART=app/packages/photolib_api/lib/src/gen
TS=viewer/src/gen
OPENAPI=docs/dev/api
mapfile -t OUT_DIRS < <(sed -nE 's/^[[:space:]]*out:[[:space:]]*//p' proto/buf.gen.yaml | LC_ALL=C sort -u)
[[ ${OUT_DIRS[*]} == "$DART $OPENAPI kernel/src/gen $RUST/buffa $RUST/connect $TS" ]] &&
  ok "buf.gen.yaml writes the server's Rust messages and services, the kernel's Rust, Dart, TypeScript and OpenAPI" ||
  fail "buf.gen.yaml out: directories: ${OUT_DIRS[*]}"

# new_repo: a sandbox repository root with the real codegen.sh and template, a fake buf.sh that logs its arguments and
# writes "generated" into every output directory (under --output when given), and the generated code in place.
new_repo() {
  REPO=$SANDBOX/repo-$RANDOM
  mkdir -p "$REPO/tools" "$REPO/proto"
  cp "$REPO_ROOT/tools/codegen.sh" "$REPO/tools/" 2>/dev/null
  cp "$REPO_ROOT/proto/buf.gen.yaml" "$REPO/proto/"
  cat >"$REPO/tools/buf.sh" <<STUB
echo "buf.sh \$* PATH=\$PATH" >>"$REPO/calls.log"
base=.
while [[ \$# -gt 0 ]]; do
  [[ \$1 == --output ]] && base=\$2
  shift
done
for out in ${OUT_DIRS[*]}; do
  mkdir -p "\$base/\$out"
  echo generated >"\$base/\$out/api.txt"
done
STUB
  echo 'echo "fetch_release.sh $*" >>"$(dirname "$0")/../calls.log" && new-plugin "$3/$4"' >"$REPO/tools/fetch_release.sh"
  local out
  for out in "${OUT_DIRS[@]}"; do
    mkdir -p "$REPO/$out"
    echo generated >"$REPO/$out/api.txt"
  done
  : >"$REPO/calls.log"
}

# run_codegen <PATH> [args...]: output in $OUT, status in $STATUS
run_codegen() {
  local path=$1
  shift
  OUT=$(cd "$REPO" && PATH=$path PHOTOLIB_TOOLS_CACHE=$SANDBOX/cache bash tools/codegen.sh "$@" 2>&1)
  STATUS=$?
}

new_repo
run_codegen "$SANDBOX/base" --check
expect_result "--check passes when the generated code is current" 0
[[ $(<"$REPO/calls.log") == *"generate proto --template proto/buf.gen.yaml --output "* ]] &&
  ok "--check generates the whole module into a scratch directory" || fail "--check called buf.sh with: $(<"$REPO/calls.log")"
[[ $(<"$REPO/calls.log") == *"PATH=$SANDBOX/cache/codegen/"* ]] &&
  ok "generation runs with the pinned plugins first on PATH" || fail "plugin cache is not on PATH: $(<"$REPO/calls.log")"

new_repo
echo stale >"$REPO/${OUT_DIRS[0]}/api.txt"
run_codegen "$SANDBOX/base" --check
expect_result "--check fails on generated code that differs and names the directory" failure "${OUT_DIRS[0]}" "out of date"

new_repo
rm "$REPO/${OUT_DIRS[1]}/api.txt"
run_codegen "$SANDBOX/base" --check
expect_result "--check fails on a generated file that is missing" failure "${OUT_DIRS[1]}"

new_repo
echo leftover >"$REPO/${OUT_DIRS[2]}/removed.txt"
run_codegen "$SANDBOX/base" --check
expect_result "--check fails on a leftover file the generator no longer writes" failure "${OUT_DIRS[2]}"

new_repo
echo stale >"$REPO/${OUT_DIRS[0]}/api.txt"
run_codegen "$SANDBOX/base"
[[ $STATUS -eq 0 && $(<"$REPO/${OUT_DIRS[0]}/api.txt") == generated ]] && ok "without arguments it regenerates in place" ||
  fail "regeneration: exit $STATUS: $OUT"
[[ $(<"$REPO/calls.log") == "buf.sh generate proto --template proto/buf.gen.yaml PATH="* ]] &&
  ok "regeneration runs buf generate from the repository root with the template" || fail "regeneration called: $(<"$REPO/calls.log")"

new_repo
run_codegen "$SANDBOX/base" nonsense
expect_result "an unknown argument is rejected with the usage" failure usage

# --- install: the plugin versions are pinned in codegen.sh and installed into the cache
declare -A PIN
for var in PROST_VERSION BUFFA_VERSION CONNECT_RUST_VERSION DART_PLUGIN_VERSION ES_VERSION OPENAPI_VERSION; do
  PIN[$var]=$(sed -n "s/^$var=//p" tools/codegen.sh)
  [[ ${PIN[$var]} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && ok "codegen.sh pins $var=${PIN[$var]}" || fail "codegen.sh does not pin $var (got '${PIN[$var]}')"
done

new_repo
# Stubs that log and install plugins; a plugin starts unless $PLUGIN_BODY says otherwise, and cargo, as the real one
# does, leaves a crate it installed before alone.
mkdir "$SANDBOX/install-stubs"
cat >"$SANDBOX/install-stubs/new-plugin" <<'EOF'
#!/bin/bash
mkdir -p "${1%/*}" && printf '#!/bin/bash\n%s\n' "${PLUGIN_BODY:-exit 0}" >"$1" && chmod +x "$1"
EOF
install_stub() { printf '#!/bin/bash\necho "%s $*" >>"%s"\n%s\n' "$1" "$REPO/calls.log" "$2" >"$SANDBOX/install-stubs/$1"; }
install_stub cargo 'bin=$4/bin/${5/connectrpc-codegen/protoc-gen-connect-rust}; [[ -e $bin ]] || new-plugin "$bin"'
install_stub dart 'new-plugin "$PUB_CACHE/bin/protoc-gen-dart"'
install_stub npm 'new-plugin "$3/node_modules/.bin/protoc-gen-es"'
chmod +x "$SANDBOX/install-stubs/"*
run_codegen "$SANDBOX/install-stubs:$SANDBOX/base" install
calls=$(<"$REPO/calls.log")
for crate in "protoc-gen-prost --version ${PIN[PROST_VERSION]}" "protoc-gen-buffa --version ${PIN[BUFFA_VERSION]}" "protoc-gen-buffa-packaging --version ${PIN[BUFFA_VERSION]}" \
  "connectrpc-codegen --version ${PIN[CONNECT_RUST_VERSION]}"; do
  [[ $STATUS -eq 0 && $calls == *"cargo install --locked --root $SANDBOX/cache/codegen/rust $crate"* ]] &&
    ok "install builds the pinned ${crate%% *}" || fail "install, ${crate%% *}: exit $STATUS: $calls $OUT"
done
[[ $calls == *"dart pub global activate protoc_plugin ${PIN[DART_PLUGIN_VERSION]}"* ]] &&
  ok "install activates the pinned protoc_plugin" || fail "install, dart: $calls"
[[ $calls == *"npm install"*"@bufbuild/protoc-gen-es@${PIN[ES_VERSION]}"* ]] &&
  ok "install fetches the pinned protoc-gen-es" || fail "install, es: $calls"
v=${PIN[OPENAPI_VERSION]}
[[ $calls =~ fetch_release\.sh\ https://github\.com/sudorandom/protoc-gen-connect-openapi/releases/download/v$v/protoc-gen-connect-openapi_${v}_[a-z0-9_]+\.tar\.gz\ [0-9a-f]{64}\ $SANDBOX/cache/codegen/openapi\ protoc-gen-connect-openapi ]] &&
  ok "install fetches the pinned protoc-gen-connect-openapi release and checks its SHA-256" || fail "install, openapi: $calls"

# The gate runs install every time: with the pins already installed it does nothing, so it needs no network.
: >"$REPO/calls.log"
run_codegen "$SANDBOX/install-stubs:$SANDBOX/base" install
[[ $STATUS -eq 0 && -z $(<"$REPO/calls.log") ]] && ok "install does nothing when the pinned plugins are installed" ||
  fail "install again: exit $STATUS: $(<"$REPO/calls.log") $OUT"
sed -i 's/^PROST_VERSION=.*/PROST_VERSION=9.9.9/' "$REPO/tools/codegen.sh"
run_codegen "$SANDBOX/install-stubs:$SANDBOX/base" install
[[ $STATUS -eq 0 && $(<"$REPO/calls.log") == *"--version 9.9.9"* ]] && ok "install runs again when a pin changes" ||
  fail "install after a pin changed: exit $STATUS: $(<"$REPO/calls.log") $OUT"

# A plugin that does not start, from a corrupt download or a damaged cache, is installed again from scratch.
printf '#!/bin/bash\nexit 126\n' >"$SANDBOX/cache/codegen/rust/bin/protoc-gen-prost"
: >"$REPO/calls.log"
run_codegen "$SANDBOX/install-stubs:$SANDBOX/base" install
[[ $STATUS -eq 0 && $(grep -c 'cargo install .* protoc-gen-prost ' "$REPO/calls.log") -eq 2 ]] &&
  "$SANDBOX/cache/codegen/rust/bin/protoc-gen-prost" </dev/null && ok "install replaces a cached plugin that does not start" ||
  fail "install over a plugin that does not start: exit $STATUS: $(<"$REPO/calls.log") $OUT"
rm -rf "$SANDBOX/cache"
: >"$REPO/calls.log"
PLUGIN_BODY='exit 126' run_codegen "$SANDBOX/install-stubs:$SANDBOX/base" install
[[ $STATUS -ne 0 && $OUT == *PHOTOLIB_TOOLS_CACHE* && $(grep -c '^npm install' "$REPO/calls.log") -eq 2 ]] &&
  ok "install fails after a second install of plugins that do not start, and says how to move the cache" ||
  fail "install of plugins that never start: exit $STATUS: $(<"$REPO/calls.log") $OUT"

new_repo
run_codegen "$SANDBOX/base" install
expect_result "install without cargo fails loudly" failure "'cargo' is required"

# --- the generated code is checked in at the consumer locations, and regenerating it is a no-op
for out in "${OUT_DIRS[@]}"; do
  [[ -d $out && -n $(find "$out" -type f -print -quit) ]] && ok "$out holds generated code" || fail "$out holds no generated code"
done
# Every proto file has its generated counterpart, so a new file that was never generated fails even without the plugins.
for proto in proto/photolib/*/v1/*.proto; do
  rel=${proto#proto/}
  stem=${rel%.proto}
  rust=$(sed -n 's/^package \(.*\);$/\1/p' "$proto").${stem##*/}
  [[ -f $RUST/buffa/$rust.rs ]] && ok "$rel has generated Rust" || fail "$RUST/buffa/$rust.rs is missing"
  if grep -q '^service ' "$proto"; then
    [[ -f $RUST/connect/$rust.__connect.rs ]] && ok "$rel has a generated Rust service" || fail "$RUST/connect/$rust.__connect.rs is missing"
  fi
  [[ -f $DART/$stem.pb.dart ]] && ok "$rel has generated Dart" || fail "$DART/$stem.pb.dart is missing"
  [[ -f $TS/${stem}_pb.ts ]] && ok "$rel has generated TypeScript" || fail "$TS/${stem}_pb.ts is missing"
done
# Third parties read the API in one OpenAPI document that documents every RPC and the error detail.
SPEC=$OPENAPI/photolib.openapi.yaml
for proto in proto/photolib/api/v1/*.proto; do
  while read -r service rpc; do
    grep -q "^  /photolib\.api\.v1\.$service/$rpc:" "$SPEC" 2>/dev/null && ok "$SPEC documents $service/$rpc" ||
      fail "$SPEC does not document /photolib.api.v1.$service/$rpc"
  done < <(awk '/^service /{service=$2} /^  rpc /{sub(/\(.*/, "", $2); print service, $2}' "$proto")
done
grep -q '^    photolib\.api\.v1\.ErrorDetail:' "$SPEC" 2>/dev/null && ok "$SPEC documents ErrorDetail" ||
  fail "$SPEC does not document photolib.api.v1.ErrorDetail"
# The kernel owns a copy of the messages its ABI uses, with ordered maps so that equal responses are equal bytes.
for package in photolib.kernel.v1 photolib.model.v1; do
  [[ -f kernel/src/gen/$package.rs ]] && ok "the kernel has generated Rust for $package" || fail "kernel/src/gen/$package.rs is missing"
done
grep -q 'BTreeMap' kernel/src/gen/photolib.kernel.v1.rs 2>/dev/null && ok "the kernel's maps are BTreeMaps" ||
  fail "kernel/src/gen/photolib.kernel.v1.rs has no BTreeMap: generate it with btree_map"

finish
