# Storage policies and offline pins

What a device keeps of the server's library, and how it is proven (M3-21, [ADR-0393](../adr/0393-storage-policies-and-offline-pins.md);
the rows P1 to P10 and D6 of [ADR-0200](../adr/0200-device-and-server-copies.md) bind it).

## Parts

| Part | Where | What it does |
|---|---|---|
| `StoragePolicy`, `OfflinePin` | `app/packages/photolib_data/lib/src/offline_policy.dart` | The four presets and a budget; pins of an album, search, person, photo or the whole library, as JSON |
| `OfflineStore` | `offline_store.dart` | Chunked blobs by key, each chunk sealed by the vault under the cache key, hashed names, ranged reads, a budget reserved before a byte is written |
| `planOffline` | `offline_plan.dart` | The files a policy and its pins want, in the order they are fetched, from the replica's `asset_file` rows |
| `OfflineSync` | `offline_sync.dart` | A pass: plan, drop what no pin wants, fetch the rest, wait for the network |
| `OfflineMedia` | `offline_media.dart` | Answers `media/<asset>/<role>` from the store with the server's ETag semantics |
| Providers | `app/lib/features/offline/offline.dart` | The sealed policy and pins, the keeper that runs the passes, `mediaProvider`'s offline layer |
| `VideoProxy` | `app/lib/features/offline/video_proxy.dart` | A loopback range server (an object URL in browsers) that plays pinned videos from the store |
| Pages | `storage_page.dart`, `pin_button.dart` | Settings › Storage, the pin button and status of albums and searches, the viewer's *Keep on this device* |

## Rules

* The store is the only place offline bytes live. A blob is `<name>/<hash of key>/<n>.<count>.<size>.<chunk>`, every
  chunk a PLB envelope bound to that name; a blob with a chunk missing is the remains of a crash and is swept at open.
* The budget counts sealed bytes on disk and is **reserved before the first byte**: `OfflineStore.put` throws
  `BudgetExceeded` without writing anything, and `reserved + used` never passes `budget`. The plan fits files to the
  budget in order; a file that does not fit is counted (`PinProgress.left`), never written in part.
* Keys name content (`<asset>.<role>.<first 16 hex of the hash>`): an edit is a new key, and the pass drops the old
  file with the next plan. Unpinning drops every key no pin wants, so space returns exactly.
* A private library's files are kept as the ciphertext the server sent. Nothing in the offline layer holds a library
  key or decrypts to disk; the viewer opens them in memory as it does online (ADR-0200 P7).
* Signing out erases the store and the pins; a removed account's store goes with it. A browser keeps previews only
  and a smaller budget (`Keep.previews` is its ceiling).
* The thumbnail pipeline needs no offline code: `mediaProvider` answers from the store first, so tiles (T5) come
  from it without a request. `serverVideoUrlProvider` gives the players the proxy's URL.

## Proofs and how to run them

```sh
cd app/packages/photolib_data
flutter test test/offline_store_test.dart test/offline_plan_test.dart test/offline_sync_test.dart
cd ../..
flutter test test/features/offline
```

`test/features/offline/airplane_test.dart` is the acceptance case: 5,000 items pinned from a stand-in server, then the
server unreachable; every tile, preview and video range is served from the store, the server is asked nothing, the
budget holds at every step, and unpinning leaves no file. `OFFLINE_ASSETS` sets fewer while you work.
`test/web_test.dart` of `photolib_data` runs the store on IndexedDB in browsers.
