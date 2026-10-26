# ADR-0388 — OCR and text search: PP-OCRv5 on the ml role, text as untrusted data, a job and a search API

* **Status**: **Proposed — owner to confirm**. Becomes *Accepted — YYYY-MM-DD*; once accepted, only *Superseded by
  ADR-NNNN* may change it.
* **Requirements**: F-01, F-06 (roadmap M5-08). **Design**: 09 §6,
  [ADR-0245](0245-server-ml-role.md), [ADR-0254](0254-on-device-ml-runner.md).

## Context

M5-08 reads the text in photos, indexes it for search, lets the user copy it and treats it as untrusted input.
`asset_ocr(asset_id, model_id, text)` and its sync stream existed since the baseline; nothing wrote or read it. The
design document the item cites (09) is not in this repository, so this ADR takes the most conservative reading and
lists what it chose below.

## Decision

* **Models.** PP-OCRv5 (Apache-2.0) as ONNX files pinned by SHA-256 (`tools/ml/artefacts.json`) and registered with
  goldens: one detector (`ppocr-v5-det`) and three recognisers, Latin, East Slavic (Cyrillic) and Chinese/Japanese
  (`ppocr-v5-rec-*`), which the ML role self-tests at start like every model (ADR-0245). Their dictionaries are
  compiled into `photolib-ml` (`data/ocr/`).
* **Pipeline.** `photolib_ml::ocr::read`: the detector's map is thresholded, blobs become boxes grown by
  `area × 1.5 / perimeter` (DB's unclip), each line is read by every recogniser and the surest reading (mean
  probability of the characters it chose) stands. Greedy CTC decoding. Text is cleaned (`ocr::clean`: no control or
  bidirectional characters, at most 20,000 characters) and otherwise kept as read.
* **Job.** The reconciler queues an `ocr` job for every image lacking `asset_ocr` text of the model `ppocr-v5`
  (`Profile.ocr`, `device` placement for private libraries). A process with the `ml` role **and a database** takes
  the jobs (`PgJobs`, `Role::Ml`); the pixels come from the sandboxed renderer as raw RGB (`Format::Raw`), so no image
  decoder runs in the process that reads. `ml.ocr: false` turns the queueing off. A remote ML node with no database
  does not take jobs; that is ADR-0245's work protocol, not this item (see Consequences).
* **API.** `SearchService.SearchText` (substring, any case through ICU's root collation, `%` `_` `\` literal, the
  assets the caller may view by `scope`, trash and private libraries excluded) and `GetText`; capability
  `search.text.v1`.
* **Clients.** The search page adds the server's hits to the names it finds; the viewer's *Copy text* shows the text in
  a dialog and copies it. The text is a `String` in a `SelectableText` and on the clipboard, never parsed as markup.
* **Desktops read on the device** (Windows, macOS, Linux; the registry lists the models for them): the same pipeline in
  Dart (`photolib_ml/ocr.dart`, charsets generated from the server's dictionaries) runs on an isolate of its own
  under the data isolate's gates, and the text joins `local_ml` (schema 28: `ocr_text`, `ocr_folded`) beside the
  vectors, so that the indexing progress counts it and the local search matches it, folded by Unicode, in any
  script. It needs the user's consent apart from the search model's, since it is another 188 MB (Settings › Read
  text in photos).
* **Untrusted input.** Control and bidirectional characters are dropped at write; the API returns the text as data in
  Connect messages (never HTML); photolibd's responses carry `nosniff` and no page renders them; the web viewer shows no
  OCR text. Threat model T33 cites the tests.

## Consequences

* Search needs PostgreSQL built with ICU for case folding beyond ASCII (Debian, Ubuntu and the official images have
  it). No index yet: a substring scan; a `pg_trgm` index is the next step if a library makes it slow.
* The three recognisers cost three runs per line; a script detector could pick one first.
* **Remote ML nodes are outside this item.** The item asks for PP-OCR "on server and desktop" and says nothing of
  nodes; ADR-0245 built the `ml` role with a database and gave a remote node only a report endpoint (`POST
  /ml/v1/report`, one shared token), and settled that "the work protocol (claiming jobs, fetching renditions by signed
  URL, returning outputs) joins the same endpoint and token when the first ML job arrives (M5-04)". It is one protocol
  for every ML job (embeddings of M5-04, faces of M5-09, text), with a table of nodes and per-job authorisation, so
  building a private one here would collide with it. Until it exists a process with the `ml` role and a database
  reads the text, which is how the server reads it today. The owner may want it built first (below).
