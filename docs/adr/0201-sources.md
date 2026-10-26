# ADR-0201 — Sources: one model for every place photos come from; drives and shares through the server

* **Status**: Accepted — 2026-10-21 (roadmap M2-46, photolib-design#466) but for proposal 6: the owner kept
  proposals 1–5 and 7–16 in
  photolib-design#579.
  Proposal 6, the OAuth model, stays **Proposed — owner to confirm**: the owner keeps it open, and no connector lands
  it before the answer. Only *Superseded by ADR-NNNN* may change the rest. The owner kept this status on 2026-10-23
  (photolib-design#670).
* **Requirements**: R-MODE-1, R-MODE-3, R-COMP-1; LIB-13, LIB-14, MOB-06, ING-22, API-09, MIG-05. **Design**:
  07, 10 §5, §8, §11, 05, 02; [ADR-0093](0093-external-libraries.md) (external libraries),
  [ADR-0042](0042-desktop-folder-sources.md), [ADR-0071](0071-desktop-folders-in-the-app.md),
  [ADR-0082](0082-web-folders.md), [ADR-0022](0022-object-store-backends.md); siblings
  [ADR-0200](0200-device-and-server-copies.md) (a photo on the device and the server) and
  [ADR-0202](0202-albums-across-custody.md) (albums over sources).

## Context

The design knows five places photos come from, each with its own words: device galleries (M1-01, M1-02), desktop
folders (M1-03), SAF and OTG providers (MOB-06), server-side external libraries on mounted paths (M2-27, docs/07 §1)
and a local store that may sit in a synced folder (M3-23); remote sources without mounting (LIB-13), buckets
(LIB-14), drop folders (ING-22) and a WebDAV view (API-09) wait in the ideas backlog. The owner asks whether cloud
drives and network shares (Google Drive, Dropbox, OneDrive, iCloud Drive, SMB, WebDAV, SFTP, DLNA, S3) become
sources — through the server (*server connectors*) or straight from each app (*client-direct*, as the Snapwood Folio
apps do) — and for one model that keeps every kind organised. The lean to test: the answer to "I want to see my NAS
on my phone" is photolibd on that NAS or on any desktop (OPS-14), with server connectors; client-direct stays what
the OS provides.

## How others behave

Gathered 2026-10-21 from vendors' documentation and store pages, rclone's source, and the competitor trackers of the
design repository's issue study; numbers are 👍 or upvotes. *(inf)* marks an inference.

| Product | Sources | Server or client | Change detection | Offline cache | Writes | Auth | Complaints |
|---|---|---|---|---|---|---|---|
| Snapwood Folio family (nFolio, dFolio, gFolio, SkyFolio) | One app per provider: SMB and DLNA, Dropbox, Google Drive, OneDrive (SN1–SN4) | Client-direct, TV and Chromecast | Browse on demand; slideshows refresh (SN2, SN3) | Downloaded folders, display-sized copies (SN3, SN4) | Read; gFolio uploads to Drive (SN3) | OAuth or SMB credentials on the device *(inf)* | File date instead of capture date; deep folders fail; a 340k folder shuffles only its first names (SN1, SN2) |
| PixFolio (iOS, and Android for Google Photos) | Photos, Google Photos, Drive, OneDrive, Dropbox, Flickr in one app (SN5, SN6) | Client-direct | "Auto update" (SN6) | Offline folders (SN6) | Download, read-only mode | Provider sign-ins | Google's 2025-03-31 API cut broke album slideshows; users left for nFolio (GP1, SN5, SN1) |
| PhotoPrism | Local disks, NFS or CIFS mounts; WebDAV services copy in and out (PP1, PP2) | Server | Scheduled re-index; a watcher asked 14 (PP5) | n/a | Originals untouched | Mount, or URL and password | Cloud storage asked 165, refused as costly and slow (PP3); an unreachable root flagged everything deleted (PP4) |
| Nextcloud Memories | Nextcloud external storage: SMB, S3, SFTP, WebDAV (DR1, NC1) | Server (Nextcloud's file cache) | Hooks; external storage needs `files:scan` (DR1) | n/a | ExifTool writes into files | Mount credentials | Downloads each file to index (NC1); timeouts loop re-downloads (NC2); no SMB transcoding (NC3) |
| Mylio | Folders, drives, NAS; Drive, OneDrive, B2, S3 only as vault targets (MY1) | Catalog on each client | External Changes Policy (MY2) | Per-device presets | Opaque folder in the cloud | OAuth | Linked folders on cloud-sync drives unsupported: "data loss and catalog corruption" (MY2) |
| Synology Photos | Folders of the NAS it runs on (SY1) | Server on the NAS | Indexes its own shares | None; 2–5 GB caches asked (DR2) | Full | DSM accounts | Slow and black thumbnails off the LAN, no client cache (75 reviews, DR2) |
| Immich | External libraries on POSIX paths only (IM1) | Server | Periodic rescan; the watcher "likely won't work" on network drives (IM1) | None; offline albums asked 195 (IM12) | Database only | The OS mount | NAS off: the whole library trashed (IM2); "never… native support for any other backends" (210, IM3) |
| Aves | MediaStore; SAF only to edit (AV2) | Client | MediaStore | Device | Device | — | WebDAV and cloud asked 64, refused: indexing needs downloads (AV1) |
| Fossify Gallery | Device storage through its own picker (FO1) | Client | Scan | Device | Device | — | An rclone (RCX) SAF remote cannot be added (8, FO1) |
| digiKam | Local, removable and network-share collections over OS mounts (DK1) | Desktop client | Monitoring "time-consuming" on network file systems (DK1) | None | Metadata into files | The OS mount | Each client's mount path differs: several paths per collection (DK1) |
| Plex | Paths on disks or OS-mounted shares (PX1) | Server | OS events "will generally not work" on SMB, NFS; scheduled scans (PX2) | n/a | Optional deletion | The OS mount | Dropped shares not remounted (PX1); missing items parked as "Unavailable" in a trash (PX3) |
| Jellyfin | Library paths, several per library (JF1) | Server | inotify; "NFS and rclone do not support inotify"; 8,192-watch limit (JF1) | n/a | — | The OS mount | No real-time monitoring on network file systems (JF1) |
| rclone | About 60 backends (RC1) | Either: FUSE mount or client | Change feeds only on Drive, Dropbox, OneDrive, Box, pCloud (RC2); else a 5 min directory cache (RC3) | VFS cache, unbounded by default (RC3) | Write-back; Drive deletes to its trash (RC4) | Tokens in `rclone.conf`; shared Google client IDs retire in 2026 (RC4) | Drive ≈ 2 files/s; case and character remapping quirks (RC4, RC1) |

### Complaints

| Behaviour | What it caused |
|---|---|
| An unreachable source read as an empty one | Immich trashed a whole library while the NAS was off, "working as expected" (IM2); PhotoPrism flagged every file deleted (PP4); Plex parks items "Unavailable" (PX3) |
| Indexing by downloading | Memories downloads every external file (NC1) and loops on timeouts (NC2); one 110 GB rclone library read 900 GB (IM4); Aves refused cloud sources for this reason (AV1) |
| Watching network file systems | inotify sees no remote change (JF1, PX2); polling burns CPU and NFS traffic (IM5); watches balloon on CIFS (IM6) |
| One app per provider, no index | Folio apps have no search, faces or capture dates (SN1); one provider's API change breaks the app (GP1, SN5) |
| Quirks of the provider | NFC and NFD names (IM7); case-insensitive and remapped names (RC1); SharePoint rewrites uploads (RC5); rclone hides directory mtimes, so new folders are never scanned (PG1) |
| Credentials | rclone's shared Google client IDs retire in 2026 (RC4); iCloud's trust token lasts 30 days and needs ADP approval (RC6) |
| Cloud-sync folders as sources | Mylio forbids linked folders on them: corruption and data loss (MY2) |
| No offline copies off the LAN | Synology's black thumbnails (DR2); Immich offline albums 195 and offline mode 202 (IM12, IM13) |

**Demand** (the trackers of 10 projects, titles naming the provider, votes on them): S3 44 threads and 410 votes, WebDAV
119 and 323, SFTP 5 and 47, rclone 11 and 30, OneDrive 8 and 24, SMB 34 and 22 (and 449 mentions, mostly bugs of mounted
shares), NFS 20 and 17, pCloud 1 and 16, Google Drive 6 and 6, Dropbox 2 and 1, DLNA 2 and 1, Box and Mega none. The
large numbers ask where the server *stores* data or how users *reach* it, not for remote sources to index; asks to index
a drive are real but diffuse (≤ 13 votes a thread; IM11, PP6; Ente's rclone request 15, EN1). Offline use on phones
(195, 202) is the larger client need.

### Sources

* IM1 — [Immich docs: external libraries](https://docs.immich.app/features/libraries/)
* IM2 — [immich#24982 NAS powered off: all assets trashed](https://github.com/immich-app/immich/issues/24982)
* IM3 — [immich#1683 Support more storage backends (210)](https://github.com/immich-app/immich/discussions/1683)
* IM4 — [immich#10607 Inefficient thumbnailing of external libraries](https://github.com/immich-app/immich/discussions/10607)
* IM5 — [immich#20858 Watching: excessive CPU and NFS traffic](https://github.com/immich-app/immich/issues/20858)
* IM6 — [immich#30456 Excessive inotify watches on CIFS](https://github.com/immich-app/immich/issues/30456)
* IM7 — [immich#30657 Integrity false positives from NFC and NFD names](https://github.com/immich-app/immich/issues/30657)
* IM8 — [immich#23745 Object storage (174)](https://github.com/immich-app/immich/discussions/23745)
* IM9 — [immich#1687 WebDAV support (163)](https://github.com/immich-app/immich/discussions/1687)
* IM10 — [immich#20522 SFTP file-level interface (43)](https://github.com/immich-app/immich/discussions/20522)
* IM11 — [immich#24608 Native cloud storage providers](https://github.com/immich-app/immich/discussions/24608)
* IM12 — [immich#7627 Make an album available offline (195)](https://github.com/immich-app/immich/discussions/7627)
* IM13 — [immich#4466 Mobile app offline or standalone (202)](https://github.com/immich-app/immich/discussions/4466)
* IM14 — [immich#5469 External library on a WebDAV mount times out](https://github.com/immich-app/immich/discussions/5469)
* PP1 — [PhotoPrism: network storage](https://docs.photoprism.app/getting-started/troubleshooting/docker/)
* PP2 — [PhotoPrism: sync services](https://docs.photoprism.app/user-guide/settings/sync/)
* PP3 — [photoprism#93 Support for cloud storage (165)](https://github.com/photoprism/photoprism/issues/93)
* PP4 — [photoprism#2299 Check the originals folder before indexing](https://github.com/photoprism/photoprism/issues/2299)
* PP5 — [photoprism#2608 Watch the originals folder (14)](https://github.com/photoprism/photoprism/issues/2608)
* PP6 — [photoprism#654 Sync with OneDrive (13)](https://github.com/photoprism/photoprism/issues/654)
* NC1 — [memories#410 Is media on external storage downloaded?](https://github.com/pulsejet/memories/issues/410)
* NC2 — [memories#917 A federated-share timeout repeats partial downloads](https://github.com/pulsejet/memories/issues/917)
* NC3 — [memories#1656 Transcoding for SMB external storage](https://github.com/pulsejet/memories/issues/1656)
* AV1 — [aves#126 WebDAV and cloud support (64)](https://github.com/deckerst/aves/issues/126)
* AV2 — [aves#709 Add a SAF folder to the collection (17)](https://github.com/deckerst/aves/issues/709)
* FO1 — [Fossify Gallery#201 Android file chooser for an rclone remote (8)](https://github.com/FossifyOrg/Gallery/issues/201)
* PG1 — [pigallery2#512 New files never scanned on an rclone volume](https://github.com/bpatrik/pigallery2/issues/512)
* EN1 — [ente#616 rclone support (15)](https://github.com/ente/ente/discussions/616)
* RC1 — [rclone: overview of backends](https://rclone.org/overview/)
* RC2 — [rclone source: backends implementing ChangeNotify](https://github.com/rclone/rclone/tree/master/backend)
* RC3 — [rclone mount: poll interval, directory and VFS caches](https://rclone.org/commands/rclone_mount/)
* RC4 — [rclone: Google Drive (rate limits, trash, client IDs)](https://rclone.org/drive/)
* RC5 — [rclone: OneDrive (SharePoint modifies files)](https://rclone.org/onedrive/)
* RC6 — [rclone: iCloud Drive (trust token, ADP)](https://rclone.org/iclouddrive/)
* RC7 — [rclone: Dropbox (too_many_requests, case)](https://rclone.org/dropbox/)
* GD1 — [Google Drive API: retrieve changes](https://developers.google.com/workspace/drive/api/guides/manage-changes)
* GD2 — [Google Drive API: usage limits](https://developers.google.com/workspace/drive/api/guides/limits)
* GD3 — [Google Drive API: trash and delete](https://developers.google.com/workspace/drive/api/guides/delete)
* DB1 — [Dropbox API: detecting changes](https://docs.dropboxapi.com/dropbox-api/docs/detecting-changes.md)
* DB2 — [Dropbox API: error handling](https://docs.dropboxapi.com/dropbox-api/docs/error-handling.md)
* MS1 — [Microsoft Graph: driveItem delta](https://learn.microsoft.com/en-us/graph/api/driveitem-delta?view=graph-rest-1.0)
* MS2 — [Microsoft Graph: throttling](https://learn.microsoft.com/en-us/graph/throttling)
* MS3 — [OneDrive: restore deleted files](https://support.microsoft.com/en-us/onedrive/restore-your-onedrive-files)
* AW1 — [Amazon S3: ListObjectsV2](https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListObjectsV2.html)
* AW2 — [Amazon S3: event notifications](https://docs.aws.amazon.com/AmazonS3/latest/userguide/EventNotifications.html)
* AW3 — [Amazon S3: versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html)
* SM1 — [MS-SMB2: CHANGE_NOTIFY request](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-smb2/598f395a-e7a2-4cc8-afb3-ccb30dd2df7c)
* WD1 — [RFC 6578: collection synchronisation for WebDAV](https://www.rfc-editor.org/rfc/rfc6578.html)
* WD2 — [Nextcloud: WebDAV basics](https://docs.nextcloud.com/server/latest/developer_manual/client_apis/WebDAV/basic.html)
* PX1 — [Plex: mounting network resources](https://support.plex.tv/articles/201122318-mounting-network-resources/)
* PX2 — [Plex: scanning versus refreshing](https://support.plex.tv/articles/200289306-scanning-vs-refreshing-a-library/)
* PX3 — [Plex: emptying the library trash](https://support.plex.tv/articles/200289326-emptying-library-trash/)
* JF1 — [Jellyfin: troubleshooting real-time monitoring](https://jellyfin.org/docs/general/administration/troubleshooting/)
* DK1 — [digiKam: collections settings](https://docs.digikam.org/en/setup_application/collections_settings.html)
* MY1 — [Mylio: your file system and cloud services](https://manual.mylio.com/24.3/en/topic/your-file-system-and-mylio-photos)
* MY2 — [Mylio: linked folders](https://manual.mylio.com/24.3/en/topic/understanding-linked-folders)
* SY1 — [Synology Photos: personal and shared spaces](https://kb.synology.com/en-global/DSM/help/SynologyPhotos/photos_desc?version=7)
* SN1 — [nFolio on Google Play](https://play.google.com/store/apps/details?id=com.snapwood.nfolio)
* SN2 — [dFolio on Google Play](https://play.google.com/store/apps/details?id=com.snapwood.dropfolio)
* SN3 — [gFolio on Google Play](https://play.google.com/store/apps/details?id=com.snapwood.gfolio)
* SN4 — [SkyFolio on Google Play](https://play.google.com/store/apps/details?id=com.snapwood.skyfolio)
* SN5 — [PixFolio for Google Photos on Google Play](https://play.google.com/store/apps/details?id=com.snapwood.photos2)
* SN6 — [PixFolio on the App Store](https://apps.apple.com/us/app/photos-slideshow-pixfolio/id1624072761)
* GP1 — [Google: Photos Picker API and Library API changes](https://developers.googleblog.com/en/google-photos-picker-api-launch-and-library-api-updates/)
* DR1 — Design research: FOSS competitors
* DR2 — Design research: Google Play reviews

## Decision

### Recommendation on the two halves

* **Server connectors: yes, staged, behind one port.** A drive, share or bucket becomes an *external library with a
  backend*: the scanner, ingest, hashing, rate limits and offline rules of ADR-0093 and 07 §4 run unchanged over a
  `Source` port (list a folder, follow changes, read a byte range, move to the provider's trash). Every client sees a
  source at once; deduplication and ML run once; the write policy of 07 §5 applies. The lean holds: the evidence shows
  diffuse demand for indexing drives (≤ 13 votes a thread) next to strong demand for offline use and for reaching
  one's server, and every product that indexes remote files in place does it on a server (Memories, PhotoPrism, Plex,
  Jellyfin). Mounted shares stay the 1.0 path; native backends follow by demand and effort (ranking below).
* **Client-direct: only what the OS provides.** Android's SAF document providers and OTG (MOB-06), desktop folders
  that the OS mounts or a sync client fills (M1-03), and folders a browser grants (ADR-0082) are *folder* sources on
  that device. Apps implement no provider protocol: one would re-do indexing, caches and ML per device, the trackers'
  answer to client-side cloud indexing is that it needs full downloads (Aves), and one provider's API change can end
  such an app (PixFolio, 2025). The cases the server story cannot meet — a NAS with no compute, a locked-down work
  laptop, a DLNA-only box — are met by photolibd on any desktop that mounts the share (OPS-14), the web app, and the
  backlog respectively.
* **Sync-client folders** (OneDrive, Dropbox, iCloud Drive, Google Drive for desktop) on a desktop are folder
  sources whose online-only placeholders are never hydrated by a scan: the OS thumbnail stands in, the item is marked
  *online only*, and its original is read only when the user opens it (Mylio's corruption warning, MY2).

### Provider ranking for 1.x

| Rank | Provider | Demand (votes, threads) | Effort | When |
|---|---|---|---|---|
| 1 | SMB and NFS mounted on the server | 449 mentions, mostly bugs of mounted shares | Hardening only: offline guard, polling, NFC/NFD, timeouts, read-once processing | 1.0 (M2-27, M2-28) |
| 2 | S3-compatible bucket, read-only link | 410 votes, 44 threads, mostly storage (IM8) | Low: ADR-0022's drivers; `ListObjectsV2` with ETag diffs (AW1); events need AWS plumbing (AW2) | 1.1 |
| 3 | WebDAV and Nextcloud | 323 votes, 119 threads, mostly access (IM9, IM14) | Low: PROPFIND with ETags; `sync-collection` where served (WD1, WD2) | 1.1 |
| 4 | SMB without a mount (an in-process client with `CHANGE_NOTIFY`) | as rank 1 | Medium (SM1) | 1.2 |
| 5 | OneDrive (Graph delta) | 24 votes, 8 threads (PP6) | Medium: OAuth app per instance, delta feed, 429 back-off (MS1, MS2) | 1.2 |
| 6 | SFTP | 47 votes, 5 threads, mostly access (IM10) | Low: polling only | 1.2 |
| 7 | Dropbox (cursor and longpoll) | 1 vote, 61 mentions | Medium: cursors, longpoll, `too_many_requests` (DB1, DB2, RC7) | 1.3 |
| 8 | Google Drive (changes feed) | 6 votes, 63 mentions | High: an OAuth client per self-hoster, quota units, shortcuts, 750 GB a day (GD1, GD2, RC4) | 1.3 |
| 9 | pCloud, Box | 16 and 0 votes | Medium each, through the same port | Ideas backlog |
| 10 | iCloud Drive, Google Photos as a source, Mega, DLNA | low; no public API, an API cut, a TV protocol | High or not possible | Ideas backlog |

Ideas backlog after this decision: ING-22 drop folders (an RW share with uploads on is the 1.x answer), API-09 a WebDAV
view of the library (it exposes, it does not source), client-direct provider browsing, and the rank 9–10 providers.

### The Sources model

A **source** is anything that contributes items. Every kind has the same card on one **Sources** screen per account
(Settings › Sources on every client): kind and icon; where it lives (*this device*, *server X*, *provider Y*); custody
and privacy (managed or linked, standard or private); access (read-only, or the write policy in force); health; what
it contributes (timeline, albums, people: three switches); and the one action that fixes its current problem.

| State | Card says | The one action |
|---|---|---|
| Connected | "1,234,567 items · last change 2 min ago" | — |
| Scanning | "Indexing: 230,000 of about 1.2 M · metadata first, 12 % hashed · 2 h left" | Pause |
| Paused | "Paused by you", "Paused on mobile data", "Rate-limited by Google until 14:05" | Resume |
| Offline | "Not reachable since 10:42 · 4,210 items kept, shown as unavailable" | Check connection |
| Needs attention | "Sign in to Dropbox again", "Folder not found: choose it again", "Cache full" | Re-authorise · Choose folder · Free cache |
| Error | the reason, the last good scan, the log line | Retry · Report |
| Removed | "Removed · 4,210 items in the trash until 2026-12-20" | Restore |

**One vocabulary**: *source* (never a tab or an app per kind); *link* (index in place, the source stays the owner) and
*import* (copy into a library); *available*, *unavailable*, *online only*, *cached here*; *pause*, *rescan*,
*remove*. A server's managed library is a source like any other ("Library 'Phone' on home server").

**Provenance on every item**: the info panel lists every source holding a copy, which one is the source of truth and
what is cached here — "Original: NAS 'Archive' (linked, read-only) · Backup: library 'Phone' on home server ·
Cached here: preview".

| Rule | Device | Folder | Managed | External | Drive | Share | Bucket |
|---|---|---|---|---|---|---|---|
| Card: where, custody, access, health | This device's gallery; read-write through the OS | A folder on this device (desktop, SAF, OTG, browser); read-only | Server X; standard or private; Photolib writes | Server X, a mounted path; read-only or a write policy | Server X → Google Drive, Dropbox or OneDrive; read-only by default | Server X → SMB, WebDAV or SFTP; read-only by default | Server X → an S3 bucket; read-only |
| Vocabulary | "Photos on this phone" | "Folder 'Pictures'" | "Library 'Phone'" | "NAS 'Archive'" | "Dropbox 'Camera Uploads'" | "Share 'photos' on nas.local" | "Bucket 'archive' on B2" |
| Provenance: truth and copies | The device until verified on the server (ADR-0200) | The folder | The managed copy once verified | The source's file; our derived data | The provider's file | The share's file | The object |
| Offline: unavailable, never deleted | OS states (SD card out) | Drive unplugged, grant lost | Server unreachable | Marker or fingerprint missing (07 §4) | Token, outage or network | Unreachable share | Unreachable endpoint |
| Cache: budget per source and device | The OS holds originals | The folder holds originals | Per-device policies (10 §11) | Server: derived data only; device: policies | Server: originals cache, default 10 GB; device: policies | as Drive | as Drive |
| Cost: metadata first, lazy hashing, feeds, estimates | Local reads | Local reads | Uploads only | Rate limits (ADR-0093) | Change feeds; quotas and back-off; estimate before start | Polling or `CHANGE_NOTIFY`; NAS rate limits | ETag diffs; egress and request estimate before start |
| Auth: per user, least privilege, revocable | OS permission | OS grant or bookmark | Account | Operator's roots, assigned per user (ADR-0093) | OAuth, the server as client, read-only scope, token in the server's secret store | Credentials in the secret store | Keys in the secret store, read-only policy |
| Link or import, chosen at connect | n/a: backed up per ADR-0200 | Link; import through upload | n/a | Link; import copies into managed | Link or import, sizes shown | Link or import | Link or import |
| Writes: off by default; deletes to a trash | OS trash | OS trash | Library trash | 07 §5; `.photolib-trash` | Policy per source; the provider's trash (GD3, MS3) | Policy; `.photolib-trash` | Never deletes (versioned buckets: a delete marker, opt-in, AW3) |

### Invariants

[ADR-0200](0200-device-and-server-copies.md) and [ADR-0202](0202-albums-across-custody.md) hold the same tile
and deletion invariants; these extend them to every source kind.

* **I1 — Originals are never touched without a write policy.** No write, move, rename, sidecar or delete reaches a
  source unless its write policy allows that operation, and every write goes through the journal (07 §6).
* **I2 — A disconnected source never deletes.** An unreachable, unauthorised, paused, throttled or failing source
  changes no asset; its items stay, marked unavailable with the reason, and come back by themselves.
* **I3 — One logical asset is one tile.** The same bytes in several sources are one asset with several files.
* **I4 — Every estimate is shown before the work starts.** Items, bytes read, API calls, egress and time are
  estimated and shown before a connect, rescan, import or conversion starts, and work over a budget waits for a yes.
* **I5 — Derived data is ours and bounded.** Thumbnails, previews, ML and metadata live in Photolib's stores; caches
  of originals have a budget per source and per device and show what they hold.
* **I6 — Credentials are per user and revocable.** A provider token belongs to one user, carries the narrowest scope,
  lives in the server's secret store, and its revocation stops every access at once.

### How the catalogue was generated

As in ADR-0200: source kind × what happened first (9 × 12 = 108 pairs), the pairs a real user can meet kept, then
crossed with auth, connectivity, limits, the half, custody and users and devices where they change the outcome; equal
outcomes merged into one row whose Dims cell lists them. Each row names its worst outcome (missing files, stale
thumbnails, duplicates, a library that looks broken, a bill, a write never allowed) and the invariants it was checked
against.

Pruned: uploads into a device gallery or a bucket by Photolib (`k1`, `k8` × `e11`: not offered); provider auth on
device and folder sources (`k1`–`k3` × `a2`–`a4`: the OS grants them); private custody in any linked source
(`k5`–`k8` × `p2`: the server reads those files, 07 §1); client-direct drives (`h2` × `k6`: not built, row K10).

| Dimension | Values |
|---|---|
| Source kind | `k1` device gallery · `k2` folder on this device (desktop, browser) · `k3` SAF provider, OTG or SD card on a phone · `k4` managed library · `k5` external library on a mounted path · `k6` cloud drive (Google Drive, Dropbox, OneDrive) · `k7` share without a mount (SMB, WebDAV, SFTP) · `k8` bucket (S3-compatible) · `k9` not a source (iCloud Drive, Google Photos, DLNA) |
| Auth state | `a1` valid · `a2` expired, sign in again · `a3` revoked at the provider · `a4` narrowed (a shared folder taken away) |
| Connectivity | `n1` online · `n2` unreachable · `n3` slow or metered · `n4` provider outage |
| Limits | `l1` rate limit hit · `l2` provider storage full · `l3` our cache full · `l4` Photolib quota full · `l5` egress cost or a daily cap |
| What happened | `e1` connect and first scan · `e2` file added · `e3` moved or renamed at the source · `e4` changed in place · `e5` deleted at the source · `e6` deleted in Photolib · `e7` the same file in two sources · `e8` link converted to import · `e9` source removed · `e10` metadata edited in Photolib · `e11` uploaded into the source · `e12` an online-only placeholder |
| Half | `h1` server connector · `h2` OS-provided on the client |
| Custody | `p1` standard · `p2` private |
| Users and devices | `u1` one user, one device · `u2` several devices · `u3` several users of one instance |

### S — Connecting a source

| ID | Dims | Story | Worst | User sees | Photolib does | Alternatives | Inv |
|---|---|---|---|---|---|---|---|
| S1 | k6 e1 a1 n1 h1 p1 u1 | "I link my 2 TB Dropbox" | A 2 TB download on first connect | Estimate first: "about 180,000 photos and videos · metadata only, about 4 GB read · 6 h · thumbnails as they come"; then progress on the card | Lists through the feed's cursor, reads headers by range, renders thumbnails, hashes last at low priority | Download everything (Memories) | I4 I5 |
| S2 | k6 e1 h1 p1 | "Link or import?" | The user does not know which they chose | The connect dialog: *Link* (Dropbox stays the owner; deleting there deletes here) or *Import* (a copy in your library; 2 TB of your quota), with sizes and what converting later means | The choice is recorded on the source | Link only (Immich); import only (Mylio) | I4 |
| S3 | k8 e1 l5 h1 p1 | "I link a B2 bucket" | An egress bill for thumbnails | "Reading metadata and making thumbnails reads about 120 GB from B2: about $1.20 at B2's price · Start" | Ranged reads; each object read whole at most once (render and hash from one read) | Read per job (900 GB for 110 GB, IM4) | I4 I5 |
| S4 | k7 e1 n1 h1 p1 | "I link the SMB share of my old NAS" | The NAS thrashes for a week | Estimate, then "Scanning slowly to spare the NAS (1,000 files/s, 64 MB/s)" with a setting | ADR-0093's per-library rates | Full speed | I4 |
| S5 | k5 e1 n1 h1 p1 | "The admin gave me the NAS folder as an external library" | A second vocabulary for the same thing | A source card like any other: "NAS 'Archive' · linked · read-only" | ADR-0093 unchanged | A separate admin-only concept | I3 |
| S6 | k6 e1 a4 h1 p1 | "I pick only the 'Camera' folder of my Drive" | The whole Drive indexed, other people's shared files included | Folder picker at connect; shared-with-me excluded unless chosen | Scope recorded; the feed filtered | Whole drive | I1 I6 |
| S7 | k6 e1 e12 h1 p1 | "My Drive has Google Docs and shortcuts" | Duplicates through shortcuts; errors on Docs | Nothing for Docs; a shortcut shows its target once | Non-media skipped; shortcuts resolved to one file id (RC4) | Follow shortcuts as files | I3 |
| S8 | k6 e1 l1 h1 p1 | "Google throttles my first scan" | Errors, or a scan that never ends | "Rate-limited by Google until 14:05 · 40 % indexed" | Back-off on 403 and 429 with Retry-After; resumes from the checkpoint | Retry at once | I2 I4 |
| S9 | k8 e1 h1 p1 | "My bucket holds 2 M objects in one prefix" | Listing takes hours before anything shows | Items appear page by page, newest pages first where keys allow | `ListObjectsV2` pages of 1,000, checkpointed | List all, then show | I4 |
| S10 | k7 e1 h1 p1 | "WebDAV without mtimes or hashes" | Every rescan re-reads every file | First scan as usual; later scans compare ETag and size | Identity by ETag, size and path until hashed | Re-read all | I4 I5 |
| S11 | k9 e1 h1 | "Can I link iCloud Drive?" | A source that breaks every 30 days | "Not available: iCloud has no public interface. On a Mac or PC, add the iCloud Drive folder as a folder source; on an iPhone, Photolib reads Photos directly" | Not offered | rclone's 30-day trust token (RC6) | I6 |
| S12 | k9 e1 h1 | "Can I link Google Photos?" | A source that stops working (API cut 2025) | "Not available: import a Google Takeout instead" (M4-02) | Not offered | The Picker API (one-off picks only) | I3 |
| S13 | k6 e1 h1 p1 u3 | "Two users on my server link their own Dropboxes" | One user sees the other's files | Each sees only their own source | Sources and tokens per user | An admin-wide connector | I6 |
| S14 | k7 e1 h1 p1 | "I link the share at a path that is already an external library" | Everything twice | "This folder is already 'NAS Archive': use that source" | Overlap refused, as ADR-0093 refuses nested roots | Allow both | I3 |

### A — Authorisation

Open, owner to confirm (proposal 6): these rows, L13 and P10 stand provisionally.

| ID | Dims | Story | Worst | User sees | Photolib does | Alternatives | Inv |
|---|---|---|---|---|---|---|---|
| A1 | k6 a1 e1 h1 p1 | "I sign in to Dropbox from the app" | A token that can write or delete everything | Provider consent for read-only access to the chosen folder; "What Dropbox can see: which files Photolib reads and when, not your photos' contents in Photolib" | OAuth code flow with PKCE, the server as client; read-only scope unless a write policy needs more | Full scope | I1 I6 |
| A2 | k6 a2 h1 p1 | "The token expired" | The source looks empty | Card: "Sign in to Dropbox again"; items stay, marked unavailable | Feed paused; no asset change | Treat 401 as empty | I2 I6 |
| A3 | k6 a3 h1 p1 | "I revoked Photolib in my Microsoft account" | Items deleted; or Photolib keeps trying forever | "Microsoft no longer allows access: sign in again or remove the source" | Paused; tokens deleted from the secret store | Delete the items | I2 I6 |
| A4 | k6 a4 e5 h1 p1 | "My friend stopped sharing her folder with me" | Read as 3,000 deletions | "3,000 items from a folder shared with you are no longer available" | Marked unavailable, the mass guard of 07 §4 asks before anything is hidden | Delete | I2 |
| A5 | k6 a1 h1 p1 u3 | "The admin wants to see users' Drive tokens" | Admin reads users' drives | Admin console: the source exists, its owner, health; never the token | Tokens sealed per user | Admin-wide connectors | I6 |
| A6 | k6 a1 h1 p1 | "Self-hosting: whose OAuth app is it?" | A shared client ID that the provider retires (rclone 2026) | Setup guide: register the instance's own app (once, by the admin) with its redirect URL | The instance's client id and secret in config, never a shared one | A Photolib-wide client id | I6 |
| A7 | k7 a2 h1 p1 | "The SMB password changed" | Repeated failed logins lock the NAS account | "Sign-in to nas.local failed: enter the new password"; retries stop | One failed attempt pauses the source | Retry with back-off | I2 I6 |
| A8 | k8 a3 h1 p1 | "I deleted the bucket's access key" | Items deleted | "B2 refuses the key: enter a new one" | Paused | Delete | I2 I6 |
| A9 | k6 a1 e9 h1 p1 | "I remove the source" | The token keeps working | "Removed · Photolib's access was revoked at Dropbox" | Token revoked at the provider and deleted | Delete locally only | I6 |
| A10 | k6 a2 h1 p1 u2 | "I signed in again from my phone" | The phone holds the token | Same card on every client | The token goes to the server only; clients hold none | Tokens on devices | I6 |

### N — Connectivity and outages

| ID | Dims | Story | Worst | User sees | Photolib does | Alternatives | Inv |
|---|---|---|---|---|---|---|---|
| N1 | k5 n2 h1 p1 | "The NAS was off during the nightly scan" | The whole library trashed (Immich) | "NAS 'Archive' not reachable since 02:10 · items kept"; tiles show thumbnails marked unavailable | Marker or fingerprint missing: offline, no asset change (07 §4) | Trash missing items | I2 |
| N2 | k6 n4 h1 p1 | "Dropbox is down" | Mass unavailability read as deletion | "Dropbox has an outage · retrying" | 5xx pauses the feed; cursors kept | Rescan | I2 |
| N3 | k7 n2 e5 h1 p1 | "The share came back with half the folders missing (a disk of the NAS failed)" | Half the library hidden or purged | "12,400 items are missing from 'photos' on nas.local: confirm before they are hidden" | Mass guard (1,000 or 5 %) | Hide at once | I2 |
| N4 | k6 n3 h1 p1 | "The server is on a metered uplink" | A bill | Per-source switch "Pause on metered connections"; estimates in bytes | The server's own metered setting stops connectors | — | I4 |
| N5 | k5 n2 e2 h1 p1 | "Files were added while the NAS was unreachable" | They never appear | They appear after the rescan the return triggers | A return queues a rescan | Wait for the schedule | I2 |
| N6 | k6 n2 h1 p1 | "The server was offline for two weeks; the Drive cursor expired" | A full re-download | "Catching up with Google Drive" | Expired feed token: a listing compared by id, size and checksum, no content reads for known files | Re-read everything | I4 I5 |
| N7 | k8 n2 h1 p1 u2 | "I open a bucket photo on my phone while the bucket is unreachable" | A blank viewer | The preview from the server's derived store; "Original not reachable now" | Derived data is ours | — | I2 I5 |
| N8 | k7 n3 h1 p1 | "The WebDAV server is slow" | Timeouts loop re-downloads (Memories) | "Slow: 2 files/s" on the card | Per-request timeouts; a failed range read retried from its offset, never from zero | Whole-file retries | I4 |
| N9 | k6 n1 e2 h1 p1 | "I added photos to Dropbox from my phone" | They show up hours later | In the timeline within minutes | Longpoll or webhook hint, then the cursor | A nightly crawl | I3 |
| N10 | k7 n1 e2 h1 p1 | "The SMB share gets new files" | Polling eats the NAS | Seconds when the NAS supports `CHANGE_NOTIFY`, else the poll interval shown on the card | `CHANGE_NOTIFY` with a tree watch, else polling with a minimum interval | Mount and inotify (fails, JF1) | I4 |
| N11 | k5 n2 h1 p1 u3 | "Three users' albums use the offline NAS" | Each user told nothing | Each owner sees the source offline; the admin is notified once | One notification per source and audience | — | I2 |

### L — Limits, cost and caches

| ID | Dims | Story | Worst | User sees | Photolib does | Alternatives | Inv |
|---|---|---|---|---|---|---|---|
| L1 | k6 l1 e1 h1 p1 | "Google's 750 GB a day" | Import stalls mysteriously | "Google's daily limit reached · continues at 00:00 UTC" | Detected by its error; scheduled | Retry | I4 |
| L2 | k6 l2 e11 h1 p1 | "My Dropbox is full and I upload into it" | Uploads fail silently or vanish | "Dropbox is full: uploads wait" and the destination falls back to the managed library only if the user chose that | The upload stays in staging, never dropped | Drop | I1 I4 |
| L3 | k6 l3 h1 p1 | "The server's originals cache is full" | Old cached originals evicted mid-view, or the disk filled | Card: "Cache 10 GB of 10 GB · Free cache"; viewing still works, slower | LRU within the source's budget | Unbounded cache (rclone default) | I5 |
| L4 | k6 l4 e8 h1 p1 | "I convert my Drive to an import but my quota is too small" | Half imported | "Needs 1.4 TB; you have 900 GB free: import a part (by year) or ask for more" | Refused before start | Start and fail | I4 |
| L5 | k8 l5 e4 h1 p1 | "A rescan of the bucket" | A full re-read every week | "Rescan: list only (2,000 requests, $0.01)" | ETag diff; only changed objects read | Re-read | I4 I5 |
| L6 | k8 l5 e8 h1 p1 | "Import the bucket" | A surprise egress bill | "Copies 2.1 TB: about $21 egress at your provider's price" | Estimate from the provider's published price, editable | No estimate | I4 |
| L7 | k6 l1 h1 p1 u3 | "Ten users link Google Drive through one OAuth app" | One user's scan starves the others | Each card shows its own rate state | Per-user quota buckets inside the project's limits | First come | I4 |
| L8 | k6 l3 u2 h1 p1 | "My phone's cache for Dropbox items" | Phone fills | Phone's storage policy applies (10 §11) | Same device policies for every source | Per-source phone settings | I5 |
| L9 | k7 n3 l5 h1 p1 | "The NAS is a spinning disk" | Hashing makes it unusable | "Hashing at 64 MB/s, after thumbnails" | ADR-0093's byte rate and hash-last priority | Hash first | I4 |
| L10 | k6 l1 e4 h1 p1 | "Thousands of files change at once (a re-tag in another tool)" | Rate limits for days | "12,000 changes · metadata only · 40 min" | Feed batches; metadata by range | Re-read whole files | I4 I5 |
| L11 | k8 l5 e6 h1 p1 | "Deleting in a versioned bucket" | Versions billed forever | "The bucket keeps old versions: deleting adds a delete marker; the space stays billed" | Opt-in only | Delete objects | I1 I4 |
| L12 | k5 l3 h1 p1 | "The derived store fills" | Thumbnails of linked sources lost | Admin: "Derived store 95 % full" | Renditions are a rebuildable cache; the admin is warned | — | I5 |
| L13 | k6 l1 e1 h1 p1 u1 | "What does linking cost my Google account?" | API quota of other apps used up | "Uses Photolib's own Google project's quota, not yours" | Instance-owned project | — | I4 I6 |

### M — Moves, renames and changes at the source

| ID | Dims | Story | Worst | User sees | Photolib does | Alternatives | Inv |
|---|---|---|---|---|---|---|---|
| M1 | k6 e3 h1 p1 | "I renamed a folder in Dropbox" | Albums, faces and edits lost (Immich: a new asset) | Nothing changes but the path | The feed's file id keeps identity; else hash and size | Delete and re-add | I3 |
| M2 | k7 e3 h1 p1 | "I moved files on the SMB share" | New assets, old ones missing | Nothing changes but the path | Matched by hash and size, provisional by name, size and mtime until hashed | By path only | I3 |
| M3 | k8 e3 h1 p1 | "Objects re-keyed by a script" | Every asset doubled | Nothing changes but the key | ETag (single-part) or hash match | By key only | I3 |
| M4 | k6 e4 h1 p1 | "I edited a photo in Dropbox's web editor" | A second tile | One tile, a new version "changed at Dropbox" | `external_change` version (04 §4.3) | New asset | I3 |
| M5 | k7 e4 h1 p1 | "Another tool rewrote EXIF in place" | Faces re-run, or the change ignored | New version; faces kept if pixels match | Pixel hash decides re-runs (07 §4) | New asset | I3 |
| M6 | k6 e3 a4 h1 p1 | "I moved files out of the linked folder into another part of Drive" | Read as deleted | "Moved out of 'Camera Uploads': 40 items unavailable" | Outside the scope is unavailable, not deleted | Delete | I2 |
| M7 | k5 k7 e3 h1 p1 | "I moved files from the NAS library to the SMB-linked share" | Albums lost | One asset, new source | Hash match across the owner's sources keeps the asset (ADR-0202 B) | New asset | I3 |
| M8 | k7 e3 h1 p1 | "The share's names are NFD (from a Mac), the old ones NFC" | Every file missing and new | Nothing changes | Paths compared after Unicode normalisation | Byte comparison | I2 I3 |
| M9 | k6 e3 h1 p1 | "Dropbox renamed a file to avoid a case clash" | Duplicates or lost files | One tile | Case-insensitive comparison for case-insensitive providers | Case-sensitive | I3 |
| M10 | k6 e4 h1 p1 | "SharePoint changed my file on upload" | Hash mismatch reads as corruption | One tile; info "the provider altered this file" | Hash from what the provider returns, recorded after upload | Flag corruption | I3 |
| M11 | k8 e4 h1 p1 | "An object overwritten with the same key" | Old version lost from Photolib | New version; the old one kept if versioning is on, else only its derived data | Version recorded | — | I3 I5 |
| M12 | k2 k6 e12 h2 p1 | "A desktop sync client turned files into online-only placeholders" | The scan downloads 500 GB to hash them | Tiles stay with "online only"; hashing waits for the user | Placeholders recognised (cloud-file attributes); never hydrated by a scan | Hydrate to hash | I4 I5 |

### D — Deletes

| ID | Dims | Story | Worst | User sees | Photolib does | Alternatives | Inv |
|---|---|---|---|---|---|---|---|
| D1 | k6 e5 h1 p1 | "I deleted a photo in Dropbox" | It lingers forever, or vanishes from albums with no trace | The tile leaves the timeline after the grace period; albums show it as a ghost (ADR-0202) | Marked `missing`, then removed after the grace period; the album entry stays | Delete at once | I2 |
| D2 | k6 e5 h1 p1 | "I restored it from Dropbox's deleted files" | A new asset without its albums | Back, with albums and faces | Same file id or hash: reunited | New asset | I3 |
| D3 | k6 e6 h1 p1 | "I delete a Drive photo in Photolib (read-only)" | Nothing happens, or the Drive file deleted | "Drive is read-only here: hide it in Photolib, or allow deletes for this source" | Hidden per user; the file untouched | Delete through the API | I1 |
| D4 | k6 e6 h1 p1 | "Deletes are allowed for my Dropbox source" | A hard delete through the API | "Moved to Dropbox's deleted files (restorable 30 days)" | Provider trash only (Drive trash, Dropbox deleted files, OneDrive recycle bin) | Permanent delete | I1 |
| D5 | k7 e6 h1 p1 | "Deletes allowed on the SMB share" | `unlink` | "Moved to .photolib-trash on the share" | 07 §5's trash folder through the journal | unlink | I1 |
| D6 | k8 e6 h1 p1 | "Delete on a bucket" | Data loss without undo | Not offered unless versioning is on and the user opts in (L11) | — | Delete objects | I1 |
| D7 | k6 e5 h1 p1 | "A sync tool emptied the folder by mistake" | 20,000 items hidden | "20,000 deleted at Dropbox in 2 min: confirm before hiding them" | Mass guard | Follow at once | I2 |
| D8 | k5 e5 n2 h1 p1 | "The mount failed and the folder is empty" | Everything missing | Offline, not missing (N1) | Marker check before any missing mark | — | I2 |
| D9 | k6 e5 e6 h1 p1 u3 | "My partner deletes a photo in a shared Drive folder I linked" | It disappears from my albums silently | My albums keep a ghost "deleted at Google Drive" | As D1 | — | I2 |
| D10 | k6 e6 e9 h1 p1 | "I remove the source, then add it again" | Duplicates, lost albums | Same assets back with their albums (within the trash retention) | Removal trashes assets; re-adding matches file ids and hashes and restores | New assets | I2 I3 |
| D11 | k3 e5 h2 p1 | "I took out the USB stick" | Items deleted | "On USB drive (not connected)" | Offline, as volumes are (ADR-0200 O10) | Delete | I2 |
| D12 | k4 e6 h1 p1 | "I delete in my managed library" | Different behaviour from other sources | Same dialog vocabulary as ADR-0200 X1 | Library trash | — | I1 |
| D13 | k7 e5 e3 h1 p1 | "A file disappears and reappears in another folder a day later" | Albums lost in between | Ghost for a day, then reunited | `missing` keeps identity until purge; hash match reunites | Purge on miss | I2 I3 |

### T — The same file in several sources

| ID | Dims | Story | Worst | User sees | Photolib does | Alternatives | Inv |
|---|---|---|---|---|---|---|---|
| T1 | k6 k5 e7 h1 p1 | "My Dropbox camera uploads are also on the NAS" | Two tiles of every photo | One tile; provenance lists both | One asset, two files, matched by hash | Two assets (Immich) | I3 |
| T2 | k1 k6 e7 h1 p1 | "My phone backs up to Photolib and to Google Drive" | Three copies, three tiles | One tile: "This phone · Library 'Phone' · Drive 'Camera'" | Hash links all (ADR-0200 T3) | — | I3 |
| T3 | k6 e7 e5 h1 p1 | "I deleted the Dropbox copy; the NAS copy stays" | The asset deleted | Tile stays; provenance loses Dropbox | The asset lives while any file does | Delete the asset | I2 I3 |
| T4 | k6 k8 e7 e6 h1 p1 | "I delete in Photolib a photo held by two linked sources" | One copy deleted, the other resurrects it | "In 2 sources: Dropbox (deletes allowed) and bucket (read-only): delete from Dropbox, hide the bucket copy" | Per-source actions listed, then the registry | Delete one | I1 I3 |
| T5 | k6 e7 h1 p1 | "Which copy opens?" | The slow one | The fastest available: a local or cached copy, else the source with the best measured throughput | Same bytes, any source | Always the first | I3 |
| T6 | k6 k4 e7 e8 h1 p1 | "I import a Drive I had linked, and my phone backup already holds half of it" | Stored twice | "1.2 TB, of which 600 GB you already have: copies 600 GB" | Dedupe by hash (ADR-0092) | Copy all | I3 I4 |
| T7 | k6 e7 h1 p1 u3 | "My wife and I link the same shared Dropbox folder" | One user's edits leak to the other | One tile each, in each one's library; edits per owner | Per-user sources and assets (ADR-0092 point 1) | Shared assets | I3 I6 |
| T8 | k7 e7 e4 h1 p1 | "Two copies diverge: one edited on the NAS" | Two tiles, or one copy's edit hidden | One tile, the edited bytes as a new version; info "copies differ" | Different bytes from a file of the asset: an `external_change` version | Split | I3 |
| T9 | k6 e7 h1 p1 | "WhatsApp backup in Drive holds re-encoded copies" | Duplicates | Stacked as ADR-0200 T4 | Evidence stack | Two tiles | I3 |
| T10 | k6 k5 e7 h1 p1 u1 | "Which copy is the source of truth?" | The user cannot tell | Provenance marks "original" on the copy that was there first, or the managed copy once verified | ADR-0200 I2 per source | — | I3 |

### C — Link, import, conversions and removal

| ID | Dims | Story | Worst | User sees | Photolib does | Alternatives | Inv |
|---|---|---|---|---|---|---|---|
| C1 | k6 e8 h1 p1 | "I convert my linked Dropbox into an import" | New assets, albums lost | "Copies 400 GB into 'Library'; albums, faces and edits stay" | Each asset gains a managed file; ids kept; the link may then be removed | Re-import as new | I3 I4 |
| C2 | k6 e8 n2 h1 p1 | "The conversion was cut halfway" | Half converted, unclear | "Copied 120 of 400 GB · Continue" | Resumable job; per-asset atomic | Restart | I4 |
| C3 | k6 e8 e5 h1 p1 | "After converting, I delete the Dropbox files" | Assets vanish | Nothing changes: the managed copy is the truth | The Dropbox files go missing; assets live | — | I2 I3 |
| C4 | k6 e9 h1 p1 | "I remove the Dropbox source" | Albums emptied at once | "4,210 items will be in the trash for 60 days; they are in 14 albums: keep them as ghosts (default), import them first (400 GB), or remove them from albums now" | Assets to trash with album entries kept until purge (ADR-0202) | Delete at once (Immich) | I2 I4 |
| C5 | k6 e9 h1 p1 | "I want to stop seeing Dropbox in the timeline but keep its albums" | Removing is the only switch | Card switches: timeline, albums, people | Contribution flags per source | Remove | I2 |
| C6 | k6 e2 e8 h1 p1 | "New files arrive in Dropbox after I converted to import" | They are ignored, or imported unasked | "Keep importing new files from Dropbox" (on by default after a conversion) | The feed continues as an import | Stop | I4 |
| C7 | k2 e8 h2 p1 | "Import a desktop folder" | Two tiles (folder and library) | One tile; the folder copy and the managed copy | Upload of the folder (ADR-0200) | — | I3 |
| C8 | k5 e9 h1 p1 | "The admin removes my external library" | My albums emptied without warning | "Your library 'NAS Archive' was removed by the admin: 4,210 items kept as ghosts until 20 December" | As C4, decided by the admin's dialog | Delete at once | I2 |
| C9 | k6 e8 l4 h1 p1 | "Import only 2023 and later" | All or nothing | Import by date range, folder or album | Filters on the conversion job | All | I4 |
| C10 | k9 e8 h1 p1 | "Import from Google Photos" | Linked source attempted | "Use Takeout import" (M4-02) | Importer, not a source | Picker API | I3 |
| C11 | k6 e1 e9 h1 p1 u2 | "I removed the source on my laptop; my phone still shows it" | Inconsistent state | Gone everywhere at the next sync | Sources sync on the `libraries` stream | Per device | I3 |

### W — Writes

| ID | Dims | Story | Worst | User sees | Photolib does | Alternatives | Inv |
|---|---|---|---|---|---|---|---|
| W1 | k6 e10 h1 p1 | "I add a caption to a Drive photo" | XMP files appear in my Drive unasked | The caption is stored in Photolib; the card says "Writes: off" | No write | Write sidecars by default | I1 |
| W2 | k6 e10 h1 p1 | "I turn on sidecars for Dropbox" | Sidecars clobber another tool's | `photo.jpg.xmp` written, unknown namespaces kept (07 §5) | Through the journal and the provider's API | — | I1 |
| W3 | k6 e11 h1 p1 | "Upload next to my folders, into Dropbox" | Files land in a random place | Destination template shown with an example | 07 §2 upload target over the Source port | — | I1 |
| W4 | k6 e11 n2 h1 p1 | "The upload into Dropbox failed mid-way" | A half file in Dropbox | Upload pending | Provider upload sessions; finished or abandoned, never half | Plain PUT | I1 |
| W5 | k6 e11 a4 h1 p1 | "My write scope was not granted" | Silent failures | "Writing needs more access: sign in again with write access" | Scope checked before a policy turns on | Ask at connect | I1 I6 |
| W6 | k7 e11 h1 p1 | "Upload into the SMB share" | `IMG_1234.HEIC` overwritten | `IMG_1234 (2).HEIC` | Deterministic suffix; never overwrite (07 §2) | Overwrite | I1 |
| W7 | k8 e11 h1 p1 | "Can Photolib upload into my bucket?" | Keys overwritten | Not offered for linked buckets (managed libraries on S3 are ADR-0022) | — | — | I1 |
| W8 | k5 e10 h1 p1 | "A read-only library flips to read-write" | Earlier edits written in one burst | "Write 2,300 pending sidecars now?" | Pending writes queued, shown, confirmed | Write silently | I1 I4 |
| W9 | k6 e10 n2 h1 p1 | "I edit while Dropbox is unreachable" | The edit lost or written late over a newer file | The edit is in Photolib at once; the sidecar waits | Journal intent waits; checked against the file's version before writing | Overwrite | I1 |
| W10 | k6 e4 e10 h1 p1 | "The file changed at Dropbox while my sidecar write waited" | My write over newer data | "Not written: the file changed at Dropbox" with a retry | Version check (ETag, rev) on write | Last write wins | I1 |
| W11 | k7 e11 l2 h1 p1 | "The share is full" | Upload lost | "nas.local is full: 12 uploads wait" | Staging keeps them | Drop | I1 I4 |

### K — Client-direct: what the OS provides

| ID | Dims | Story | Worst | User sees | Photolib does | Alternatives | Inv |
|---|---|---|---|---|---|---|---|
| K1 | k3 e1 h2 p1 | "I add my SD card on Android" | Second vocabulary | A folder source "SD card" on this phone | MediaStore volume (MOB-06) | A separate screen | I3 |
| K2 | k3 e1 h2 p1 | "I add an SMB share through an Android SAF provider" | A full download to index | Folder source "nas (via CIFS Documents)"; estimate first | SAF tree read lazily: metadata by range where the provider allows, else thumbnails by the provider | Download all | I4 |
| K3 | k3 n2 h2 p1 | "The SAF provider lost its connection" | Items deleted | Unavailable on this phone | Offline, as volumes | Delete | I2 |
| K4 | k2 e1 h2 p1 | "I add my OneDrive folder on Windows" | Placeholders hydrated (M12) | Folder source "OneDrive · online-only files stay online" | Cloud-file attributes respected | Hydrate | I4 I5 |
| K5 | k2 e1 h2 p1 | "I add a mounted SMB share on my Mac" | inotify-style watching fails silently | Folder source "on network volume · checked every 10 min" | Polling on network volumes (10 §8.1) | Watch | I2 |
| K6 | k2 n2 h2 p1 | "The Mac's share unmounted" | Items deleted | Offline (ADR-0042) | — | — | I2 |
| K7 | k2 e1 h2 p1 u2 | "I want my laptop's folder on my phone" | The phone cannot reach it | "Back up this folder to your server" or "Run photolibd here" (OPS-14) | No device-to-device sync | Peer sync | I3 |
| K8 | k7 e1 h2 p1 | "My phone should see my NAS, without a server" | No answer | "Photolib shows your NAS through a Photolib server: run photolibd on the NAS or a desktop (guide)", and SAF providers on Android | Lean: no client protocol | nFolio-style client | I3 |
| K9 | k7 e1 h2 p1 | "My NAS cannot run anything" | No answer | photolibd on any desktop that mounts it | — | Client-direct SMB | I3 |
| K10 | k6 e1 h2 p1 | "Browse my Google Drive on my phone without a server" | Duplicated indexing per device | Not offered; "Link it on your server" or Drive's own SAF provider on Android | — | Folio apps | I3 I5 |
| K11 | k2 e1 h2 p1 | "On a locked-down work laptop" | No way in | The web app over the user's server | — | Desktop client-direct | I6 |
| K12 | k9 e1 h2 p1 | "Show my DLNA server on the TV" | — | Ideas backlog; the server's own web and TV clients instead | — | DLNA client | I3 |
| K13 | k2 e1 h2 p1 | "Add a browser folder in Chrome" | Folder re-picked each visit | Folder source on this browser (ADR-0082) | Handles kept in IndexedDB | — | I2 |
| K14 | k2 k3 e3 h2 p1 | "I moved the folder on my desktop" | A new source, albums lost | Card: "Folder moved: follow it?" when the OS reports it; else "Folder not found: choose it again" | Identity by file id (ADR-0042) | New source | I2 I3 |

### P — Privacy, sharing and users

| ID | Dims | Story | Worst | User sees | Photolib does | Alternatives | Inv |
|---|---|---|---|---|---|---|---|
| P1 | k6 p2 e1 h1 | "I want my Dropbox photos private" | A linked drive labelled private | "Linked sources are standard: the server reads them. Import into a private library to encrypt" | 07 §1 rule applied to every linked kind | Call it private | I6 |
| P2 | k6 p2 e8 h1 | "Import Dropbox into my private library" | Plaintext on the server | A client imports (the desktop or phone downloads, encrypts, uploads) | Private imports run on a device, never on the server | Server import | I6 |
| P3 | k6 p1 e1 h1 | "What does Dropbox learn?" | False reassurance | "Dropbox sees which files Photolib reads and when; Photolib's albums, faces and captions stay on your server" | — | — | I6 |
| P4 | k6 p1 e1 h1 u3 | "I share an album with drive items with my brother" | His access depends on my token in ways he can't see | Works like any album; if my source is offline, his tiles show unavailable | Album sharing over our renditions (ADR-0202 E) | — | I2 |
| P5 | k6 p1 h1 u3 | "Public link to drive items" | The link hotlinks the provider | Served from our renditions and cache | Never redirect to the provider | Redirect | I5 |
| P6 | k6 p1 a3 h1 u3 | "My token is revoked; my shared album's recipients" | Broken links | Cached renditions keep serving; originals "unavailable" | — | — | I2 |
| P7 | k6 p1 h1 u3 | "The admin wants to limit which providers users may link" | Users link anything | Admin setting: allowed source kinds and providers | Policy checked at connect | — | I6 |
| P8 | k6 k8 p1 h1 u3 | "Audit: who linked what" | No trail | Admin audit: source added, removed, writes enabled | `audit_append` for each (ADR-0035) | — | I6 |
| P9 | k6 p1 e1 h1 | "The connector is new outbound traffic" | Undeclared egress | A privacy-manifest row per connector (kill switch, timeout) | `test_outbound.sh` | — | I6 |
| P10 | k6 p1 e9 h1 u1 | "I delete my account" | Tokens left at the provider | Tokens revoked at the provider with the account | Account deletion revokes every source | Leave them | I6 |

## Proposals for sign-off

1. **Server connectors, staged, behind one `Source` port**: a drive, share or bucket is an external library with a
   backend; scanning, ingest, hashing, rate limits and offline rules stay ADR-0093's and 07 §4's (rows S1–S4,
   S6–S10, S13, S14, N9, N10).
2. **The provider ranking for 1.x** in the table above, and what stays in the ideas backlog.
3. **Client-direct is only what the OS provides**: SAF, OTG and SD cards, OS-mounted and sync-client folders,
   browser folders; apps implement no provider protocol; "my NAS on my phone" is photolibd on the NAS or a desktop
   (rows K1–K14).
4. **Not sources**: iCloud Drive (a folder source on a computer instead), Google Photos (Takeout import), DLNA
   (rows S11, S12, C10).
5. **One Sources screen**: one card for every kind with its states and one fix action, one vocabulary (*source*,
   *link*, *import*, *available*, *online only*, *cached here*), provenance on every item, and three contribution
   switches (rows S5, C5, C11, T10).
6. **Authorisation** — *open, owner to confirm*: OAuth with PKCE, the server as client through the instance's own
   registered app, the narrowest scope, tokens sealed per user in the server's secret store, never admin-wide, revoked
   at removal and account deletion (rows A1–A10, L13, P10). The owner has not chosen between apps per instance and a
   Photolib-wide app; the cost to weigh when Drive and Dropbox reach their 1.3 slot is every self-hoster registering a
   Google or Microsoft OAuth app and passing Google's verification for Drive scopes.
7. **A disconnected source never deletes**: offline, expired, revoked, outage and narrowed scopes keep items as
   unavailable; mass changes wait for confirmation; returns rescan by themselves (rows N1–N8, N11, D7, D8, D11, D13).
8. **Cost**: an estimate of items, bytes, requests, egress and time before every connect, rescan or import; metadata
   by range first, one whole read per file, hashing last; feeds and ETag diffs instead of crawls; back-off and daily
   caps shown (rows L1, L5–L7, L9, L10).
9. **Caches**: derived data in Photolib's stores; a server cache of originals per linked source (default 10 GB); the
   device policies of 10 §11 for every source (rows L3, L8, L12).
10. **Moves and changes keep identity**: provider file ids, then hash and size; Unicode and case normalised; changes
    in place are versions; online-only placeholders are never hydrated by a scan (rows M1–M12).
11. **Deletes**: a source's deletion marks items missing, then hides them after the grace period, keeping album
    entries; restores reunite; Photolib deletes in a source only under its write policy and only into the provider's
    trash or `.photolib-trash`; buckets never (rows D1–D6, D9, D10, D12, L11).
12. **The same file in several sources is one asset with several files**; a delete lists what happens in each source
    (rows T1–T9).
13. **Link or import, chosen at connect with sizes**; converting keeps asset ids; removing a source keeps its items as
    album ghosts for the trash retention, with import-first offered (rows C1–C4, C6–C9, L4).
14. **Writes off by default**: sidecars, uploads and deletes per source under 07 §5; upload sessions, deterministic
    names, version checks before every write; a read-only to read-write flip shows pending writes first (rows W1–W11,
    L2).
15. **Privacy**: linked sources are standard; a private import runs on a device; the card says what the provider can
    see; shares and links serve our renditions, never the provider's URLs; admins choose allowed providers; every
    source change is audited and every connector is a privacy-manifest row (rows P1–P9).
16. **How connectors are built**: native Rust for S3, WebDAV, SMB and SFTP; for the OAuth drives, native clients
    over each provider's documented change feed, with rclone in the media sandbox evaluated against them when rank 5
    is built (a new dependency needs its own ADR).

## Design changes after sign-off

| Document | Change |
|---|---|
| 02 | LIB-13: WebDAV and SMB links leave the ideas backlog for 1.1–1.2; LIB-14: bucket links in 1.1; MOB-06: SAF, OTG and SD sources are folder sources; ING-22 and API-09 stay in the ideas backlog; new rows: the Sources screen, OAuth drive connectors (1.2–1.3) |
| 07 §1 | External libraries gain a backend (mount, S3, WebDAV, SMB, SFTP, OneDrive, Dropbox, Google Drive) behind the `Source` port; every linked kind stays standard |
| 07 §4 | Change detection per backend (feeds, `CHANGE_NOTIFY`, ETag diffs, polling); one read per file; Unicode and case normalisation; auth states and outages are offline states |
| 07 §5 | The write policy applies per source; deletes go to the provider's trash; buckets never delete |
| 07 §10 | Both questions answered: no two-way folder sync; buckets are linked read-only in 1.1 |
| 10 §5 | Android's SAF, OTG and SD sources appear as folder sources on the Sources screen |
| 10 §8 | Desktop sync-client placeholders are never hydrated by a scan; network volumes are polled |
| 10 §11 | Device policies cover every source; the server keeps a per-source originals cache |
| 05 | Sources and their health travel on the `libraries` stream; connectors obey the server's metered setting |

Roadmap: M2-27 and M2-28 gain the `Source` port, the health states and Unicode and case rules; M1-03 gains placeholder
handling; M3-23 shows the local store's folder as a card; new tasks: the Sources screen (M2), bucket links (1.1),
WebDAV and SMB links (1.1–1.2), OAuth drive connectors (1.2–1.3).

## Consequences

* M2-27, M2-28, M1-03, M3-22, M3-23 and M2-45 land no source behaviour this ADR leaves open; ADR-0200 and ADR-0202
  share its tile and deletion invariants.
* Each connector is new outbound traffic: it ships with its privacy-manifest row and, if it brings a dependency, its
  own ADR.
* photolib-design#571 (the replica model) gives a source's files the replica rows these decisions assume.
* The design documents and roadmap change as the section above says, now that the owner has answered; what depends
  on proposal 6 waits for its answer.

## Options considered

* **Client-direct connectors in every app** (the Folio family, PixFolio): cheapest per provider, but every device
  re-indexes, nothing is searchable without full downloads, and one API change ends the feature. Rejected.
* **No remote sources** (Immich's answer): mounted paths only. Rejected as the end state: buckets and WebDAV are cheap
  through the port, and a mount hides change feeds and placeholders.
* **rclone mounts under external libraries**, as users do today: documented as a workaround; FUSE hides change feeds
  behind a 5-minute cache, multiplies egress and hydrates placeholders.
* **A screen and a word per source kind**: what the design had; rejected for one Sources model.
