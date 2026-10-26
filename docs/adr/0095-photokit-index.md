# ADR-0095 — PhotoKit index: JSON pages, the persistent history and an install id kept on the phone

* **Status**: **Proposed — owner to confirm** (roadmap M1-02).
* **Requirements**: R-MODE-1, R-APP-4. **Design**: 10 §3.4, §6.1 and §6.2, [ADR-0045](0045-mediastore-index.md),
  [ADR-0049](0049-ios-backup-strategy.md).

## Context

Design 10 §6.1 indexes PHAssets with their cloud identifier, dates, location, subtypes, bursts, adjustments and
favourites, replays `fetchPersistentChanges` from a stored token, applies changes within seconds, explains limited
access and takes grid thumbnails from `PHCachingImageManager` without the network. It leaves open what a row holds before
any resource is read, how 100k assets reach the replica without stalling the UI, what limited access and an expired
token cost, and where the install id that invalidates the hash cache lives.

## Decision

We will:

* **Rows**: write what an asset says without reading its resources, which iCloud may keep off the phone: local and
  cloud identifiers, modification date (`mtime`) and creation date (`taken`), pixel size, duration, location,
  `mediaSubtypes` as facets (`live`, `panorama`, `hdr`, `screenshot`, `depth_effect`, `spatial`, `cinematic`,
  `high_frame_rate`, `time_lapse`, `screen_recording`, `streamed`), `burst_cover` and `burst_pick`, the burst id,
  favourite and `edited` (`hasAdjustments`). The size stays 0 and the MIME type a range (`image/*`, `video/*`): only
  resources name them. Every burst frame is a row; hidden assets and shared albums are left out.
* **Transfer**: hand pages of 2,000 assets over as JSON text that one SQL statement writes through `json_each`, never
  as a Dart object per asset: collecting their garbage pauses the UI isolate too.
* **Reads**: a full read takes one fetch result newest first and pages through it, stamping the rows it writes, then
  drops the unstamped ones. Otherwise the persistent history since the stored token names the assets to read again;
  those the library no longer returns, deleted or hidden, are dropped with their backup state. An expired token,
  unavailable details and limited access, whose selection can change outside the history, mean a full read; no access
  leaves the index alone.
* **Install id**: a random id in a keychain item with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, which never
  moves to another phone. When the stored one differs, the PhotoKit index is dropped with its hashes, matches and
  backup states, and read again. Before the first unlock the read fails and the sync waits, rather than make a new id.
* **Changes**: `PHPhotoLibraryChangeObserver` and every resume start a sync on an isolate of its own, coalesced as on
  Android; the observer is registered only once the user has answered, as registering earlier asks them.
* **Limited access**: the library's banner says what is missing and offers *Select more photos*
  (`presentLimitedLibraryPicker`) and *Allow access* (Settings); `PHPhotoLibraryPreventAutomaticLimitedAccessAlert`
  stops iOS from asking at every launch.
* **Thumbnails**: T3 is `PHCachingImageManager` at the tier, `highQualityFormat`, no network, handed over upright in
  sRGB BGRA, CoreGraphics' own order (ADR-0040); iOS needs no T2 disk cache of its own.

## Consequences

* An iCloud-optimised library indexes without a download; whether an original is on the phone is learnt by the work
  that needs it (metadata reading, backup), which design 10 §6.2 throttles.
* A cold index of 100,000 assets took 1.7 s on a desktop against a fake library while the calling isolate missed
  none of its 60 Hz frames; a change of 20 assets landed in 49 ms. The phone's numbers are the spike's open rows.
* Restored app data on a new phone costs a cold index and hashing again; the keychain item survives a reinstall on the
  same phone, whose replica is gone anyway.
* With limited access every sync reads the whole selection, which is small by nature.
* Personal and Shared Library assets, which iOS does not tell apart, are both indexed; Recently Deleted is never seen.
* The gate compiles no Swift: `tools/tests/test_photo_kit.sh` checks the channels against the Dart as text, and the
  iOS smoke test indexes a simulator's library.
* Follow-ups: caching windows that follow the viewport (`startCachingImages`); a metadata reader for PhotoKit's
  originals on the phone (ADR-0072 skips them until then); backup matching by cloud identifier (M2).

## Options considered

* **A flat list of values per page**, as MediaStore's channel sends: 100,000 assets as Dart objects in the data
  isolate's group, whose collections pause the UI isolate.
* **The persistent history alone**: a changed limited selection may leave no trace in it, and an expired token none.
* **A file excluded from backup**, Android's way: Apple documents that exclusion for backups only, and the keychain
  attribute for every move to another phone.
* **`identifierForVendor`**: nil before the first unlock and reset when every app of the vendor is removed.
* **Reading each asset's resources for its size, name and type**: a query per asset during the index, deferred to the
  metadata reader and backup, which need them.
