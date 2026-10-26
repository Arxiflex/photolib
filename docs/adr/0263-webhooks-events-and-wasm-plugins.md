# ADR-0263 — Webhooks, the events API and WASM plugins

* **Status**: Accepted — 2026-10-23 (roadmap M9-04). The owner kept all five decisions as made
  (photolib-design#677): no events of private libraries, ids only, webhooks managed by an
  account signed in and kept off this machine's and link-local addresses, plugins as item 6 says, and feeds and embeds
  with public links.
* **Requirements**: R-COMP-3; features `API-03`, `API-05`, `API-07`, `API-08`. **Design**:
  16 §6,
  05 §9,
  06 §1.

## Context

Home Assistant, photo frames, kiosks and scripts want to hear when photos arrive or leave, and to show a random photo,
without syncing a replica. The design asks for signed webhooks, an events API and an ADR for sandboxed plugins (built in
M11-05), and leaves open what an event carries, who receives it, how deliveries are signed and how a plugin is
confined. Webhooks are the first connection photolibd makes to an address a user types, so they also need the privacy
manifest's kill switch and a guard against reaching the server's own services.

## Decision

1. **Events are hints, never data.** A trigger on `assets` records `asset.created`, `asset.trashed`,
   `asset.restored` and `asset.deleted` in `events`, whatever wrote the row (uploads, ingest, scans, later APIs). An
   event is its id, type, time, library and asset: no name, date, place, size or file. They are read in the order
   their transactions committed, below the sync watermark (ADR-0053), so a cursor never skips one, and kept 7 days.
2. **One read path.** An account reads the events of the assets it may view now (`photolib_authz::scope`) but locked
   ones, and the deletions in the libraries it may view, and **only of standard libraries**: nothing about a private
   library leaves through events or webhooks, not even its ids or timing. `EventService.ListEvents` pages them with an
   opaque cursor, to a session or a key with `view`; frames and Home Assistant poll it.
3. **Webhooks.** An account registers at most 10 HTTPS or HTTP URLs through `WebhookService`, signed in, never with an
   API key, so a leaked key cannot set up a lasting leak; creating and deleting one is audited. Each gets the account's
   events, one JSON `Event` per POST, in order and at least once, signed as
   [Standard Webhooks](https://www.standardwebhooks.com/) sign: `webhook-id` (the event id), `webhook-timestamp` and
   `webhook-signature: v1,<base64 HMAC-SHA256 of "id.timestamp.body">` under a 32-byte secret shown once as `whsec_…`.
   The `events` job (scheduler, every minute, `worker:io`) delivers and purges; a failure (10 s timeout, a status other
   than 2xx, no redirects followed) stops that webhook until the next run and shows on it. A URL may name a LAN host,
   never a loopback, `0.0.0.0/8`, link-local, broadcast or multicast address, checked again on every address its name
   resolves to, which is the one connected to.
4. **Off by default.** `webhooks: true` in photolibd's configuration turns deliveries and new webhooks on;
   `outbound: none` wins. The events API needs no switch: it answers the account's own calls.
5. **Random photo.** `GET /media/random/{role}` serves a rendition of a random photo the caller may view in a standard
   library, as `/media` serves any (API-07, API-08). RSS feeds and embeds of albums wait for public links (M3-13), which
   they will be views of.
6. **Plugins (M11-05)** run in [Wasmtime](https://wasmtime.dev/) as WebAssembly components against a versioned WIT
   world, `photolib:plugin@1`: no file system, sockets, clock or environment, only the host functions their manifest
   declares (read an asset's metadata, a rendition, add tags or album items, call an allowed host), each checked by
   `photolib_authz` as the account that enabled the plugin, on standard libraries only. Each call gets a fuel budget, a
   memory limit (64 MiB by default), an epoch deadline (10 s) and a bounded output; plugins run as jobs fed by the
   events of item 1 on their own worker class. Only an administrator installs a plugin, from a file whose SHA-256 and
   publisher signature (cosign) are checked, after reading its capabilities; accounts then enable it. A host a plugin
   calls is a privacy-manifest connection, off by default. The server keeps the previous major of the world for a
   year, and an upgrade names the plugins it would break before it applies.

## Consequences

* ✅ Integrations hear of new photos within a minute without a replica, and a receiver checks each delivery with any
  Standard Webhooks library; no path shows what the caller could not see, and private libraries stay silent.
* ✅ Plugins get a confined, versioned surface instead of the server's internals (lessons LL-111).
* ⚠️ Receivers fetch what they need through the API with a key; an event alone says little.
* ⚠️ The secret is stored as is (the HMAC needs it): a stolen database could forge deliveries until it is replaced.
* ⚠️ A webhook that fails forever is tried every minute; receivers with a self-signed certificate are refused.
* ⚠️ Private-library users get no webhooks; a receiver away more than 7 days misses events and syncs instead.

## Options considered

* **Full payloads** (names, dates, places): every receiver, often plain HTTP on a LAN, would hold copies; ids suffice.
* **Ids-only events of private libraries**: would still tell a third party when and how much the owner uploads, which
  design 06 leaves visible only to the operator.
* **Events streamed over SSE or WebSocket**: one connection per integration held open; the `/events` SSE of design 16
  stays the apps' sync hint, and webhooks cover pushing.
* **Deliveries queued per event in the same transaction**: a job row per event; a cursor per webhook is one row.
* **Refusing private addresses too**: Home Assistant runs on the LAN; loopback and link-local are what an SSRF wants.
* **Plugins as processes or containers**: heavier, platform-bound and harder to bound than a WASM sandbox; scripts in
  Lua or JavaScript would need their own sandboxing and versioning.
