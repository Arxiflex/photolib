# ADR-0071 — Desktop folders in the app: a desktop-only picker, the scan state in the replica, sandboxed macOS

* **Status**: Accepted — 2026-10-17. The owner answered M1-25's provisional choice in
  photolib-design#371:
  the App Sandbox stays, and security-scoped bookmarks come now, with the desktop gallery (M1-26 built them,
  [ADR-0107](0107-desktop-and-web-thumbnail-decoders.md)), not as a follow-up. The read-only entitlement was at odds
  with the save dialog of later write features ([ADR-0115](0115-debug-diagnostics.md), [ADR-0128](0128-downloads.md)).
  Applied in photolib-design#403. The owner kept read-write for the save dialog and read-only folder bookmarks
  (photolib-design#593,
  2026-10-21).
* **Requirements**: R-MODE-1. **Design**: 10 §8,
  07.

## Context

On Windows, macOS and Linux the library is the folders the user adds ([ADR-0042](0042-desktop-folder-sources.md)).
The app needs a native folder picker, and Settings must show each folder as scanning with progress, online or offline,
with its item count. The design names neither the picker nor what progress means, and the macOS app is sandboxed.

## Decision

We will:

* Pick folders with `file_selector`'s Linux (GTK's native chooser, the file-chooser portal under Flatpak), macOS and
  Windows implementations through its platform interface, not the federated package, so that phones and the web carry
  no picker plugin. Only desktops offer *Add folder*; the web's folders are M1-04.
* Keep the scan state in `media_source.state`: `scanning` from when a folder is added until a full scan ends (the
  first, a resumed one and the hourly reconcile), then `online`, or `offline`. Progress is the number of items found
  so far under an indeterminate bar; a folder's count is its items in the library, present or offline.
* Confirm a removal, which deletes the folder's rows and never a file.
* Keep the macOS App Sandbox: the app parses untrusted media with bundled C decoders (FFmpeg, libmpv, libvips), and the
  sandbox confines an exploit to the picked folders and the app's container. M10-04 packages a sandboxed, notarised
  DMG.
* Keep picked folders across launches with `com.apple.security.files.bookmarks.app-scope`: the macOS runner
  (`FolderAccess.swift`) makes a read-only security-scoped bookmark when a folder is added, picked or dropped on the
  window, and resolves it at launch (`startAccessingSecurityScopedResource`) before the app's Dart starts. Bookmarks
  are device-local, kept in this device's user defaults and never in the synced replica. A stale bookmark (the folder
  was moved or renamed) is recreated from the resolved URL; one that does not resolve (a drive unmounted, a folder
  deleted) leaves the folder offline, as ADR-0042 does, and Settings offers to pick it again.
* Read only, so that an exploit can read photos but not encrypt or delete them: folders get read-only bookmarks
  (`securityScopeAllowOnlyReadAccess`). A write feature on the library's folders (XMP sidecars, delete to trash) asks
  for read-write, and the user picks each folder once more. The save dialog of the diagnostic bundle and downloads
  needs `files.user-selected.read-write`, which the app holds (ADR-0115, ADR-0128), so a folder just picked or dropped
  is writable through that grant until the app quits.

## Consequences

* The state survives restarts and every client of the replica sees it; it costs no extra write, as a full scan already
  writes the row for each directory.
* No counting pass before a scan, so no determinate bar: counting would read every directory of a NAS twice.
* Once relaunched, the app cannot write into the user's folders on macOS; a later write feature asks for read-write.
* On macOS a picked folder stays readable across launches as long as its bookmark resolves; the gate compiles no Swift,
  so `tools/tests/test_desktop_thumbnails.sh` checks the runner and the entitlements as text and the smoke test runs
  them.

## Options considered

* The federated `file_selector`: adds Android, iOS and web plugins nobody calls. `file_picker`: more code and
  platforms for the same dialog.
* Progress as an in-memory signal from the data isolate: lost on restart and invisible to other clients.
* No App Sandbox for the DMG (hardened runtime only, TCC prompts for protected folders): keeps access without
  bookmarks, but an exploit in a decoder could then read and write everything the user can.
* Bookmarks later: every folder would turn offline at each relaunch, which breaks the desktop gallery on macOS.
* `files.user-selected.read-only` with macOS downloads saved into `~/Downloads` (`files.downloads.read-write`): no
  save dialog, so no choice of place.
