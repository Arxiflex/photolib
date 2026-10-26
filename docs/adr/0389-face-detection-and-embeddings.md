# ADR-0389 — Faces: YuNet and SFace behind one consent, boxes kept against the original and moved by the kernel

* **Status**: **Proposed — owner to confirm** (roadmap M5-09).
* **Requirements**: F-02, R-PRIV-1, NFR-PRIV-1. **Design**: 09 §7, [ADR-0064](0064-model-registry-and-licence-gate.md),
  [ADR-0245](0245-server-ml-role.md), [ADR-0254](0254-on-device-ml-runner.md),
  [ADR-0278](0278-on-device-ml-in-production.md), [ADR-0331](0331-basic-edits-saved-as-copies.md).

## Context

People and pets (M5) start with faces. A description of a face can count as biometric data (GDPR Art. 9, Illinois BIPA
and similar laws), so nothing about faces may be computed before the person agreed to a notice that says what, where,
for how long and that it is optional. The registry already holds YuNet (MIT) and SFace (Apache-2.0); the `faces` table,
the face sync stream and the `face_recognition` capability exist. Edits are saved as copies, never over the original
(ADR-0331), so a box found in the original must stay right on a copy that was turned, mirrored or cropped.

## Decision

* **One consent, per account, versioned.** A row of `face_consents` is the opt-in (`notice_version`, `granted_at`);
  `FaceService.SetFaceConsent` writes it, only for the account's own session, never an API key. Every job and every
  app checks it where it computes: the server's `faces` job reads the row `FOR SHARE` in the transaction that writes
  (`faces::consented`) and keeps nothing without it; the app starts nothing until `Settings.faceNotice` is the current
  notice (`OnDeviceFaces`). A new notice version asks again. Agreeing and withdrawing are audit events
  (`faces.consent_grant`, `faces.consent_withdraw`).
* **Withdrawing deletes.** In one transaction: the account's faces, people, scans and queued face jobs; the app deletes
  its `local_ml` face rows. The admin's `face_recognition` capability still limits what the server does and shows;
  `instance_settings.face_recognition_default` is not consent and does not start anything.
