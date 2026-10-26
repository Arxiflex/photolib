# ADR-0265 — Mutations: an outbox of edits merged by photolibd per field, per album item and by fractional keys

* **Status**: **Proposed — owner to confirm** (photolib-design#90).
* **Requirements**: R-REL-1. **Design**:
  sync §5, §8,
  domain model §1, §4.1, §5, §9,
  client app §1.4,
  [ADR-0091](0091-sync-rpc.md), [ADR-0120](0120-client-sync-engine.md).

## Context

Design 05 §5 has every user action applied to the replica at once, kept in a persistent outbox with a UUIDv7 and a
hybrid logical clock (HLC) reading, and merged on the server: per-field last-writer-wins by HLC, add/remove per set
element by HLC, fractional keys for custom order, a delete (to trash) that wins over edits, clocks more than five
minutes ahead clamped, mutation ids kept 30 days, poison mutations rolled back with feedback. It leaves open the wire
form of a mutation, how a device rolls back without the server's state, where an album item's HLC lives once the item
is removed, how two devices that add the same asset to an album name its item, and where the HLC and key code runs
(design 10 §1.4 lists them among the kernel's cheap calls).

## Decision

* **Wire**: `photolib.sync.v1.Mutation` carries a `FieldEdit` (a table, a row id and typed values of its user fields)
  or a `MemberEdit` (an asset added to an album, with its fractional key, or removed). `SyncService.PushMutations`
  takes at most 500 in order and answers each one's outcome, the rows they touched as sync sends them (a deletion
  for one gone or out of sight) and the server's clock; capability `sync.mutations.v1`.
* **Fields** devices set: an asset's `title`, `description`, `rating`, `color_label`, `archived` (`Edit`) and
  `trashed_at` (`Delete`, at the edit's HLC; null restores), one's own `favorite` and `hidden_from_memories`
  (`View`), an album item's `sort_key` (`Edit` on the album). In a private library or album the server refuses in
  clear what design 04 §9 encrypts: an asset's fields but its trash, an item's key.
* **Merge**: each field keeps its latest edit by `(ms, counter, device)`, kept per row in `field_hlc` (assets,
  `asset_user_state`, `album_items`); of two at one reading, from one device, the later applied. An album item's
  presence and key live in `album_item_states`, which outlives a removed item, so a key moved before a removal is not
  lost to an older re-add; `album_items` holds the present ones. A delete is the trash field, which no other field's
  edit undoes. A reading more than five minutes past the server's clock counts as five minutes past it, counter 0.
* **Item ids**: an asset's item in an album is the UUIDv8 of the first 16 bytes of SHA-256(`photolib.album_item` ‖
  album ‖ asset), so that two devices' adds name one item. Equal fractional keys order by the item's id.
* **Once**: `processed_mutations` keeps each account's mutation ids and outcomes 30 days, purged daily by the
  scheduler; a retry gets the first outcome. Refusals are `mutation.not_found` (gone, or out of the caller's sight),
  `mutation.forbidden` and `mutation.invalid`.
* **Device**: `Mutations` in `photolib_data` applies an edit to the replica, ticks the persisted clock (table `clock`,
  schema 23) and appends the mutation to the outbox in one transaction. `SyncEngine.run` pushes first; an answer
  replaces the touched rows and the edits still waiting show over them again, as they do over every sync batch. A
  refused one is so rolled back and kept, with its reason, for the UI until dismissed. A failed push waits 2 s,
  doubling to an hour. The device does not compare clocks: its own waiting edits show until the server answers.
* **Code**: the HLC tick and fractional keys are Dart (`clock` table, `albums.dart`'s `keyBetween`), the merge Rust in
  photolibd; neither is a kernel call.

## Consequences

* Randomized tests prove convergence on both sides: two devices' mutations in any interleaving, with retries, leave
  photolibd as the rules say (`rpc/sync/mutations.rs`), and two replicas editing offline end as a merging stand-in
  holds (`test/convergence_test.dart`).
* M2-26 builds favourites, archive, trash and albums on `Mutations`; creating albums, tags and faces' people are new
  `FieldEdit` tables or `MemberEdit` sets. Whatever creates album items must use the same item id.
* Private libraries (M6-05) merge inside their blobs; the clear fields are refused, not merged.
* A sort by `sort_key` on the server must order bytewise (`COLLATE "C"`).

## Options considered

* **HLC tick and fractional keys as kernel calls** (design 10 §1.4): one code for every client, but an FFI or WASM
  call per edit, asynchronous on the web, for a few lines of arithmetic only devices run.
* **Client-side merge by HLC** (`field_hlc` in the replica): exact optimistic views, but every synced table needs the
  column and every apply a comparison; the server's answer settles the view anyway.
* **A base copy per pending field**: rollback without the server, but stale whenever another device edits.
* **Clamping to the server's clock**: an edit from a fast clock would lose to everything since; the bound keeps the
  order of the device's own edits.
* **Random item ids, deduplicated on the server**: devices would hold a second item until the next sync.
* **Removed items as rows with a flag**: every reader of `album_items` would have to skip them.
