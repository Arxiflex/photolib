# ADR-0393 — Storage policies and offline pins: four presets, a sealed budgeted store, pins of albums, searches and photos

* **Status**: **Proposed — owner to confirm**. Becomes *Accepted — YYYY-MM-DD*; once accepted, only *Superseded by
  ADR-NNNN* may change it.
* **Requirements**: R-MODE-1, R-MODE-2; LIB-20, MOB-15 (roadmap M3-21). **Design**: docs/10-client-app.md §11,
  [ADR-0200](0200-device-and-server-copies.md) rows P1 to P10 and D6, [ADR-0070](0070-thumbnail-caches.md),
  [ADR-0246](0246-adaptive-streaming.md).

## Context

ADR-0200 settled that a device copy is a cache under the device's storage policy, and its rows P1 to P10 say what
users see: the preview a policy kept while offline, *Keep on this device* with a pin badge and a size, nothing into the
gallery unasked, a budget per preset, "Will download when online", exact numbers, no decrypted copies of a private
library, and a budgeted browser. Nothing built it: the app cached thumbnails (T2) and fetched server tiles (T5) on
demand, and no client played a server video. The design document the item cites (docs/10 §11) is not in this
repository, so this ADR takes ADR-0200's quotations of it as the design and lists what it chose.

## Decision

We will build it in the client only: no proto, kernel, server or replica schema change (the server already serves
`GET /media/{asset}/{role}`), so nothing here moves a number other work uses.

* **Presets and budget** (`StoragePolicy`, one per device, a sealed vault object): *catalogue only* keeps nothing and
  pins wait; *space saver* keeps previews (`thumb_s`, `thumb_m`, `preview`, a video's `r1` proxy) of the whole library,
  newest first; *travel*, the default, keeps only pins, as previews or with their originals; *everything* keeps the
  originals of the library. The budget is in bytes, 5 GB by default, 500 MB in a browser.
* **Pins** (`OfflinePin`, sealed per account, not synced): an album, a search, a person, a photo (*Keep on this
  device*, original included) or the whole library. A plan orders files by pin, then every item's tiles before
  previews, proxies and originals, then the library's baseline; files that do not fit are counted and shown.
* **The store** (`OfflineStore`): chunks of 1 MiB (256 KiB in a browser), each a PLB envelope under the vault's cache
  key bound to its hashed name; ranged reads open only the chunks asked for; the budget is reserved before a byte is
  written; half-written blobs are swept at open; keys name content, so an edit replaces a file and unpinning frees
  exactly its bytes. Private libraries are kept as the ciphertext the server sent.
* **Passes** (`OfflineSync`): plan, drop what no pin wants, fetch the rest four at a time, wait for the network (the
  pin stays: *Will download when online*), resume on the next change, network return or five minutes. Signing out
  erases the store and the pins.
* **Reading**: `mediaProvider` answers `media/<asset>/<role>` from the store before the network, so tiles need no
  other path; a loopback range proxy (an object URL in browsers) plays pinned videos, and the server's ranges when a
  video is not kept. Albums list the server's assets no device item shows.
* **UI**: Settings › Storage, a pin in albums, searches and the viewer, a status line, a pin on kept cells; every
  string in every launched language.

## Consequences

* A pinned album works in airplane mode, and `test/features/offline/airplane_test.dart` proves it for 5,000 items:
  nothing is asked of the server, the budget holds at every step, unpinning leaves no file.
* A pinned search only finds server assets by file name and the server's text hits, as local search indexes device
  items; people pins are in the model and plan but have no page to hold their button until the people page lands.
* Each pass plans from the replica: the whole-library baseline of a very large library holds its plan in memory.
* Open decisions, taken as the item leans and listed for the owner: defaults (*travel*, 5 GB); the web ceiling
  (previews only, 500 MB); whether *clear* also leaves a whole-library preset (it does).

## Evidence

Screenshots of the built web app (`flutter build web --wasm`, served on 127.0.0.1, driven by Playwright; the page is
the real one, a browser has no replica data to pin from yet), source `app/lib/features/offline/storage_page.dart`:

* `assets/0393/chrome-mobile-settings.jpg`, `assets/0393/chrome-mobile-storage.jpg`: Chrome with Pixel 7 emulation;
* `assets/0393/firefox-storage.jpg`: Firefox at 420 × 860.

## Options considered

* **The existing T2 disk cache for pins**: it evicts least recently used first, which ADR-0200 P2 and P5 forbid for pins.
* **Storing decrypted private copies for speed**: against P7.
* **A server-side "offline set" synced to every device**: a policy is per device (D2), and pins would leak between them.
* **Plaintext files under a folder for the players**: simpler for libmpv, but nothing sealed would remain at rest.
