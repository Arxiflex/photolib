#!/usr/bin/env bash
# Private-mode keys (ADR-0255, M6-02) as the owner kept them (photolib-design#724): three words proven at setup, the
# whole phrase in a drill every six months, a reset that removes the password path, the uploader's own keys at the
# gate and BIP-39's English list in every language.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0255-private-mode-keys-and-recovery.md
SERVER=server/crates/photolib-server/src
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-23\. The owner kept [^*]*photolib-design#724' \
  "is Accepted, recording the owner's answer (#724)"
assert_matches docs/adr/README.md \
  '\(0255-private-mode-keys-and-recovery\.md\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-23\)' \
  "the index lists ADR-0255 as Accepted"
assert_prose app/lib/features/privacy/privacy_page.dart 'const int _asked = 3;' "1: setup asks three words of the kit"
assert_prose "$SERVER/account_keys.rs" "recovery_verified_at \+ interval '6 months'" "2: a drill falls due six months on"
assert_prose "$ADR" 'A drill, due six months after the last verification, takes the whole phrase' \
  "2: a drill takes the whole phrase"
assert_prose "$SERVER/account_keys.rs" "DELETE FROM unlock_paths WHERE user_id = \\\$1 AND kind = 'password'" \
  "3: a new password without a wrap removes the password path"
assert_prose "$SERVER/uploads.rs" 'Principal::User\(owner, _\) \| Principal::Key\(owner, \.\.\)' \
  "4: the gate takes the uploader's account"
assert_prose "$SERVER/uploads.rs" 'account_keys::ready\(&self\.pool, owner\)' "4: and checks the uploader's own keys"
assert_prose "$ADR" 'One word list in every language' "5: one word list in every language"
assert_file kernel/src/bip39-english.txt

finish
