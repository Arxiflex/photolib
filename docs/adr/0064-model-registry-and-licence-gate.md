# ADR-0064 — Model registry: one compiled-in list, a licence gate in the gate, bundles for air-gapped installs

* **Status**: Accepted — 2026-10-23 (roadmap M5-01). The owner kept no signed manifest until a signing key exists,
  the compiled-in registry and each file's SHA-256 the trust anchor, for the apps as for photolibd
  (photolib-design#689); the
  other decisions, not mentioned there, stand as decided, as ADR-0093's did (photolib-design#686).
* **Requirements**: F-01, F-02, R-REL-2; feature PRIV-25. **Design**: 09 §1, §2.1, §12.

## Context

Design 09 lets only weights licensed for redistribution and commercial use be defaults; non-commercial, research-only
and custom-licensed weights (InsightFace, nllb-clip, MobileCLIP…) are bring-your-own, never shipped or downloaded
automatically, and CI enforces it (§12.1). Models download on first use, verified by SHA-256 against a signed
manifest, and air-gapped servers import bundles (§12.2). Licences move (MobileCLIP turned research-only in 2025), and
the classic trap is a repository whose code is MIT while its weights are not. No project mirror or signing key exists
yet.

## Decision

* **One registry, compiled in.** `server/crates/photolib-models/registry.json` lists every model by `id@revision`
  with its task, licence (SPDX id, attribution, source at a commit, training-data caveat) and files (SHA-256, size,
  targets, URLs at a commit). photolibd embeds it; the apps will read the same file (M5-03). A model is never
  downloaded unless it is listed there.
* **The licence gate is a test.** `cargo test` fails unless every entry is permissive (Apache-2.0, MIT, BSD, CC0,
  ISC) or attribution-licensed (CC-BY, with its notice), pinned and well-formed. An SPDX id it does not know counts as
  restricted, and the families design 09 §2.1 excludes are refused by name whatever licence an entry records.
  Copyleft and restricted weights enter only as bring-your-own.
* **No signed manifest yet.** The registry is as trusted as the binary it is compiled into; each file is trusted by
  its SHA-256. A separately signed manifest (design 09 P2) comes when models must change without a release.
* **Downloads are explicit.** `photolibd models fetch [<id>...]` downloads the server's files from each file's URLs
  in order (Hugging Face and GitHub at a commit until a project mirror exists; the next after 30 s without data),
  keeps only what matches its pin and installs it under `<data_dir>/models/<id>@<revision>/`, so revisions coexist
  for migrations (R-REL-2). The [privacy manifest](../admin/privacy.md) lists these hosts.
* **A bundle is a tar of store directories**, `<id>@<revision>/manifest.json` and files, so a tar of a connected
  store is a bundle. `photolibd models import` checks registry models against the registry, whatever their manifest
  says; any other model is bring-your-own and refused, with a warning naming its licence, until
  `--accept-licence <SPDX>` accepts it. Nothing is installed unless the whole bundle checks out.

## Consequences

* Adding or bumping a model is a registry change with its licence page re-read by its author; the gate catches a
  wrong class, not a wrong SPDX id, so the excluded list grows with design 09 §2.1.
* The server's `ml` role (M5-02) fetches on first use through the same `Store::fetch`; until then only the command
  downloads. The apps' consented, resumable downloads, served by the user's server, are M5-03's; they never fetch
  bring-your-own models.
* Accepting a bring-your-own licence is not yet an audit event: the command has no actor. The admin API that imports
  models adds one.
* A project mirror and a signing key are owner decisions; adding them prepends a URL and verifies a signature.

## Options considered

* **A signed manifest fetched at runtime now**: updates without a release, but needs a key, a host and rotation
  before any model ships, and the binary still has to pin the key.
* **Recording the licence class in the registry** (design 09's `class` field): a second, contradictable claim; the
  class follows from the SPDX id.
* **Download on first use now**: no consumer runs models yet, and an explicit command keeps "no silent model
  downloads" (PRIV-25) trivially true until the `ml` role and its configuration exist.
* **A bundle format of its own** (an index plus blobs): needs an export command; a tar of the store needs none.
