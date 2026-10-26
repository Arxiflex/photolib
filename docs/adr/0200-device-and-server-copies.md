# ADR-0200 — One photo on the device and the server: one tile, the verified server copy as truth, the device a cache

* **Status**: Accepted — 2026-10-21 (roadmap M2-45, photolib-design#457): the owner kept every numbered proposal in
  photolib-design#576,
  proposals 3 and 7 with the caveats they now state. Only *Superseded by ADR-NNNN* may change it.
* **Requirements**: R-MODE-1, R-MODE-2, R-REL-1; VIEW-05, ING-14, ING-15, LIB-06. **Design**: 04 §4,
  05 §6–6.1, 10 §3.6, §5.4, §6.2, §11. Siblings: [ADR-0202](0202-albums-across-custody.md) (albums
  over the same copies) and [ADR-0201](0201-sources.md) (every other source kind);
  [ADR-0092](0092-per-user-deduplication.md) (links by hash), [ADR-0094](0094-device-timeline.md),
  [ADR-0045](0045-mediastore-index.md), [ADR-0095](0095-photokit-index.md).

## Context

A photo taken on a phone and backed up exists twice. The design has the pieces — one tile per logical asset with a
badge (M2-24), per-asset backup states (M2-18), free up space over verified backups only (M2-22), storage policies for
remote copies (10 §11), deletion intent and the registry that stops resurrection (05 §6.1) — but not what the user
sees and what the app does, end to end, in each situation. The owner's lean, tested here against the alternatives:
once the server copy is verified it is the preferred one and the local copy goes, as after Google Photos' "Free up
space" or Apple's "Optimise iPhone Storage"; the device keeps what its storage policy says. The user never sees two of
one photo, never wonders which copy is real, never loses a photo and is never surprised by space.

The words used everywhere (10 §3.6): **backed up** means verified (05 §1.4); **on this device**, **cloud only**,
**not backed up**; **Move to trash** (everywhere it is), **Remove from this device** (the library keeps it),
**Delete forever** (from a trash).

## How others behave

Gathered 2026-10-21 from the vendors' documentation, the competitor trackers of the design repository's issue study
and its Google Play review analysis; reactions are 👍 counts. *(inf)* marks an inference, *?* nothing documented.

| Situation | Google Photos | Apple Photos + iCloud | Immich | Ente | Mylio | Synology Photos | PhotoPrism | Nextcloud | Amazon Photos | OneDrive |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 Backup states and badges | Per-item icons, status screen (GP5) | Library status only; opaque "Unable to upload" (AP5) | Local / backed up / remote tile icon; filter asked 103 (IM1, IM14) | Not-backed-up icon, no cloud-only state (EN1, EN10) | Per-device sync health, unprotected alerts (MY4) | "On device", "Backed up to" (SY2) | No app; PhotoSync over WebDAV (PP1) | Memories marks local-only (NC9) | ? | Online-only, local, always kept (OD1) |
| 2 One tile or two | One item *(inf)* | One asset, a mirror (AP3) | One when checksums match; two after edits (IM15–IM17) | Hash dedupe; edits separate (EN1) | ? | "All my photos in 3 versions" (SY1) | Related files stacked (PP3) | A gallery's `.trashed` file uploaded as new (NC2) | ? | ? |
| 3 Which copy opens | ? | Optimised copy, original on demand (AP2) | The local file when present (IM22) | iOS preview, cached on view (EN1, EN2) | Tiers, on-demand cache (MY3) | ? | n/a | ? | ? | Downloads on open (OD1) |
| 4 Deleted in another app | Cloud stays *(inf)* | A delete in any app deletes everywhere (AP1) | Becomes remote-only (IM1) | Stays in Ente: "a backup, not a sync" (EN1) | Desktop policy: restore (default), this device, everywhere (MY1) | ? | ? | One-way; may upload the trashed file (NC2) | ? | An online-only delete deletes everywhere (OD1) |
| 5 Deleted in the app | Trash = device and cloud; "delete from device" apart (GP1) | One delete, 30 days in Recently Deleted (AP1) | Three buttons, confusing (IM13, IM32) | Ente / device / both, remembered (EN6, EN12) | Always every device (MY1) | Both, forced (SY1) | Server only | Both, no choice (NC8) | ? | ? |
| 6 Server copy deleted elsewhere | Removes device copies (GP1) | Propagates | Re-uploaded once the trash empties (IM12) | "Ignored", never re-uploaded (EN1) | Restored by default (MY1) | Re-uploaded after v2.0 (SY1) | Re-upload hidden as a duplicate (PP2) | ? | ? | ? |
| 7 Free up space | Manual, every backed-up item, keeps the last 30 days (GP2) | Automatic Optimise, on by default (AP2) | Manual, review, keep-rules, OS trash (IM1, IM5) | Manual, all at once; Android skips the trash (EN2) | iOS: only items verified on another device, scheduled (MY2) | One button; permission loops (SY1) | None | Delete right after upload (NC1) | Exists, unverified (AM1) | Per file or folder, "doesn't delete" (OD1) |
| 8 Edited in another app | In-app edits are versions (GP5) | Same asset, adjustments (AP3) | Missed, later new assets (IM18, IM19) | A new photo (EN1) | ? | ? | Stacked, wrong primary (PP3) | ? | ? | ? |
| 9 iCloud placeholders | n/a | Originals in iCloud (AP2) | Downloaded to hash; re-upload storm (IM20) | Fetches originals; temp files fill phones (EN1, EN14) | Warns only (MY2) | ? | ? | ? | ? | n/a |
| 10 Live Photo, RAW+JPEG halves | ? | One asset, two resources | Live pairs; one RAW+JPEG half lost (IM29) | Live Photo zipped as one (EN1) | ? | Motion clips lost (SY1) | Stacked (PP5, PP7) | Live Photos open since 2020 (NC11) | ? | ? |
| 11 Several devices, pin back | Partner auto-save undoes "Undo backup" (GP1) | Full mirror; Mac downloads originals (AP3) | No pin; re-download lands in a new folder (IM33) | Offline download asked 69 (EN11) | Per-device presets (MY4) | Duplicates after re-login (SY1) | n/a | Two-way sync asked 841 (NC4) | ? | "Always keep on this device" (OD1) |
| 12 Storage saver | Storage saver, permanent (GP3) | Never | Refused, "not in scope" (IM21) | Never (EN1) | Optimised tier beside originals (MY3) | Originals (SY3) | Compressed copy stacked (PP4) | n/a | Full resolution *(inf)* (AM1) | ? |

### Complaints

| Situation | The strongest complaints |
|---|---|
| 1 States | Immich: filter by upload status (103, IM14); Ente cannot tell cloud-only items apart (EN10); Apple's opaque "Unable to upload" (AP5) |
| 2 Duplicates | Synology "all my photos show up in 3 versions" (SY1); Immich two tiles after an edit or a hash mismatch (IM15–IM17); Nextcloud uploads a gallery's `.trashed` files as new (24, NC2) |
| 3 Which copy | Immich could not show a photo once another app deleted the local copy (8, IM22); Ente hides the device copy for 15–30 min after a cloud delete (EN13) |
| 4 Deleted in another app | Ente: "deleting locally should delete in Ente" (25, EN3); Immich two-way sync (214, IM10); on Apple any third-party delete is iCloud-wide (AP1, MY2) |
| 5 Delete dialog | Immich "Delete" versus "Move to trash" (34, IM13) and three buttons (IM32); Synology's forced delete-both (SY1); Memories offers no choice (NC8) |
| 6 Resurrection | Immich "delete from web and sync to mobile" (274, IM9), "avoid resyncing if deleted manually" (131, IM11), re-upload after the trash empties (IM12); Ente re-upload after another device emptied the trash (EN7) |
| 7 Free up space | Immich's mass removal request (141, IM4), its trash invisible on Samsung and OnePlus (IM7) and deleted WhatsApp media (IM8, IM6); Ente frees everything with no preview (EN5, EN15); Nextcloud deletes right after upload (59, NC1) |
| 8 Edits | Immich iOS edits not synced (12, IM18); PhotoPrism's edited copy not the primary (29, PP3); Ente duplicates edited Takeout copies (EN16) |
| 9 Placeholders | Immich re-uploaded every iCloud asset (83 comments, IM20); Ente's temporary files filled storage (EN14) |
| 10 Pairs | Immich iOS RAW+JPEG (31, IM29); Synology lost motion clips (SY1); Nextcloud iOS Live Photos (22, NC11); icloudpd leaves the `.mov` half (IC3) |
| 11 Devices, offline | Nextcloud two-way sync (841, NC4); Ente offline download (69, EN11); Memories offline mode (45, NC7) |
| 12 Compression | Immich's compression request refused (32, IM21); Google's Storage saver is permanent (GP3) |

**What each got right**, and where it lands here: Google's free-up shows the amount and acts on backed-up items only
(F1); Apple has one library and one meaning of delete (X1, I1); Immich's free-up reviews, keeps WhatsApp and uses the
OS trash (F5, F8); Ente remembers deletions and never re-uploads them (X8, E1); Mylio frees only what is verified
elsewhere and lets each device choose what another app's deletion means (F1, O6); Synology says where each item is
backed up (B5); PhotoPrism stacks related files into one tile (T4); OneDrive's "Free up space" and "Always keep on
this device" are one clear vocabulary (P2).

### Sources

* GP1 — [Google Photos: Delete & restore](https://support.google.com/photos/answer/6128858)
* GP2 — [Google Photos: Free up space](https://support.google.com/photos/answer/6128843)
* GP3 — [Google Photos: Storage saver](https://support.google.com/photos/answer/6220791)
* GP5 — Design research: Google Photos backup and sync
* AP1 — [Apple: Manage iCloud storage, deleting photos](https://support.apple.com/en-us/108922)
* AP2 — [Apple: Optimise iPhone Storage](https://support.apple.com/en-us/105061)
* AP3 — Design research: iCloud Photos is a mirror
* AP5 — [Apple: Unable to upload, couldn't sync](https://support.apple.com/en-sa/101984)
* IM1 — [Immich docs: mobile app, indicator and Free Up Space](https://docs.immich.app/features/mobile-app)
* IM4 — [immich#23743 Mass remove already backed-up photos (141)](https://github.com/immich-app/immich/discussions/23743)
* IM5 — [immich#25577 v2.5.0 release: Free Up Space](https://github.com/immich-app/immich/discussions/25577)
* IM6 — [immich#25725 Free Up Space broadens deletion scope by default (6)](https://github.com/immich-app/immich/discussions/25725)
* IM7 — [immich#26024 Free Up Space trash invisible on Samsung and OnePlus (4)](https://github.com/immich-app/immich/issues/26024)
* IM8 — [immich#25184 Freeing up space may break media in other apps (9)](https://github.com/immich-app/immich/discussions/25184)
* IM9 — [immich#3594 Delete from web and sync to mobile (274)](https://github.com/immich-app/immich/discussions/3594)
* IM10 — [immich#4341 Two-way sync (214)](https://github.com/immich-app/immich/discussions/4341)
* IM11 — [immich#4282 Avoid resyncing if deleted manually (131)](https://github.com/immich-app/immich/discussions/4282)
* IM12 — [immich#20978 Remote deletions re-uploaded after clearing the trash (13)](https://github.com/immich-app/immich/issues/20978)
* IM13 — [immich#14441 "Delete" and "Move to Trash" is confusing (34)](https://github.com/immich-app/immich/discussions/14441)
* IM14 — [immich#2155 Mobile: filter by upload status (103)](https://github.com/immich-app/immich/discussions/2155)
* IM15 — [immich#12693 Two thumbnails for the same asset](https://github.com/immich-app/immich/issues/12693)
* IM16 — [immich#6209 Modified asset shown twice](https://github.com/immich-app/immich/issues/6209)
* IM17 — [immich#3985 Different checksum, the photo appears twice](https://github.com/immich-app/immich/issues/3985)
* IM18 — [immich#9250 Edited photos on iPhone not synced (12)](https://github.com/immich-app/immich/issues/9250)
* IM19 — [immich#23426 iOS edits re-uploaded as new assets](https://github.com/immich-app/immich/discussions/23426)
* IM20 — [immich#20331 iOS app re-uploads every iCloud asset (83 comments)](https://github.com/immich-app/immich/issues/20331)
* IM21 — [immich#1202 Optimise uploaded images: not in scope (32)](https://github.com/immich-app/immich/issues/1202)
* IM22 — [immich#9249 Cannot view images after another app deleted the local copy (8)](https://github.com/immich-app/immich/issues/9249)
* IM29 — [immich#18201 Upload both halves of an iOS JPEG+RAW (31)](https://github.com/immich-app/immich/discussions/18201)
* IM32 — [immich#20789 Three delete buttons (7)](https://github.com/immich-app/immich/discussions/20789)
* IM33 — [immich#29563 A re-downloaded photo lands in a new folder (1)](https://github.com/immich-app/immich/discussions/29563)
* EN1 — [Ente: Backup and sync FAQ](https://ente.com/help/photos/faq/backup-and-sync)
* EN2 — [Ente: Storage optimisation](https://ente.com/help/photos/features/albums-and-organization/storage-optimization)
* EN3 — [ente#3546 Deleting a local file should delete it from Ente (25)](https://github.com/ente/ente/discussions/3546)
* EN5 — [ente#905 Preview before freeing up space (4)](https://github.com/ente/ente/discussions/905)
* EN6 — [ente#7751 Deleted photos reappear (5)](https://github.com/ente/ente/issues/7751)
* EN7 — [ente#3242 Resync again after deletion](https://github.com/ente/ente/discussions/3242)
* EN10 — [ente#12065 Distinguish local, cloud-only and unsynced (5)](https://github.com/ente/ente/discussions/12065)
* EN11 — [ente#885 Download photos for offline use (69)](https://github.com/ente/ente/discussions/885)
* EN12 — [ente#947 Three dialogs for an on-device delete (7)](https://github.com/ente/ente/discussions/947)
* EN13 — [ente#8357 A cloud delete hides the item from On Device for 15–30 min](https://github.com/ente/ente/issues/8357)
* EN14 — [ente#10055 Large iCloud backups leave temporary files](https://github.com/ente/ente/issues/10055)
* EN15 — [ente#4792 Make Free up space configurable (6)](https://github.com/ente/ente/discussions/4792)
* EN16 — [ente#3169 Edited Takeout photos cause duplicates (4)](https://github.com/ente/ente/issues/3169)
* MY1 — [Mylio: External Changes Policy](https://manual.mylio.com/24.3/en/topic/understanding-safe-delete)
* MY2 — [Mylio: Free up space on the camera roll](https://manual.mylio.com/24.3/en/topic/free-up-space-on-camera-roll-or-media-library)
* MY3 — [Mylio: Download original or optimised images](https://manual.mylio.com/24.3/en/topic/download-original-or-optimized-images)
* MY4 — [Mylio: Device sync policy presets](https://manual.mylio.com/24.3/en/topic/set-a-device-sync-policy-preset)
* SY1 — Design research: Synology Photos Play reviews
* SY2 — [SpaceRex forum: "No backed-up items to clear" after a server move](https://forums.spacerex.co/t/photos-mobile-free-up-space-no-backed-up-items-to-clear/3053)
* SY3 — Design research: Synology Photos
* PP1 — [PhotoPrism: Sync mobile devices with PhotoSync](https://docs.photoprism.app/user-guide/sync/mobile-devices/)
* PP2 — [photoprism#250 An archived photo uploaded again stays hidden](https://github.com/photoprism/photoprism/issues/250)
* PP3 — [photoprism#1028 Stacks: prefer edited photos as primary (29)](https://github.com/photoprism/photoprism/issues/1028)
* PP4 — [photoprism#1182 Stack compressed and original versions (8)](https://github.com/photoprism/photoprism/issues/1182)
* PP5 — [photoprism#1739 Google Camera motion photos (40)](https://github.com/photoprism/photoprism/issues/1739)
* PP7 — [photoprism#3034 RAW stacks (4)](https://github.com/photoprism/photoprism/issues/3034)
* NC1 — [nextcloud/android#2323 Delay before deleting after auto upload (59)](https://github.com/nextcloud/android/issues/2323)
* NC2 — [nextcloud/android#10645 Externally deleted files uploaded again (24)](https://github.com/nextcloud/android/issues/10645)
* NC4 — [nextcloud/android#19 Allow two-way sync (841)](https://github.com/nextcloud/android/issues/19)
* NC7 — [memories#854 Android app offline mode (45)](https://github.com/pulsejet/memories/issues/854)
* NC8 — [memories#1585 Choose which copy to delete](https://github.com/pulsejet/memories/issues/1585)
* NC9 — [memories#1445 Filter local photos not on Nextcloud](https://github.com/pulsejet/memories/issues/1445)
* NC11 — [nextcloud/photos#344 iOS Live Photos support (22)](https://github.com/nextcloud/photos/issues/344)
* AM1 — Design research: Amazon Photos
* OD1 — [Microsoft: OneDrive Files On-Demand](https://support.microsoft.com/en-us/office/save-disk-space-with-onedrive-files-on-demand-for-windows-0e6860d3-d9f3-4971-b321-7092438fb38e)
* IC3 — [icloud_photos_downloader#515 Live Photo MOV halves left behind](https://github.com/icloud-photos-downloader/icloud_photos_downloader/issues/515)

## Decision

We will show one tile per logical asset, treat the verified server copy as the source of truth and every device copy
as a cache under that device's storage policy, follow the user's deletion intent without ever resurrecting, remove
nothing from a device whose backup is not verified, and state every space claim exactly. The scenario tables below
decide each case; the numbered proposals at the end group them for the owner.

### Invariants

[ADR-0202](0202-albums-across-custody.md) holds albums to the same invariants and adds its own for membership;
[ADR-0201](0201-sources.md) extends them to every source kind.

* **I1 — One logical asset is one tile.** Copies with the same bytes are one asset (BLAKE3, keyed in private
  libraries); copies with different bytes that strong evidence ties together are stacked under one tile, never merged.
* **I2 — The server copy is the source of truth once verified.** Verified means hashed, fsynced and committed by the
  server (05 §1.4, ADR-0061) in a library Photolib holds; from then on a device copy is a cache of the same bytes, and
  edits and versions live on the server.
* **I3 — Deletion follows intent and never resurrects.** Only a deletion the user made (in Photolib, or in another
  app under the device's deletion policy) removes an asset; a deleted asset's hash in the registry is never uploaded
  again without the user's re-add; a missing volume, a failed mount or a reinstall is no deletion.
* **I4 — Nothing leaves a device unless its backup is verified.** Photolib removes a device original only after
  re-checking, at that moment and under the current server epoch, that every file of the asset is verified, and only
  through the OS trash.
* **I5 — Every space claim is exact.** A number of bytes shown is the sum of the files that action removes or adds on
  that device, it says when the space returns (an OS trash), and it never counts bytes that are not there.

### How the catalogue was generated

We named the dimensions of the body below, each value a code, and walked copies × actions first (8 × 13 = 104
pairs). A pair was kept when a real user can meet it; a pair that cannot happen was dropped with its reason (pruned
below). Each kept pair was then crossed with the failure moments where a step can be interrupted, the returns, the
device and account counts, custody and the OS behaviours that change its outcome; a combination with the same
outcome as a kept row was merged into it, so a row's Dims cell lists every value it stands for. Clients are not
multiplied into rows: every row says what each client shows (Android, iOS, desktop, web). Each row was then asked
for its worst outcome (a lost photo, a duplicate, a wrong space claim, a resurrected deletion, a silent change) and
checked against the invariants it lists.

Pruned: a cloud-only item deleted or edited in another app (`c5` × `a5`, `a8`: no device file); freeing a device-only
or uploading item (`c1`, `c2` × `a7`: nothing verified, shown only as "kept" in F4); a private copy in an external
library (`p2` × `c6`: external libraries are always standard, 07 §1); OS behaviours in a browser (`k4` × `o1`–`o7`:
the web has no device gallery); an iCloud placeholder edited by another app (`c7` × `a8`: Photos downloads it first,
which makes it `c4`).

| Dimension | Values |
|---|---|
| Copies and verification | `c1` device only · `c2` uploading · `c3` uploaded, verifying · `c4` on the device and verified on the server · `c5` server only (cloud only) · `c6` device and a read-only external library only · `c7` iCloud placeholder on the device · `c8` a multi-file asset with parts in different places |
| User action | `a1` view · `a2` edit in Photolib · `a3` share, export, download or drag out · `a4` delete in Photolib · `a5` delete in another app or the OS gallery · `a6` delete on another client · `a7` free up space · `a8` edit in another app · `a9` re-scan, reinstall or new phone · `a10` restore from a trash · `a11` keep on the device or restore to the gallery · `a12` move, rename or copy on the device · `a13` choose what is backed up |
| Surface and client | `k1` Android · `k2` iOS · `k3` desktop · `k4` web |
| What failed, and when | `f1` mid-upload · `f2` mid-verify · `f3` mid-free-up · `f4` mid-edit · `f5` offline or server unreachable · `f6` server restored from an older backup (epoch change) · `f7` library offline or in error · `f8` device storage or quota full · `f9` permission revoked or limited |
| What came back, and how | `r1` the same bytes again · `r2` different bytes (edited, re-encoded, transcoded) · `r3` the same bytes at another path or volume · `r4` the server copy restored from its trash |
| Devices and accounts | `d1` one device · `d2` two devices of one account · `d3` two accounts (partner, family, shared album) · `d4` a new or reinstalled device |
| Custody | `p1` standard library · `p2` private library |
| The OS's own behaviour | `o1` Android's MediaStore trash · `o2` iCloud Photos on · `o3` iCloud optimised storage · `o4` folders other apps own (WhatsApp, Telegram, screenshots) · `o5` a removable volume (SD card, USB drive) · `o6` an OEM or Google cloud gallery acting on its own · `o7` iOS limited photo access |

### B — Backup states and badges

| ID | Dims | Story | Worst | Clients show | App and server do | Never | Alternatives | Inv |
|---|---|---|---|---|---|---|---|---|
| B1 | c1 a1 d1 p1 p2 | "I just took a photo: is it safe yet?" | The user believes an unsent photo is backed up | All: a crossed-cloud badge "Not backed up" (on by default, VIEW-05 lets it be hidden); phones: the backup screen counts it under "Not protected yet" | Indexed, queued when its folder is selected; the server knows nothing | Show "backed up" before the server verified it | No badge until uploaded (Apple); a tick on every backed-up tile (Immich: clutter) | I2 I4 |
| B2 | c1 a13 p1 | "I left WhatsApp and Downloads out of the backup" | The user thinks excluded photos are protected | All: the same "Not backed up · excluded" badge; the filter "Not backed up" lists them | Not uploaded; counted under "not protected" with the reason "excluded folder" | Hide excluded items from the timeline or the count | Hide them (Immich shows only selected albums) | I4 I5 |
| B3 | c2 f1 p1 p2 | "The 4 GB video was at 60 % when I closed the app" | A half upload counted, or restarted from zero forever | Phones and desktop: a progress ring on the tile and the backup screen; web: the upload panel | The upload resumes at the server's offset (ADR-0061); nothing counts until verified | Mark it backed up when the transfer ends | Restart from zero | I2 I4 |
| B4 | c3 f2 p1 p2 | "The upload finished, then the server crashed before saving it" | The device frees a photo the server never stored | All: "Verifying" until the server's acknowledgement | The server hashes, fsyncs and commits, then answers the asset id; only that answer makes it backed up | Treat the end of the transfer as verification | Trust the transfer | I2 I4 |
| B5 | c4 a1 d1 p1 | "My photo is backed up" | Reassurance lost in badges, or two tiles | All: no badge (the normal state); the info panel says "On this phone · on 'home server', verified 12 May"; a "Backed up" filter | The device item links to the asset (`local_asset.asset_id`) | Show two tiles | A badge on every tile | I1 I2 |
| B6 | c1 f8 p1 | "My quota is full" | Backup silently stops | All: "Not backed up · quota full" and a banner saying what to do | The server refuses with a reason; the queue waits for the quota | Drop the queue or retry blindly | Silent retries (the opaque stuck backup) | I4 I5 |
| B7 | c1 f5 p1 p2 | "I'm on a plane" | The queue is lost, or the user thinks backup broke | All: "Waiting for the server · last contact 2 h ago"; constraints (Wi-Fi only, battery) shown as reasons | The queue persists and resumes | Mark items failed for being offline | An "Error" state | I4 |
| B8 | c1 a13 f9 k2 o7 p1 | "I gave Photolib access to selected photos only" | Full protection claimed under iOS limited access | iOS: "Photolib sees 120 of your photos" with the picker; others: unchanged | Backs up what it sees; the count says the rest is not visible | Claim the library is protected | Ignore limited access | I4 I5 |
| B9 | c1 f9 k1 p1 | "I revoked the media permission" | Backup stops without a word | Android: banner "Backup paused: Photolib can't read your photos" with the fix; others: unchanged | Backup paused with its reason | Fail silently | — | I4 |
| B10 | c2 a1 p2 | "My private library is still uploading" | Plaintext reaches the server, or a pending item looks backed up | All: lock-and-clock badge "Private · pending" | The client encrypts, uploads ciphertext; the server verifies its hash and size, the client the envelope header | Upload plaintext into a private library | — | I2 I4 |
| B11 | c4 a13 p1 | "I took a folder out of the backup after it was backed up" | Server copies deleted on deselect | All: its items keep "backed up"; new items there show "Not backed up · excluded" | Deselecting stops future uploads only | Delete server copies when a folder is deselected | Delete on deselect | I3 |
| B12 | c1 c2 c3 c4 a1 p1 | "What isn't protected?" | An opaque "stuck backup" | Phones and desktop: the backup screen lists counts per state with reasons and retry times (ING-14); web: the same for the account's devices | States from `backup_state` and the server's answers | Show a total without its reasons | A single progress bar | I4 I5 |
| B13 | c4 k3 p1 | "My watched Pictures folder is backed up" | Desktop folders behave unlike phones | Desktop: the same badges and dialogs on folder items; web: browser folders the same (ADR-0082); phones: unchanged | Same state machine over folder items | Two vocabularies | Desktop-only wording | I1 I2 |

### T — One tile: identity and duplicates

| ID | Dims | Story | Worst | Clients show | App and server do | Never | Alternatives | Inv |
|---|---|---|---|---|---|---|---|---|
| T1 | c4 a9 r1 d1 p1 | "Android re-indexed my photos" | A second tile, a second upload | All: one tile | The device item re-links by install id, then by hash (ADR-0045) | A second tile or upload for the same bytes | — | I1 |
| T2 | c4 a12 r3 o5 k1 p1 | "I moved my photos to the SD card" | Re-upload and two tiles, or the backup state lost | Android: one tile, new path in the info panel; others: unchanged | Same hash, same asset; the device row updates | Treat a move as a delete and a new photo | Delete and re-add | I1 I3 |
| T3 | c4 d2 p1 | "The same photo is on my phone and my tablet" | Two tiles, quota counted twice | All: one tile; the info panel lists the devices holding it (10 §11, 1.x) | Both devices link to one asset (ADR-0092); stored once | Store an owner's bytes twice | — | I1 |
| T4 | c4 c1 r2 o4 p1 | "WhatsApp re-encoded the photo I sent and saved a copy" | Two tiles of one photo, or an automatic merge that keeps the worse copy | All: one tile with a stack badge "2" when the evidence is strong (capture time to the second, camera, perceptual hash); otherwise a suggestion in duplicate review | A stack of kind `duplicate`, cover the larger original; both files kept and backed up | Merge or delete different bytes on its own | Merge (loses a copy); two tiles (Immich) | I1 I3 |
| T5 | c4 r2 k2 p1 | "My phone has the HEIC; the server already had a JPEG of it from my old export" | Two tiles; the JPEG replacing the original | All: one tile, a `duplicate` stack with the HEIC as cover | Same evidence as T4; both kept | Transcode or replace an original | Keep only one | I1 I2 |
| T6 | c4 a3 p1 | "Does the server keep my HEIC?" | A lossy transcode replaces the original | All: the info panel shows the original format; the web shows a rendition | Originals stored byte for byte; renditions derived (ADR-0084) | Replace an original by a transcode ("Storage saver") | Storage saver (Google) | I2 |
| T7 | c8 f1 k2 p1 | "Only the still of my Live Photo made it" | Half an asset, or the video as its own tile | All: one tile with the Live badge; "Live · motion not backed up" until it is | `CommitAsset` commits every part at once (M2-21); a part alone is not the asset | Show the video part as a tile | Upload parts separately | I1 I4 |
| T8 | c8 a5 o1 k1 p1 | "I deleted the JPEG of a RAW+JPEG pair in another app" | The pair splits into two tiles | All: one tile; info "JPEG: server only · RAW: this phone and server" | The asset keeps both files; the device part is marked gone | Split a pair | — | I1 I3 |
| T9 | c1 c4 a12 o4 p1 | "The same image sits in two folders on my phone" | Two tiles, two uploads, or the tile vanishing when one copy goes | All: one tile, both paths in the info panel; it stays while either copy does | Both device items link to one asset | Upload twice | Two tiles | I1 |
| T10 | c4 a9 d4 o2 k2 p1 | "My new iPhone restored from iCloud: every photo has a new identifier" | The whole library re-uploaded | iOS: one tile each, briefly "Checking"; others: unchanged | Match by cloud identifier, then by hash (10 §6.2) | Re-upload what the server holds | Re-upload and deduplicate on the server | I1 |
| T11 | c6 a1 p1 | "My NAS library already has this photo; my phone backs it up" | Stored twice, or the phone freed relying on a copy Photolib does not hold | All: one tile; info "Also in NAS 'Archive' (read-only, not a backup)"; state "Linked to NAS copy" | Linked by hash (ADR-0092); free up space does not count it (F14) | Count a read-only copy as a backup by default | Count it | I1 I4 |
| T12 | c4 r2 o6 k1 p1 | "A cloud app restored my photos to the phone smaller" | Duplicates of lower quality | Android: one tile, stacked as in T4; others: unchanged | Evidence stack; the better original is the cover | Upload the smaller copy as a separate tile | Two tiles | I1 |
| T13 | c4 c1 p1 p2 | "The same photo is in my private and my standard library" | Two tiles, and a plaintext copy undermining privacy | All: one tile with both library badges; info "Also in 'Family' (standard): remove that copy?"; two tiles until a device holding the key has seen both, the Info tab saying why | A client holding the key joins them by plain hash and syncs the link up as the user's claim; the server cannot, as private hashes are keyed (06 §9) | Join by hash on the server across custody | Two tiles | I1 |
| T14 | c4 d3 p1 | "My partner shares the photo I also have" | Two tiles in my timeline | All: my copy's tile; the partner's copy behind it in a stack | The client hides a partner's copy with the same hash behind the owner's | Two tiles | — | I1 |
| T15 | c4 a12 k3 p1 | "I renamed the file in Explorer" | Re-upload and a new tile | Desktop: one tile, new name; others: unchanged | Identity by file id, then hash (ADR-0042) | Re-upload | — | I1 |
| T16 | c4 a1 p1 | "A burst of 30 shots" | 30 tiles, or 29 lost when freeing | All: one tile with a stack badge (04 §4.4) | Each member backed up and verified on its own | Free a member that is not verified | — | I1 I4 |

### V — Which copy opens, edits and leaves

| ID | Dims | Story | Worst | Clients show | App and server do | Never | Alternatives | Inv |
|---|---|---|---|---|---|---|---|---|
| V1 | c4 a1 k1 k2 k3 p1 | "I open a backed-up photo" | A slow open from the network, or a stale copy | Phones and desktop: the local bytes at once (same hash); web: the server's preview, the original on zoom | The local file is read while its link holds (hash, or id with size and time unchanged) | Wait for the network when a local copy exists | Always the server (fresh but slow) | I1 I2 |
| V2 | c5 a1 p1 | "I open a photo I freed" | A blank or spinning tile | All: thumbnail, then preview, then the original on zoom with progress; offline: the best cached rendition and "Full quality needs the server" | Ranged download; cached under the storage policy | Show an empty tile | — | I2 |
| V3 | c4 a1 r2 d2 p1 | "I edited it on my laptop; my phone shows the old one" | A stale version shown as current | All: the current version: the server's render, or the kernel's render of the recipe over the local original | Version recipes sync; the device original stays the base | Show the unedited device file as current | Show the device file | I2 |
| V4 | c4 a2 k1 k2 p1 | "I edit it in Photolib on the phone" | The camera file overwritten | Phones: the editor opens the local original; desktop and web: the server original | The edit is a version (04 §4.3); iOS also saves a Photos adjustment (M8-11); Android's file is not rewritten | Rewrite the original | Rewrite the file (Samsung) | I2 |
| V5 | c5 a2 f5 p1 | "I edit a freed photo offline" | The edit lost, or the editor refusing | All: the editor works on the cached preview and says "Full quality when online"; export waits | The recipe goes to the outbox; renders once online | Lose the recipe | Refuse to edit | I2 |
| V6 | c4 a3 p1 | "I share it to a messenger" | The unedited file, or the location, leaks | Phones: the share sheet sends the current version rendered from the local original, location stripped by default; desktop: drag out the file (ADR-0144); web: download | Export from the local original when present, else the server's | Send the unedited file when an edit is current, unless "Original" is chosen | Share the device file as is | I2 |
| V7 | c5 a3 f5 k1 k2 p1 | "I share a freed photo with no signal" | A thumbnail sent as if it were the photo | Phones: "Full quality needs the server: share the preview, or wait"; desktop and web: the same | — | Send a downscaled copy without saying so | Send the preview silently | I2 I5 |
| V8 | c7 a1 k2 o3 p1 | "I open an iCloud-optimised photo that is backed up" | A long iCloud download | iOS: the Photolib original when backed up, else iCloud with progress; others: the server | The faster source is picked; `isNetworkAccessAllowed` only for explicit work (10 §6.2) | Download from iCloud when Photolib holds it | Always iCloud | I2 |
| V9 | c4 a1 k4 p2 | "I open my private library in the browser" | The server asked to decrypt | Web: decrypted in the browser (ADR-0059); phones and desktop: decrypted on the device | Ciphertext only on the server | Send keys to the server | — | I2 |
| V10 | c3 a1 p1 | "I open a photo that is still verifying" | It opens slowly or not at all | All: the local copy; the badge says "Verifying" | — | Hide it until verified | — | I1 |
| V11 | c5 a3 k3 p1 | "I drag a cloud-only cell out to Finder" | An empty or broken file dropped | Desktop: the drag starts once the original is downloaded, with progress (ADR-0144); others: download | Download, then drag | Drag a placeholder | Drag a preview | I2 |
| V12 | c5 a3 k4 p2 | "I download a private photo from the web" | A file with the location the user stripped elsewhere | Web: "Original" or "Current version", location stripped by default; others: the same choice | Decrypted and rewritten client-side (12 §6) | Download the ciphertext as the photo | — | I2 |
| V13 | c4 a2 f4 a6 d2 p1 | "I was editing when someone deleted the photo on the web" | The edit silently dropped | All: "Deleted in your library: save your edit as a copy?" | The tombstone arrives; the edit is offered as "save as copy" (05 §8) | Drop the edit | Restore the asset | I2 I3 |

### O — Deletes on the device, outside Photolib

The device's deletion policy (05 §6.1) is *backup-only* by default; *ask* and *mirror* are per-device settings.

| ID | Dims | Story | Worst | Clients show | App and server do | Never | Alternatives | Inv |
|---|---|---|---|---|---|---|---|---|
| O1 | c4 a5 o1 k1 p1 | "I deleted it in Samsung Gallery" | The backup deleted too, or the photo resurrected | Android: the tile stays, badge "Cloud only"; others: unchanged | MediaStore reports it trashed; the device link is cleared; the server copy untouched | Delete the server copy on a device deletion by default; upload it again | Mirror (Google Photos' own app); ask | I2 I3 |
| O2 | c4 a5 a10 r1 o1 k1 p1 | "I restored it from Samsung's trash" | A second tile or upload | Android: the tile is back to normal; others: unchanged | Same bytes, re-linked | Upload it again | — | I1 I3 |
| O3 | c1 a5 o1 k1 p1 | "I deleted a photo before it was backed up" | Lost without a word | Android: the tile shows in Photolib's trash view "In the phone's trash · 29 days left"; others: nothing | Nothing uploaded from the OS trash | Back up an item from the OS trash | Upload trashed items | I3 I4 |
| O4 | c4 a5 o2 k2 p1 | "I deleted it in Apple Photos with iCloud Photos on" | The deletion propagates and the backup goes too | iOS: "Cloud only", info "Deleted from Photos on 3 June"; others: unchanged | Backup-only: the server keeps it; the registry is untouched | Treat Apple's deletion as a Photolib deletion by default | Mirror | I2 I3 |
| O5 | c4 a5 o2 d2 k2 p1 | "I deleted it on my Mac's Photos; my iPhone follows" | The same as O4, twice | iOS and the Mac: "Cloud only"; others: unchanged | Each device clears its link | Count two deletions as intent | — | I3 |
| O6 | c4 a5 o1 k1 k2 p1 | "My policy is *ask*" | A wrong guess either way | Phones: a daily digest "You deleted 12 photos in other apps: delete them from your library too?" with the items; others: nothing | Nothing changes until answered | Decide for the user | Mirror; ignore | I3 |
| O7 | c4 a5 o1 k1 p1 | "My policy is *mirror*" | A slip in another app deletes the backup forever | Android: a toast "Moved to your library's trash too"; others: the item in the trash | The server copy goes to the trash within one sync, restorable for its retention | Purge it without the trash | — | I3 |
| O8 | c2 a5 f1 k1 p1 | "I deleted it while it was uploading" | A deleted photo lands on the server | Android: the progress stops; nothing in the library; others: nothing | The upload is cancelled and its staging discarded; a committed one follows O1 | Finish an upload of a deleted item | Finish and keep | I3 |
| O9 | c4 a5 o4 k1 p1 | "WhatsApp cleared its media" | Thousands of cloud-only tiles, or the backup purged | Android: "Cloud only" tiles; the backup screen: "WhatsApp removed 2,300 items from this phone; they stay in your library"; others: unchanged | Backup-only, as O1 | Purge app folders' backups on their own | Mirror app folders | I3 |
| O10 | c4 a5 o5 k1 p1 | "I took the SD card out" | Mass "cloud only", or a mirror policy deleting backups | Android: "On SD card (not inserted)"; others: unchanged | An unmounted volume is no deletion (MediaStore volume state) | Mirror a deletion caused by a missing volume | Treat as deleted | I3 |
| O11 | c4 a5 o6 k1 p1 | "Google Photos' own Free up space removed 2,300 photos" | A mirror policy empties the library | Android: "Cloud only" tiles and a banner; under *mirror*, "Another app removed 2,300 photos: delete them from your library too?"; others: unchanged | The mass guard of 07 §4 (over 1,000 or 5 %) pauses mirroring and asks | Mirror a mass deletion unasked | — | I3 I5 |
| O12 | c4 a5 k3 p1 | "I deleted the file in Finder" | The backup deleted | Desktop: "Cloud only"; others: unchanged | Backup-only, as O1 | Delete the server copy by default | Mirror | I3 |
| O13 | c4 a5 o5 k3 p1 | "I unplugged the drive" | Items marked deleted | Desktop: "Offline · drive not connected" (ADR-0042); others: unchanged | No asset change | Treat it as deletion | — | I3 |
| O14 | c8 a5 o2 k2 p1 | "I deleted a Live Photo in Photos" | Its parts split | iOS: one "Cloud only" tile with the Live badge; others: unchanged | Both parts cleared together | Split it | — | I1 I3 |
| O15 | c4 a5 a9 d4 p1 | "I factory-reset the phone" | Read as a mass deletion | All: "Cloud only" for that device's items; the old device listed as gone | A reset device leaves; its links are dropped, never as deletions | Mirror a reset | — | I3 |

### X — Deletes inside Photolib

| ID | Dims | Story | Worst | Clients show | App and server do | Never | Alternatives | Inv |
|---|---|---|---|---|---|---|---|---|
| X1 | c4 a4 k1 k2 p1 | "I delete a backed-up photo on the phone" | Ambiguity: the user meant this phone only, or everywhere | Phones: "Move to trash" (default: this phone and your library) or "Remove from this phone" (the library keeps it), each with counts and sizes; desktop and web: "Move to trash" | Server trash; the device copy to the OS trash; others follow E1 | Hard-delete; use another vocabulary per client | One "delete" that deletes everywhere (Google); three buttons with unclear scope (Immich) | I3 I4 I5 |
| X2 | c1 a4 p1 | "I delete a photo that was never backed up" | The user thinks a backup exists | All: "Move to trash · only on this device, not backed up" | OS trash | Imply a backup | — | I3 |
| X3 | c5 a4 p1 | "I delete a cloud-only photo" | The device asks for a gallery dialog it does not need | All: "Move to trash" (library) | Server trash | Touch device files | — | I3 |
| X4 | c1 c4 c5 a4 p1 | "I delete a mixed selection of 20" | A dialog that hides what goes where | All: "12 on this phone and backed up, 3 only on this phone, 5 only in your library" with sizes | One `DeletionService` call per platform batch (10 §5.4) | Summarise as "20 items" | — | I3 I5 |
| X5 | c4 a4 o2 k2 p1 | "I delete in Photolib on an iPhone with iCloud Photos" | The user does not expect iCloud to follow | iOS: the dialog states it also leaves iCloud and other Apple devices; others: unchanged | One `PHAssetChangeRequest` batch | Hide iCloud's propagation | — | I3 |
| X6 | c4 a4 o1 k1 p1 | "I delete 600 photos on Android" | 600 system dialogs, or a hard delete | Android: at most two system dialogs (500 a batch; none as default gallery with media management); others: unchanged | MediaStore trash requests | Hard-delete | `ContentResolver.delete` | I3 |
| X7 | c4 a10 r4 o1 p1 | "I restore it from Photolib's trash" | Restored in the library but not on the phone | All: restored; Android: the device copy restored from the OS trash when still there; iOS: "Restore it in Photos › Recently Deleted too" | Server untrash; device restore where the OS allows | Leave the device copy in the trash silently | — | I3 |
| X8 | c5 a4 a10 p1 | "I delete forever from the trash" | It returns from a phone's next backup | All: "Deleted forever"; it never comes back unasked | The hash enters the registry (05 §6.1) | Upload a registry hash | — | I3 |
| X9 | c4 a4 f5 p1 | "I delete with no signal" | The deletion lost, or an edit elsewhere wins | All: gone at once (optimistic) with "Waiting to sync" | Outbox; delete-to-trash wins over edits (05 §5) | Lose the deletion | — | I3 |
| X10 | c2 a4 f1 p1 | "I delete a photo that is uploading" | A deleted photo lands on the server | All: removed; the upload stops | Cancel and discard the staging | Finish the upload | — | I3 |
| X11 | c4 a4 p2 | "I delete in my private library" | A plaintext trace remains | All: as X1 | Trash flag and keyed hash in the registry (06 §9) | Keep a plain hash for a private item | — | I3 |
| X12 | c4 a4 k3 p1 | "I delete a backed-up file of a watched folder on my desktop" | The user's archive emptied by surprise | Desktop: "Move to trash" (recycle bin and library) or "Remove from this computer"; others: E1 | The OS trash, never unlink | Unlink files | — | I3 I4 |
| X13 | c4 a4 k4 p1 | "I delete from the web" | Devices keep resurrecting it | Web: "Move to trash" (library); devices: E1; phones and desktop: E1 for their copies | Server trash; devices learn by sync | Leave device copies uploadable | — | I3 |
| X14 | c4 a4 d3 p1 | "I delete a photo my sister added to our shared album" | Her photo deleted | All: "Remove from album" only (12 §2) | Membership removed; the asset stays hers | Delete another owner's asset | — | I3 |
| X15 | c6 a4 p1 | "I delete a photo whose only server copy is in my read-only NAS library" | The NAS written, or nothing happens | All: "The NAS folder is read-only: hide from your library, or remove from this phone" | No write to a read-only library (07 §5) | Write a read-only library | — | I3 |
| X16 | c1 a4 a12 r1 p1 | "I deleted it, then copied the same file back from my PC" | It resurrects silently, or vanishes silently | All: it shows under "Deleted earlier" with one tap to add it back | The registry matches the hash (05 §6.1) | Upload a registry hash unasked | — | I3 |
| X17 | c4 a4 a10 o1 k1 p1 | "I deleted it in Photolib, then restored it from Android's trash" | Restored on the phone, still deleted in the library | Android: restored, toast "Restored in your library too"; others: back | Restoring from the OS trash is an undo: the server untrashes it | Treat the restored file as new | Ask | I3 |

### E — Deleted elsewhere while this device still has the file

Each device also has a *library deletions* setting: *ask* (default), *always* (the device copy goes to the OS trash)
or *never* (the device copy stays as a device-only item).

| ID | Dims | Story | Worst | Clients show | App and server do | Never | Alternatives | Inv |
|---|---|---|---|---|---|---|---|---|
| E1 | c4 a6 d2 k1 k2 p1 | "I deleted it on the web; my phone still has the file" | It resurrects from the phone, or the phone deletes the file unasked | Phones: the tile leaves the timeline; a card "3 photos you deleted elsewhere are still on this phone: Move them to the phone's trash · Keep on this phone only"; desktop: the same card for folder files; web: in the trash | The registry and the trash flag block re-upload; the device link records "asset trashed" | Re-upload; delete a device file without its policy or a confirmation | Always delete the device copy (Google Photos); never touch it and let it re-upload (Immich) | I3 |
| E2 | c4 a6 o1 k1 p1 | "My phone is set to *always* follow library deletions" | A mistaken web deletion empties the camera roll | Android: no prompt (default gallery with media management) or one system dialog; the trash view shows them; others: unchanged | MediaStore trash, restorable 30 days | Hard-delete | — | I3 |
| E3 | c4 a6 o2 k2 p1 | "*Always* on an iPhone" | iOS forbids silent deletes; the user sees an unexplained system prompt | iOS: one batched system confirmation when the app opens, introduced by Photolib's own sentence; others: unchanged | One `PHAssetChangeRequest` | Ask per item | — | I3 |
| E4 | c4 a10 r4 d2 p1 | "I restored it on the web" | The library restored, the phone copy already trashed | All: back; Android: restored from the OS trash if still there; iOS: "Restore it in Photos › Recently Deleted"; desktop: from the recycle bin when the OS allows | Untrash; the device restores where it can | Leave the device copy trashed silently | — | I3 |
| E5 | c4 a6 d2 p1 | "I chose *Keep on this phone only*" | It re-uploads at the next backup | Phones: the tile returns as "Not backed up · deleted from your library", with "Back up again"; desktop: the same for folder files; web: device-only items are not listed | The registry entry stands; the device item is device-only | Upload it without "Back up again" | — | I3 I4 |
| E6 | c4 a6 f5 d2 p1 | "My phone was offline for 3 months while I emptied the trash" | Resurrection after the reset | Phones: the E1 card after the sync; others: nothing | `RESET_REQUIRED`, snapshot; the registry still blocks | Upload a registry hash | — | I3 |
| E7 | c4 a6 d2 a5 p1 | "My tablet has *mirror* on and deleted it" | Read as a web deletion and asked again | All: as E1 on the other devices | One intent, one registry entry | Ask twice for one intent | — | I3 |
| E8 | c4 a6 d3 p1 | "The admin removed my account's library" | Device files deleted, or re-uploaded into nothing | All: "Your library on 'home server' was removed: these photos are only on your devices"; device files untouched | Links dropped; no registry deletion intent | Delete device files for an admin action | — | I3 |
| E9 | c4 a6 a8 r2 d2 p1 | "I edited it in another app on my phone after deleting it on the web" | The new version uploaded into a trashed asset, or lost | Phones: "Deleted in your library; your newer edit is only on this phone: keep it on the phone · back it up as new"; desktop: the same for folder files; web: the asset in the trash | The version upload is refused (asset trashed) | Resurrect the asset | Restore with the edit | I3 I4 |
| E10 | c5 a6 d3 p1 | "My partner deleted a photo I had added to my library" | It vanishes from my albums without warning | All: "Ben deleted 4 photos you kept: keep a copy?" (12 §2) | A reference until copied | Remove it silently | — | I3 |
| E11 | c4 a6 p2 | "I deleted a private photo on another device" | A plain hash or name leaks in the registry | All: as E1 | Keyed hash in the registry | Store a plain hash | — | I3 |
| E12 | c1 a6 a9 d4 p1 | "I deleted a photo last year; a restored phone backup brings it back" | Resurrection from an old phone backup | All: "Deleted earlier: 230 items · add back" | Registry kept ≥ 1 year and exportable (05 §6.1) | Upload them | — | I3 |

### F — Free up space

| ID | Dims | Story | Worst | Clients show | App and server do | Never | Alternatives | Inv |
|---|---|---|---|---|---|---|---|---|
| F1 | c4 a7 o1 k1 p1 | "I free up space on Android" | Unverified photos deleted, or a hard delete | Android: "2,314 photos and videos · 18.4 GB, verified on 'home server'. They go to the phone's trash; the space returns when it empties (30 days) · Empty now"; others: n/a | Each candidate re-checked with `CheckHashes` under the current epoch just before; MediaStore trash in batches; a "freed" journal | Delete an item not re-verified; hard-delete | Delete at once (no undo) | I4 I5 |
| F2 | c4 a7 o2 k2 p1 | "I free up space on an iPhone with iCloud Photos" | The user deletes from iCloud believing only the phone is freed | iOS: "With iCloud Photos on, this deletes them from iCloud and your other Apple devices. To keep iCloud, turn on Optimise iPhone Storage" · two buttons; others: n/a | One system confirmation; Recently Deleted | Imply iCloud is untouched | Hide the option | I4 I5 |
| F3 | c7 a7 o3 k2 p1 | "Most of my originals are already in iCloud" | A claim of space that will not be freed | iOS: "Frees 0.3 GB: 1,200 of these are already only in iCloud"; others: n/a | Only local resources' sizes count | Count bytes not on the device | Count asset sizes | I5 |
| F4 | c2 c3 c1 a7 p1 | "Some photos are still uploading" | They are freed | Phones: "4 not yet backed up are kept"; desktop staging folders the same (F16); web: n/a | Excluded until verified | Free them | — | I4 |
| F5 | c4 a7 o4 p1 | "WhatsApp's folder is backed up" | Another app's files deleted unexpectedly | Phones: app folders skipped by default, a switch per folder; others: n/a | Keep-rule | Delete app-owned folders by default | Treat them as camera photos | I4 |
| F6 | c4 a2 a7 p1 | "I edited it here and free space before the edit synced" | The base of an unsent edit removed | Phones: "2 with unsent changes are kept"; desktop staging folders the same (F16); web: n/a | Kept while the outbox holds anything for the asset | Free it | — | I4 |
| F7 | c8 a7 p1 | "A Live Photo whose motion is still uploading" | Half an asset freed | Phones: kept until every part is verified; desktop staging folders the same (F16); web: n/a | All parts or none | Free a part | — | I4 |
| F8 | c4 a7 a11 p1 | "Keep the last 30 days, favourites and my 'Kids' album on the phone" | Freeing what the user wants at hand | Phones: keep-rules shown with what each keeps and its size (ING-15); desktop staging folders the same (F16); web: n/a | Rules filter the candidates | Free a pinned item | — | I4 I5 |
| F9 | c4 a7 f8 p1 | "My phone is nearly full" | Nagging, or nothing | Phones: a suggestion card when free space is under 10 % or over 2 GB can be freed; dismissible for 30 days; desktop staging folders the same (F16); web: n/a | Suggestion only | Free space unasked | Automatic by default (Apple's optimisation) | I4 I5 |
| F10 | c4 a7 k1 k2 p1 | "Remove device copies 30 days after a verified backup" | A silent mass deletion | Android: runs by itself (default gallery with media management) else one dialog; iOS: a reminder, as iOS asks for every delete; desktop and web: n/a | Opt-in per device; the same checks as F1 at each run | Turn it on by default | On by default | I4 I5 |
| F11 | c4 a7 f3 p1 | "The phone died halfway through freeing space" | Half freed, the claim wrong | Phones: "Freed 1,200 of 2,314 · Continue"; the claim recomputed; desktop staging folders the same (F16); web: n/a | The journal resumes; each OS batch is atomic | Report the planned total as done | — | I4 I5 |
| F12 | c4 a7 f5 f7 p1 | "The server is unreachable or its library in error" | Freed against a server that may have lost them | Phones: "Can't confirm your backups now"; desktop staging folders the same (F16); web: n/a | Refused without a fresh verification | Free on cached state | — | I4 |
| F13 | c4 a7 f6 o1 p1 | "The server was restored from last week's backup after I freed space" | Photos lost | Phones: "52 freed photos are missing on the restored server: restore them from the phone's trash and back them up"; desktop staging folders the same (F16); web: n/a | On the epoch change the app re-verifies the freed journal; items still in the OS trash are restored and queued | Forget the freed journal before the OS trash expires | — | I4 |
| F14 | c6 a7 p1 | "These are only in my read-only NAS library" | Freed, then the NAS folder is deleted by another tool | Phones: "Kept: only in a NAS folder Photolib does not manage"; a per-library switch "Count as backup" (off); desktop staging folders the same (F16); web: n/a | Not candidates by default | Count read-only copies by default | Count them | I4 |
| F15 | c4 a7 p2 | "I free up space in my private library" | Freed, then the phone is lost with the only key | Phones: refused until recovery is set up (06 §6); then as F1; desktop staging folders the same (F16); web: n/a | Ciphertext and the envelope round-trip verified | Free private items without a recovery path | — | I4 |
| F16 | c4 a7 k3 p1 | "Can I free space on my desktop?" | The user's folder archive emptied | Desktop: only for a folder marked "staging area" (a camera import folder), else not offered; others: n/a | — | Free a desktop folder by default | Treat folders as a camera roll | I4 |
| F17 | c5 a7 k4 p1 | "Free up space in the browser" | Confusion with deleting | Web: "Clear offline copies (120 MB)", never photos; others: n/a | Clears the cache only | Offer deleting as freeing | — | I5 |
| F18 | c4 a7 p1 | "How much did I actually get back?" | A claim that does not match the storage settings | Phones: after the run "18.4 GB in the phone's trash"; after emptying, the measured change; desktop staging folders the same (F16); web: n/a | Sums `SIZE` / local resource sizes; measures free space before and after | Show estimated sizes | — | I5 |
| F19 | c4 a7 a10 r1 o1 k1 p1 | "I restored some freed photos from the trash" | They upload again | Android: back on the phone, linked; others: unchanged | Same bytes, re-linked | Upload | — | I1 I5 |
| F20 | c4 a7 d2 p1 | "My tablet has a copy too: does that count?" | The phone frees relying on the tablet | Phones: only the server's verified copy counts; info lists "Copies: server, tablet"; desktop staging folders the same (F16); web: n/a | — | Count a device as a backup | Count devices (Mylio) | I4 |
| F21 | c4 a7 o5 k1 p1 | "Half my photos are on the SD card" | The claim mixes volumes | Android: the claim per volume; others: n/a | Per-volume sums | One total | — | I5 |
| F22 | c4 a7 p1 | "What protects each photo?" | Trusting a number blindly | Phones: the detail list "On 'home server' · managed library 'Phone' · verified 12 May" grouped by protection; desktop staging folders the same (F16); web: n/a | — | Free without showing protection | — | I4 I5 |

### C — Changed bytes and edits

| ID | Dims | Story | Worst | Clients show | App and server do | Never | Alternatives | Inv |
|---|---|---|---|---|---|---|---|---|
| C1 | c4 a8 r2 o6 k1 p1 | "I edited it in Samsung Gallery and saved over it" | A second tile, or the earlier backup overwritten | All: one tile with the new version; versions panel "Edited in another app" | Same device item, new bytes: an `external_change` version of the same asset; the earlier version kept | Replace the server's earlier version; a second tile | A new asset (Immich) | I1 I2 |
| C2 | c1 a8 r2 k1 p1 | "Google Photos' editor saved a copy" | Two tiles of one photo | All: one tile, a stack "edited copy" when evidence is strong | A new device item, a new asset, stacked | Merge the bytes | Two tiles | I1 |
| C3 | c4 a8 k2 p1 | "I edited it in Apple Photos" | A new asset, or the edit lost | iOS: one tile, the new version; others: the new version after sync | Adjustments on the same `PHAsset`: an `external_change` version (05 §6) | A new asset | — | I1 I2 |
| C4 | c5 a2 d2 k3 p1 | "I freed space on the plane, then edited the photo on my laptop" | The phone shows the old one, or the edit cannot apply | Desktop and web: edit the server original; phones: the new version when online | Recipe on the server; no device file to update | Expect a device file | — | I2 |
| C5 | c4 a8 r2 k3 p1 | "Lightroom rewrote the file in my watched folder" | A new asset, or the backup overwritten | Desktop: one tile, new version; others: after sync | `external_change` version, uploaded | Overwrite the earlier version | — | I1 I2 |
| C6 | c4 a8 f4 r2 k1 p1 | "The other app crashed while saving: the file is truncated" | A broken file replaces a good backup | All: "Couldn't read the new file: your library keeps the previous version" | The kernel fails to read it; nothing uploaded | Upload a file the kernel cannot read as a new version | — | I2 I4 |
| C7 | c4 a8 r2 p1 | "Another app only rotated it or wrote a rating" | A full re-upload, or the change ignored | All: one tile, rotated | A version (new bytes) | A new asset | Ignore metadata changes | I1 I2 |
| C8 | c4 a8 r2 p2 | "I edited a private photo in another app" | Plaintext of the new version uploaded | All: as C1 | The client encrypts the new version | Plaintext upload | — | I2 |
| C9 | c4 a2 d2 p1 | "I edited on the phone and the tablet at once" | One edit lost | All: the later edit is current; the other is a version | Versions branch; per-field HLC (05 §5) | Drop an edit | — | I2 |
| C10 | c4 a8 r2 a7 p1 | "I edited it in another app, then freed space before the new version uploaded" | The new bytes freed before upload | Phones: "1 changed photo is kept until backed up"; desktop staging folders the same; web: n/a | A changed device file is unverified until its version is | Free unverified bytes | — | I4 |

### P — Storage policies: when remote copies come back

| ID | Dims | Story | Worst | Clients show | App and server do | Never | Alternatives | Inv |
|---|---|---|---|---|---|---|---|---|
| P1 | c5 a1 f5 p1 | "I'm offline and open a freed photo" | Nothing to see | All: the preview the policy kept (10 §11) | — | Show an empty tile | — | I2 |
| P2 | c5 a11 p1 | "Keep this one on the phone" | Evicted later; space unclear | All: "Keep on this device (24 MB)" and a pin badge | The original goes to the app's cache, sealed (21 §3); never evicted | Evict a pin | — | I5 |
| P3 | c5 a11 r1 k1 k2 p1 | "Put this photo back in my camera roll" | A second tile and a second upload | Phones: "Save to the phone's gallery"; desktop: "Save to a folder"; web: download | Written to MediaStore or Photos; links by hash; never uploaded | Upload or show two tiles | Pin only | I1 |
| P4 | c5 a9 d4 p1 | "I set up a new phone" | 400 GB pulled into the camera roll | Phones: nothing into the gallery; "Restore my photos to this phone" by selection with the exact size; desktop and web: unchanged | Policy decides the cache only | Fill the gallery unasked | Download all (iCloud) | I5 |
| P5 | c5 a1 f8 p1 | "The cache is full" | Pins or unsent items evicted | All: the cache shrinks, LRU; pins and outbox never | Budget per preset | Evict pins, outbox or unsent | — | I4 I5 |
| P6 | c5 a11 k3 p1 | "My desktop is a vault: keep every original" | It also re-uploads them | Desktop: preset "Full originals"; others: unchanged | Downloads to the cache, never into watched folders | Download into a watched folder | — | I1 |
| P7 | c5 a1 p2 | "Offline copies of my private library" | Decrypted files at rest | All: as P1 | Envelopes decrypted on read (21 §3) | Store decrypted copies | — | I2 |
| P8 | c5 a1 k4 p1 | "Offline in the browser" | Unbounded browser storage | Web: thumbnails and previews in OPFS under a budget; others: n/a | — | Exceed the budget | — | I5 |
| P9 | c5 a11 f5 p1 | "I pinned it with no signal" | The pin silently fails | All: "Will download when online" | Queued | Drop the pin | — | I5 |
| P10 | c5 a1 p1 | "What is this cache using?" | A wrong number | All: cache size per tier; "Clear" frees exactly that | — | Count originals the gallery holds | — | I5 |

### R — Failures and recovery

| ID | Dims | Story | Worst | Clients show | App and server do | Never | Alternatives | Inv |
|---|---|---|---|---|---|---|---|---|
| R1 | c4 f6 d2 p1 | "The server was restored from an older backup" | Missing photos stay missing; deleted ones come back | All: "Your server was restored: checking backups"; then "Backed up again: 120" | Epoch change: devices re-verify every backed-up item, re-upload what is missing, never registry items (05 §8) | Re-upload registry items | — | I2 I3 |
| R2 | c4 f7 p1 | "The server's copy failed a scrub" | The only good copy left on a phone gets freed | All: "Repaired from your phone" | The asset is `integrity_error`; any device holding the hash re-uploads it | Free a copy of an asset in error | — | I2 I4 |
| R3 | c1 f5 d1 p1 | "The server was down for a month" | Photos taken meanwhile lost or freed | All: "Waiting for the server · 1,200 not backed up" | Nothing freed; the queue persists | Free unverified items | — | I4 |
| R4 | c4 a9 d4 p1 | "I moved to a new server" | Device links point at the old one; mixed state | All: per account; the new server's states start at "Checking" | Links are per account and server | Assume the old server's verification | — | I2 |
| R5 | c4 a7 d3 p1 | "Two accounts on one phone" | Freed for account A while account B still needs it | Phones: "Kept: still waiting for backup to 'Work'"; desktop and web: per account as well | Free only when every account that selects it holds it verified | Free with one account's verification | — | I4 |
| R6 | c4 f8 k1 p1 | "The phone is so full the app cannot stage" | Backup fails silently | Phones: "Backup paused: free 200 MB"; others: unchanged | Uploads stream from the file without staging | Fail silently | — | I4 |
| R7 | c4 a9 r1 k1 p1 | "An OS update re-numbered every MediaStore id" | Every item re-uploaded | Android: unchanged tiles; others: unchanged | Install id and hash re-link (ADR-0045) | Re-upload | — | I1 |
| R8 | c4 a1 d2 p1 | "My phone's clock was wrong" | Two capture times for one photo | All: one tile; time from the bytes | Same bytes, same asset; capture time from the file (ADR-0051) | Use the device clock for capture time | — | I1 |

### D — Several devices and accounts

| ID | Dims | Story | Worst | Clients show | App and server do | Never | Alternatives | Inv |
|---|---|---|---|---|---|---|---|---|
| D1 | c4 a4 d2 k1 k2 p1 | "I trashed it on my phone; my tablet has it in its gallery" | It returns from the tablet | Tablet: the E1 card; others: in the trash | Registry blocks the tablet's upload | Re-upload | — | I3 |
| D2 | c4 a7 d2 p1 | "I freed space on the phone; the tablet still has its copy" | The tablet's copy assumed gone | All: "Copies: server, tablet" | Independent per device | Couple devices' frees | — | I4 |
| D3 | c4 d3 p1 | "My wife backed up the same photo to her library" | Each sees two tiles in a partner timeline | All: one tile per owner; the partner's copy behind mine | Per-user dedupe (ADR-0092); the client hides the partner's duplicate | Cross-user dedupe on the server | — | I1 |
| D4 | c1 a3 d3 p1 | "I added a device-only photo to a shared album" | Others see a hole | All: as decided in ADR-0202; the upload jumps the queue | Upload prioritised | Show a broken tile | — | I1 I4 |
| D5 | c4 o2 d2 k2 p1 | "My iPad and iPhone share iCloud Photos" | Each device uploads its copy | iOS: one tile; each device linked; others: unchanged | Cloud identifier links both | Store twice | — | I1 |
| D6 | c5 a9 d4 k4 p1 | "I signed in on a friend's laptop browser" | Originals left behind on their machine | Web: thumbnails only under a session budget, cleared on sign-out; others: unchanged | No offline originals in a browser by default | Keep originals after sign-out | — | I5 |

### The owner's lean, tested

The lean — once the server copy is verified it is preferred and the local copy goes, the device keeping what its
policy says — holds as the model: a device copy is a cache of verified bytes (V1, O1, O4), deleting it in another
app removes a cache, not the photo (O1–O15), and free up space removes it (F1). It bends in five places, each a
proposal below:

* **"Goes" is the user's call, not automatic.** Removing files from the camera roll by default would delete them for
  every other app on the phone, and iOS confirms every delete; free up space stays manual and suggested, with an
  opt-in automatic policy (F9, F10). Apple can optimise by default because its originals become placeholders in the
  same gallery; ours would vanish.
* **With iCloud Photos on, the local copy cannot go alone**: deleting it deletes it from iCloud; Optimise iPhone
  Storage is the better answer (F2, F3).
* **A read-only external copy is not a copy Photolib holds** (T11, F14).
* **A private library without a recovery path** would lose everything with the phone (F15).
* **The viewer prefers the local bytes** for speed (V1); they are the same bytes, so the truth is unchanged, and the
  current version always comes from the server's recipes (V3).

## Proposals for sign-off

1. **One vocabulary and two badges.** *Backed up* means verified; tiles show *Not backed up* (with its reason) and
   *Cloud only*, nothing for the normal state; a backup-state filter and a backup screen with counts, reasons and
   retry times on every client (rows B1–B13).
2. **One tile by content hash.** Device items link to assets by install id, cloud identifier, then hash; moves,
   renames, re-indexes and new phones never re-upload or add a tile (rows T1–T3, T9, T10, T15, R7).
3. **Near-duplicates are stacked, not merged.** Re-encoded, restored or edited copies tied by strong evidence (capture
   time, camera, perceptual hash) become a `duplicate` stack under one tile, the better original as cover; weaker
   evidence is a suggestion (rows T4, T5, T12, C2). No merge logic lands here: choosing the best of duplicates is
   M5-14's review, where photolib-design#571's finer model (the lesser copy a non-canonical content of one asset)
   belongs.
4. **Originals byte for byte**; no "storage saver" (row T6).
5. **Multi-file assets move together**: Live Photos, RAW+JPEG and bursts are committed, shown, deleted and freed whole
   (rows T7, T8, T16, O14, F7).
6. **A read-only external copy links but protects nothing by default**; a per-library "Count as backup" switch, off
   (rows T11, X15, F14).
7. **Same bytes across libraries and owners show once**: a private and a standard copy are one tile with an offer to
   remove the plaintext copy; a partner's copy hides behind the owner's (rows T13, T14, D3). The server cannot match
   a private copy with a standard one, as private hashes are keyed (06 §9): a client holding the key makes the link
   and syncs it up as the user's claim (photolib-design#571, gap G1); until a key-holding device has seen both, two
   tiles are expected and the Info tab says why.
8. **Which copy opens**: the local bytes while linked, else thumbnail, preview, original; always the current
   version; edits as versions; shares and exports of the current version with location stripped; any degraded copy
   says so (rows V1–V12).
9. **An edit racing a deletion is kept as a copy** (rows V13, E9).
10. **Deletes in other apps follow the device's policy**: *backup-only* by default (the tile becomes *Cloud only*),
    *ask* with a daily digest, *mirror* through the library's trash; a mass deletion pauses mirroring and asks; an
    unmounted volume, an unplugged drive or a reset device is no deletion (rows O1–O15).
11. **The delete dialog**: *Move to trash* (default: everywhere it is) and *Remove from this device* (only when
    verified), itemised by where each item is with sizes; the iCloud consequence stated on iOS; at most one system
    dialog per 500; a read-only copy offers hiding; others' contributions are only removed from the album
    (rows X1–X15).
12. **The registry**: a deleted item copied back shows under *Deleted earlier* with one-tap re-add; restoring from
    the OS trash restores the library copy too (rows X16, X17, E12).
13. **Library deletions on devices**: *ask* by default (a card offering the OS trash or *Keep on this phone only*),
    *always* or *never* per device; restores follow where the OS allows; a kept copy is device-only and never
    re-uploaded unasked; admin removals and partner deletions are told, never mirrored (rows E1–E8, E10, E11).
14. **Free up space**: manual, plus a suggestion card; an automatic policy only by opt-in per device; through the OS
    trash; each candidate re-verified at that moment under the current epoch; keep-rules, app folders skipped,
    unsent edits kept; on iOS the iCloud consequence stated and Optimise Storage offered; claims per volume, only
    local bytes, with when the space returns and the measured result (rows F1–F12, F18–F22).
15. **A freed journal survives server restores**: after an epoch change, freed items missing on the server are
    restored from the OS trash and backed up again; a scrub failure is repaired from any device (rows F13, R1, R2).
16. **Private libraries free space only with recovery set up** (row F15).
17. **Desktop and web**: free up space only for folders marked as staging areas; the web clears its cache only
    (rows F16, F17).
18. **Edits in other apps are versions of the same asset**; a file the kernel cannot read is never uploaded over a
    good version; concurrent edits keep both (rows C1, C3–C10).
19. **Storage policies bring copies back**: nothing into a new phone's gallery unasked; *Keep on this device* pins;
    *Save to the phone's gallery* links by hash; budgets per tier and in the browser (rows P1–P10, D6).
20. **Failures change nothing silently**: the queue persists, nothing is freed offline, a new server verifies afresh,
    two accounts both must hold an item, the clock never sets capture time (rows R3–R6, R8).
21. **Several devices**: the registry stops every device; frees are per device; iCloud-shared devices link by cloud
    identifier; device-only items in shared albums follow ADR-0202 (rows D1, D2, D4, D5).

## Design changes after sign-off

| Document | Change |
|---|---|
| 02 | VIEW-05: the two default badges and the backup-state filter; ING-14: the states *verifying*, *linked to NAS copy*, *excluded* with reasons; ING-15: re-verification at the moment, the freed journal, keep-rules, the iOS iCloud wording, recovery first for private libraries; a row for the per-device *library deletions* setting |
| 04 §4 | Device items join assets by hash (§4, §11 `local_asset`); §4.4 stacks gain the kind `duplicate`; a read-only external copy is a file of the asset, not a backup |
| 05 §6 | *Backed up* requires a library Photolib holds; free up space re-verifies with `CheckHashes` under the current epoch and keeps a freed journal; two accounts must both hold an item |
| 05 §6.1 | The second per-device setting, *library deletions* (*ask*, *always*, *never*); the mass guard for *mirror*; restoring from the OS trash undoes a library deletion |
| 10 §3.6 | The badges, the dialog's two choices and their defaults, the itemised summary |
| 10 §5.4, §6.2 | Free up space on iOS with iCloud Photos; app folders; per-volume claims; placeholders count nothing |
| 10 §11 | *Save to the phone's gallery*; nothing into a new phone's gallery; desktop staging folders; the browser's session budget |

## Consequences

* M2-18, M2-22, M2-24, M3-21 and M2-36 implement these rows and land no behaviour this ADR leaves open; ADR-0202 uses
  the same invariants for albums, and ADR-0201 extends them to every source kind.
* A `duplicate` stack kind, the freed journal and the per-device *library deletions* setting are new state: the
  replica and the server schema gain them with their migrations when M2-22 and M2-36 land.
* ADR-0092 stays as it is under proposal 6, read literally ("links"): an upload whose bytes only a read-only external
  library holds is linked by hash (T11), its device item *Linked to NAS copy*, never *backed up*, and free up space
  skips it unless that library counts as a backup; the owner kept this reading, not a managed copy, on 2026-10-23
  (photolib-design#668).
* The data model beneath these rows is photolib-design#571 (asset → version → content → replica): once it lands as
  M2-48, each row names which replica serves the bytes.
* The design documents change as the table above says, now that the owner has answered.

## Options considered

* **Two worlds, merged in the timeline** (Immich before its timeline rework): local and remote assets stay separate
  and the timeline hides one when hashes match. Rejected: duplicates appear whenever hashing lags, and every action
  needs a "which copy?" question.
* **Mirror everything** (Google Photos' and Apple's own apps): a deletion anywhere deletes everywhere. Rejected as the
  default for deletions in other apps, where most deletions clean a gallery, not the library; kept as the *mirror*
  policy.
* **Optimise by default**: free device copies automatically after backup. Rejected: our freed originals leave the
  OS gallery for every app, unlike Apple's placeholders; offered as an opt-in policy.
* **Storage saver**: keep a compressed copy instead of the original. Rejected: it destroys data by default (10 §11).
