#!/usr/bin/env bash
# Accounts and first run (ADR-0035, M2-01) as the owner answered them (photolib-design#322), and password login
# (ADR-0052, M2-02) as the owner answered it (photolib-design#370, #591): each ADR is Accepted with its choices, and the
# admin guide and ADR-0125 say the same.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0035-accounts-and-first-run.md
GUIDE=docs/admin/users.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-16\. The owner confirmed [^*]*deferred [^*]*photolib-design#322' \
  "is Accepted, recording what the owner confirmed and deferred (#322)"
assert_matches docs/adr/README.md '\(0035-accounts-and-first-run\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0035 as Accepted"
assert_prose "$ADR" '`purge_at` seven days later' "purges a deleted account after a fixed seven days"
assert_prose "$GUIDE" 'purged seven days later' "tells administrators about the seven days"
assert_prose "$ADR" 'keeps it in memory and logs it once at WARN' "keeps the setup token in each process's memory"
assert_prose "$GUIDE" 'A restart logs a new token and invalidates the old one' "says a restart replaces the token"
assert_prose "$ADR" 'Roles\*\* are `admin`, `user` and `viewer`' "makes viewer a role"
assert_prose "$GUIDE" '\| `viewer` \| Browse what others share with them; never upload\. \|' "lists the viewer role"
assert_prose "$ADR" 'handle, display name and email are named, never copied' "keeps personal values out of the audit"
assert_prose "$GUIDE" 'Handles, names and emails are named, never copied' "tells administrators so"

LOGIN=docs/adr/0052-password-login-and-sessions.md
assert_prose "$LOGIN" '\* \*\*Status\*\*: Accepted — 2026-10-17\. The owner answered [^*]*photolib-design#370' \
  "ADR-0052 is Accepted, recording the owner's answers (#370)"
assert_prose "$LOGIN" '\* \*\*Status\*\*: Accepted — [^*]*The owner kept #402.s choices[^*]*photolib-design#591' \
  "ADR-0052 records that the owner kept #402's choices (#591)"
assert_matches docs/adr/README.md '\(0052-password-login-and-sessions\.md\) \| [^|]* \| Accepted \(owner answered' \
  "the index lists ADR-0052 as Accepted"
assert_patterns assert_prose "$LOGIN" \
  'a link and a QR code' "setup tokens travel as a link and a QR code" \
  'photolibd admin password-setup <handle>' "the host prints a setup token" \
  'never in .data_dir.' "the key file is never in data_dir" \
  'locks out only the guesser' "a known device counts its attempts apart" \
  'per address' "attempts also count per address" \
  'until the new one is first used, or for 24 hours' "a rotated token keeps working a while"
assert_patterns assert_prose "$GUIDE" \
  'photolibd admin password-setup <handle>' "tells administrators how the host makes a token" \
  'Back it up apart from the database dumps' "says to back the key up apart from the dumps" \
  'locks out only themselves' "explains device secrets" \
  'or for 24 hours' "explains the rotation grace"
SIGN_IN=docs/adr/0125-sign-in-from-the-app.md
assert_prose "$SIGN_IN" 'forgotten administrator password[^.]*`photolibd admin password-setup' \
  "ADR-0125 recovers a forgotten administrator password from the host"
check "ADR-0125 no longer recovers it only while the app runs" \
  bash -c "! grep -qi 'recovered only while the app runs' '$REPO_ROOT/$SIGN_IN'"

finish
