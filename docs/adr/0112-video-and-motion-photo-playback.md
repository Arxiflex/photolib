# ADR-0112 — Video and motion-photo playback: video_player on every target, libmpv on desktops through our adapter

* **Status**: Accepted — 2026-10-20. The owner kept all three decisions of
  photolib-design#492
  (roadmap M1-12): libmpv through media_kit under `MpvPlayers`, which decides open decision 13; no prebuilt libmpv
  (ADR-0013), so Windows videos say they cannot play until M1-39 builds one; motion clips copied on every platform.
* **Requirements**: R-APP-5. **Design**: docs/10 §4.2, §4.3, §14.3,
  docs/08 §2.2, §2.3, [ADR-0013](0013-licence.md), [ADR-0106](0106-photo-viewer.md).

## Context

M1-12 plays videos, Live Photos and motion photos in the viewer. Design 10 §4.2 names the players (ExoPlayer, AVPlayer,
libmpv on Windows and Linux) and leaves the desktop backend open between libmpv (media_kit) and fvp, whose libmdk core
is proprietary. ADR-0013 allows only an LGPL libmpv built in our CI on desktops, never a prebuilt binary, and no
FFmpeg in the mobile apps. Playing the corpus' videos with media_kit on Linux showed four problems: its video_player
adapter waits forever on a file that fails to open; libmpv refuses to start under GTK's number locale; media_kit_video
attaches its output only after a frame, which an idle screen never draws; and libmpv's software renderer, which
media_kit_video uses under Impeller, aborts the app on a turned video (`mp_image_crop` assertion). Its
media_kit_libs_* packages fetch a 2023 prebuilt libmpv (Windows) or mimalloc (Linux) while building.

## Decision

We will:

* **Play through `video_player` on every target**: ExoPlayer by MediaStore URI on Android, AVPlayer on Apple targets
  (PhotoKit's videos by the file PhotoKit keeps, `ViewerChannel` in `ThumbnailChannel.swift`), and libmpv on Windows
  and Linux through `MpvPlayers` (`app/lib/features/viewer/mpv.dart`) over media_kit and media_kit_video. Its
  initialisation fails on a file libmpv cannot open (a missing sound device is no failure), it schedules the frame
  media_kit_video waits for, and libmpv draws the stored picture (`video-rotate=no`) that Flutter turns. A disposed
  player is stopped and kept for the next video, never torn down: media_kit_video's Linux output frees itself while
  GTK idles and the raster thread still point at it, which froze or crashed the app within a few dozen players, and
  media_kit destroys a disposed player on the UI isolate 5 s later. The Linux runner sets `LC_NUMERIC` to `C` after
  GTK starts.
* **Link the system's libmpv on Linux** (`libmpv-dev`), as libvips is, and announce it to media_kit_video ourselves
  (`MEDIA_KIT_LIBS_AVAILABLE`), without media_kit_libs_linux. Windows gets no libmpv until M1-39 builds an LGPL one
  from pinned source tags, reproducibly and pinned by SHA-256; until then its videos say they cannot play.
* **Play a video when it is shown, and never move with a player**: the viewer's `VideoPlayers` makes, plays, pauses,
  rewinds and disposes players one step at a time, only once the viewer's route has opened and its pages rest, so
  neither the opening nor a swipe waits on a player (macOS dragged when they did). The shown video's player comes first,
  then its neighbours', whose first frame slides in with their page; a view shows its poster until its player has a
  first frame, and a player out of reach is disposed after the swipe, once its view has let go of it. Controls: play and
  pause, a seek bar that seeks on every move (the player's own frames are the scrub previews until sprites, M2-10), the
  position to the millisecond, a frame step at the file's frame rate (`local_asset.frame_rate`, schema 12; 1/30 s when
  unknown), mute, loop and speed from 0.25× to 2×; Space, `,`, `.` and `m` on keyboards. A video the player cannot
  open or play says so over its poster.
* **Index a motion photo's video once**: extraction stores the kernel's `motion_video` span in `local_asset` (schema 9,
  whose migration reads motion photos again). While such a photo is shown, the viewer copies those bytes into
  `motion/<item key>.mp4` in the app's cache, which keeps the newest 128 MiB, and plays the copy, its player made by
  `VideoPlayers` too, while the photo is pressed or from the bar's button. A Live Photo from PhotoKit gets its paired
  video written into the same cache. Android copies too, instead of playing the byte range from the file descriptor
  (design 10 §4.3): one path on every platform for a clip of a few megabytes.
* **Prove it on Linux**: `app/integration_test/playback_probe.dart` (`bash tools/video/app_play.sh`, in the gate's
  `dart` part) plays a twin of every corpus video and motion photo, made as the server's video test makes them, with the
  app's players, and checks the size shown and that it plays, then plays 40 players made and disposed in a row;
  `app/benchmark/perf_test.dart` holds the swipes between videos to the frame budget and the next video's first frame to
  design 10 §4.2's local start (500 ms).

## Consequences

* Building and testing the Linux app needs `libmpv-dev`; the workflows install it. media_kit_video's plugin links
  libmpv, so its libraries (about 220 with FFmpeg's) load as the Linux app starts, before the engine's own startup
  time is measured; the Dart side opens libmpv only with the first video.
* Every corpus video and motion photo plays on Linux. Android, iOS, macOS and Windows are not measured here: the probe
  runs by hand on macOS and Windows, and on phones once the smoke runs carry twins.
* Follow-ups: an LGPL libmpv for Windows (M1-39), built by [ADR-0229](0229-windows-libmpv.md); slow-motion ranges,
  once the kernel reads them (M7-06);
  resume position (synced, design 08 §5.8) and picture-in-picture (M7-06); Live Photo pairs of folders and MediaStore,
  whose video shows as an item of its own until pairing (M2-21); iCloud-only PhotoKit videos, which do not download;
  posters of macOS and Windows videos from their players (Linux's come from libmpv); HDR video, which plays as SDR
  (M1-14, M7-03).

## Options considered

* **fvp (libmdk)**: proprietary core, doubtful under the AGPL (design 10 §14.3).
* **media_kit's video_player adapter** (video_player_media_kit): waits forever on a file that fails to open, and
  leaves turned video to the renderer that aborts on it.
* **media_kit on every target**: puts FFmpeg in the mobile apps, against ADR-0013.
* **media_kit_libs_linux and media_kit_libs_windows_video**: fetch mimalloc or a prebuilt libmpv of unknown licence
  while building.
* **Play the byte range in place on Android** (an ExoPlayer `DataSource`): native code for what a copy of a few
  megabytes does on every platform.
* **Find the span when the photo is shown**: a kernel call per view, where design 10 §4.3 indexes it once.
