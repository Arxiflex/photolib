#!/usr/bin/env bash
# Exercise the shared dependency allow-list with Rust crates, a fake Dart cache and npm lock files.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_tool python3
cd "$REPO_ROOT" || exit 1

DENY=deny.toml
DART="$REPO_ROOT/tools/dart_licenses.py"
assert_file "$DENY"
assert_file tools/dart_licenses.py

allow_list() { python3 -c 'import sys, tomllib; print("\n".join(tomllib.load(open(sys.argv[1], "rb"))["licenses"]["allow"]))' "$1"; }
ALLOWED=$(allow_list "$DENY" 2>&1) && ok "$DENY parses and has licenses.allow" || fail "$DENY is not valid: $ALLOWED"
yanked=$(python3 -c 'import sys, tomllib; print(tomllib.load(open(sys.argv[1], "rb")).get("advisories", {}).get("yanked"))' "$DENY")
[[ $yanked == deny ]] && ok "$DENY denies yanked crates" || fail "$DENY must set advisories.yanked = \"deny\", not $yanked"
for id in MIT Apache-2.0 BSD-2-Clause BSD-3-Clause ISC Zlib MPL-2.0 Unicode-3.0 AGPL-3.0-only; do
  grep -qxF -- "$id" <<<"$ALLOWED" && ok "allowed: $id" || fail "$DENY must allow $id"
done
excluded=$(grep -E 'GPL|SSPL|BUSL|Elastic|-NC|Commons-Clause|LicenseRef' <<<"$ALLOWED" | grep -vxF AGPL-3.0-only)
[[ -z $excluded ]] && ok "no other copyleft or restricted licence is allowed" || fail "$DENY allows $(tr '\n' ' ' <<<"$excluded")"

# --- cargo-deny against throwaway crates, when it is installed (the gate fails loudly when Rust code needs it)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if command -v cargo >/dev/null && command -v cargo-deny >/dev/null; then
  WORK=$TMP/cargo
  mkdir -p "$WORK/app"
  cp "$DENY" "$WORK/app/deny.toml"
  # crate <name> <licence expression or "-">: a crate depended on by app
  crate() {
    mkdir -p "$WORK/$1/src"
    : >"$WORK/$1/src/lib.rs"
    printf '[package]\nname = "%s"\nversion = "0.0.0"\nedition = "2021"\npublish = false\n' "$1" >"$WORK/$1/Cargo.toml"
    [[ $2 == - ]] || printf 'license = "%s"\n' "$2" >>"$WORK/$1/Cargo.toml"
    printf '%s = { path = "../%s" }\n' "$1" "$1" >>"$WORK/app/Cargo.toml"
  }
  deny() { (cd "$WORK/app" && cargo deny --offline --config deny.toml check licenses >/dev/null 2>&1); }
  new_app() {
    printf '[package]\nname = "app"\nversion = "0.0.0"\nedition = "2021"\npublish = false\nlicense = "AGPL-3.0-only"\n[dependencies]\n' >"$WORK/app/Cargo.toml"
    mkdir -p "$WORK/app/src"
    echo 'fn main() {}' >"$WORK/app/src/main.rs"
  }
  new_app
  crate dual "MIT OR Apache-2.0"
  crate bsd "BSD-3-Clause"
  deny && ok "cargo-deny accepts permissive crates, and our own AGPL-3.0-only" || fail "cargo-deny rejected permissive crates"
  for bad in GPL-3.0-only GPL-2.0-only LGPL-3.0-only "GPL-3.0-only OR LGPL-3.0-only" CC-BY-NC-4.0 -; do
    new_app
    crate dual "MIT OR Apache-2.0"
    crate bad "$bad"
    deny && fail "cargo-deny accepted a crate licensed '$bad'" || ok "cargo-deny rejects a crate licensed '$bad'"
  done
else
  echo "skip: cargo and cargo-deny are not both installed; $DENY is not exercised by the real tool here"
fi

