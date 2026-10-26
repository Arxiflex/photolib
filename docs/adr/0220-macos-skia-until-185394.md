# ADR-0220 — macOS renders with Skia until the pinned Flutter fixes flutter/flutter#185394

* **Status**: Superseded by [ADR-0252](0252-macos-keeps-impeller.md): macOS keeps Impeller (owner,
  photolib-design#584, 2026-10-21).
* **Requirements**: R-APP-5. **Design**: client app §1.1, [ADR-0060](0060-hdr-native-leaf-views.md),
  [ADR-0146](0146-panoramas-and-360-video.md).

## Context

The macOS app crashes on the raster thread when it comes back to the foreground (photolib-design#572): when the frame
size flips A → B → A, the pinned engine's back-buffer cache (`FlutterSurfaceManager.mm`, `removeSurfaceForSize:`)
compares the request with its first surface only and hands Impeller the B surface; its texture invalidates itself and
`Canvas::SetupRenderPass` dereferences the dropped colour attachment (flutter/flutter#185394). The fix,
flutter/flutter#192522, is not in a stable release. The engine still ships its Skia path and honours
`FLTEnableImpeller`.

## Decision

We will set `FLTEnableImpeller` to false in `app/macos/Runner/Info.plist` until the pinned Flutter carries the fix.
`tools/tests/test_macos_impeller.sh` reads the pinned engine's `FlutterSurfaceManager.mm` and fails once its cache
checks the size of the surfaces it keeps or hands out; the key then goes, after the upgrade gate of design 10 D8.

## Consequences

* No raster-thread crash on foregrounding, fullscreen or a display change on macOS.
* The engine enables wide gamut only with Impeller: Display P3 renders as sRGB on macOS meanwhile. HDR is unaffected,
  as the native leaf of ADR-0060 draws it.
* `ImageFilter.shader` is Impeller's: a 360° video on macOS, which AVPlayer plays as a texture, says it cannot play
  over its projected poster (ADR-0146's fallback) meanwhile. Photo spheres and the editor's shaders run on Skia.

## Options considered

* Keep Impeller: every user who hides and shows the app risks the crash.
* Build a patched engine or fork Flutter: hours per build and a fork to keep in step, for a fix upstream is reviewing.
* Project 360° video natively on macOS meanwhile: ADR-0146 keeps projection out of native code, for a stopgap.
