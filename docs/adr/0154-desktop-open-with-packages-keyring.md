# ADR-0154 — Desktop integration: open with Photolib, packaging smoke builds, a keyring fallback

* **Status**: Accepted — 2026-10-21. The owner kept every decision
  (photolib-design#553,
  roadmap M1-20): the passphrase fallback, the AppImage smoke build, the unsigned MSIX with its placeholder publisher
  until the owner's certificate exists (M10-04), and Photolib offered as an alternative viewer, never the default.
* **Requirements**: R-MODE-1. **Design**: docs/10 §8.2.

## Context

docs/10 §8.2 asks for open-with and file associations on the three desktops, and M1-20 for smoke builds of the
packages that M10-04 ships signed (MSIX, DMG, AppImage or Flatpak). The app ignored the files it was started with, no
desktop knew it opens photos and videos, and nothing built a package. Its keyrings hold the store's keystore keys
(ADR-0057) with "a passphrase-wrapped fallback when no secret service runs"; without one the Linux app could not open
its store.

## Decision

* **Open with**: every desktop offers Photolib for the file types the library indexes (`mediaExtensions`), never as
  their default: Linux through the desktop entry's `MimeType` (`app/linux/packaging/org.photolib.photolib.desktop`,
  `Exec=photolib %U`, URIs for its `photolib:` links too, ADR-0243), macOS through `CFBundleDocumentTypes`
  (`public.image`, `public.movie`, rank *Alternate*), Windows through the MSIX package's file type association
  (`app/windows/packaging/AppxManifest.xml`). Linux and Windows start the app with the paths (on Linux also `file:`
  URIs), which `main` hands to the app, or a later start to the running one (ADR-0206); macOS's Finder sends them to
  `FileDrag.swift`, which keeps them until Dart asks (`opened`) and later sends them as a drop. They are taken as a
  drop is (ADR-0144): folders join the library, photos and videos open in the viewer over those files alone.
* **Packages**: `tools/package.sh` builds each desktop's package from a release build, unsigned, after its smoke test
  (`tools/smoke.sh`, twice a day on `main`): an AppImage by appimagetool and AppImage's runtime (fetched, SHA-256
  pinned), started under `xvfb-run` and failing unless it stays up and takes a later start's photo (ADR-0206); a DMG
  by `hdiutil`, verified, and refused unless the app's signature grants the App Sandbox and folder bookmarks
  (ADR-0071); an MSIX by the Windows SDK's `makeappx`, from `AppxManifest.xml` with the pubspec's version.
  AppImage first: it builds offline from the bundle, where Flatpak needs its SDK runtime from Flathub.
* **Keyring fallback**: on Linux the keystore is the Secret Service unless it fails, for another reason than a
  locked keyring, as the store makes its first key; then, until M1-24, it is `PassphraseKeystore`: the keystore keys'
  32 bytes each, in one PLB envelope (kind 11) under `KEK_pass` of a passphrase, stretched with device parameters
  (64 MiB, passes calibrated to 250 ms, at least 3) kept before it in the store's `keystore` file. The user chooses
  it once, at least 10 characters (docs/21 §7 without hardware binding), and gives it at every start; a wrong one is
  asked again. Crypto-erase deletes the file with the store.

## Consequences

* One Photolib runs over the store: a later start on Linux or Windows hands its files to the running app and ends
  (ADR-0206).
* An unpackaged Windows build has no associations; only the MSIX does.
* A copy of the `keystore` file is open to offline guessing at Argon2id's cost; a keyring that appears later is not
  used until M1-24 moves the keys into it (the owner's answer). A store whose keys the Secret Service holds does not
  open while it is away. The app passcode (M1-24) will be another factor of the lockbox itself.
* Signing, notarisation, the MSIX's publisher, Flatpak and the stores stay with M10-04; the MSIX's `CN=Photolib`
  publisher is a placeholder that signing replaces.

## Options considered

* **Registry entries written by the app** on Windows: the MSIX package declares them and removes them on uninstall.
* **Flatpak as the Linux smoke build**: docs/10 prefers it for release, but its build needs `flatpak-builder` and the
  freedesktop SDK from Flathub; M10-04 adds it.
* **A passcode slot of the lockbox** (factor 2): the design's own factor, but M1-24's, with its policies, back-off and
  the class B key it leaves unsolved; the fallback keeps the vault as it is.
* **A key file without a passphrase**: readable from any copy of the store (ADR-0057).
* **The `msix` pub package**: a dependency of the app for what `makeappx` does from one manifest.
* **Becoming the default viewer**: the system's own viewers and Apple Photos stay the owners; Photolib is offered.
