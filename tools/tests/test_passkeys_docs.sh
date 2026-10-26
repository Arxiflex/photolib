#!/usr/bin/env bash
# Passkeys and TOTP (ADR-0088, M2-05) as the owner accepted them (photolib-design#474): a verifier on ring with
# attestation 'none', one relay page for every app, the policy for every account and session, TOTP secrets in the clear.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0088-passkeys-and-totp.md
SERVER=server/crates/photolib-server
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-20\. The owner accepted all four decisions [^*]*photolib-design#474' \
  "is Accepted, recording the owner's answer (#474)"
assert_matches docs/adr/README.md '\(0088-passkeys-and-totp\.md\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-20\)' \
  "the index lists ADR-0088 as Accepted"
# 1. A relying party on ring: attestation 'none', ES256, EdDSA and RS256, no webauthn-rs and so no OpenSSL.
assert_matches "$SERVER/Cargo.toml" '^ring = ' "photolibd links ring"
if crates=$(grep -nE '^name = "(webauthn-rs|openssl|openssl-sys)"$' server/Cargo.lock); then
  fail "webauthn-rs or OpenSSL in the server: $crates"
else ok "no webauthn-rs or OpenSSL in the server"; fi
assert_prose "$SERVER/src/webauthn.rs" '"attestation": "none"' "registration asks for no attestation"
assert_prose "$SERVER/src/webauthn.rs" 'const ALGORITHMS: \[i64; 3\] = \[-8, -7, -257\];' "keys are EdDSA, ES256 or RS256"
# 2. The relay page on photolibd's origin returns the credential to photolib: or a loopback port.
assert_prose "$SERVER/src/relay.rs" '"/passkey",' "the relay page is /passkey"
assert_prose "$SERVER/src/relay/passkey.js" \
  "\['127\.0\.0\.1', '\[::1\]'\]\.includes\(url\.hostname\);[^;]*url\.protocol === 'photolib:' \|\| loopback" \
  "the relay returns only to photolib: or a loopback address"
# 3. Every account's sessions, from their next request; only the auth service while enrolling.
assert_prose "$SERVER/src/rpc/auth.rs" 'EXISTS \(SELECT FROM instance_settings WHERE require_two_factor\)' \
  "the session lookup checks the policy on every request"
assert_prose "$SERVER/src/rpc/authz.rs" '\(None, Rule::Anyone\) => Principal::Anonymous, \(None, _\) => \{[^}]*"second_factor\.required"' \
  "a session that must enrol reaches only what anyone may call"
assert_matches app/lib/l10n/app_en.arb '"adminTwoFactor": "Every account must set up a second factor"' \
  "the admin console's setting says every account"
# 4. TOTP secrets in the clear.
assert_prose server/migrations/0018_second_factors.sql 'CREATE TABLE totp_secrets \( user_id [^,]*, secret bytea NOT NULL,' \
  "TOTP secrets are stored as they are"

# Step-up (ADR-0242, M2-43) as the owner answered it (photolib-design#717): no OIDC proof, passkeys that verify their
# user (kept), and a step-up to add a passkey or set a password, but for a first TOTP or an account with nothing yet.
STEP=docs/adr/0242-step-up.md
assert_prose "$STEP" '\* \*\*Status\*\*: Accepted — 2026-10-23\. The owner kept [^*]*photolib-design#717' \
  "ADR-0242 is Accepted, recording the owner's answer (#717)"
assert_matches docs/adr/README.md '\(0242-step-up\.md\) \| [^|]* \| Accepted \(owner answered, 2026-10-23\)' \
  "the index lists ADR-0242 as Accepted"
assert_patterns assert_prose "$STEP" \
  'An OIDC sign-in does not' "1: an OIDC sign-in is no proof" \
  'StartPasskeySetup, and StartPasswordSetup and FinishPasswordSetup with a session' "2: adding a way in needs one" \
  'A first TOTP secret needs no proof[^.]*; nor does a first passkey or password of an account with no password, second factor or recovery code' "2: but not a first TOTP or an account with nothing" \
  'a passkey that verifies its user' "3: a passkey must verify its user"
assert_prose "$SERVER/src/rpc/oidc.rs" 'self\.open_session\(user, &device, false\)' "1: an OIDC session proves nothing"
assert_prose "$SERVER/src/rpc/auth.rs" 'let rp = self\.rp\(\)\?; self\.fresh\(&caller, true\)' \
  "2: adding a passkey asks for a fresh proof"
assert_prose "$SERVER/src/rpc/auth.rs" 'self\.passkey_signer\(&challenge, &credential, true\)' \
  "3: a step-up passkey verifies its user"
assert_matches docs/dev/threat-model.md '^\| T89 \|.*adding a passkey and setting a password with a session.*\(ADR-0242\)' \
  "threat model T89 covers adding a way in, by ADR-0242"

finish
