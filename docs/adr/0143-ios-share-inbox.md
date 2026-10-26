# ADR-0143 — Sharing into the iOS app: an App Group inbox the app saves into the Photos library

* **Status**: Accepted — 2026-10-20 (photolib-design#68). The owner kept both decisions of
  photolib-design#503:
  shared items are saved into the Photos library, which on iOS is the app's library, and the entitlements stay as
  they are until the test phase registers the App Group. He kept "Open in Photolib" an alternative viewer too, its
  document types ranked Alternate, never the default
  (photolib-design#551,
  2026-10-21).
* **Requirements**: R-APP-4. **Design**: docs/10 §6.4, §6.5, MOB-08 of docs/02.

## Context

Other apps share photos and videos through the share sheet. docs/10 §6.4 gives the share extension no Flutter engine
(an extension has about 120 MB) and has it copy items and a manifest into the App Group inbox for the app to ingest,
without saying where they go. On iOS the app's library is the Photos library it indexes (ADR-0095); M1 has no upload.

## Decision

We will ship `app/ios/ShareExtension`, a Swift share extension named Photolib for up to 500 photos and videos:

* It copies each shared file, never loading it, into `Inbox/<uuid>/<n>/<name>` of the App Group
  `group.org.photolib.photolib`, then writes `manifest.json` (`{"items": [{"file", "kind": "photo" | "video"}]}`)
  last, and closes the sheet. An entry without a manifest is still being copied.
* "Open in Photolib", from Files or another app's share sheet, feeds the same inbox: the Runner declares photos and
  videos as document types it opens (rank *Alternate*, so Photos stays their owner), gets a copy of each
  (`LSSupportsOpeningDocumentsInPlace` false), moves the copies into an entry with its manifest last
  (`ShareInbox.swift`) and tells the app (`changed`).
* The app drains the inbox at start, on every resume and on `changed` (`app/lib/core/share_inbox.dart`): each
  complete entry is saved into the Photos library in one `PHAssetCreationRequest` change (`ShareInbox.swift`),
  keeping the files' names, then deleted; PhotoKit's observer brings the new assets into the timeline. An entry whose
  save fails stays for the next resume; after 7 days any entry goes. While Photos refuses access (`denied`), a banner
  over the library counts what waits, says when it goes, and asks for access (`allow`), or opens Settings once iOS no
  longer asks.

## Consequences

* Shared items behave as if saved from the other app: they reach iCloud Photos and every other Photos client.
* The App Group is registered with Apple in the test phase, before the first device build; simulators do not check
  it. Its identifier is the placeholder application ID's ([ADR-0023](0023-flutter-app-shell.md)) and is renamed
  with it.
* Upload to a server (M2-18) and adding to an album will read the same inbox.

## Options considered

* **A Photolib-only folder in the app's container**: shared items would live outside Photos and outside its iCloud,
  in a source no iOS client has yet.
* **A Flutter engine in the extension**: over the memory limit for a video, and a second engine (docs/10 §1.5).
* **Saving from the extension**: it would need Photos access of its own and finish while the sheet waits.
