# ADR-0146 — Panoramas and 360° video: one shader, projected where the frames are, without native renderers

* **Status**: Accepted — 2026-10-21. The owner kept one shader over the player's texture on every platform, libmpv's
  `v360` on Linux and Windows, without native renderers (the test phase shows whether poles or cubemaps fall short),
  and changed how a sphere pages: a 360° view entered by a button instead of Previous and Next buttons
  (photolib-design#556,
  roadmap M1-13). On 2026-10-23 the owner kept how that answer was read, the keys paging in the 360° view too
  (photolib-design#658).
* **Requirements**: R-APP-5. **Design**: docs/10 §4.4, docs/08 §7,
  [ADR-0112](0112-video-and-motion-photo-playback.md).

## Context

M1-13 shows photo spheres and 360° videos projected on every target, never flat, with the same gestures, gyroscope,
little planet and compass lock everywhere, and a golden frame per corpus 360° video that every target matches. Design
10 §4.4 projects video natively: ExoPlayer's spherical surface, a Metal view fed by `AVPlayerItemVideoOutput`, D3D11
and HLSL, libmpv's render API with GLSL and WebGL, as a Flutter `Texture` cannot be sampled by a fragment shader. None
of the native code could be built or tested where the gate runs, and it would be five copies of one ray-caster. What
we found: under Impeller a snapshot of a platform texture (`toImage`) is blank; media_kit_video renders libmpv in
software under Impeller, so libmpv runs no GLSL; Impeller's `ImageFilter.shader` does sample a player's texture, but
its input is only what the viewport holds; browser widget tests create no platform view.

## Decision

We will:

* **Decide from metadata**: extraction keeps the kernel's projection, GPano crop and stereo packing in `local_asset`
  (schema 12); Insta360's dual fisheyes stay flat, and so does anything else: no flat item can be seen as a panorama
  (owner, 2026-10-20, M1-40).
* **Ray-cast in one shader**, `app/shaders/sphere.frag`, in FFmpeg v360's axes: equirectangular pictures and GPano
  crops, 3 × 2 cubemaps, one eye of a top-bottom or side-by-side stereo frame, through a rectilinear or stereographic
  (little planet) lens, filtered by hand, bilinear and wrapping round the sphere so that no seam shows. `SphereView`
  (yaw, pitch, field of view) is the one view state: drags, pinches, the wheel and the keys move it, clamped so that a
  partial panorama never shows black, and a photo's halvings give its levels of detail.
* **Page past a sphere as past any photo** (the owner's answer, Google Photos' pattern): shown projected, a photo
  sphere or 360° video pages like any other item until a button enters its 360° view (the viewer bar's *360° view*,
  `v`). In its 360° view drags turn it and the pager is locked: swipes, edge taps, side drags, swiping it away and a
  mouse's drag out of its file wait until the same button leaves it, which unlocks the pager. Keys and the filmstrip
  still turn the page, which leaves the 360° view, for now: the viewer's interface is revisited later. Its other
  commands (little planet, gyroscope, zoom keys) work in or out of it, as the answer locks only drags and the pager.
* **Project video where its frames are, from that state**: libmpv (Linux, Windows) through FFmpeg's `v360` filter at
  the viewport's size; players of textures (ExoPlayer, AVPlayer) through the same shader as Impeller's
  `ImageFilter.shader` over the player's own view, laid out so that the viewport holds the part of the frame in view;
  the browser from its `<video>` element's frames, which `BrowserPlayers` keeps and copies into the shader. A target
  that can do neither says the video cannot play, over its projected poster.
* **Turn with the device** from sensors_plus' raw gyroscope, accelerometer and magnetometer through a complementary
  filter (`Attitude`): the gyroscope at once, gravity for the pitch, with the compass lock the magnetic field for the
  yaw. The gyroscope's bias is the mean of its readings while the device is still, when the view rests; gravity draws
  up at most 1° a second, so that a push is no turn; each sensor's first readings, and the time the app is away or a
  route covers the viewer, count for nothing (M1-54).
* **Hold every renderer to FFmpeg's**: each corpus 360° video's twin has a golden frame, what `v360` shows at a fixed
  yaw, pitch, field of view and time; the shader on the VM, libmpv and the shader filter on Linux's screen under Xvfb,
  and Chrome's `<video>` path must be within a mean of 4/255 of it.

## Consequences

* No Kotlin, Swift or C++ projects anything: Android, iOS and macOS run the shader the gate runs on Linux's Impeller,
  and Windows the libmpv path Linux runs; `tools/smoke.sh` holds them to the golden frames (ADR-0190).
* The filter's input is the viewport's pixels, into which ADR-0190 packs only the cells in view.
* Video is SDR through Flutter; an HDR 360° video is tone-mapped. Windows plays through the LGPL libmpv we build
  (ADR-0229).
* The Linux app's 4K 360° playback is decoded and projected in software; the perf budget `sphere-video` holds it to
  30 fps on the GPU-less gate since M1-41 had libmpv render each frame at its time. No libmpv option depends on the GL
  renderer: a software one keeps libmpv's defaults, as its GL scalers are not on Linux's path and cheaper conversion
  gained no frames (owner, 2026-10-23,
  photolib-design#662).

## Options considered

* **Previous and Next buttons at a sphere's sides** while the controls show, its drags always turning it: no mode, but
  a phone could not swipe past a sphere; the owner chose the 360° view.
* **Edge swipes** to page past a sphere: Android's back gesture takes them.
* **Native renderers per design 10 §4.4**: five implementations of one ray-caster, none buildable or testable in the
  gate; a later item can replace the filter where it falls short.
* **Snapshots of the player's texture into the shader**: blank under Impeller.
* **libmpv's GLSL user shaders**: media_kit_video renders libmpv in software under Impeller.
* **Sphere-mesh packages**: no mipmaps, texture-size failures (docs/08 §7).