* **The notice** (English; in every launched language): what is found and kept (where a face is and a list of numbers
  that describes it, possibly biometric data); where (this device and the user's own server, never a service of ours or
  anyone's); what is kept, who sees it and when it goes; that it is optional and stops at any time.
* **Models.** YuNet (detector) and SFace (embedding, 128 values) by default, both in the registry with goldens and run
  on ONNX Runtime by the ML role and by every device through the same kernel calls. AuraFace (Apache-2.0, 512 values,
  261 MB) is the registry's `optional` embedding: `photolibd models fetch` installs it only when named, it has
  server and desktop targets only, and a desktop uses it when the user switches it on. Embeddings of different models
  are never compared.
* **The kernel prepares and reads, hosts only run models.** `PrepareFaceDetection` (YuNet's input at a multiple of 32,
  at most 640), `DecodeFaces` (twelve outputs to boxes and landmarks with non-maximum suppression), `AlignFace`
  (a least-squares similarity transform of the five landmarks onto ArcFace's template, bilinear, with the model's own
  scaling) and `NormalizeFaceEmbedding`, with conformance vectors for every binding.
* **Boxes are fractions of the upright original.** `MapFaces` moves boxes and landmarks through an edit's quarter
  turns, mirror and crop exactly as `Develop` does, and back; a mirror swaps the eyes and mouth corners as a detector
  lists them; a box with less than half left in a crop is not visible and is clipped. A lossless JPEG crop moves its
  corner to the block grid, so `EditCopyResponse.crop` says what the copy really shows. Tests render the editor over a
  marked face for every turn, mirror and crop and find the marks again.
* **Where results live.** Server: `faces` (box, landmarks, score, detector, embedding as half floats, `time_ms` for a
  video's keyframe) and `face_scans` (an asset a model looked at, with or without faces). Device: `local_ml` rows named
  `faces:<detector>+<embedder>`, the faces packed as half floats, so that the indexer's gates, resume and progress
  apply. Embeddings never leave the server through the API: `ListFaces` returns boxes only.

## Consequences

* Nothing runs for an account that has not agreed; a test per layer proves it (API, job, app).
* A device and a server compute the same boxes within the models' tolerance (golden self-tests, parity tests on real
  portraits against OpenCV's own detector and recogniser).
* YuNet reads upright faces; a box on a face turned a quarter is drawn differently by the detector, which the mapped
  box does not claim to reproduce.
* Clustering faces into people, names and the people UI are the next items; their `persons` rows are deleted with the
  consent already.

## Options considered

* **Consent as a server-wide setting**: simpler, but not a person's choice in a multi-user server.
* **Detecting on the edited copy again**: the original's boxes would stay unmoved; copies would cost a second pass and
  could disagree with the original.
* **Boxes in pixels**: break with every resized rendition.
* **InsightFace's buffalo models**: best accuracy, but non-commercial weights (design 09 §2.1).

## Evidence

* **Edits** (AC2): `kernel/tests/face_edits.rs` marks faces in a picture, renders it through `Develop` for every turn,
  mirror and crop, and finds the marks where `MapFaces` says; `photolib-ml/tests/faces.rs` runs the real detector on the
  edited picture and finds the face where the mapped box is.
* **Consent** (AC1): `photolib-server/tests/faces.rs` runs the server on PostgreSQL with real YuNet and SFace: the
  account that agreed gets jobs, faces and a scan, the other gets none of them; withdrawing deletes and agreeing again
  scans again; a video gets its keyframes. `app/test/features/people_test.dart` shows no model call before the user
  agrees.
* **Models on real photographs** (public-domain NASA portraits that `tools/ml/fetch.py` pins, never committed): YuNet's
  boxes agree with OpenCV's `FaceDetectorYN` (IoU above 0.85) and SFace gives the same person 0.62 and other people
  under 0.3, as OpenCV's `FaceRecognizerSF` does (0.621, 0.107, 0.150).
* **Browsers**: the kernel's vectors, the face calls among them, pass in Chrome 156 and Firefox 158 (dart2js and
  dart2wasm); onnxruntime-web reproduces both models' golden outputs in each (cosine 0.9999999999999 or more; a run of
  YuNet takes 24 ms in Chrome and 34 ms in Firefox, one of SFace 28 and 38 ms, on this machine's CPU).
* **Cost**, one CPU core or all of them alike, printed by
  `finding_the_faces_of_a_photograph_is_repeatable_and_its_cost_is_reported` (aarch64): a 1279 by 1701 portrait takes
  0.52 s, a 4535 by 3023 group of four faces 1.9 s, most of it in the full-size picture's resampling; the server's job
  runs on the bounded raw rendition. The test asserts that the work is the same on every run, not a time: a budget
  belongs to the perf lane, and a loaded runner took 5.5 s for the group.
* **Screens**: the web app as a Pixel 7 (Chrome, device pixel ratio 2.625, touch): [the settings with the switch][settings]
  and [the notice it asks to agree to][notice]. The web client of this base runs no model, so agreeing there only
  records the answer.
  The same journey in Firefox 158 (Playwright's build, a 900 by 900 window): [the notice][ffnotice] with *Not now*
  leaving the switch off, *I agree* turning it [on][ffon], and the switch asking [before it deletes][ffwithdraw].
* **The daemon**: `tests/faces_daemon.rs` starts the `photolibd` binary with every role on a PostgreSQL cluster, ONNX
  Runtime and the models, creates the first administrator and signs in with OPAQUE, uploads a portrait, and shows that
  the sweep, which runs every minute, queues nothing and nothing is kept until the account agrees through
  `FaceService`; then the face job finds the one face (`ListFaces` carries no embedding), and withdrawing deletes it.
* **Android**: the APK builds (`flutter build apk --debug --flavor play`, with the kernel for x86_64).

[settings]: assets/0389/settings-faces-chrome-mobile-emulation.jpg
[notice]: assets/0389/faces-notice-chrome-mobile-emulation.jpg
[ffnotice]: assets/0389/faces-notice-firefox.jpg
[ffon]: assets/0389/faces-on-firefox.jpg
[ffwithdraw]: assets/0389/faces-withdraw-firefox.jpg