* **Phones read with the platform.** Google ML Kit on Android (Play flavour only: `src/play/.../PlatformText.kt`,
  Latin, Chinese and Japanese recognisers bundled in the app, the surest reading by summed word confidence; the libre
  flavour has a stub, because ML Kit is not free software and `tools/scan_libre.py` fails any build containing it) and
  Apple Vision on iOS (`PlatformText` in `MlChannel.swift`, accurate level, language detected, revision 3), both
  behind `org.photolib/ml` (`textSupport` names the engine or answers null, `recognize` returns the text of one
  item). The text goes through the same `cleanOcrText` in the data isolate, is kept in `local_ml` under the same model
  id with the engine in `rt_flags`, and is found by the same local search. Nothing downloads, so the switch has no size
  and no metered-data wait; the device gates (battery, thermal, saver) still hold. Phones read new photos while the
  app runs (no backlog; the server reads the backed-up library). ML Kit has no Cyrillic model: Cyrillic on a phone is
  read by the server only. ML Kit's own telemetry (its common library carries Firebase transport) is a Play-flavour
  cost the owner may refuse (below).
* **Not run here**: Kotlin and Swift on a phone. Android compiles (`flutter build apk --debug --flavor play`, with
  ML Kit and `PlatformText` in the dex and `libmlkit_google_ocr_pipeline.so` in the APK; `--flavor libre` builds
  without it and the libre dependency scan passes); Swift cannot be compiled on this host (`xcrun`: command not found,
  no `swiftc`), only linted (SwiftLint ratchet), and nothing ran on a device (`adb devices` lists none). The Dart side
  (channel contract, data isolate, switch and gates) runs against fakes.
* OCR of private libraries is read only by a device. The desktops' reader runs on the CPU only (no provider choice,
  unlike the search model's runner).

* **For the owner to confirm** (taken here as the most reversible choice): remote ML nodes take `ocr` jobs only with
  ADR-0245's work protocol, not before; ML Kit ships in the Play flavour with its telemetry (the alternative is no
  Android reading until a free engine is bundled, i.e. PP-OCR through the runner of ADR-0254); phones read new photos
  only; substring search over a trigram index; and the desktop's separate consent for the 188 MB models.

## Options considered

* **Tokenised full-text search** (`tsvector`): fails Chinese and Japanese, which have no spaces. Substring chosen.
* **One multilingual recogniser**: PP-OCRv5 has none covering Latin, Cyrillic and CJK at once; three small ones are
  cheaper than the 84 MB Chinese model on every line.
* **Tesseract or EasyOCR**: not on the design's list and heavier to ship; PP-OCR is Apache-2.0 and runs on the ONNX
  Runtime the role already has.
* **Syncing `asset_ocr` into the replica**: offline search, but every client would download text (and, in the same
  stream, embeddings) for the whole library; the API keeps the client small. Revisit with M5-06's kernel search.

## Evidence

A photolibd built from this branch, with its own PostgreSQL cluster, ONNX Runtime 1.31.0 and the four models that
`photolibd models fetch ppocr-v5-det ppocr-v5-rec-latin ppocr-v5-rec-eslav ppocr-v5-rec-chinese` installed (each passes
its golden self-test at start), had the pictures of `testdata/ocr/` scanned as an external library from the web app's
*Server administration*. Its scan, ingest, render and `ocr` jobs ran by themselves (`ocr` done 4, `render` done 12), and

```text
 cjk.png      | ppocr-v5 | 東京駅 丸の内
 cyrillic.png | ppocr-v5 | Красная площадь, Москва
 latin.png    | ppocr-v5 | Lisboa Estação 2026
 xss.png      | ppocr-v5 | <img src=x onerror=alert(1)>
```

is `asset_ocr`. The web app was driven in Chromium 131 as a Pixel 7 (touch, device pixel ratio 2.625, CPU slowed 4×,
1.6 Mbit/s with 150 ms of latency once signed in): [the library of the OCR pictures in the administration overview][overview]
and [the settings][settings-chrome]. The web client of this base neither syncs nor uploads yet, so the screens this
change adds are rendered from their widget tests, with the server's answers faked: [Copy text][copy], and
[the switch to read text on a desktop][read], [downloading][download]. The Android APK builds
(`flutter build apk --debug --flavor play`, with the kernel and ONNX Runtime for x86_64).

[overview]: assets/0388/admin-overview-chrome-mobile-emulation.jpg
[settings-chrome]: assets/0388/settings-chrome-mobile-emulation.jpg
[copy]: assets/0388/viewer-copy-text-widget-render.jpg
[read]: assets/0388/settings-read-text-widget-render.jpg
[download]: assets/0388/settings-downloading-widget-render.jpg
