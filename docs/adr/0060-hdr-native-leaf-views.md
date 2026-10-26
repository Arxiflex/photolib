# ADR-0060 — HDR through native leaf views: Flutter keeps the gestures, the leaf cross-fades in

* **Status**: Accepted — 2026-10-17 (roadmap M0-39). The owner chose to implement M1-14 now and to test and verify the
  leaves on devices later (photolib-design#347), and confirmed on 2026-10-20 that M1-14 is
  built in its roadmap turn and merges on the gate, the device measurements being the test phase's
  (photolib-design#473). No Android 14+ phone, iPhone or Mac was available, so only the
  Linux baseline is measured.
* **Requirements**: R-APP-5, VIEW-20. **Design**: 10 §4.5, 08 §5.7.

## Context

Flutter composites SDR only, so HDR stills and video need native views (10 §4.5), which stutter when they
are created ([Immich D7262](https://github.com/immich-app/immich/discussions/7262)). The spike built one prototype
and a probe for it:

* `HdrLeaf` (`app/lib/features/viewer/hdr_leaf.dart`) keeps the Flutter-drawn SDR frame on top, creates the native
  view after a 150 ms dwell (a fling past an item creates nothing) and fades the SDR frame out over `Motion.short`
  (150 ms, instant under reduce motion, ADR-0037) once the native side reports its first frame; a failure keeps the
  SDR frame. The native view takes no gestures.
* The leaves: Android 14+ draws the `ImageDecoder` bitmap with its gain map in an `ImageView`, or plays video with
  `MediaPlayer` on a `SurfaceView`, with the window in `COLOR_MODE_HDR` while a leaf exists (`HdrLeaf.kt`). iOS 17+
  and macOS 14+ decode stills with ImageIO's `kCGImageSourceDecodeToHDR` (gain maps applied) into a `UIImageView` /
  `NSImageView` that prefers high dynamic range, and play video in an `AVPlayerLayer` (`HdrLeaf.swift`).
* The probe, `app/integration_test/hdr_probe.dart`, opens samples in a minimal pager, pinches, pans when zoomed,
  swipes at 1× and reports frames over 16.7 ms, the worst build and raster times and the process RSS
  ([how to run it](../dev/flutter.md#checks-specific-to-the-app)).

Gesture hand-off follows from how each embedder routes input, read in the engine's sources: Android's hybrid
composition sends touches to Flutter first and to a platform view only when its recognisers win the arena; iOS's
touch-intercepting view does the same; macOS gives pointer events to the view under the cursor, so the leaf declines
hit tests. Each embedder applies the transforms and clips above the view in the frame Flutter draws them.

## Measurements

The Linux row is the SDR path that every platform shows before the native frame: seven `flutter drive --profile` runs
under Xvfb (software GL) on a shared 16-thread x64 machine at load 8–40, with the probe's generated 12 MP still.

| Platform | Jank | Memory | Gestures |
|---|---|---|---|
| Android 14+ | Not measured: no phone, and no emulator without KVM. Hybrid composition merges the raster and platform threads while a leaf exists, which is the risk to measure | Not measured; the leaf caps a decode at 24 MP (100 MB canvas limit), plus the gain map | By design: the leaf has no recognisers, so Flutter wins every gesture; unverified on a device |
| iOS | Not measured: no iPhone | Not measured; an HDR decode is half-float, 8 bytes a pixel (96 MB at 12 MP) | By design, with `isUserInteractionEnabled` off; unverified |
| macOS | Not measured: no Mac | Not measured; half-float as on iOS | The leaf declines hit tests so Flutter gets pointer events; unverified |
| Linux (SDR baseline) | Opening: 0–12 of 29–62 frames over budget, build ≤ 6.6 ms, raster ≤ 39 ms. Gestures: 0–83 of 129–222 frames, build ≤ 7 ms, raster ≤ 56 ms; the misses are software rasterisation on a loaded machine (the run at load 8 missed none) | In the four runs that free the generated still first: RSS 271–304 MB with the item open, at most 3 MB more after the gestures and after leaving it | Pinch to 2.2×, a zoomed pan stays on the item, a swipe at 1× moves to the next, in 7 of 7 runs |

## Decision

**Go** for M1-14, now. M1-14 builds the HDR viewer on `HdrLeaf` as prototyped and merges on the gate, without waiting
for the device numbers:

* Flutter keeps every gesture (zoom, pan, swipe, dismiss) and the leaf follows the engine's transforms; there is one
  gesture model for SDR and HDR items.
* The native view appears only behind a rendered SDR frame, after the dwell, and cross-fades in on its first frame.
* Android uses hybrid composition, and HCPP wherever the engine enables it (the
  `io.flutter.embedding.android.EnableHcpp` opt-in, API 34+, Vulkan, Impeller).

The test phase runs the probe on the device lab's (M10-02) Android 14+ phone, iPhone and HDR Mac with real Ultra HDR,
Apple gain-map, HDR10 and HLG samples and records the rows above; until then they are unverified, not failed. Its
budget is that of 08 §9: entering a native leaf drops no frame. A platform that misses it shows SDR until it
is fixed; on Android, the fix first tries HCPP.

## Consequences

* The prototype is the M1-14 starting point, not a viewer: it has no HDR/SDR toggle, battery-saver rule, tiling,
  poster for video or player controls, and its video players (`MediaPlayer`, plain `AVPlayer`) give way to the
  `media_player` stack of M1-12.
* Apple decodes the whole image in half-float; deep zoom of large HDR images needs subsampled or tiled decodes
  (M1-11), and Android's 24 MP cap is too coarse for 50 MP sensors at full zoom.
* The probe is not in the smoke test: on Linux a second integration file fails to launch in one `flutter test` run,
  whatever it holds, so the test phase runs it by hand.
* As the owner confirmed, *now* builds M1-14 in its turn in the roadmap (after M1-11), not within this decision, and
  *later* is the test phase.

## Options considered

* **Native zoom** (a `UIScrollView`, an Android matrix view) with hand-off back to Flutter's pager at the zoom edges:
  two gesture systems that disagree at exactly the edges users hit, and HDR items would behave unlike SDR ones.
* **Textures** (`AndroidView` in texture-layer mode, a `FlutterTexture`): the SDR compositor drops the headroom,
  which is the washed-out or flat result of [Aves #838](https://github.com/deckerst/aves/issues/838) and
  [Ente #1166](https://github.com/ente/ente/issues/1166).
* **Waiting for Flutter EDR** ([#127520](https://github.com/flutter/flutter/issues/127520), open since 2023), or
  **SDR everywhere**: both leave VIEW-20, a MUST, unmet.
