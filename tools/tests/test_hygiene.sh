#!/usr/bin/env bash
# Repository hygiene: .editorconfig states the formatting rules, every text file follows them, and .gitignore keeps
# build output, caches and secrets out of the repository without hiding real sources.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool git
require_tool awk
cd "$REPO_ROOT" || exit 1

assert_file .editorconfig
assert_file .gitignore

# ec_get <section> <key>: value of a key inside an exact .editorconfig section header, or empty.
ec_get() {
  awk -v section="[$1]" -v key="$2" '
    /^\[/ { in_section = ($0 == section); next }
    in_section {
      split($0, kv, "=")
      k = kv[1]; gsub(/[ \t]/, "", k)
      v = $0; sub(/^[^=]*=[ \t]*/, "", v)
      if (k == key) { print v; exit }
    }' .editorconfig 2>/dev/null
}

expect_ec() {
  local section=$1 key=$2 want=$3 got
  got=$(ec_get "$section" "$key")
  if [[ "$got" == "$want" ]]; then ok ".editorconfig [$section] $key = $want"; else
    fail ".editorconfig [$section] $key: want '$want', got '$got'"
  fi
}

if [[ -f .editorconfig ]]; then
  first_setting=$(awk '/^[ \t]*[^#; \t]/ { print; exit }' .editorconfig)
  [[ "$first_setting" == "root = true" ]] && ok ".editorconfig is the root file" || fail ".editorconfig must start with 'root = true' (got '$first_setting')"
fi
expect_ec '*' charset utf-8
expect_ec '*' end_of_line lf
expect_ec '*' insert_final_newline true
expect_ec '*' trim_trailing_whitespace true
expect_ec '*' indent_style space
expect_ec '*' indent_size 2
expect_ec '*.rs' indent_size 4
expect_ec '*.md' max_line_length 120
expect_ec 'Makefile' indent_style tab
expect_ec '*.{pbxproj,plist,entitlements,xcsettings}' indent_style tab

# --- every text file we would commit follows those rules
bad=0
while IFS= read -r -d '' file; do
  [[ -f $file ]] || continue
  grep -Iq . "$file" || continue
  if grep -q $'\r' "$file"; then fail "$file: CRLF line endings"; bad=1; fi
  if grep -Eq '[ '$'\t'']+$' "$file"; then fail "$file: trailing whitespace"; bad=1; fi
  if [[ -n $(tail -c1 "$file") ]]; then fail "$file: no newline at end of file"; bad=1; fi
  case "$file" in
    Makefile | */Makefile | *.go | *.pbxproj | *.plist | *.entitlements | *.xcsettings) ;;
    *) if grep -q $'\t' "$file"; then fail "$file: tab indentation"; bad=1; fi ;;
  esac
done < <(git ls-files -z --cached --others --exclude-standard)
[[ $bad -eq 0 ]] && ok "every committed text file follows .editorconfig"

# --- ignore rules, checked with git itself
ignored() {
  local path
  for path in "$@"; do
    git check-ignore -q --no-index "$path" && ok "ignored: $path" || fail "not ignored: $path"
  done
}
tracked() {
  local path
  for path in "$@"; do
    git check-ignore -q --no-index "$path" && fail "wrongly ignored: $path" || ok "not ignored: $path"
  done
}
ignored server/target/debug/photolibd kernel/target/release/libphotolib_kernel.so \
  viewer/node_modules/left-pad/index.js app/.dart_tool/package_config.json app/build \
  app/packages/photolib_data/build app/web/sqlite3mc.wasm app/web/drift_worker.js app/web/data_worker.js \
  app/web/metadata_worker.js \
  .env deploy/.env deploy/compose/.env.local secrets/server.pem keys/id_ed25519 .DS_Store app/ios/Pods/Manifest.lock \
  tools/tests/__pycache__/miniyaml.cpython-312.pyc
tracked app/lib/main.dart server/Cargo.lock kernel/testvectors/crypto/aead.json deploy/compose/.env.example \
  server/migrations/0001_init.sql viewer/src/build/index.ts proto/buf.yaml testdata/README.md

finish
