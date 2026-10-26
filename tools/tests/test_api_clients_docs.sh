#!/usr/bin/env bash
# The API clients and their one network stack (M0-09): the decision, what administrators are told about private CAs,
# client certificates and reverse proxies, and the rule contributors follow, as the owner confirmed them
# (photolib-design#312).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0032-one-network-stack.md
assert_file "$ADR"
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-16\. The owner confirmed [^*]*photolib-design#312' \
  "is Accepted, recording the owner's confirmation (#312)"
assert_matches docs/adr/README.md '\(0032-one-network-stack\.md\) \| [^|]* \| Accepted \(owner confirmed' \
  "the index lists ADR-0032 as Accepted"
assert_prose "$ADR" 'dart:io[^.]*SecurityContext' "puts the native targets on dart:io with an explicit SecurityContext"
assert_prose "$ADR" 'ok_http[^.]*cupertino_http|cupertino_http[^.]*ok_http' "says why OkHttp and URLSession wait"
assert_prose "$ADR" 'follows no redirect[^.]*headers over HTTPS only' "follows no redirect, sends headers over HTTPS only"
assert_prose "$ADR" 'epoch, the instance id' "pins an endpoint by the GetServerInfo epoch"
assert_prose "$ADR" 'appends of at most 8 MiB' "uploads in appends of at most 8 MiB"
assert_prose "$ADR" 'loopback' "routes players through the loopback proxy"
assert_prose "$ADR" 'unauthenticated[^.]*reason' "logs out only on unauthenticated with a reason"

PAGE=docs/admin/clients.md
assert_file "$PAGE"
assert_prose docs/admin/README.md '\]\(clients\.md\)' "the administrator guide links the clients page"
assert_prose "$PAGE" 'private (CA|certificate authority)' "covers a private CA"
assert_prose "$PAGE" 'PKCS#12' "covers client certificates"
assert_prose "$PAGE" 'self-signed[^.]*fingerprint' "covers self-signed servers"
assert_prose "$PAGE" 'browser[^.]*(install|operating system)' "states the browser limitation"
assert_prose "$PAGE" '100 MB[^.]*8 MiB|8 MiB[^.]*100 MB' "explains why request caps do not matter"
assert_prose "$PAGE" '(502|504)[^.]*never[^.]*(log|sign)s? (you )?out|never[^.]*(log|sign)s? (you )?out[^.]*(502|504)' \
  "says proxy error pages never log out"
assert_prose docs/dev/README.md '0032-one-network-stack\.md' "the developer guide links the decision"

# ADR-0125 as the owner answered it (photolib-design#480): 1, 2, 3 and 5 kept, 4 and 6 changed.
ADR=docs/adr/0125-sign-in-from-the-app.md
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-20\. The owner kept [^*]*photolib-design#480' \
  "is Accepted, recording the owner's answer (#480)"
assert_matches docs/adr/README.md \
  '\(0125-sign-in-from-the-app\.md\) \| [^|]* \| Accepted \(owner answered, 2026-10-20; #522.s choices kept, 2026-10-23\)' \
  "the index lists ADR-0125 as Accepted, #522's choices kept"
# #522's three choices as the owner kept them (photolib-design#674).
assert_patterns assert_prose "$ADR" \
  '\* \*\*Status\*\*: [^*]*photolib-design#674[^*]*passwords set before keep their parameters until' \
  "1: earlier passwords keep their parameters until photolibd can change a password" \
  '\* \*\*Status\*\*: [^*]*photolib-design#674[^*]*browsers? [^*]*only an address or .localhost. counts as local' \
  "2: in browsers only an address or localhost is local" \
  '\* \*\*Status\*\*: [^*]*photolib-design#674[^*]*ADR-0057[^*]*ADR-0065[^*]*own answers' \
  "3: ADR-0057 and ADR-0065 stand on their own answers"
assert_prose app/packages/photolib_api/lib/src/stack_web.dart \
  "if \(host == 'localhost'\) return \[Uri\.parseIPv4Address\('127\.0\.0\.1'\)\];.{0,200}on FormatException \{ return \[\];" \
  "2: a browser counts no other name as an address"
for adr in 0057-encrypted-local-store 0065-photolib-upload; do
  assert_matches docs/adr/README.md "\($adr\.md\) \| [^|]* \| Accepted \(" "ADR-${adr%%-*} is Accepted on its own answer"
done
assert_patterns assert_prose "$ADR" \
  'over plain HTTP only to an address photolibd itself counts as local' "4: the bearer over plain HTTP only locally" \
  'every address the endpoint.s name resolves to' "4: judged by the addresses a name resolves to" \
  'needs HTTPS' "4: says the server needs HTTPS elsewhere" \
  'calibrated at enrolment[^,]*, to about a second' "6: new passwords are calibrated to about a second" \
  '128 MiB and six' "6: falls back to 128 MiB and six passes" \
  'Folder backup stays with M2-18\*\*[^*]*BLAKE3' "1: folder backup, hashing and a library are M2-18's"
assert_prose "$PAGE" 'session over plain HTTP only to an address of the local networks' \
  "the clients page says where the session crosses plain HTTP"
assert_prose AGENTS.md 'every request to a server[^.]*goes through[^.]*`Server`' \
  "AGENTS.md says every request to a server goes through its one client"

# Follow-ups of M2-44 as the owner kept them (photolib-design#719): the library each account but viewers gets
# (ADR-0089), the desktops' passkey relay, renewal once fewer than 60 of 90 days are left, sync every five minutes,
# a refused upload an hour later, and the 4 GiB line for Argon2id's start cost (ADR-0125).
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-20\.[^*]*photolib-design#719' \
  "ADR-0125 records that the owner kept #481's choices (#719)"
LAYOUT=docs/adr/0089-managed-library-layout.md
assert_prose "$LAYOUT" '\* \*\*Status\*\*: Accepted — 2026-10-23\.[^*]*photolib-design#719' \
  "ADR-0089 is Accepted, recording the owner's answer (#719)"
assert_matches docs/adr/README.md '\(0089-managed-library-layout\.md\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-23\)' \
  "the index lists ADR-0089 as Accepted"
assert_prose "$LAYOUT" 'every account but viewers[^.]*"Photos"' "1: every account but viewers gets Photos"
assert_prose server/crates/photolib-server/src/library.rs "role <> 'viewer'" "1: the job gives viewers none"
assert_prose server/crates/photolib-server/src/jobs.rs '\(CREATE, "\*/15 \* \* \* \*"\)' "1: queued every 15 minutes"
assert_prose "$ADR" 'on desktops with a passkey through photolibd.s relay page' "2: passkeys through the relay on desktops"
for doc in "$ADR" docs/adr/0052-password-login-and-sessions.md docs/admin/users.md; do
  assert_prose "$doc" 'fewer than 60 of (its|the) 90 days' "3: renewed once fewer than 60 of 90 days are left"
done
assert_prose app/lib/features/servers/servers.dart 'const _renewal = Duration\(days: 60\);' "3: the app's renewal"
assert_prose app/lib/features/servers/sync.dart 'Timer\.periodic\(const Duration\(minutes: 5\)' "3: sync every 5 minutes"
assert_prose app/packages/photolib_data/lib/src/backup.dart 'min\(\(refused \? 60 : 1\) << ' \
  "3: a refused upload an hour later"
assert_prose app/lib/features/servers/ksf.dart '< 4 << 20;' "4: under 4 GiB is constrained"

finish
