#!/usr/bin/env bash
# Protobuf IDL (M0-06): the four v1 packages, the buf configuration, the style guide and the code generation setup.
# shellcheck disable=SC2016 # stubs and bash -c scripts are literal
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

# --- the packages photolib.{model,api,sync,kernel}.v1 exist, each in its own directory
for domain in model api sync kernel; do
  files=(proto/photolib/"$domain"/v1/*.proto)
  if [[ -f ${files[0]} ]]; then ok "photolib.$domain.v1 has proto files"; else
    fail "proto/photolib/$domain/v1 has no .proto files"
    continue
  fi
  if grep -L "^package photolib\.$domain\.v1;" "${files[@]}" | grep -q .; then
    fail "a file in proto/photolib/$domain/v1 does not declare package photolib.$domain.v1"
  else
    ok "files in proto/photolib/$domain/v1 declare package photolib.$domain.v1"
  fi
done

# --- buf: STANDARD lint plus comments, wire and JSON breaking rules, and three generated languages
assert_patterns assert_matches proto/buf.yaml \
  '^version: v2$' "uses the buf v2 configuration" \
  '^ +- STANDARD$' "lints with the STANDARD rules (enum zero value, versioned packages, ...)" \
  '^ +- WIRE_JSON$' "rejects wire and JSON incompatible changes"
for plugin in protoc-gen-buffa protoc-gen-buffa-packaging protoc-gen-connect-rust protoc-gen-dart protoc-gen-es; do
  assert_matches proto/buf.gen.yaml "local: $plugin\$" "generates with $plugin"
done
assert_patterns assert_matches proto/buf.gen.yaml \
  'out: server/crates/photolib-proto/src/gen/buffa$' "writes the Rust messages into the proto crate" \
  'out: server/crates/photolib-proto/src/gen/connect$' "writes the Rust Connect services into the proto crate" \
  'out: app/packages/photolib_api/lib/src/gen$' "writes Dart where the app package will be" \
  'out: viewer/src/gen$' "writes TypeScript where the viewer will be"

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

# --- tools/buf.sh runs the buf on PATH, else the pinned release that npm installs once into a per-user cache
# The stubs below install fake bufs: never into the user's cache (PHOTOLIB_TOOLS_CACHE), which the real buf gets back.
# Meanwhile it names a cache holding a working buf, as a shared one does, which no case may reach.
TOOLS_CACHE=${PHOTOLIB_TOOLS_CACHE-}
pin=$(sed -n 's/^BUF_VERSION=//p' "$REPO_ROOT/tools/buf.sh")
export PHOTOLIB_TOOLS_CACHE=$SANDBOX/outer
BASE_BIN=$SANDBOX/base
mkdir "$BASE_BIN"
for tool in bash env mkdir id chmod rm dirname mktemp ln node; do ln -s "$(command -v "$tool")" "$BASE_BIN/$tool"; done

# stub <dir> <name> <body>: an executable bash script
stub() {
  mkdir -p "$1"
  printf '#!/bin/bash\n%s\n' "$3" >"$1/$2"
  chmod +x "$1/$2"
}

# run_buf_sh <PATH> <args...>: output in $OUT, exit status in $STATUS; the cache is $CACHE or the sandbox's, never the
# machine's, where a stub npm would leave a fake buf
run_buf_sh() {
  local path=$1 cache=${CACHE:-$SANDBOX/cache}
  shift
  OUT=$(PATH=$path TMPDIR=$SANDBOX/tmp PHOTOLIB_TOOLS_CACHE=$cache bash "$REPO_ROOT/tools/buf.sh" "$@" 2>&1)
  STATUS=$?
}

stub "$PHOTOLIB_TOOLS_CACHE/buf-$pin/node_modules/.bin" buf "echo \"outer-buf $pin \$*\""

run_buf_sh "$BASE_BIN" lint
[[ $STATUS -ne 0 && $OUT == *"'buf' is required"* ]] && ok "buf.sh fails loudly with neither buf nor npm" ||
  fail "buf.sh without buf and npm: exit $STATUS: $OUT"

stub "$SANDBOX/on-path" buf 'echo "buf-on-path $*"; exit 3'
run_buf_sh "$SANDBOX/on-path:$BASE_BIN" format --diff
[[ $STATUS -eq 3 && $OUT == "buf-on-path format --diff" ]] && ok "buf.sh runs the buf on PATH with its arguments and exit status" ||
  fail "buf.sh with buf on PATH: exit $STATUS: $OUT"

# The bufs the npm stubs install report the version asked for, as npm_tool.sh checks.
stub "$SANDBOX/with-npm" npm 'echo "$*" >>"$NPM_LOG"
package=${*: -1}
while [[ $1 != --prefix ]]; do shift; done
mkdir -p "$2/node_modules/.bin"
printf "#!/bin/bash\necho pinned-buf %s \$*\n" "${package##*@}" >"$2/node_modules/.bin/buf"
chmod +x "$2/node_modules/.bin/buf"'
export NPM_LOG=$SANDBOX/npm.log
run_buf_sh "$SANDBOX/with-npm:$BASE_BIN" lint
run_buf_sh "$SANDBOX/with-npm:$BASE_BIN" lint
[[ $STATUS -eq 0 && $OUT == "pinned-buf $pin lint" ]] && ok "buf.sh runs the buf that npm installed" || fail "buf.sh with npm: exit $STATUS: $OUT"
[[ -n $pin && $(grep -c "@bufbuild/buf@$pin" "$NPM_LOG") -eq 1 && $(wc -l <"$NPM_LOG") -eq 1 ]] &&
  ok "buf.sh installs the pinned buf $pin once and reuses it" || fail "buf.sh did not install @bufbuild/buf@$pin exactly once: $(cat "$NPM_LOG" 2>&1)"

# npm fails on a network error, and still succeeds when the download of buf's optional platform binary fails
stub "$SANDBOX/flaky-npm" npm 'echo "$*" >>"$NPM_LOG"
[[ -e $FLAKY.1 ]] || { : >"$FLAKY.1"; exit 1; }
package=${*: -1}
while [[ $1 != --prefix ]]; do shift; done
mkdir -p "$2/node_modules/.bin"
if [[ -e $FLAKY.2 ]]; then body="echo pinned-buf ${package##*@} \$*"; else body="exit 1"; : >"$FLAKY.2"; fi
printf "#!/bin/bash\n%s\n" "$body" >"$2/node_modules/.bin/buf"
chmod +x "$2/node_modules/.bin/buf"'
NPM_LOG=$SANDBOX/flaky-npm.log FLAKY=$SANDBOX/flaky CACHE=$SANDBOX/flaky-cache \
  run_buf_sh "$SANDBOX/flaky-npm:$BASE_BIN" lint
[[ $STATUS -eq 0 && $OUT == "pinned-buf $pin lint" && $(wc -l <"$SANDBOX/flaky-npm.log") -eq 3 ]] &&
  ok "buf.sh installs again after a failed install and after a buf that cannot run (failed downloads)" ||
  fail "buf.sh after failed installs: exit $STATUS: $OUT"

stub "$SANDBOX/broken-npm" npm 'while [[ $1 != --prefix ]]; do shift; done
mkdir -p "$2/node_modules/.bin"
printf "#!/bin/bash\nexit 126\n" >"$2/node_modules/.bin/buf"
chmod +x "$2/node_modules/.bin/buf"'
CACHE=$SANDBOX/broken-cache run_buf_sh "$SANDBOX/broken-npm:$BASE_BIN" lint
[[ $STATUS -ne 0 && $OUT == *PHOTOLIB_TOOLS_CACHE* ]] && ok "buf.sh explains a buf that cannot run (noexec cache) and how to move the cache" ||
  fail "buf.sh with a buf that cannot start: exit $STATUS: $OUT"

stub "$SANDBOX/stale-cache/buf-$pin/node_modules/.bin" buf 'exit 126'
: >"$NPM_LOG"
CACHE=$SANDBOX/stale-cache run_buf_sh "$SANDBOX/with-npm:$BASE_BIN" lint
[[ $STATUS -eq 0 && $OUT == "pinned-buf $pin lint" && $(wc -l <"$NPM_LOG") -eq 1 ]] &&
  ok "buf.sh installs again over a cached buf that does not start (a corrupt download)" ||
  fail "buf.sh with a cached buf that does not start: exit $STATUS: $OUT"

# --- the style guide is enforced by buf: the real proto module passes, and breaking each rule fails
if [[ -n $TOOLS_CACHE ]]; then export PHOTOLIB_TOOLS_CACHE=$TOOLS_CACHE; else unset PHOTOLIB_TOOLS_CACHE; fi
BUF=(bash "$REPO_ROOT/tools/buf.sh")
check "buf lint passes on proto/" bash -c 'cd "$1" && shift && "$@" lint' _ "$REPO_ROOT/proto" "${BUF[@]}"
check "buf format finds proto/ formatted" bash -c 'cd "$1" && shift && "$@" format --diff --exit-code' _ "$REPO_ROOT/proto" "${BUF[@]}"

# lint_rejects <description> <file> <old> <new> <finding>: the module with one replacement (in a copy) must fail
# buf lint with a finding matching the pattern
lint_rejects() {
  local description=$1 file=$2 old=$3 new=$4 finding=$5 copy=$SANDBOX/lint-$RANDOM text output
  cp -r "$REPO_ROOT/proto" "$copy"
  text=$(<"$copy/$file")
  [[ $text == *"$old"* ]] || { fail "$description: test bug, '$old' not found in $file"; return; }
  printf '%s\n' "${text/"$old"/"$new"}" >"$copy/$file"
  output=$(cd "$copy" && "${BUF[@]}" lint 2>&1)
  if [[ $? -ne 0 && $output =~ $finding ]]; then ok "buf lint rejects $description"; else
    fail "buf lint did not reject $description with /$finding/: $output"
  fi
}

lint_rejects "an enum without a *_UNSPECIFIED zero value" photolib/kernel/v1/call.proto \
  "CALL_ERROR_CODE_UNSPECIFIED = 0" "CALL_ERROR_CODE_NONE = 0" "suffixed with \"_UNSPECIFIED\""
lint_rejects "an undocumented message" photolib/sync/v1/mutation.proto \
  $'// Mutations drained from a device\'s outbox in causal order.\n' "" "MutationBatch.*comment"
# In a file no other imports, so that only lint can object.
lint_rejects "a package without a version" photolib/kernel/v1/logs.proto \
  "package photolib.kernel.v1;" "package photolib.kernel;" "correctly formed version"

# --- tools/proto_breaking.sh: buf breaking against the last release tag, else origin/dev, in a throwaway git repository
GIT=(git -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false -c init.defaultBranch=main)

# git_in_repo <args...>: git inside $REPO
git_in_repo() { "${GIT[@]}" -C "$REPO" "$@"; }

# new_repo <name>: a repository with the real proto/ committed and origin/dev pointing at it; sets REPO to its path
new_repo() {
  REPO=$SANDBOX/$1
  mkdir "$REPO"
  git_in_repo init --quiet
  cp -r "$REPO_ROOT/proto" "$REPO/proto"
  git_in_repo add -A
  git_in_repo commit --quiet -m "feat(proto): baseline"
  git_in_repo update-ref refs/remotes/origin/dev HEAD
}

# edit_proto <old> <new>: replace the first occurrence in the sync mutation proto of $REPO and commit it
edit_proto() {
  local file=$REPO/proto/photolib/sync/v1/mutation.proto text
  text=$(<"$file")
  [[ $text == *"$1"* ]] || fail "test bug: '$1' not found in mutation.proto"
  printf '%s\n' "${text/"$1"/"$2"}" >"$file"
  git_in_repo commit --quiet -am "feat(proto): change"
}

# run_breaking: runs the script in $REPO; output in $OUT, exit status in $STATUS
run_breaking() {
  OUT=$(cd "$REPO" && bash "$REPO_ROOT/tools/proto_breaking.sh" proto 2>&1)
  STATUS=$?
}

# expect_breaking pass <description>, or: expect_breaking fail <description> <pattern buf's findings must match>
expect_breaking() {
  local want=$1 description=$2 pattern=${3:-}
  run_breaking
  if [[ $want == pass && $STATUS -eq 0 ]]; then ok "$description"
  elif [[ $want == fail && $STATUS -eq 100 && $OUT =~ $pattern ]]; then ok "$description"
  else fail "$description (exit $STATUS): $OUT"; fi
}

new_repo compatible
edit_proto "  uint32 counter = 2;" $'  uint32 counter = 2;\n  uint32 shard = 4;'
expect_breaking pass "breaking check accepts adding a field"

new_repo deleted-field
edit_proto "  uint32 counter = 2;" ""
expect_breaking fail "breaking check rejects deleting a field without reserving it" "without reserving the number"

new_repo reserved-field
edit_proto "  uint32 counter = 2;" $'  reserved 2;\n  reserved "counter";'
expect_breaking pass "breaking check accepts deleting a field once its number and name are reserved"

new_repo retyped-field
edit_proto "  uint32 counter = 2;" "  string counter = 2;"
expect_breaking fail "breaking check rejects changing a field's type" "changed type from"

new_repo tag-first
git_in_repo tag v0.1.0
edit_proto "  uint32 counter = 2;" ""
git_in_repo update-ref refs/remotes/origin/dev HEAD
expect_breaking fail "breaking check compares against the last release tag before origin/dev" "comparing proto with v0.1.0"

new_repo no-baseline
git_in_repo update-ref -d refs/remotes/origin/dev
edit_proto "  uint32 counter = 2;" ""
run_breaking
[[ $STATUS -ne 0 && $OUT == *"origin/dev"* ]] && ok "breaking check fails loudly with no release tag and no origin/dev" ||
  fail "breaking check without a baseline: exit $STATUS: $OUT"

REPO=$SANDBOX/introduction
mkdir "$REPO"
git_in_repo init --quiet
printf '# proto\n' >"$REPO/README.md"
git_in_repo add -A
git_in_repo commit --quiet -m "docs: readme"
git_in_repo update-ref refs/remotes/origin/dev HEAD
cp -r "$REPO_ROOT/proto" "$REPO/proto"
git_in_repo add -A
git_in_repo commit --quiet -m "feat(proto): add the module"
expect_breaking pass "breaking check passes in the change that introduces the module"

# --- the style guide is published in the developer guide and says what the packages and buf enforce
GUIDE=docs/dev/protobuf-style-guide.md
assert_matches $GUIDE '^# Protobuf style guide$' "is the protobuf style guide"
for package in model api sync kernel; do
  assert_prose $GUIDE "photolib\\.$package\\.v1" "the style guide names the package photolib.$package.v1"
done
assert_patterns assert_prose "$GUIDE" \
  'UUIDv7.*lowercase.*hyphen' "identifiers are lowercase hyphenated UUIDv7 strings" \
  'google\.protobuf\.Timestamp.*_at' "instants are Timestamps named *_at" \
  'CaptureTime.*(explicit|zone)' "capture times use CaptureTime with an explicit zone" \
  'unknown zone.*(absent|never).*UTC|never assum.*UTC' "an unknown time zone is never assumed to be UTC" \
  '_UNSPECIFIED = 0' "enums start with a *_UNSPECIFIED zero value" \
  'tolerate unknown (enum )?values' "readers tolerate unknown enum values" \
  'never renumber' "field numbers are never renumbered" \
  'never reuse' "field numbers are never reused" \
  'reserved <number>;.*reserved "<name>";' "a removed field reserves its number and its name" \
  '1 to 15.*one byte' "numbers 1 to 15 are for the common fields" \
  'optional.*(absent|presence)' "optional is for fields whose absence matters" \
  'schema_version' "payload plaintexts carry a schema_version" \
  'buf breaking.*last .*release tag.*origin/dev' "breaking changes are checked against the last release tag, else main" \
  'tools/codegen\.sh' "the guide says how to regenerate" \
  'checked in' "generated code is checked in"
assert_patterns assert_prose docs/dev/README.md \
  'style guide\]\(protobuf-style-guide\.md\)' "the developer guide links the style guide" \
  'tools/codegen\.sh' "the developer guide says how to regenerate the code"

# --- ADR-0019 records the toolchain decisions
ADR=docs/adr/0019-protobuf-toolchain.md
assert_file $ADR
assert_patterns assert_matches "$ADR" \
  '^\* \*\*Status\*\*: Accepted — 2026-10-15 .*owner confirmed' "is Accepted: the owner confirmed it" \
  'photolib-design#266' "links the owner's answer (#266)"
assert_patterns assert_prose "$ADR" \
  'checked in' "records that generated code is checked in" \
  'origin/dev' "records the breaking-change baseline before the first release" \
  'buf\.build|remote plugin|BSR' "records why plugins run locally rather than on the Buf Schema Registry"
assert_matches docs/adr/README.md '\]\(0019-protobuf-toolchain\.md\) \| [^|]* \| Accepted \(owner confirmed' "is listed in the ADR index as Accepted"

finish
