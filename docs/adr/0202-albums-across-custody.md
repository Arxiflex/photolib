# ADR-0202 — Albums across custody and over files that come and go: members are never dropped, absence is shown

* **Status**: Accepted — 2026-10-21 (roadmap M3-22, photolib-design#456): the owner kept every numbered proposal in
  photolib-design#581,
  proposals 10 and 16 with the notes they now state. Only *Superseded by ADR-NNNN* may change it.
* **Requirements**: R-MODE-1, R-MODE-3. **Design**: 04 §4, §5, §9, 05 §7, 06 §1, §5, §8, §13,
  07 §4, 10 §3.6, 12 §1, §2, §5, §6; siblings
  [ADR-0200](0200-device-and-server-copies.md) (one photo on the device and the server) and
  [ADR-0201](0201-sources.md) (every source kind); [ADR-0093](0093-external-libraries.md),
  [ADR-0092](0092-per-user-deduplication.md), [ADR-0155](0155-partner-shares-own-libraries.md).

## Context

One user, one timeline, several libraries of different custody: a private (E2EE) managed library, a standard one,
external read-only or read-write folders on a NAS, and files that exist only on a device. The design fixes the
pieces — encryption is a property of the library (06 §1), the album membership graph is clear in every mode (04 §9),
an offline library root changes no asset (07 §4), standalone albums replay through the outbox (05 §7) — but never says
how an album that spans them behaves. The owner's requirement: seamless. An album built over a library survives that
library going away and comes back whole, without user action, when it returns; nothing is silently dropped from an
album; nothing is deleted because a mount failed. ADR-0200 decides the sibling question (one photo on the device and
the server); the two share their invariants.

## How others behave

Gathered 2026-10-21 from the vendors' documentation and the competitor trackers of the design repository's issue
study; numbers are 👍 or upvotes. *(inf)* marks an inference, *(pk)* prior knowledge no fetched page confirms, *?*
nothing documented.

| Scenario | Google Photos | Apple Photos + iCloud | Immich | Ente | Mylio | Synology Photos | PhotoPrism | digiKam | Lightroom Classic | Nextcloud Memories |
|---|---|---|---|---|---|---|---|---|---|---|
| A Mixed custody in one album | One custody; Locked Folder items cannot join albums (GP4) | Personal and Shared Library items mix; Shared Albums never E2EE (AP2) | Upload and external items mix, no source badge *(inf)* | Everything E2EE; "hidden" is an album flag (EN2) | Albums span devices (DR1) | ? | A private flag hides items; private items left out of shares (DR2) | Albums are folders (DK2) | Collections span drives (LR1) | Albums reference files *(inf)* |
| A Share, link, make private, delete a library | Locked Folder drops items from albums and shares (GP4) | Deleting a Shared Library offers copies (AP3) | Deleting a library deletes its assets at once (IM1) | Key in the link; deleting a hidden album unhides its items (EN5, EN2) | "Remove from Mylio" keeps files (MY2) | Links with password, expiry (SY1) | ? | Removing a collection asks first (DK1) | Removing a folder drops its photos from collections *(pk)* | Every member can delete; no viewer role (NC3) |
| B Library offline | n/a | n/a | Scan trashes everything, "expected" (IM2) | n/a | Linked folder shown missing until reconnected (MY2) | n/a (files on the NAS) | All flagged deleted; an empty-root check since 2022 (PP1) | Collection unavailable, database kept (DK2) | "Photo is missing" icon, catalog kept (LR1) | ? |
| B Returns at a new path, or a file elsewhere | n/a | n/a | Path is identity: new assets, albums lost (IM1, IM3) | n/a | Remove and re-link on a new computer (MY2) | ? | Reunited by SHA-1 with albums unless edited (PP2) | "Update Path" re-binds by volume id (DK1) | Find Missing Folder *(pk)* | ? |
| B Library removed on purpose | n/a | Leave Shared Library: copy all or yours (AP3) | Assets and memberships deleted (IM1) | n/a | Files stay on disk (MY2) | ? | n/a | Entry removed after confirmation (DK1) | Remove folder *(pk)* | ? |
| C Device-only items | Albums hold backed-up items *(inf)* | Everything syncs *(pk)* | Local items cannot join a server album (IM4) | Device folders mirrored as albums (DR2) | Catalog on every device (DR1) | ? | n/a | n/a | n/a | n/a |
| C Local copy gone, same photo elsewhere | Free-up removes only backed-up items (GP3) | Deletions sync *(pk)* | Remote deletes re-uploaded (IM5); external libraries not hashed, so duplicates (IM6) | Device delete keeps the cloud copy (EN1) | External Changes Policy (MY1) | ? | Import skips duplicates (PP3) | Removable volume by id (DK1) | Missing badge (LR1) | ? |
| D Folder-backed albums | n/a | n/a | No folder albums; scripts (211, IM7) | Watch folder → album; deletes to "uncategorized" (EN3) | Folders and albums apart (DR1) | Folder view beside albums (SY1) | Folder albums follow the tree (DR2) | Album is the folder (DK2) | Renamed outside: missing (LR1) | Folders → albums asked (22, NC4) |
| E Shared items unavailable | Deleted items leave shared albums (GP2) | Owner's delete removes it for all (AP1) | Trash, even offline, drops membership (IM8) | Deleted item stayed for a recipient (EN4) | Vault alerts name the device (DR1) | ? | Missing items hidden *(inf)* (PP4) | n/a | n/a | One trashed file broke the albums listing (NC1) |
| F Copies arriving by another road | n/a | Shared-album copies are degraded duplicates (IM9) | Phone and NAS copies both kept (IM6) | ? | Linked folders may duplicate *(inf)* | ? | Re-encoded copy = a new photo (PP2) | ? | ? | ? |

### Complaints

| Scenario | The strongest complaints |
|---|---|
| A Custody | Immich "albums in a locked folder" (266, IM10); Ente's hidden albums unhid on sharing and deletion (17, EN2); Google's Locked Folder silently drops items from albums and shares (GP4); Apple's Shared Albums break ADP (AP2) |
| A Sharing | Immich per-library partner sharing (296, IM11) and partners cannot delete (88, IM12); Ente's organising makes quota-charged copies (32, EN6); Memories has no viewer role (13, NC3) |
| B Offline | Immich trashed a library while the NAS was off (IM2) and an exclusion glob soft-deleted 176k assets (IM13); PhotoPrism flagged everything deleted (PP1) and 50k photos left albums after an update (PP4); LibrePhotos' "remove missing" deleted a library with albums and faces (LP1); Piwigo deleted a gallery after an empty sync (PW1) |
| B Moved | Immich move detection (70, IM3); "files in trash are removed from their album… a lot of albums became empty" (IM8); moving SSD to HDD loses curation (IM14); a folder rename deleted Live Photo videos (IM15); Photoview rescans fail after a mount change (PV1) |
| B Removed | Immich deletes a library's assets and memberships at once (IM1); emptying the trash deleted excluded files on a read-write mount (12, IM16) |
| C Device | Immich re-uploads remote deletions (13, IM5); offline albums (195, IM17); local items cannot join server albums (IM4) |
| D Folder albums | Immich automatic folder albums (211, IM7); Memories folders → albums (22, NC4); PhotoPrism hierarchical folders (103, PP5) |
| E Unavailable | Nextcloud's albums view failed on one trashed file (NC1); Ente's deleted photo stayed for a recipient (EN4); Lychee's upgrade broke every public URL (LY1); Immich counts included deleted assets (IM18) and its admin can see but not fix offline paths (33, IM19) |
| F Another road | Immich phone backup plus NAS sync duplicates everything, "libraries don't use checksums" (IM6); iOS shared-album copies are degraded duplicates (86, IM9); Live Photos split on edit (IM20); PhotoPrism cannot reunite an edited file (PP2) |

**What each got right**, and where it lands here: Google never deletes a photo removed from an album (GP1, A17); Mylio
and Lightroom show a missing original instead of deleting it (B1); digiKam re-binds a moved volume by its id (B5);
PhotoPrism reunites a file by its hash with its albums (B8) and refuses to index an empty root (B7); Apple offers copies
when a shared library goes away (B13); Ente keeps public links end-to-end encrypted with the key in the fragment (A5);
Immich's duplicate resolver merges album memberships (G9).

### Sources

* IM1 — [Immich docs: external libraries](https://docs.immich.app/features/libraries/)
* IM2 — [immich#24982 All assets trashed while the NAS was off](https://github.com/immich-app/immich/issues/24982)
* IM3 — [immich#16394 Move detection in external libraries (70)](https://github.com/immich-app/immich/discussions/16394)
* IM4 — [immich#8595 Add local assets to an album, triggering upload](https://github.com/immich-app/immich/discussions/8595)
* IM5 — [immich#20978 Remote deletions re-uploaded after clearing the trash (13)](https://github.com/immich-app/immich/issues/20978)
* IM6 — [immich#4763 Android app duplicates an external library](https://github.com/immich-app/immich/discussions/4763)
* IM7 — [immich#4279 Automatic albums in external libraries (211)](https://github.com/immich-app/immich/discussions/4279)
* IM8 — [immich#30042 Files in the trash are removed from their album](https://github.com/immich-app/immich/issues/30042)
* IM9 — [immich#10262 Duplicate detector: sync metadata and albums (86)](https://github.com/immich-app/immich/discussions/10262)
* IM10 — [immich#18470 Albums in a locked folder (266)](https://github.com/immich-app/immich/discussions/18470)
* IM11 — [immich#4500 Choose libraries for partner sharing (296)](https://github.com/immich-app/immich/discussions/4500)
* IM12 — [immich#9441 Partner sharing: unable to delete (88)](https://github.com/immich-app/immich/discussions/9441)
* IM13 — [immich#28178 A scan soft-deletes all assets on a "*.*" exclusion](https://github.com/immich-app/immich/issues/28178)
* IM14 — [immich#24602 Move assets between storage, keeping albums](https://github.com/immich-app/immich/discussions/24602)
* IM15 — [immich#20031 Renaming a folder deletes Live Photo videos](https://github.com/immich-app/immich/issues/20031)
* IM16 — [immich#14995 Excluded files deleted when the trash empties (12)](https://github.com/immich-app/immich/issues/14995)
* IM17 — [immich#7627 Make an album available offline (195)](https://github.com/immich-app/immich/discussions/7627)
* IM18 — [immich#4523 Album count includes deleted assets](https://github.com/immich-app/immich/issues/4523)
* IM19 — [immich#4747 Remove offline files from the default library (33)](https://github.com/immich-app/immich/discussions/4747)
* IM20 — [immich#5473 Edited Live Photos shown as separate image and video](https://github.com/immich-app/immich/issues/5473)
* EN1 — [Ente: deleting photos](https://ente.com/help/photos/features/albums-and-organization/deleting)
* EN2 — [ente#1571 Fix sharing of hidden albums (17)](https://github.com/ente/ente/discussions/1571)
* EN3 — [Ente: watch folders](https://ente.com/help/photos/features/backup-and-sync/watch-folders)
* EN4 — [ente#3727 Deleted photos are not removed from a shared album](https://github.com/ente/ente/discussions/3727)
* EN5 — [Ente: sharing and public links](https://ente.com/help/photos/features/sharing-and-collaboration/share)
* EN6 — [ente#790 Organise shared photos without duplicates (32)](https://github.com/ente/ente/discussions/790)
* GP1 — [Google Photos: create and edit albums](https://support.google.com/photos/answer/6128849)
* GP2 — [Google Photos: delete photos, shared albums, partner](https://support.google.com/photos/answer/6128858)
* GP3 — [Google Photos: free up space](https://support.google.com/photos/answer/6128843)
* GP4 — [Google Photos: Locked Folder](https://support.google.com/photos/answer/10694388)
* AP1 — [Apple: Shared Albums](https://support.apple.com/en-us/108314)
* AP2 — [Apple: iCloud data security and Advanced Data Protection](https://support.apple.com/en-us/102651)
* AP3 — [Apple: iCloud Shared Photo Library](https://support.apple.com/guide/iphone/use-icloud-shared-photo-library-iph28ac9ea81/ios)
* MY1 — [Mylio: External Changes Policy](https://manual.mylio.com/24.3/en/topic/understanding-safe-delete)
* MY2 — [Mylio: linked folders](https://manual.mylio.com/24.3/en/topic/understanding-linked-folders)
* SY1 — [Synology Photos: features](https://www.synology.com/en-global/dsm/feature/photos)
* PP1 — [photoprism#2299 Check the originals folder before indexing](https://github.com/photoprism/photoprism/issues/2299)
* PP2 — [photoprism#2298 Photos lost: reuniting by SHA-1](https://github.com/photoprism/photoprism/discussions/2298)
* PP3 — [PhotoPrism: indexing your library](https://docs.photoprism.app/user-guide/library/index.html)
* PP4 — [photoprism#1239 Photos gone from albums after a Docker update](https://github.com/photoprism/photoprism/issues/1239)
* PP5 — [photoprism#1536 Folders shown hierarchically (103)](https://github.com/photoprism/photoprism/issues/1536)
* DK1 — [digiKam: collections settings](https://docs.digikam.org/en/setup_application/collections_settings.html)
* DK2 — [digiKam: albums view](https://docs.digikam.org/en/left_sidebar/albums_view.html)
* LR1 — [Adobe: locate missing photos in Lightroom Classic](https://helpx.adobe.com/lightroom-classic/help/locate-missing-photos.html)
* NC1 — [nextcloud/photos#3513 Albums listing 404s on a trashed file](https://github.com/nextcloud/photos/issues/3513)
* NC3 — [memories#530 Permissions on shared albums (13)](https://github.com/pulsejet/memories/issues/530)
* NC4 — [memories#810 Convert folders to albums (22)](https://github.com/pulsejet/memories/issues/810)
* LP1 — [librephotos#2195 An unmounted library marks every photo missing](https://github.com/LibrePhotos/librephotos/issues/2195)
* PW1 — [Piwigo#1341 Check for an empty galleries folder before sync](https://github.com/Piwigo/Piwigo/issues/1341)
* PV1 — [photoview#150 Mount point changed, rescan fails](https://github.com/photoview/photoview/discussions/150)
* LY1 — [Lychee#1527 Upgrade broke every old public URL](https://github.com/LycheeOrg/Lychee/issues/1527)
* DR1 — Design research: commercial competitors (Mylio, Synology)
* DR2 — Design research: FOSS competitors (PhotoPrism, Ente)

## Decision

We will keep every album member until a user removes it, show every unavailable member with its cached rendition and
the reason, identify returning files by content hash and library-relative path, restore everything by itself when a
source returns, and keep each member's custody as its library's. The scenario tables below decide each case; the
numbered proposals at the end group them for the owner.

### Invariants

ADR-0200's invariants hold for albums too (I5 restates its first); [ADR-0201](0201-sources.md) extends them to every
source kind.

* **I1 — The system never drops an album member.** Membership changes only through a user's action on the album or
  the item: removing it, deleting it (when its trash retention ends), purging missing items, or a move out of a synced
  folder made on the disk. A member that is unavailable, missing, pending or in the trash stays.
* **I2 — The system never deletes an asset because a library is offline or a file is missing.** Offline changes no
  asset; missing marks and waits; only a previewed purge by the user removes.
* **I3 — A returning file is identified by content hash and library-relative path.** The hash when known; the
  library-relative path (or a provider's file id) with size and time for files not hashed yet; different bytes are
  never matched silently.
* **I4 — The system restores everything on reconnection without user action.** A library or file that returns brings
  back its albums, faces, edits, shares and links as they were.
* **I5 — One logical asset is one tile**, in an album as in the timeline (ADR-0200 I1).
* **I6 — Custody is never lowered silently.** An item reaches only whom its library's custody and the user's shares
  allow; the server never decrypts a private item; making anything readable by more parties is an explicit, listed
  action.
* **I7 — Nothing is a hole.** Every unavailable member shows its cached rendition, or a placeholder, with a reason
  the viewer may see (owners see the library and path, recipients only "unavailable for now").

### How the catalogue was generated

As in ADR-0200: copies and custody × the user's actions first (7 × 12 = 84 pairs), the pairs a real user can meet kept,
then crossed with surfaces, clients, failures and their moment, what came back and how many devices, users and
libraries, where they change the outcome; equal outcomes merged into one row whose Dims cell lists them. Each row names
its worst outcome (a lost photo, a dropped member, a duplicate, a broken link, a silent change, a custody leak) and the
invariants it was checked against; group G is the hunt beyond the item's lists.

Pruned: making an external item private in place (`p3`, `p4` × `u5`: the server reads it, 07 §1 — A18 copies it
instead); binding a folder album to a device-only or private library (`p5`, `p1` × `u10`: folder albums are a server
library's, 04 §5); another user's item in a static export of mine without its owner's share (`p6` × `u4` outside a
shared album: not reachable).

| Dimension | Values |
|---|---|
| Copies and custody | `p1` private managed library · `p2` standard managed library · `p3` external read-only library · `p4` external read-write library · `p5` device only, not backed up · `p6` another user's item (contribution, partner, shared library) · `p7` a device copy and a copy arriving by another road |
| User action, before and after | `u1` add to an album · `u2` share with a user or group · `u3` public link · `u4` static export · `u5` make the album private, or convert its library · `u6` remove or delete a library · `u7` remove from the album, or delete the item · `u8` edit, favourite, name faces · `u9` move, rename or re-encode the file outside Photolib · `u10` bind or detach a folder album · `u11` restore from a trash · `u12` purge missing items, or reject a suggestion |
| Surface | `s1` timeline · `s2` album page, cover and count · `s3` viewer · `s4` shared with a user on the instance · `s5` public link · `s6` static export · `s7` search inside the album · `s8` memories · `s9` admin view |
| Client | `k1` phones · `k2` desktop · `k3` web · `k4` the TypeScript viewer |
| What failed, and when | `f1` the library's root offline · `f2` some files missing · `f3` mid-scan · `f4` mid-upload · `f5` mid-move · `f6` mid-share (a key not wrapped yet) · `f7` device lost or app reinstalled · `f8` free up space removed the device copy · `f9` another app deleted the device file · `f10` server restored from an older backup |
| What came back, and how | `r1` unchanged at the same root · `r2` at a new root · `r3` with some files missing · `r4` the same bytes at another path or library · `r5` different bytes (re-encoded, resized, metadata rewritten) · `r6` the same bytes from another device or road · `r7` never |
| How many | `n1` one device, user and library · `n2` several devices · `n3` several users of the instance · `n4` several libraries of one user |

### A — Mixed custody in one album

| ID | Dims | Story | Worst | Surfaces show | Server does | Guarantee | Reverse | Alternatives | Inv |
|---|---|---|---|---|---|---|---|---|---|
| A1 | p1 p2 p3 u1 s2 k1 k2 k3 n4 | "My 'Italy' album mixes private, standard and NAS photos" | The user cannot tell what the server reads | Album page: "12 private · 30 standard · 5 NAS (read-only)"; a lock on private tiles; the same on every client | Membership is clear (04 §9); private content is opaque | Each member keeps its library's custody | Removing members updates the line | One custody per album (Google's Locked Folder drops items) | I5 I6 |
| A2 | p1 p2 u1 s2 | "The cover is a private photo" | A plaintext cover on the server, or none | Apps and web decrypt it; server-made pages (link previews, emails) show a neutral cover | Stores the cover reference only | The server never renders a private cover | A standard cover makes previews show it | Force a standard cover | I6 I7 |
| A3 | p1 p2 p3 s2 f1 | "The count says 47; I see 40" | A wrong count | "47 · 7 unavailable" | Counts members, unavailable ones too | Counts are exact | — when they return | Count only available ones (Immich counted deleted ones) | I1 I7 |
| A4 | p1 p2 u2 s4 f6 n3 | "I share the mixed album with my brother" | Private items unreadable for him, or sent in plaintext | Him: standard items at once; private ones once my device wraps their keys, until then "3 private items wait for Anna's device" | Serves standard renditions; stores the wrapped keys my client sends (06 §5) | Private keys only through the owner's devices | Unsharing revokes; private albums take a new key epoch (12 §1) | Refuse mixed shares | I6 I7 |
| A5 | p1 p2 p3 u3 s5 k4 | "A public link to the mixed album" | Private items leak, or the link breaks for them | The viewer: standard and NAS items from the server; private ones decrypted in the browser from keys under the fragment's link key | My client writes the link's encrypted key manifest | The fragment never reaches the server | Revoking the link deletes its manifest | Two links per album | I6 |
| A6 | p1 p2 p3 u4 s6 | "A static export of the mixed album" | Private originals with their GPS in the bucket | Export dialog as 12 §6; private originals rewritten on the client | Built by a client whenever the album holds private items | Fresh export keys; nothing re-uses library keys (06 §8) | Re-publish or expire | Server-only exports | I6 |
| A7 | p2 p3 u5 s2 | "Make this album private" | Standard items stay readable silently, or get moved and deleted | "Title, captions and order become encrypted. 30 standard and 5 NAS items stay readable by the server: copy them into your private library (420 MB)?" — copy is the default | The album key comes from my client; copies are uploaded by it; album entries switch to the copies | Originals never moved or deleted; the NAS never written | "Make standard" decrypts the album's own fields, listed first | Move (deletes standard copies); refuse | I1 I6 |
| A8 | p2 u5 s4 s5 n3 | "I convert my standard library to private (M6-12)" | Shares and links serve converted items in the clear, or break silently | The conversion lists affected shares and links: shares get key wraps automatically; old links keep standard items and show converted ones as "private now: ask Anna for a new link" | Shares re-wrapped by my client; links flagged | Never serve a converted item in the clear | Converting back is a new conversion | Break links | I6 I7 |
| A9 | p2 u6 s2 | "I delete my standard library 'Old phone'" | Albums emptied at once | "4,210 items in 14 albums go to the trash for 60 days; albums keep them, marked 'in the trash'" | Assets to the trash; memberships kept until purge | Members leave only when the trash expires | Restoring brings them back in place | Delete assets and memberships (Immich) | I1 I2 |
| A10 | p1 p2 s7 k1 k2 k3 | "I search inside the mixed album" | Private items missing from results | Results merge the server's (standard) and the client's (private, decrypted locally) on every client | Searches standard members | Private search never on the server | — | Server-only search | I5 I6 |
| A11 | p1 p2 s8 | "Memories from my mixed album" | Private items in server-made memories | Memories that touch private items are built on the client | Builds standard-only memories | — | — | Skip private items | I6 |
| A12 | p1 p6 u1 u2 n3 | "My brother adds his private photo to my shared album" | I cannot see it, or the server can | Visible to members once his device wraps it to the album key | Stores ciphertext and wraps | He owns it and its quota (12 §2) | He removes it; it leaves | — | I6 |
| A13 | p1 u7 s4 n3 | "I remove a private photo from the shared album" | Recipients keep reading it | Gone for them | The album's next change uses a new key epoch | Removal is immediate for new reads | Re-adding wraps again | — | I6 |
| A14 | p6 u1 n3 | "I add a partner-shared photo to my album" | A copy charged to me, or it vanishes when she deletes | It joins as a reference ("Add to my library", 12 §2) | References the partner's asset | If she deletes it, I am offered "keep a copy" first | — | Hard copies (Ente) | I1 I6 |
| A15 | p1 p2 u8 | "I favourite and caption items of both kinds" | Private captions in clear | Same actions everywhere | Standard fields in clear, private in `meta_user` | Per-custody storage (04 §9) | — | — | I6 |
| A16 | p1 s3 k3 | "I open a private member on the web" | The server asked to decrypt | Decrypted in the browser | Ciphertext only | — | — | Standard links only | I6 |
| A17 | p1 p2 p3 u7 | "I delete the album" | Its photos deleted | "Delete album · photos stay in your libraries"; a separate "also move its photos to the trash" lists them by library | Removes the album only (04 §5) | Members' assets untouched | Undo restores the album | Delete photos with it | I1 I2 |
| A18 | p3 u5 | "Make a NAS photo private" | The NAS file called private | "Copy it into your private library" | A copy by a client | External stays standard (07 §1) | Remove the copy | Call it private | I6 |
| A19 | p2 s9 n3 | "The admin looks at storage" | Album titles of private albums shown | Counts per user and library; never private titles | Admin reads only clear metadata | — | — | — | I6 |
| A20 | p1 p2 u2 f6 k1 | "My phone was off when I shared; my brother waits" | He sees nothing for hours | "Waiting for Anna's device to share 3 private items"; my phone wraps them when it next runs, in the background where the OS allows | — | — | — | Escrow keys on the server | I6 I7 |

### B — An external library disconnects and returns

| ID | Dims | Story | Worst | Surfaces show | Server does | Guarantee | Reverse | Alternatives | Inv |
|---|---|---|---|---|---|---|---|---|---|
| B1 | p3 f1 s1 s2 s3 k1 k2 k3 | "The NAS is off" | The album empties or shows holes | Timeline and album: cached thumbnails marked unavailable; viewer: the best cached rendition and "On 'NAS Archive', offline since 10:42"; the original's download disabled with the reason | Library offline: no asset changes (07 §4); renditions from the derived store | Every member kept | Back online: the marks go, no action | Hide or trash offline items (Immich) | I1 I2 I7 |
| B2 | p3 f1 s5 k4 | "Someone opens my public link while the NAS is off" | A broken link | Cached renditions; "Original not available right now" on download | Serves derived renditions | The link URL keeps working | — when it returns | A 404 | I2 I7 |
| B3 | p3 f1 u4 s6 | "I publish a static export while the NAS is off" | A silently incomplete export | "5 originals are offline: wait (default), publish with previews, or leave them out (listed)" | The build waits | Never a silent omission | Re-publish adds them | Publish without them | I1 I7 |
| B4 | p3 r1 s2 | "The NAS is back" | Nothing comes back without a rescan | Everything back by itself | Marker or fingerprint found: online; a rescan is queued | — | — | A manual rescan | I4 |
| B5 | p3 r2 s9 | "The NAS came back at a new mount path" | Re-ingest as new assets, albums lost | Owner: "NAS 'Archive' found at /mnt/new: relocate?"; read-write libraries with a marker relocate by themselves | Looks for the marker or fingerprint under the operator's roots; relocation keeps ids (07 §4) | Paths are library-relative | Relocate back | Path as identity (Immich) | I3 I4 |
| B6 | p3 r3 f2 s2 | "30 of 4,000 files did not come back" | Members vanish | Ghost tiles: the cached thumbnail and "Missing since 3 May"; "Purge missing" is explicit and previewed | Marked `missing` with time; nothing purged | Ghosts stay until the user purges | A file that returns is reunited (B8) | Hide after a grace period | I1 I2 I7 |
| B7 | p3 r3 f2 s9 | "It came back with 40 % of files missing" | Half the library hidden | "1,600 files missing at once: confirm before they are marked" | Mass-disappearance guard stops the scan (07 §4) | — | Files returning later are reunited | Mark them | I2 |
| B8 | p3 r4 s2 | "A missing file reappears in another folder" | A new asset; albums, faces, edits lost | It is back in its albums, with faces and edits | Hash match reunites the file with its asset id | Identity by hash | — | New asset (Immich) | I3 I4 |
| B9 | p3 p4 r4 n4 | "I moved files from one NAS library to another of mine" | New assets in the second | Back in their albums | Hash match across the owner's libraries: the asset moves to the new library, keeping its id | — | Moving back the same | New asset | I3 I4 |
| B10 | p3 r4 f2 f3 | "The file went missing before it was ever hashed" | It cannot be matched | Back in its albums when the match is unique; else a suggestion "Is this 'IMG_1234' from 'Italy'?" | Matches by name, size, time and capture time; album members are hashed first so this stays rare | Unique matches only | Rejecting keeps both apart | Path only | I3 |
| B11 | p3 r5 u9 | "Another tool re-encoded the missing file" | A silent wrong match, or a second tile | Suggestion "Looks like 'IMG_1234' from 'Italy': link it?" | Evidence: perceptual hash, capture time, camera, aspect | Never matched silently | Unlink splits them again | Auto-merge | I3 I5 |
| B12 | p3 r7 u12 s2 | "The files are gone for good; I purge" | Albums emptied without a list | Purge preview: "1,200 items in 9 albums: Italy (40), …" | Removes memberships with the assets | The user's purge is the only path | Restore from the purge's trash for its retention | Auto-purge | I1 I2 |
| B13 | p3 u6 s2 | "I remove the NAS library on purpose" | Its albums emptied | "4,210 items in 14 albums: keep them as ghosts until 20 December (default), copy their originals into your library first (380 GB), or remove them from albums now" | As chosen; files on the NAS untouched | No file is written | Re-adding within the retention restores them (B8) | Delete assets and memberships (Immich) | I1 I2 |
| B14 | p3 u6 f1 | "I remove it while it is offline" | Import offered but impossible | "Offline: originals cannot be copied; keep as ghosts or remove from albums" | — | — | — | — | I1 I7 |
| B15 | p3 f3 f1 | "The NAS dropped mid-scan" | Unscanned folders marked missing | Card: "Scan paused: NAS not reachable" | Checkpointed scan (ADR-0093) resumes | Only scanned folders decide | — | Mark missing | I2 |
| B16 | p4 f5 | "The NAS dropped while Photolib was moving files (organise)" | Files in two places or lost | "Organise paused" | The journal completes or rolls back (07 §6) | Every intent finishes or reverts | — | — | I2 I3 |
| B17 | p3 f1 s8 | "A memory falls on a day whose photos are on the offline NAS" | A memory of holes | Built from cached renditions; unavailable items are never its cover | Uses derived data | — | — | Skip the day | I7 |
| B18 | p3 f1 s7 | "I search the album while the NAS is off" | Offline items missing from results | Found, marked unavailable | Metadata stays on the server | — | — | Exclude them | I7 |
| B19 | p3 f1 s9 n3 | "Three users' albums sit on the offline NAS" | Nobody knows why | Each owner: the source card; the admin: one notice per library | — | — | Cleared on return | — | I7 |
| B20 | p3 f1 k1 n2 | "I pinned the album offline on my phone" | The pins vanish | Pinned originals open from the phone | Device cache (10 §11) | Pins are not evicted | — | — | I7 |

### C — Device-local files in albums

| ID | Dims | Story | Worst | Surfaces show | Server does | Guarantee | Reverse | Alternatives | Inv |
|---|---|---|---|---|---|---|---|---|---|
| C1 | p5 u1 n1 k1 | "I made albums without a server, then connected one" | New ids; albums rebuilt by hand | The same albums, members becoming backed up one by one | Outbox replay with the original UUIDs (05 §7) | Entries keep their ids | Disconnecting keeps local albums | Re-create on connect | I1 I4 |
| C2 | p5 u1 u2 s4 n3 | "I put device-only photos in an album shared with my family" | They see broken tiles | Members see "+3 waiting to upload from Anna's phone" at the end | Stores pending entries with the item's hash; the upload jumps the queue | Pending entries are members | They become tiles as uploads verify | Hide them; refuse (Immich) | I1 I7 |
| C3 | p5 u3 s5 k4 | "The same album has a public link" | A grid with holes | The viewer shows available items and "3 more on their way" | — | — | Shown once uploaded | Show nothing | I7 |
| C4 | p5 f4 n2 | "The upload stopped halfway" | The entry lost | Still pending | Upload resumes (ADR-0061) | — | — | — | I1 |
| C5 | p5 f7 r7 | "My phone was stolen before the upload" | The entries vanish silently | Ghost entries "Lost with Anna's phone · never backed up", a placeholder each | Pending entries stay until removed | Never dropped by the system | The user removes them | Drop them | I1 I7 |
| C6 | p5 f7 r6 k1 | "I reinstalled the app" | Entries orphaned | Entries re-link as the phone re-indexes | Entries carry the hash; the device item matches it | — | — | Lost | I3 I4 |
| C7 | p5 f9 | "Another app deleted the file before it was backed up" | Silently dropped | Ghost "Deleted on Anna's phone before backup" | — | Never dropped by the system | The user removes it | Drop | I1 I7 |
| C8 | p5 f8 | "Free up space removed the phone copy" | The member lost | Nothing changes | The entry already references the verified asset | ADR-0200 I4 | Pinning back restores the local copy | — | I1 |
| C9 | p5 p7 r6 n2 | "My tablet uploaded the same photo later" | Two tiles | One tile | The pending entry resolves by hash to the backed-up asset | — | — | — | I3 I5 |
| C10 | p5 u8 | "I favourited and named faces on device-only photos" | Lost on upload | Kept | Replayed with the asset (05 §7) | — | — | — | I4 |
| C11 | p5 u7 | "I remove a pending item from the album" | It comes back on upload | Gone | Entry removed with an HLC (05 §5) | — | Add it again | — | I1 |
| C12 | p5 u1 k3 | "I add photos from a browser folder to an album" | They vanish after the tab closes | Pending until uploaded from that browser | As C2 | — | — | Refuse | I1 I7 |
| C13 | p5 p1 u1 | "I put device-only photos in a private album" | They upload into a standard library | Upload goes to the private library | The client encrypts | Custody of the album's library | — | — | I6 |
| C14 | p5 u1 n2 | "I added them on my phone; my laptop opens the album" | Laptop sees holes | "1 waiting for Anna's phone" | — | — | — | — | I7 |
| C15 | p5 u1 k1 | "I never connect a server" | Albums trapped on one phone | Local albums; export and restore (M1-33) | — | — | — | — | I1 |
| C16 | p5 u2 f4 n3 | "My sister opens the album while it uploads" | Half-loaded tiles | Tiles appear as uploads verify | Visible on verification only | — | — | — | I7 |
| C17 | p5 u9 k1 | "I moved the file to another folder before it uploaded" | Entry orphaned | Entry follows | Device identity (ADR-0045, ADR-0095) | — | — | — | I3 |
| C18 | p5 s8 | "A memory with a device-only photo" | A server memory with a hole | Device-made memories may use it; server-made ones do not | — | — | — | — | I7 |

### D — Folder-backed albums

| ID | Dims | Story | Worst | Surfaces show | Server does | Guarantee | Reverse | Alternatives | Inv |
|---|---|---|---|---|---|---|---|---|---|
| D1 | p3 u10 u9 s2 | "I renamed the bound folder on the NAS" | A new album; shares, captions and cover lost | The same album, new folder name in its info | Folder identity by its files' identities (04 §5) | Album id kept | Renaming back the same | A new album | I1 I3 |
| D2 | p3 u9 s2 | "I moved the folder inside the library" | As D1 | As D1 | As D1 | — | — | — | I1 I3 |
| D3 | p3 u9 f2 s2 | "I deleted the folder" | The album deleted | The album stays; members become ghosts after the grace period and mass guard | Members `missing`; the album is never deleted automatically (04 §5) | Ghosts until purge | Files returning are reunited | Delete the album | I1 I2 |
| D4 | p3 f1 s2 | "Its library went offline" | Members hidden | As B1 | — | — | — | — | I2 I7 |
| D5 | p3 u10 | "I bound the album one-shot" | Later folder changes rewrite it | Membership fixed at binding; members that move keep their place | Snapshot of identities | — | Re-bind | Synced only | I1 I3 |
| D6 | p3 u10 | "I detach a synced album" | It empties | A regular album with today's members | Binding removed | — | Bind again | — | I1 |
| D7 | p4 u1 u10 | "I add a photo to a synced album of a read-write library" | It appears and disappears | With *Organise* on: "Move IMG_1 into 2019/Italy?"; else "Detach to add other photos" | Journaled move (07 §6) | The disk decides synced members | Undo journal | Add without moving | I1 |
| D8 | p3 u9 s2 | "I split the folder into two on disk" | Members vanish unexplained | Activity: "12 moved to '2019-b'" and, with mirroring, a new album for it | The disk decides a synced album; a move out on disk is the user's act | — | Moving back restores | — | I1 I7 |
| D9 | p3 r2 | "The library was relocated" | Bindings broken | Unchanged | Bindings are library-relative | — | — | — | I3 I4 |
| D10 | p3 u9 f1 r1 | "I renamed the folder while the library was offline" | Old album ghosts, a new album | On return, the album follows the renamed folder | Rename detected by its files' identities | — | — | — | I3 I4 |
| D11 | p3 u10 u2 n3 | "The synced album is shared" | Recipients surprised by changes | They see the disk's changes; activity says why | — | — | — | — | I7 |
| D12 | p3 u9 r4 n4 | "The folder was copied to a second place" | Duplicates | One tile per asset; with mirroring, a second album over the same assets | Same bytes: one asset, two files (ADR-0201 T1) | — | — | — | I5 |
| D13 | p3 u10 u5 | "Make a folder album private" | The NAS file called private | "Copy into a private album" (A7) | — | — | — | — | I6 |
| D14 | p4 f5 u10 | "An organise move into the folder was cut off" | A file in two folders | Consistent after recovery | Journal (07 §6) | — | — | — | I2 I3 |

### E — Shared and public albums whose items become unavailable

| ID | Dims | Story | Worst | Surfaces show | Server does | Guarantee | Reverse | Alternatives | Inv |
|---|---|---|---|---|---|---|---|---|---|
| E1 | p3 f1 s4 n3 | "My NAS is off; my sister opens our shared album" | Holes, or my NAS path revealed | Her: cached renditions marked "Unavailable for now" | Serves derived data | Recipients never see paths | Back by itself | Hide | I7 |
| E2 | p3 f1 s5 k4 | "A public link with offline items" | A broken page | Cached renditions; "temporarily unavailable" on original downloads; a zip lists what it left out | — | The link never breaks for availability | — | A 404 | I2 I7 |
| E3 | p3 f1 s9 n3 | "Am I told?" | Nobody knows | Owner: "5 items in 'Italy' (shared with 4 people) are unavailable: NAS offline since …"; the admin per library | One notification per library and audience | — | Cleared on return | Silence | I7 |
| E4 | p2 u7 s4 n3 | "I delete a photo of a shared album" | Recipients lose a photo they kept | It leaves the album for everyone; those who added it to their library get "keep a copy" first (12 §2) | — | — | Restoring returns it | Silent | I1 |
| E5 | p6 u7 n3 | "My brother deletes the photo he contributed" | My album silently shrinks | His dialog: "It leaves 'Italy', shared by Anna"; my activity says so | — | His item, his deletion | His restore returns it | — | I1 I7 |
| E6 | p6 u6 n3 | "My brother's account is being deleted" | His contributions vanish without warning | Members warned when the deletion is scheduled (seven days, ADR-0035) with "keep a copy" | — | — | Cancelled deletion keeps all | — | I1 I7 |
| E7 | p2 u7 r7 s5 | "An item was purged from a linked album" | The album link 404s | The rest shows; the item's own URL says "removed by the owner" | — | No page fails for one item (NC1) | — | — | I7 |
| E8 | p1 f6 s4 | "A private item's key is not wrapped for a new member yet" | A broken tile | Placeholder "waiting for Anna's device" | — | — | — | — | I6 I7 |
| E9 | p3 r7 s5 | "A missing (ghost) item in a linked album" | Holes, or a silent purge | Its cached rendition, marked unavailable | — | — | — | Hide | I1 I7 |
| E10 | p2 u3 f1 | "Expiry and password while items are offline" | Expiry pushed or ignored | Unchanged | — | — | — | — | I7 |
| E11 | p2 u3 r2 | "The server was upgraded and the library relocated" | Old URLs dead (Lychee) | Same URLs | Link ids, never paths; upgrade fixtures (ADR-0033) | URL stability | — | — | I4 |
| E12 | p3 f1 s2 s5 | "The cover is on the offline NAS" | A blank cover | The cached cover | — | — | — | — | I7 |
| E13 | p2 u7 r7 s2 | "The cover photo was deleted" | An empty cover forever (Ente) | The next member becomes the cover; the owner sees why | — | — | Choosing again | — | I7 |
| E14 | p3 f1 s6 | "My static export is published and the NAS dies" | The export breaks | Unaffected: it is self-contained | — | — | — | — | I7 |

### How an entry moves to a file that arrives by another road

1. **Pending entries carry their hash.** A device hashes the device-only members of its albums first and records each
   hash with the entry (keyed in private libraries); standard entries are visible to the server.
2. **A scan that hashes a matching file attaches it.** External scans hash album members' candidates first: files
   whose size and capture time match a pending entry. On a match the file becomes a file of the device's asset; if
   the scan already made an asset for it (metadata comes before hashing), the two merge — the older id survives, with
   the union of albums, faces, favourites and edits — and clients follow a redirect, as `merged_into` does for people.
3. **The device copy becomes a cache** under ADR-0200; it counts as a backup only under ADR-0200's proposal 6.
4. **A changed copy is suggested, never merged.** Different bytes are scored on a perceptual hash, capture time
   (tolerating whole-hour zone shifts), camera, dimensions and file-name stem. A strong score suggests, per album
   ("12 photos of 'Italy' arrived on NAS 'Archive' in another form: link them"); a confirmed pair becomes a
   `duplicate` stack (ADR-0200 T4) with the better original as cover, and the album entry stays where it was. A
   rejection is remembered.

### F — Albums made before the files arrive by another road

| ID | Dims | Story | Worst | Surfaces show | Server does | Guarantee | Reverse | Alternatives | Inv |
|---|---|---|---|---|---|---|---|---|---|
| F1 | p7 p5 p3 r6 s2 | "I copied my 2019 folder to the NAS a year after making the trip album" | Two tiles; album entries stuck on the phone copies | One tile each; album unchanged; info lists both copies | Hash match attaches the NAS file to the device asset | Identity by hash | The NAS copy leaving changes nothing (F9) | A duplicates screen | I3 I5 |
| F2 | p7 r6 f3 | "The scan made assets before hashing; my album points at the phone's" | Two assets until someone merges | One tile after the hash job | Merge: the older id survives, unions albums, faces, edits; a redirect for clients | — | — | Keep both | I3 I5 |
| F3 | p7 r5 u9 | "The NAS copy is re-encoded (Syncthing via a cloud drive)" | A silent wrong merge, or two tiles | Album suggestion "12 arrived in another form: link them" | Evidence score | Never silent | Unlink | Auto-merge | I3 I5 |
| F4 | p7 r6 u9 | "Only the name changed on the NAS" | Treated as new | Plain merge | Same hash | — | — | — | I3 |
| F5 | p7 r5 | "A tool rewrote the EXIF of the NAS copy" | A duplicate | Suggestion "same picture, metadata differs" with one tap | Pixel hash equal: strongest evidence | — | Unlink | Auto-merge | I3 I5 |
| F6 | p7 r3 s2 | "Only part of the gallery arrived" | The album looks half broken | "8 of 40 on NAS 'Archive', 32 only on Anna's phone" | — | — | The rest resolve as they arrive | — | I7 |
| F7 | p7 p2 p3 r6 | "The file is on the NAS and my phone backs up too" | Three copies, which is the asset? | One tile; info "NAS (original) · Library 'Phone' (backup) · this phone" | One asset, several files; a managed copy unless the NAS counts as backup (ADR-0200 proposal 6); with *next to my folders* the upload lands in the NAS tree and a second file there is offered for removal | — | — | Drop one copy | I3 I5 |
| F8 | p7 u9 r4 | "The NAS copy moved later" | Lost from albums | Unchanged | As B8 | — | — | — | I3 I4 |
| F9 | p7 u7 f2 | "The NAS copy was deleted; my phone still has the file" | The member lost | Album keeps it; info "only on Anna's phone now"; backed up again if backup is on | The asset lives while any file does | — | — | Drop | I1 I2 |
| F10 | p7 r6 n4 | "I copied the gallery twice, into two folders" | Two tiles | One tile; both folder albums contain it | One asset, two files | — | — | — | I5 |
| F11 | p7 r3 | "The Live Photo's video did not arrive" | Half a Live Photo | One tile; "motion only on Anna's phone" | Matched by the still; the motion part stays the device's | — | It attaches when it arrives | Split | I3 I5 |
| F12 | p7 u8 | "I edited it in Photolib after the copy" | The edit tied to one copy | Edit shows everywhere | Recipes belong to the asset | — | Revert | — | I4 |
| F13 | p7 u8 r5 | "I edited it in another app on the phone after the copy" | The NAS copy wins as current | The phone's version is current; the NAS file is the original version | `external_change` version | — | — | — | I3 |
| F14 | p7 r5 | "The copies disagree on capture time" | Wrong sort, a wrong match | One tile; info "copies disagree on time" | Evidence tolerates whole-hour shifts; the first copy's time stays | — | Fix the date | — | I3 |
| F15 | p7 n2 | "Both phones made albums before the copy" | Only one phone's entries resolve | Every device's entries resolve | Each device's hashes | — | — | — | I3 I4 |
| F16 | p7 n3 | "The family NAS library is my wife's" | Merged across users | Nothing merges across users | Per-user identity (ADR-0092) | — | — | Cross-user dedupe | I6 |
| F17 | p7 p1 p3 | "The phone photos were in my private album; the NAS copy is plain" | The private album now served in the clear | One tile; the private entry stays on the private copy; info "also on NAS 'Archive' (standard)" | The client links them; the server cannot | — | — | Switch to the NAS copy | I5 I6 |
| F18 | p7 r7 | "The copy never arrives" | Entries stuck | Device-only, backed up as usual | — | — | — | — | I1 |
| F19 | p7 r6 f3 | "It arrives while a long first scan is still hashing" | Hours of duplicates | Matched first | Candidates hashed first (step 2) | — | — | Hash in order | I3 I5 |
| F20 | p7 u7 r6 | "I deleted the phone copy after the NAS had it" | Member gone | Album shows the NAS copy | Backup-only policy (ADR-0200 O1) | — | — | — | I1 |
| F21 | p7 r6 s5 | "The album has a public link" | Still "on their way" | The link now serves it | — | — | — | — | I4 I7 |
| F22 | p7 r5 u12 | "I said no to a suggested link" | Asked again forever | Never asked again for that pair | The rejection is stored | — | Undo in duplicate review | — | I3 |

### G — Corner cases the hunt found

| ID | Dims | Story | Worst | Surfaces show | Server does | Guarantee | Reverse | Alternatives | Inv |
|---|---|---|---|---|---|---|---|---|---|
| G1 | p2 p6 u2 f1 n3 | "A family group album where one member's NAS is off" | Holes for everyone | Every member: cached renditions, "unavailable for now" | — | — | Back by itself | Hide | I7 |
| G2 | p3 p4 u10 | "The admin flips the NAS library from read-only to read-write" | Pending writes land in a burst; albums change | Albums unchanged; folder albums gain *Organise*; pending writes listed first (ADR-0201 W8) | — | — | Flip back | Write silently | I1 |
| G3 | p4 p3 | "…and back to read-only" | Queued writes lost | "12 writes wait: the library is read-only now" | Held | — | — | Drop | I1 |
| G4 | p2 u7 u11 s2 | "I trashed a photo of an album and restored it" | It returns outside the album, or at its end | In the trash it is hidden from the grid with "1 in the trash"; restored in its place | Membership and sort key kept while trashed | — | — | Drop membership (Immich) | I1 |
| G5 | p3 u7 | "I hide a NAS photo I cannot delete" | Albums lose it | Hidden from the timeline; albums keep it until removed | Per-user hidden flag | — | Unhide | Remove from albums | I1 |
| G6 | p6 u1 n3 | "Who pays for my brother's contributions?" | My quota eaten | His (12 §2, 07 §9) | — | — | — | Copies (Ente) | I6 |
| G7 | p2 r6 u12 | "I resolve duplicates" | The kept copy leaves the album (Immich) | The kept asset is in every album of the others | Union of memberships | — | Undo in the review | Keep one's | I1 I5 |
| G8 | p2 n4 s1 s2 | "A library hidden from my timeline" | Album members vanish | Albums still show its items | Show-in-timeline is the timeline's switch | — | — | Hide everywhere | I1 |
| G9 | p2 f9 k1 | "iOS split my edited Live Photo" | Two tiles in the album | One tile | Parts kept by the asset (M2-21) | — | — | — | I5 |
| G10 | p6 u6 n3 | "The album's owner is deleting their account" | Members lose the album without warning | Members warned seven days before, with "keep a copy" of what they can see | ADR-0035's delay | — | Cancelled deletion | — | I1 I7 |
| G11 | p2 p3 u8 f1 s2 | "A smart album over offline items" | They drop out | Still matched by metadata, shown unavailable | — | — | — | Drop | I1 I7 |
| G12 | p2 u8 f2 s2 | "A tag-album whose tagged file goes missing" | Dropped | Ghost, like any member | — | — | — | — | I1 I7 |
| G13 | p2 f10 | "The server was restored from last week's backup" | A week of album changes silently lost | "Restored to 14 May: devices are re-sending changes" | Devices re-send unconfirmed outbox items (05 §8); managed manifests restore membership (07 §8) | — | — | — | I4 |
| G14 | p2 u1 u7 n2 | "I removed a photo on my phone while my laptop added it offline" | One action lost | The later action wins | OR-set with HLC (05 §5) | — | — | — | I1 |
| G15 | p3 r2 n3 | "Two users' libraries sit on one NAS that moved" | One relocated, one broken | Each library relocates by its marker or fingerprint | — | — | — | — | I3 I4 |
| G16 | p2 u8 u2 n3 | "My wife names faces in our shared album" | Names leak to everyone | Names stay hers unless she shares the person (12 §2) | — | — | — | — | I6 |
| G17 | p3 f2 s1 s2 | "The timeline and the album disagree about a missing photo" | It vanishes from one, a ghost in the other | The timeline hides missing items after the grace period (07 §4); albums keep the ghost | — | — | — | — | I1 I7 |
| G18 | p2 p3 u4 r1 | "Re-publish the export after the NAS returned" | A full re-upload | Incremental: adds what was left out | — | — | — | — | I4 |
| G19 | p1 u2 f7 n3 | "I lost the only device with my private keys" | Shared private items unreadable | Members keep reading (their wraps exist); new members wait until I recover on a new device (06 §6) | — | — | — | Escrow | I6 |
| G20 | p2 u1 k3 | "I add 5,000 photos to an album on the web" | A partial add | A bulk job with progress and cancel (10 §3.6) | — | — | Cancel | — | I1 |
| G21 | p3 f1 u2 n3 | "I share an album while its NAS is offline" | The share fails | It works; recipients see unavailable members | — | — | — | Refuse | I7 |
| G22 | p2 p3 s9 u12 | "The admin sees offline and missing files" | The admin cannot act, or purges users' items (Immich) | Per library: offline since, missing counts, albums affected (counts only); purging stays the owner's | — | — | — | — | I2 I6 |

## Proposals for sign-off

1. **Each member keeps its library's custody**: the album shows a custody line and lock badges; covers and counts
   never expose a private item (rows A1–A3, A15, A16, A19).
2. **Sharing a mixed album**: standard items at once, private items once the owner's device wraps their keys,
   "waiting for Anna's device" meanwhile; contributors own their items; removals start a new key epoch; partner
   items join as references (rows A4, A12–A14, A20, E8).
3. **Links and exports of mixed albums**: one link whose fragment key opens the private items in the browser; an
   export with private items is built on a client (rows A5, A6).
4. **"Make private" copies, never moves**: album fields are encrypted and standard and NAS members are copied into the
   private library by default; converting a library re-wraps its shares and flags its links (rows A7, A8, A18, D13).
5. **Deleting a library keeps memberships for the trash retention; deleting an album never deletes photos**
   (rows A9, A17).
6. **Search and memories over private members run on the client** (rows A10, A11).
7. **An offline library changes nothing**: cached renditions with the reason, links and exports keep working,
   everything returns by itself (rows B1–B4, B14–B20).
8. **Relocation**: automatic when a library's marker is found under the operator's roots, a one-click suggestion
   when only its fingerprint matches (row B5).
9. **Missing files are ghosts until an explicit, previewed purge**; the mass guard applies (rows B6, B7, B12).
10. **Reunion by hash across the owner's libraries, keeping the asset id**; unhashed files by a unique match of name,
    size and time; album members hashed first; different bytes only suggested (rows B8–B11). The asset moving
    library (B9) stands until photolib-design#571's gap G2, an asset's home library versus its replicas in other
    libraries, refines it.
11. **Removing a library on purpose** offers ghosts (default), copying originals first, or removal from albums now
    (row B13).
12. **Device-only members are pending entries with their hash**: others see a count, uploads jump the queue, lost or
    deleted ones stay as ghosts, reinstalls and other devices resolve them by hash (rows C1–C18).
13. **Folder albums follow renames and moves and are never deleted by the system**; one-shot or synced; detach;
    organise; the activity says why members moved (rows D1–D12, D14).
14. **Shared and public albums never break for availability**: recipients see "unavailable for now", owners are told,
    deletions by contributors and owners are announced, URLs and covers stay stable (rows E1–E7, E9–E14).
15. **Entries move to files that arrive by another road**: a hash match attaches the file, a merge keeps the older id
    with every album, face and edit, clients follow a redirect (rows F1, F2, F4, F8, F10, F15, F19, F21).
16. **Changed copies are suggested and confirmed, never merged silently**; a confirmed pair is a `duplicate` stack; a
    rejection is remembered (rows F3, F5, F14, F22). No automatic merge: M5-14's duplicate review chooses the best
    copy later.
17. **Partial and mixed arrivals**: counts per source, Live Photo halves kept, all copies as files of one asset with
    backup on, the asset kept while any copy lives, edits after the copy as versions, nothing merged across users,
    private entries stay private (rows F6, F7, F9, F11–F13, F16–F18, F20).
18. **The corner cases**: read-write flips, the trash and hiding, quota, duplicate resolution, hidden libraries, Live
    Photo splits, owners leaving, smart and tag albums, server restores, concurrent edits, shared paths, face names,
    timeline versus album, re-publishing, lost keys, bulk adds and the admin's view (rows G1–G22).

## Design changes after sign-off

| Document | Change |
|---|---|
| 04 §4, §5 | Album entries may be *pending* (a device item and its hash) or *ghosts*; assets merge by hash with a redirect; `duplicate` stacks; folder albums follow their folder's identity; the trash keeps membership |
| 04 §9 | A private cover is a reference only; the custody line counts from the clear membership graph |
| 05 §7 | Pending entries replay with their hash; uploads of album members jump the queue |
| 06 §13 | Question 6 answered here; key wraps for shares and links come only from the owner's devices |
| 07 §4 | Album members hashed first; reunion across the owner's libraries keeps ids; marker libraries relocate by themselves; removing a library keeps ghosts |
| 10 §3.6 | Badges *unavailable*, *missing*, *pending*, *private*; the album's custody line |
| 12 §5 | The viewer shows unavailable members from cached renditions and pending counts; links never break for availability |
| 12 §6 | Exports wait for offline originals or publish with previews by choice; re-publishing adds them |

## Consequences

* M3-01, M3-02, M3-20, M6-08, M6-09 and the export items (M4-06, M9-01, M9-02) implement these rows and land no
  behaviour this ADR leaves open; ADR-0200 and this ADR share their invariants, and ADR-0201 extends them.
* Pending entries, ghosts, asset merges with redirects and per-pair rejections are new state: the replica and the
  server schema gain them with their migrations when M3-01 and M2-28 land.
* photolib-design#571 (asset → version → content → replica) is the model beneath rows B8–B11 and F1–F21.
* The design documents change as the table above says, now that the owner has answered.

## Options considered

* **The path as identity** (Immich): a moved or remounted file is a new asset and loses its albums. Rejected: it is
  the root of the trackers' worst incidents.
* **Albums as folders only** (digiKam): simple, but an album cannot span libraries or custody. Rejected; folder-backed
  albums remain one kind.
* **Copies per share** (Apple's Shared Albums, Ente's hard copies): survives deletion, but duplicates storage and
  custody. Rejected; contributions stay references with "keep a copy" offered.
* **Hide unavailable members**: tidy, but members seem lost and links break. Rejected for ghosts with reasons.
* **Merge near-duplicates automatically**: seamless when right, silent loss when wrong. Rejected for suggestions.
