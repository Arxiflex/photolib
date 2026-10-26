# ADR-0225 — Real-time hints: a Server-Sent Events channel per foreground device, the watermark polled while it is open

* **Status**: **Proposed** — awaiting the product owner's decision. Becomes *Accepted — YYYY-MM-DD*; once accepted, only
  *Superseded by ADR-NNNN* may change it.
* **Requirements**: R-MODE-2. **Design**:
  sync §9,
  API §2,
  client app §10,
  [ADR-0091](0091-sync-rpc.md), [ADR-0120](0120-client-sync-engine.md).

## Context

Design 05 §9 asks for hints ("stream X advanced") over Server-Sent Events to apps in the foreground, never data, and
roadmap M2-17 for a change on one device to appear on another within 2 s on a LAN. Design 16 §2 names `GET /events`.
It leaves open how photolibd learns that a stream advanced, what a hint and the request carry, and how apps reconnect.

## Decision

* **Request**: `GET /events?streams=<name>,…` with the session or API key, for at most 1,000 streams the device
  follows (ADR-0120 lists them); no session is `unauthenticated`, as on `/upload`. The channel has no other state.
  Clients feature-detect `sync.hints.v1`.
* **Events**: each event's data is stream names, one a `data` line. The first names those of the request the caller
  may read, which may have advanced since its last sync; each later one those that a change advanced, as the stream's
  own tables read them (`photolib_db::sync::changes`) between two watermarks, and that `can` still allows. A quiet
  channel gets a comment every 15 s; stopping photolibd ends every channel.
* **Detection**: each open channel reads the watermark every 250 ms and, only when it moved, asks each stream for one
  change since it last looked. Nothing runs while no device is in the foreground.
* **Apps**: in the foreground a signed-in app holds one channel on the endpoint that answers as its instance; each
  hint, the first included, runs a sync, one at a time with later hints folded into one more; a sync that opens or
  closes streams opens the channel again with them. A lost channel opens again after 1 s, doubling up to a minute;
  a revoked session signs the app out. Browsers follow none until they have a data worker.

## Consequences

* A rename through the API reaches a following device and its sync in 160-400 ms on loopback; against the stand-in,
  a hinted change is in the replica within 90 ms.
* An open channel costs a trivial query four times a second, and a stream's change query only after writes; many
  foreground devices during a large ingest repeat those queries per channel.
* Hints name only streams the device asked for and may read, never rows; their timing tells a member when a library
  they see changed, which their sync tells them anyway.

## Options considered

* **`LISTEN/NOTIFY` from the capture trigger**: no polling, but a migration of every synced table's trigger and still
  a wait for the watermark to pass the notifying transaction.
* **One poller per process shared by its channels**: fewer watermark reads with many devices; more code for a
  household's few.
* **The server deriving the account's streams**: no list in the request, but a second copy of the app's stream logic.
* **WebSockets or long polling**: SSE passes every proxy template already (`tests/proxies.rs`) and needs nothing from
  the client back.
