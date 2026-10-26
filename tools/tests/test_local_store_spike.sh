#!/usr/bin/env bash
# The local store encryption spike (M0-42, photolib-design#249): numbers per target against every budget of design 21
# §8, the hardware binding and passcode policy per platform, and ADR-0090 with the cipher and the Argon2id floor.
# store_cost_test.dart (`dart` part) and web_test.dart (`web` part) re-measure the budgets.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

REPORT=docs/dev/local-store-spike.md
ADR=docs/adr/0090-local-store-cipher-and-passcode-binding.md
assert_file "$REPORT"
assert_prose docs/dev/README.md '\]\(local-store-spike\.md\)' "the developer guide links the report"
for target in 'VM 100k' 'VM 1M' 'App, Linux AOT' 'Chrome 155' 'Firefox 158'; do
  assert_matches "$REPORT" "^\| $target[^|]* \| [^|]+ \|( [^|]+ \|){5}\$" "has database costs for $target"
done
for target in VM 'App, Linux AOT' 'Chrome 155 dart2js' 'Chrome 155 dart2wasm' 'Firefox 158 dart2js' \
  'Firefox 158 dart2wasm'; do
  assert_matches "$REPORT" "^\| $target \|( [^|]+ \|){6}\$" "has thumbnail, start and unlock numbers for $target"
done
for budget in 'Unlock ≤ 600 ms' 'Database overhead ≤ 10 %' 'T2 read with decryption ≤ 12 ms p95' 'Cold start at L1'; do
  assert_matches "$REPORT" "^\| $budget[^|]* \| [^|]+ \| (Met|Missed; mitigation: |Unverified)" \
    "gives a verdict on the budget '$budget'"
done
assert_matches "$REPORT" '^\| Platform \| Secure hardware \| `HW` key \| Present on \| Detected by \| Without it \|$' \
  "has the hardware-binding table"
for platform in 'Android \| StrongBox' 'Android \| TEE' 'iOS, iPadOS \| Secure Enclave' 'macOS \| Secure Enclave' \
  'Windows \| TPM 2\.0' 'Linux \| TPM 2\.0' 'Web \| none'; do
  assert_matches "$REPORT" "^\| $platform" "binds a passcode on ${platform//\\/}"
done
assert_matches "$REPORT" '^\| Platform \| PIN \(≥ 6 digits\) \| Passphrase \(≥ 10 characters\) \|$' \
  "has the passcode policy table"
for platform in Android 'iOS, iPadOS' macOS Windows Linux Web; do
  assert_matches "$REPORT" "^\| $platform \|( [^|]+ \|){2}\$" "has a passcode policy for $platform"
done
assert_prose "$REPORT" 'tools/data/web\.sh` compiles with dart2js' "says why browsers measure the database in dart2js"
assert_matches tools/data/web.sh 'dart compile js .*drift_worker' \
  "the web store's worker is compiled with dart2js, where page copies are cheap"
assert_file app/packages/photolib_data/test/store_cost_test.dart
assert_file app/benchmark/store_cost_test.dart

assert_file "$ADR"
assert_patterns assert_prose "$ADR" \
  'We will use AEGIS-256 .{0,300}ChaCha20-Poly1305 stays' "records the chosen ciphers" \
  '`m = 64 MiB, t = 3, p = 1` stays' "records the Argon2id floor" \
  '`HW` takes a challenge derived from the Argon2id output' "binds the hardware per guess" \
  '\(\.\./dev/local-store-spike\.md\)' "links the report"

finish
