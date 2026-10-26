#!/usr/bin/env bash
# Webhooks, the events API and plugins (M9-04, ADR-0263) as the owner kept them (photolib-design#677): ids-only events
# of standard libraries, webhooks managed only by an account signed in and kept off loopback, 0.0.0.0/8, link-local,
# broadcast and multicast, Wasmtime plugins for M11-05, and feeds and embeds with public links.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

ADR=docs/adr/0263-webhooks-events-and-wasm-plugins.md
SERVER=server/crates/photolib-server/src
assert_prose "$ADR" '\* \*\*Status\*\*: Accepted — 2026-10-23 \(roadmap M9-04\)\. The owner kept [^*]*photolib-design#677' \
  "is Accepted, recording the owner's answer (#677)"
assert_matches docs/adr/README.md \
  '\(0263-webhooks-events-and-wasm-plugins\.md\) \| [^|]* \| Accepted \(owner confirmed, 2026-10-23\)' \
  "the index lists ADR-0263 as Accepted"
# 1. Private libraries emit nothing, not even ids.
assert_prose "$SERVER/events.rs" "JOIN libraries l ON l\.id = e\.library_id AND l\.privacy = 'standard'" \
  "events are read of standard libraries only"
# 2. An event is its id, type, time, library and asset.
assert_prose proto/photolib/api/v1/events.proto \
  'message Event \{[^}]*event_id = 1;[^}]*type = 2;[^}]*recorded_at = 3;[^}]*library_id = 4;[^}]*asset_id = 5; \}' \
  "an event carries ids only"
# 3. Only an account signed in manages its webhooks, up to 10, never at this machine's or link-local addresses.
for procedure in ListWebhooks CreateWebhook DeleteWebhook; do
  assert_matches "$SERVER/rpc/authz.rs" "\"/photolib\.api\.v1\.WebhookService/$procedure\", KEYS\)" \
    "$procedure needs ManageKeys, which no API key has"
done
assert_matches "$SERVER/events.rs" '^const MAX_WEBHOOKS: i64 = 10;$' "an account has at most 10 webhooks"
assert_prose "$SERVER/events.rs" \
  'v4\.is_loopback\(\) \|\| v4\.octets\(\)\[0\] == 0 \|\| v4\.is_link_local\(\) \|\| v4\.is_broadcast\(\) \|\| v4\.is_multicast\(\)' \
  "refuses loopback, 0.0.0.0/8, link-local, broadcast and multicast"
for doc in "$ADR" docs/admin/integrations.md docs/dev/threat-model.md; do
  assert_prose "$doc" 'loopback, .0\.0\.0\.0/8., link-local, broadcast or multicast' "names the addresses refused"
done
# 4. Plugins: Wasmtime components, a manifest's capabilities, 64 MiB and 10 s, signed files an administrator installs.
assert_prose "$ADR" 'Wasmtime[^*]*WIT world[^*]*manifest[^*]*64 MiB[^*]*10 s[^*]*administrator installs[^*]*cosign' \
  "plugins run as M11-05 will build them"
# 5. The random photo now; feeds and embeds with public links (M3-13).
assert_prose "$SERVER/media.rs" '"random" => media\.random\(' "/media/random serves a random photo"
assert_prose "$ADR" 'RSS feeds and embeds of albums wait for public links \(M3-13\)' "feeds and embeds wait for M3-13"

finish
