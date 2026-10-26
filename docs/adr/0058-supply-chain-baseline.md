# ADR-0058 — Supply-chain baseline: lock-file SBOMs, keyless cosign signatures, air-gapped test suites

* **Status**: Accepted — 2026-10-17. The owner answered M0-29's provisional choices in
  photolib-design#367
  (whose questions call this ADR 0040): keyless signing stays, never with a personal identity (1); Sigstore's public
  instance is accepted (2); the preloaded library stays (3); the setting names stay, every connection off by default,
  with the master switch `outbound: none` (4).
  The owner kept photolib-design#400's two choices in
  photolib-design#588
  (2026-10-21): only a `pkcs11:` URI signs outside CI, and the master switch is `outbound: none` or unset.
  Amended — 2026-10-24 by the owner in
  photolib-design#799: a RustSec advisory warns in
  the gate's log, never fails it (decision 3).
* **Requirements**: R-SEC-1, NFR-SEC-2, NFR-PRIV-1, OPS-25. **Design**: 06 §2 and §10,
  19 §1.

## Context

Releases must carry SBOMs and signatures, every outbound path must be tested with egress blocked, and the gate is the
only check before a merge. The one release pipeline today publishes the kernel's prebuilt libraries; container images
arrive with M2-30. The gate also runs in containers without user namespaces or a Docker daemon, where a test cannot
get a network namespace of its own.

## Decision

We will:

1. Write CycloneDX 1.6 SBOMs from lock files with the stdlib `tools/sbom.py`: every third-party package a
   `Cargo.lock`, `pubspec.lock` or `package-lock.json` pins, with its package URL and pinned hash, reproducible with
   `SOURCE_DATE_EPOCH`.
2. Sign releases keylessly: `tools/release.sh` puts the SBOM and every file into `SHA256SUMS`, and cosign signs it with
   the release job's GitHub OIDC identity through Sigstore's public instance (Fulcio and Rekor). The bundle
   `SHA256SUMS.sigstore.json` is attached; there is no long-lived signing key. The release job runs in CI once
   distribution starts. Never with a personal identity: outside CI cosign falls back to an interactive login, which
   writes that account's e-mail into Sigstore's public log for good, so a release signed outside CI uses a
   hardware-held key (`COSIGN_KEY`, a `pkcs11:` URI) and `tools/release.sh` refuses anything else. cosign covers
   server images, kernel libraries, the CLI, Linux packages and SBOMs; app stores sign their own packages.
3. Audit dependencies with `cargo deny` in the gate and Renovate's OSV alerts in every ecosystem. Bans, licences and
   sources fail the gate; an advisory (a yanked crate too) is a warning, as one is published against a locked crate
   whatever a branch changed: RUSTSEC-2026-0382 and RUSTSEC-2026-0387 each held the merge train for hours, the second
   with no release of `opaque-ke` that lifts it. No `ignore` entry in `deny.toml` hides one: each stays in every gate's
   log, and its fix is a task of its own.
4. Block egress for `cargo test`, `flutter test` and `npm test` with `tools/offline.sh`, a preloaded library that
   fails connections and datagrams to anything but loopback, DNS, and lookups of names other than `localhost`. cargo,
   rustc and dart, which fetch pinned dependencies, are exempt. On the gate's machine `unshare -rn` fails (`uid_map`:
   operation not permitted) and no Docker daemon runs, so a network namespace is not available there.
5. Keep the privacy manifest (`docs/admin/privacy.md`) true with `tools/tests/check_outbound.py`, which compares it with
   the hosts and periodic timers in product code. Every connection is off by default (`updates.check`,
   `maps.upstream`, `ml.download`, `places.download`, `push.relay`); photolibd's first-run setup, and the apps on first
   use, ask once per connection, naming the host it contacts. `outbound: none` in photolibd's configuration turns
   every connection off and wins over the individual switches, for air-gapped installs; `photolibd models fetch`
   refuses under it. The check fails a run-time row that is not off by default, and a manifest without the switch.

## Consequences

* Anyone can verify a release with cosign alone, offline from the attached bundle, and the signature names the
  workflow and tag that built it. Signing needs Sigstore's public instance at release time: a third-party service that
  sees the release's checksum file and workflow identity, never user data. A release signed outside CI is verified
  with the hardware key's published public key instead.
* The gate needs Linux and `cc`. The preloaded library guards tests against accidental egress; it is not a security
  boundary, since static binaries and raw system calls bypass it. The browser suites of the `web` part are not
  blocked: their first run downloads toolchains.
* A known-vulnerable crate can merge and stay until its fix lands: the gate's warnings and Renovate's alerts raise it,
  nothing blocks on it.
* A lock-file SBOM lists every package the lock pins, including development and other-target dependencies.
* Follow-ups: images signed with `cosign sign` and their SBOMs attached with `cosign attest` (M2-30), SLSA provenance,
  and an advisory scan of pub and npm packages in the gate (osv-scanner sends package lists to osv.dev, so it needs
  its own decision).

## Options considered

* **syft or cdxgen for SBOMs**: they also read images and binaries, which M2-30 needs, but add a downloaded tool to
  every gate run for what three lock-file readers do.
* **A signing key in GitHub secrets or hardware**: no third-party service, but a long-lived key to guard, rotate and
  publish, and a signature that does not say which workflow made it.
* **GitHub artifact attestations**: also Sigstore, but verified through GitHub's API and tied to it.
* **A network namespace** (`unshare -rn`, `docker run --network none`): real isolation, but unavailable where the
  gate runs without user namespaces or Docker; blocking egress in CI only would leave the gate unchecked.
* **In-process overrides** (Dart's `HttpOverrides`): cover one language, and not sockets opened outside `HttpClient`.
