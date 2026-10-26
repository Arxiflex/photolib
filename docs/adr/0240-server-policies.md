# ADR-0240 — Server policies: capability switches in the authorisation module, presets, pins in the configuration

* **Status**: Accepted — 2026-10-23. The owner kept all six decisions: what each preset switches off, a pin deciding
  for everyone, shares made inert while sharing is off, presets clearing narrower switches, one switch for every
  upload channel, and edits and deletes covering assets only
  (photolib-design#684).
* **Requirements**: R-MODE-5, R-MODE-3, R-SEC-2. **Design**: 15 §10, 12 §4,
  07 §1–2, [ADR-0038](0038-authorization-policy.md), [ADR-0063](0063-admin-console.md).

## Context

M2-40 asks for capability switches set per server, user and library (groups join with M3-20), the narrowest set level
winning, enforced by the authorisation module before roles for sessions, API keys and sync alike; presets that fill
them (*Archive viewer*, *Family backup*, *Personal*); and any setting pinnable in the YAML file. The design names the
capabilities but not what each refuses, what the two other presets hold, how a pin relates to narrower levels, or what
sharing switched off does to shares that exist.

## Decision

* **A switch is a row of `policy_switches`** (capability, account or library or neither, on or off, pinned). What
  decides for an account in a library is a pin, else the library's row, else the account's, else the server's; none
  leaves the capability on, so a server without rows behaves as before. `photolib_authz` holds this precedence once
  (`DECIDING`) and inlines it as a subquery into every check, so a check stays one plan reading rows by id.
* **What each capability refuses**, in `scope` and `can`, to sessions, API keys, links, grants and sync streams alike:

  | Capability | Refused while off |
  |---|---|
  | `managed_libraries` | Contributing to a managed library; `library::create` makes none |
  | `uploads` | Contributing to any library, and appending to an upload |
  | `folder_browser` | A library's folder tree (`Resource::Folders`) |
  | `device_folders` | The device folders a connected app shows (`Resource::DeviceFolders`) |
  | `sharing` | Share on anything; access through an album's membership, a partner share or a link, judged by the album's or partner share's owner |
  | `edits` / `deletes` | Editing / trashing and deleting assets |
  | `xmp_writes` | An asset's XMP sidecar (`Resource::Sidecar`) |
  | `face_recognition` | Face streams and crops, the people stream, grants' face processing |
  | `ml_search` | ML streams, grants' embeddings |

  Albums, libraries' settings and library members stay outside: an owner still files their own assets into their own
  albums with sharing off. Folders, sidecars and device folders are resources now so that every capability has one
  to refuse; their APIs arrive with their items.
* **Uploads take only libraries that accept them**: managed ones while managed libraries are on, and read-write
  external ones marked as an upload target (design 07 §2); never a read-only one. A refused upload says why:
  `permission_denied` `policy.disabled` with the `capability`.
* **Presets** set every switch the configuration does not pin at the server level and clear the accounts' and
  libraries' own, so the whole server gets the preset; the switches stay editable. *Archive viewer* switches off
  managed libraries, uploads, device folders, edits, deletes and XMP writes; *Family backup* only XMP writes, so that
  a household's edits stay in Photolib; *Personal* only sharing and public links.
* **Pins** are the configuration's `settings` (the console's instance settings and `policy.<capability>`). Every start
  writes them over the database, server switches marked pinned, and a pinned switch wins over every narrower level:
  an operator who pins uploads off means no uploads. The API refuses a change with `failed_precondition`
  `setting.pinned`; the console shows the value read-only as set in config.
* **The admin service** gains `GetPolicy`, `UpdatePolicy` (set or clear one capability at one level) and `ApplyPreset`,
  each change an audit event (`policy.update`, `policy.preset`; `settings.pin` when a start changes something).

## Consequences

* ✅ Hiding a feature in an app is never the only control: the matrix test switches each capability off and checks
  that it takes away exactly what its table says, and sync's policy test runs a round with switches off.
* ⚠️ Turning sharing off makes existing shares inert rather than deleting them; turning it on restores them.
* ⚠️ Apps learn the effective policy with M2-41; until then a switched-off feature fails with its refusal. A stream
  whose rows a policy change hides sends no deletion for them until M2-41's sync change.
* Groups (M3-20) add a level between the server and the account.

## Options considered

* **Pins as server values that narrower levels may override**: an operator's pin would not mean what it says.
* **A SQL function for the precedence**: planned again at every call, it doubled what a check reads.
* **Presets that keep narrower levels**: *Archive viewer* would leave the uploads an account was allowed.
* **One switch per upload channel** (device, web, CLI): the server cannot tell an app from a script reliably; one
  switch covers all three.
