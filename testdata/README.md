# testdata/

Small, licence-clean fixtures that tests across the repository share: a few media files, golden JSON, and
synthetic-library seeds.

## Architecture

* Fixtures here are small enough to live in git. `corpus/` is the synthetic media corpus: every format, vendor and
  quirk, each file decodable where a stdlib encoder is reasonable and with a golden JSON of expected metadata. Real,
  licence-clean captures can follow in a separate repository using Git LFS.
* Known-answer vectors for the kernel live next to it in `kernel/testvectors/`, not here.
* Every fixture must be redistributable under the project's licence; say where a file came from and under what
  terms. Never commit real personal photos or any secret.
* A bug report with a reproducible file, shared with permission, becomes a corpus entry.

## Contents

* `seed/`: the development seed set loaded by `tools/dev/seed.py`: `seed.json` (users and libraries) and one folder
  of media per library. The images are synthetic gradients generated for this repository, with EXIF capture dates and
  no third-party content.
* `edl/`: edit decision lists that every video executor runs (`app/packages/photolib_video`), in the JSON form of the
  design's `EditDecisionList`.
* `corpus/`: the generated media files, their golden records and the schema; its README documents every field.
  `tools/corpus/` generates and validates it.
* `oidc/`: sign-ins recorded at a Keycloak 26.8 and an Authelia 4.39 set up for the purpose (`tools/oidc/signin.py
  --record`): public keys, an ID token in its three parts, userinfo; nothing secret.
* `discovery/`: the multicast DNS question the apps ask and photolibd's answer to it, in hex; the server's
  `discovery.rs` and the app's `nearby_test.dart` both hold to them (a changed answer fails the Rust test, which prints
  the new one).
* `thumbhash.json`: images and their ThumbHashes from the reference implementation (`node tools/thumbhash_vectors.mjs`),
  which the kernel's encoder (`testvectors/thumb_hash.json`) and the app's decoder `ThumbHash` match.
* `fuzz/<target>/`: inputs the kernel's coverage-guided fuzzer found, minimized by `tools/kernel/fuzz.sh`;
  `kernel/tests/fuzz.rs` replays them in the gate.
* `photolibignore.json`: the folder scans' ignore rules as cases, which the app's folder indexer runs
  (`app/packages/photolib_data/test/ignore_test.dart`) and the server's external libraries must run too.

## Design

* Quality and testing: media corpus
* Media pipeline
