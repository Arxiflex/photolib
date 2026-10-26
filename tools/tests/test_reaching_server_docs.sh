#!/usr/bin/env bash
# Reaching the server (ADR-0311, M2-47) as the owner kept it (photolib-design#713): LAN discovery on by default,
# check-host.net for the outside test only when an administrator asks, no relay in 1.0, metered as mobile data alone.
# shellcheck disable=SC2016 # patterns match literal backticks
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0311-reaching-the-server.md
assert_prose "$ADR" \
  '\* \*\*Status\*\*: Accepted — 2026-10-23 \(roadmap M2-47\)\. The owner kept [^*]*photolib-design#713' \
  "is Accepted, recording the owner's answer (#713)"
assert_matches docs/adr/README.md \
  '\(0311-reaching-the-server\.md\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-23\)' \
  "the index lists ADR-0311 as Accepted"
assert_prose server/crates/photolib-server/src/config.rs 'fn default_discovery\(\) -> bool \{ true \}' \
  "1. photolibd answers LAN discovery by default"
assert_prose server/crates/photolib-server/src/run.rs \
  'if !config\.discovery \|\| !config\.roles\.contains\(&Role::Api\) \|\| at\.ip\(\)\.is_loopback\(\)' \
  "1. only an api process listening beyond loopback answers"
assert_matches docs/admin/configuration.md '^\| `discovery` \| `true` \|' "1. the docs give discovery's default"
assert_matches app/lib/features/admin/remote_access.dart \
  "^final Uri checkHost = Uri\.parse\('https://check-host\.net/'\);" \
  "2. the outside test asks check-host.net"
assert_matches docs/admin/privacy.md \
  '^\| Public-URL self-test \| check-host\.net[^|]*\| Only when an administrator taps' \
  "2. the privacy manifest lists it, sent only when an administrator asks"
assert_prose "$ADR" '\*\*Leave the relay for later\*\*: no hosted or end-to-end encrypted relay of our own in 1\.0' \
  "3. no relay in 1.0"
assert_prose app/lib/features/servers/connection_check.dart \
  'bool metered\(List<ConnectivityResult> networks\) => networks\.contains\(ConnectivityResult\.mobile\) && '\
'!networks\.contains\(ConnectivityResult\.wifi\) && !networks\.contains\(ConnectivityResult\.ethernet\);' \
  "4. metered is mobile data without Wi-Fi or Ethernet"

finish