APP="$TMP/app"
ENTRIES=()
new_dart_app() {
  rm -rf "$TMP/cache" "$TMP/sdk" "$APP"
  mkdir -p "$APP/.dart_tool"
  ENTRIES=('{"name": "app", "rootUri": "../", "packageUri": "lib/"}')
  FLUTTER_ROOT=
}
# hosted <name> [licence text]: a package in the pub cache; no licence file when no text is given
hosted() {
  mkdir -p "$TMP/cache/$1"
  [[ $# -lt 2 ]] || printf '%s\n' "$2" >"$TMP/cache/$1/LICENSE"
  ENTRIES+=("{\"name\": \"$1\", \"rootUri\": \"file://$TMP/cache/$1\", \"packageUri\": \"lib/\"}")
}
# sdk_package <name> [licence text]: a package of the Flutter SDK, whose root LICENSE is the BSD-3-Clause text
sdk_package() {
  mkdir -p "$TMP/sdk/packages/$1"
  printf '%s\n' "$BSD3_TEXT" >"$TMP/sdk/LICENSE"
  [[ $# -lt 2 ]] || printf '%s\n' "$2" >"$TMP/sdk/packages/$1/LICENSE"
  FLUTTER_ROOT=",\"flutterRoot\": \"file://$TMP/sdk\""
  ENTRIES+=("{\"name\": \"$1\", \"rootUri\": \"file://$TMP/sdk/packages/$1\", \"packageUri\": \"lib/\"}")
}
write_config() {
  local IFS=,
  echo "{\"configVersion\": 2$FLUTTER_ROOT, \"packages\": [${ENTRIES[*]}]}" >"$APP/.dart_tool/package_config.json"
}
# Optional arguments replace the default allow-list with these SPDX identifiers.
run_dart() {
  local config=()
  if [[ $# -gt 0 ]]; then
    printf '[licenses]\nallow = [%s]\n' "$(printf '"%s", ' "$@")" >"$TMP/deny.toml"
    config=("$TMP/deny.toml")
  fi
  write_config
  capture python3 "$DART" "$APP" ${config[@]+"${config[@]}"}
}

MIT_TEXT=$'MIT License\n\nCopyright (c) 2024 Someone\n\nPermission is hereby granted, free of charge, to any person obtaining a copy\nof this software and associated documentation files (the "Software"), to deal\nin the Software without restriction.'
BSD2_TEXT=$'Copyright 2020 Someone. All rights reserved.\n\nRedistribution and use in source and binary forms, with or without\nmodification, are permitted provided that the following conditions are met:\n\n1. Redistributions of source code must retain the above copyright notice.\n2. Redistributions in binary form must reproduce the above copyright notice.'
BSD3_TEXT="$BSD2_TEXT"$'\n3. Neither the name of Google LLC nor the names of its contributors may be used to endorse\nor promote products derived from this software without specific prior written permission.'
BSD4_TEXT="$BSD3_TEXT"$'\n4. All advertising materials mentioning features or use of this software must display an acknowledgement.'
APACHE_TEXT=$'                                 Apache License\n                           Version 2.0, January 2004\n                        http://www.apache.org/licenses/'
ISC_TEXT=$'ISC License\n\nPermission to use, copy, modify, and/or distribute this software for any purpose\nwith or without fee is hereby granted, provided that the above copyright notice appears.'
ZLIB_TEXT=$'This software is provided \'as-is\', without any express or implied warranty.\n\n2. Altered source versions must be plainly marked as such, and must not be\n   misrepresented as being the original software.'
MPL_TEXT=$'Mozilla Public License Version 2.0\n==================================\n\n1. Definitions'
UNLICENSE_TEXT=$'This is free and unencumbered software released into the public domain.'
CC0_TEXT=$'Creative Commons Legal Code\n\nCC0 1.0 Universal'
GPL_TEXT=$'                    GNU GENERAL PUBLIC LICENSE\n                       Version 3, 29 June 2007'

# each licence text is recognised as exactly its SPDX id: only a list allowing that id lets it through
for pair in "MIT:$MIT_TEXT" "BSD-2-Clause:$BSD2_TEXT" "BSD-3-Clause:$BSD3_TEXT" "Apache-2.0:$APACHE_TEXT" "ISC:$ISC_TEXT" \
  "Zlib:$ZLIB_TEXT" "MPL-2.0:$MPL_TEXT" "Unlicense:$UNLICENSE_TEXT" "CC0-1.0:$CC0_TEXT"; do
  id=${pair%%:*}
  new_dart_app
  hosted pkg "${pair#*:}"
  run_dart "$id"
  expect_result "a $id package passes a list allowing $id" 0
  run_dart GPL-3.0-only
  expect_result "a $id package fails a list without $id" 1 pkg
done

new_dart_app
hosted a "$MIT_TEXT"
hosted b "$BSD3_TEXT"
hosted c "$APACHE_TEXT"
run_dart
expect_result "the repository's own deny.toml allows MIT, BSD-3-Clause and Apache-2.0 packages" 0

new_dart_app
hosted both "$MIT_TEXT"$'\n\n'"$APACHE_TEXT"
run_dart MIT Apache-2.0
expect_result "a file holding two allowed licences passes" 0
run_dart MIT
expect_result "a file holding an allowed and a disallowed licence fails" 1

new_dart_app
hosted gpl "$GPL_TEXT"
run_dart
expect_result "an unrecognised licence fails, naming the package" 1 gpl "not recognised"

new_dart_app
hosted advertising "$BSD4_TEXT"
run_dart
expect_result "BSD-4-Clause is recognised and rejected" 1 advertising BSD-4-Clause

new_dart_app
hosted nolicence
run_dart
expect_result "a package without a licence file fails" 1 nolicence "no licence file"

new_dart_app
hosted fine "$MIT_TEXT"
hosted bad_one "$GPL_TEXT"
hosted bad_two
run_dart
[[ "$OUT" == *bad_one* && "$OUT" == *bad_two* && "$OUT" != *fine* ]] && ok "every offending package is reported, and only those" || fail "report: $OUT"

new_dart_app
hosted fine "$MIT_TEXT"
sdk_package flutter_test
sdk_package sky_engine "$BSD4_TEXT"
run_dart BSD-3-Clause MIT
expect_result "Flutter SDK packages are covered by the SDK's own root LICENSE, not by their own files" 0
run_dart MIT
[[ $STATUS -eq 1 && "$OUT" == *flutter_test* && "$OUT" == *BSD-3-Clause* && "$OUT" != *fine* ]] && ok "an SDK whose root LICENSE is not on the list fails, naming its packages" || fail "SDK root licence: $STATUS $OUT"

new_dart_app
hosted fine "$MIT_TEXT"
mkdir -p "$TMP/shared"
ENTRIES+=('{"name": "shared", "rootUri": "../../shared", "packageUri": "lib/"}')
run_dart
expect_result "packages inside the repository (relative paths) are first-party and not checked" 0

new_dart_app
run_dart
expect_result "an app without dependencies passes" 0

new_dart_app
capture python3 "$DART" "$APP"
expect_result "a missing package_config.json fails and says how to create it" 1 "flutter pub get"

capture python3 "$DART"
expect_result "no arguments is a usage error" 2

# --- tools/node_licenses.py: the SPDX expression package-lock.json records for each npm package
NODE="$REPO_ROOT/tools/node_licenses.py"
# run_node <expression or "-" for none>...: a lock file with the package pkg<i> under each licence
run_node() {
  mkdir -p "$TMP/viewer"
  python3 - "$TMP/viewer/package-lock.json" "$@" <<'PY'
import json, sys
packages = {"": {"name": "viewer", "license": "AGPL-3.0-only"}, "../shared": {"link": True}}
for i, licence in enumerate(sys.argv[2:]):
    packages[f"node_modules/@scope/pkg{i}"] = {} if licence == "-" else {"license": licence}
json.dump({"lockfileVersion": 3, "packages": packages}, open(sys.argv[1], "w"))
PY
  capture python3 "$NODE" "$TMP/viewer"
}
run_node MIT "(Apache-2.0 AND BSD-3-Clause)" "MIT OR GPL-3.0-only" "Apache-2.0 WITH LLVM-exception" "(MIT OR CC0-1.0) AND ISC"
expect_result "npm packages pass when their SPDX expressions allow them" 0
for bad in GPL-3.0-only "MIT AND GPL-3.0-only" "(GPL-2.0-only OR LGPL-3.0-only)" UNLICENSED "MIT OR" -; do
  run_node MIT "$bad"
  [[ $STATUS -eq 1 && $OUT == *@scope/pkg1* && $OUT != *pkg0* ]] && ok "an npm package licensed '$bad' fails, and is named" ||
    fail "an npm package licensed '$bad': $STATUS $OUT"
done
rm "$TMP/viewer/package-lock.json"
capture python3 "$NODE" "$TMP/viewer"
expect_result "a missing package-lock.json fails and says how to create it" 1 "npm install"
capture python3 "$NODE"
expect_result "node_licenses.py without arguments is a usage error" 2

assert_patterns assert_prose AGENTS.md \
  'cargo deny' "AGENTS.md lists the Rust licence check" \
  'dart_licenses\.py' "AGENTS.md lists the Dart licence check" \
  'node_licenses\.py' "AGENTS.md lists the npm licence check"

finish
