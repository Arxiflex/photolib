# ADR-0394 — The macOS desktop app builds from a fresh checkout and runs with its network, libvips and orientation

* **Status**: **Proposed — owner to confirm**. Found by building and running `dev` on a Mac; amends
  [ADR-0026](0026-kernel-prebuilt-libraries.md) (the build hook may run `tools/kernel/build.py`).
* **Requirements**: R-APP-1, R-APP-3, F-12. **Design**: [ADR-0026](0026-kernel-prebuilt-libraries.md),
  [ADR-0071](0071-desktop-folders-in-the-app.md), [ADR-0107](0107-desktop-and-web-thumbnail-decoders.md),
  [ADR-0278](0278-on-device-ml-in-production.md), [ADR-0389](0389-face-detection-and-embeddings.md),
  [ADR-0390](0390-hdr-handling.md).

## Context

Four things failed on a real Mac, one after the other:

1. `flutter build macos` failed on a fresh checkout: no `kernel-v*` release is published, the package's `prebuilt.json`
   pins nothing, and `app/build/kernel/` (the user-define of ADR-0026) did not exist. A release build is universal, so
   both `macos-arm64` and `macos-x64` were needed. Rust was installed but not on `PATH`, and a build hook's environment
   is filtered anyway.
2. The sandboxed app had `app-sandbox` and no outbound network entitlement: map tiles and model downloads were blocked.
3. Settings > Faces showed nothing and face finding never started. On desktops `mlHost()` is null unless
   `vipsLibrary()` finds libvips (`Contents/Frameworks/libvips.42.dylib`, else the bare name on the default library
   path); the app did not bundle it, Homebrew's copy is not on a Finder-launched app's path, and nothing said so.
4. HDR photos showed rotated: `HdrLeaf.swift` decodes with `CGImageSourceCreateImageAtIndex`, which ignores the EXIF
   orientation, while the SDR thumbnails (`kCGImageSourceCreateThumbnailWithTransform`) are upright.

## Decision

1. **Kernel**: when `hooks.user_defines.photolib_kernel.artifacts` names a directory whose `prebuilt.json` lacks the
   target's library and pins no release, the build hook runs `tools/kernel/build.py --out <dir> <target>` for that one
   target (the macOS build asks per architecture, so a release build is universal) and re-reads the manifest; if that
   fails the build stops with one message holding the exact command. `build.py` finds cargo itself: on `PATH`, else
   `$CARGO_HOME/bin` (`~/.cargo/bin`), else the toolchain `rust-toolchain.toml` pins under `~/.rustup/toolchains`. A
   pinned release is never replaced by a local build, and the hook still verifies the SHA-256 it pins.
2. **Entitlements**: `com.apple.security.network.client` in `Release.entitlements` and `DebugProfile.entitlements`
   (`tools/tests/test_macos_entitlements.sh`). Nothing else is added: `network.server` stays in the debug profile only
   (the Flutter debug service), and iOS has no sandbox entitlement to extend.
3. **libvips**: a Run Script phase of the Runner target (after Flutter embeds its frameworks) runs
   `tools/macos/bundle_vips.py`. Per architecture of the app's executable it takes Homebrew's libvips (`/opt/homebrew`
   for arm64, `/usr/local` for x86_64), walks every non-system dependency, adds the HEIF and JPEG XL modules (in
   `Frameworks/vips-modules`, which the app names in `VIPS_MODULEDIR` before `vips_init`), rewrites install names to
   `@loader_path`, removes RPATHs, joins the architectures with `lipo`, and signs each library and then the app ad hoc
   with the entitlements. Release and profile builds fail with `brew install vips` when there is no libvips; debug builds
   warn; `SKIP_VIPS_BUNDLE=1` skips it. An architecture without a Homebrew libvips is left out with a warning
   naming it. The app says so when the library is missing anyway: a `noDecoder` phase gives Settings > Faces and the
   search line a status ("the image library (libvips) was not found") instead of hiding them.
4. **HDR orientation**: `decodeUpright` in both `HdrLeaf.swift` files sends a photo whose orientation is not 1 through
   `CGImageSourceCreateThumbnailAtIndex` with the transform flag and the full pixel size, keeping `DecodeToHDR`;
   upright photos keep the old call. `tools/tests/test_hdr_orientation.sh` reads both copies as text, and
   `tools/macos/verify_hdr_orientation.swift` measures it on a Mac.

## Consequences

* A fresh `flutter build macos --release` needs Rust (rustup) and Homebrew's `vips`, and no manual step; the first
  build compiles the kernel twice (a few minutes). Where a release is pinned the hook downloads as before.
* The app grows by libvips and its dependencies: 67 libraries took it from about 112 MB to 142 MB on arm64 (the HEIF and
  JPEG XL modules add a few more; a universal app carries both slices).
* On a GitHub macOS runner Homebrew exists; the build needs `brew install vips` first, and an arm64 runner has no
  x86_64 Homebrew, so its universal app has libvips for arm64 only and warns. `tools/package.sh` signs the app for
  release afterwards (`--deep`, Developer ID, hardened runtime), replacing the ad hoc signatures.
* Windows and Linux packages were checked for the same gap; see the pull request.
* Not decided here: a `kernel-v*` release (which makes the local build unnecessary), the info-panel map (`MapSlot`)
  and people search.

## Options considered

* **A Run Script phase that builds the kernel**: runs per Xcode build and knows nothing of the other platforms; the hook
  already knows the target and the manifest.
* **Failing with the command only**: honest but a manual step on every fresh checkout; kept as the failure message.
* **Bundling libvips from source or a pinned archive**: reproducible, but a build farm for 67 libraries; Homebrew's
  copy is what the owner verified.
* **`DYLD_FALLBACK_LIBRARY_PATH` to `/opt/homebrew/lib`**: works on this Mac only and is lost under the sandbox.
