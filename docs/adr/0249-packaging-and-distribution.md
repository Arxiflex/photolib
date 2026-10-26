# ADR-0249 — Packaging and distribution: a package per channel, one version, photolibd with its own PostgreSQL

* **Status**: Accepted — 2026-10-23. The owner kept every decision
  (photolib-design#695,
  roadmap M10-04; open decision 20): its package names and identifiers are placeholders, renamed once the name is
  final.
* **Requirements**: R-REL-3; features `OPS-14`, `OPS-16`, `MOB-23`, `DSK-05`, `DSK-06`. **Design**:
  15 §8, §9,
  10 §8.2,
  03 §10,
  open decisions.

## Context

1.0 ships through Google Play, the App Store, F-Droid, signed MSIX with winget, a notarised DMG with Homebrew,
Flatpak, AppImage and deb, a Helm chart and NAS app stores, and every channel must install and upgrade cleanly in a
release-candidate dry run. Only the image, compose (ADR-0096) and unsigned smoke builds of the desktop packages
(ADR-0154) existed. Desktop users who want the server without Docker had nothing (open decision 20).

## Decision

1. **A package per channel, from one script.** `tools/package.sh` builds each: `apk` (the libre flavour per ABI,
   scanned for proprietary services and 16 KB pages: F-Droid, GitHub), `aab` (the play flavour: Google Play), `ipa`
   (App Store), `dmg` with its Homebrew cask, `msix` with its winget manifests, `appimage`, `deb` (the Linux bundle in
   `/opt/photolib`) and `photolibd` (the server's deb). Without a release's keys every package is unsigned or
   debug-signed, as the smoke builds are.
2. **Signing with the release's keys, never a person's.** Android signs with the upload key `ANDROID_KEYSTORE` names;
   the DMG with the Developer ID `APPLE_SIGNING_IDENTITY` names, for the hardened runtime with the app's sandbox
   entitlements, then notarised and stapled; the MSIX by certificate thumbprint, so its key stays on a token or HSM,
   as the publisher `MSIX_PUBLISHER` names; the App Store archive by Xcode's automatic signing.
3. **One version.** `app/pubspec.yaml`'s version is the release of every channel: the chart, the NAS entries, the
   AppStream metadata and F-Droid's recipe carry it, and the tests hold them to it.
4. **Listings in every launched language** in the app's Android module (Triple-T: Google Play and F-Droid read it),
   and the same words in the AppStream metadata of the Linux packages. F-Droid builds the kernel from source and
   publishes our signed APK when its build matches.
5. **Servers.** The Helm chart runs a Deployment per photolibd process against a PostgreSQL of the user's, and
   `photolibd migrate` in a pre-upgrade Job; a first install's pod migrates itself, as photolibd always does. The NAS
   entries run the release's image beside the compose bundle's pinned PostgreSQL, non-root on read-only roots.
6. **photolibd with its own PostgreSQL (decision 20).** With `database.cluster`, photolibd creates and runs a
   PostgreSQL cluster from the system's programs, reached only on a Unix socket in its `0700` directory, and stops it
   when it stops. The `photolibd` deb runs it as a systemd service (`DynamicUser`, state in `/var/lib/photolib`) with
   the distribution's PostgreSQL, libvips, FFmpeg and ExifTool: the server on a Linux desktop or a small box, no
   Docker.
7. **The dry run.** [Releasing](../dev/releasing.md) lists each channel's install and upgrade check. The gate runs
   what Linux can: the debs installed, upgraded and removed by dpkg, the chart linted and rendered by the pinned Helm,
   the NAS entries through `docker compose config`, the AppStream metadata through `appstreamcli`, the AppImage
   started.

## Consequences

* Package names and identifiers (`org.photolib.photolib`, winget's `Photolib.Photolib`, the `photolib` cask, deb and
  NAS ids, the MSIX's `CN=Photolib`) are placeholders until the name is final; renaming them is one change across
  `tools/package.sh`, `deploy/` and the app's platform folders.
* Publishing stays outside the repository and needs the owner's accounts and keys: Play Console, App Store Connect,
  the Apple Developer ID and notary credentials, a Windows code-signing certificate, the Android upload key, and
  submissions to F-Droid, winget-pkgs, Homebrew, Flathub and each NAS store.
* Flatpak, docs/10's first Linux channel, is not built yet: libmpv and its dependencies must be modules built in the
  GNOME SDK, which needs `flatpak-builder` and Flathub's runtimes; AppImage and deb ship until then.
* The appliance mode is Linux only, as photolibd is; a PostgreSQL major upgrade of its cluster is `pg_upgrade` by
  hand, and photolibd refuses a cluster of another major than its programs.
* The Helm chart brings no PostgreSQL, and its scaled form needs storage every node reaches.

## Options considered

* **`postgresql_embedded`**: downloads PostgreSQL's binaries at build or first start, an outbound dependency, and
  leaves pgvector unsolved; the system's packages are updated with the system.
* **An all-in-one image with PostgreSQL supervised inside**: still Docker; ADR-0096 declined it.
* **A deb whose maintainer scripts configure the distribution's PostgreSQL cluster**: root scripts and a shared
  cluster to upgrade; photolibd's own cluster needs no script.
* **Bitnami's PostgreSQL chart as a dependency**: an outside chart and images that changed their terms in 2025.
* **Store listings in English only**: AGENTS.md wants every launched language for store listings.
