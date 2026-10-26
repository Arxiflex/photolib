#!/usr/bin/env bash
# The authorization policy (ADR-0038, M2-03) as the owner answered it (photolib-design#330), and scoped API keys
# (ADR-0055, M2-06) as the owner confirmed them (photolib-design#369), and server policies (ADR-0240, M2-40) as the
# owner kept them (photolib-design#684); the policy matrix (server/crates/photolib-authz/tests/matrix.rs) pins the same
# rules in code.
# shellcheck disable=SC2016 # patterns match literal backticks
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0038-authorization-policy.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-17\. The owner answered [^*]*photolib-design#330' \
  "is Accepted, recording the owner's answers (#330)"
assert_patterns assert_prose "$ADR" \
  'whoever may delete an asset also sees it in the trash and may restore it' "the trash shows to whoever may delete" \
  'covers, memories, face crops, search hits and map pins' "locked assets leak through no surface" \
  'acts as an editor over what others put into it, without Share' "a library's owner does not share others' assets" \
  'Adding an asset to an album needs Share on the asset' "adding to an album needs Share" \
  'never upload, edit or delete' "viewer accounts never change anything" \
  'favourite, seen, hidden from memories\) needs only View' "per-user state needs only View" \
  'comments and likes need View and an album that allows comments' "viewers will like and comment" \
  'private libraries are shared whole' "private libraries are shared whole with partners" \
  'disables the date filter' "the partner UI explains why private libraries have no date filter" \
  'per-file key rows' "grants will take their scope from per-file keys" \
  'at most 24 h after' "a grant's expiry will be checked by the database" \
  'stay with the owner until M3-11 adds co-owners' "only an album's owner shares or deletes it"
assert_matches docs/adr/README.md '\(0038-authorization-policy\.md\) \| [^|]* \| Accepted \(owner answered' \
  "the index lists ADR-0038 as Accepted"
assert_prose docs/admin/users.md 'only whoever may delete a photo sees it in the trash' \
  "administrators are told who sees the trash"

KEYS=docs/adr/0055-scoped-api-keys.md
assert_prose "$KEYS" '\* \*\*Status\*\*: Accepted — 2026-10-17\. The owner confirmed [^*]*photolib-design#369' \
  "ADR-0055 is Accepted, recording the owner's confirmation (#369)"
assert_patterns assert_prose "$KEYS" \
  'Expiry is required' "every key expires" \
  'No key manages keys' "keys never manage keys" \
  'requests per minute, 600 unless set' "keys are rate limited per process, 600 a minute by default" \
  'A separate service rather than design 16.s .AuthService.' "keys have their own service"
assert_matches docs/adr/README.md '\(0055-scoped-api-keys\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0055 as Accepted"

POLICY=docs/adr/0240-server-policies.md
assert_prose "$POLICY" '\* \*\*Status\*\*: Accepted — 2026-10-23\. The owner kept [^*]*photolib-design#684' \
  "ADR-0240 is Accepted, as the owner kept its six decisions (#684)"
assert_patterns assert_prose "$POLICY" \
  '\*Archive viewer\* switches off managed libraries, uploads, device folders, edits, deletes and XMP writes;' \
  "1: what Archive viewer switches off" \
  '\*Family backup\* only XMP writes[^;]*; \*Personal\* only sharing and public links' \
  "1: what Family backup and Personal switch off" \
  'a pinned switch wins over every narrower level' "2: a pin decides for everyone" \
  'Turning sharing off makes existing shares inert rather than deleting them; turning it on restores them' \
  "3: sharing off leaves shares inert" \
  'clear the accounts. and libraries. own, so the whole server gets the preset; the switches stay editable' \
  "4: a preset clears narrower switches" \
  'one switch covers all three' "5: one switch for every upload channel" \
  '`edits` / `deletes` \| Editing / trashing and deleting assets' "6: edits and deletes cover assets only" \
  'Albums, libraries. settings and library members stay outside' "6: albums and library settings are organisation"
assert_matches docs/adr/README.md '\(0240-server-policies\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0240 as Accepted"
assert_matches server/crates/photolib-authz/src/lib.rs 'ORDER BY pinned DESC, library_id IS NULL, user_id IS NULL' \
  "a pin wins, then the narrowest level"

finish
