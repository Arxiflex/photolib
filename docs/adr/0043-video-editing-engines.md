# ADR-0043 — Video engines: OS frameworks on phones and Apple, LGPL FFmpeg on desktops, the server for the web

* **Status**: Accepted — 2026-10-17. The owner answered M0-35's provisional choices in
  photolib-design#338:
  no executor in the browser in 1.0 and the pinned LGPL FFmpeg as a test tool stand (confirmed; the script now refuses
  a GPL FFmpeg on `PATH`); kept HDR and Linux's H.264 follow the owner's orders below instead of AV1 and a built-in
  OpenH264.
* **Requirements**: F-04, F-18. **Design**: 11 §6, research §4,
  [ADR-0013](0013-licence.md).

## Context

The video editor (M8-09, M8-10) trims, losslessly at keyframes, and merges clips of different size, rotation, rate,
colour and audio on six targets and the server, keeping rotation, HDR and the capture metadata. Design 11 §6.4 named
an engine per platform; the spike built prototype executors for one shared edit decision list and ran what this Linux
machine can run ([report](../dev/video-engines.md)):

* **FFmpeg**, with a pinned LGPL 8.1 build: a keyframe trim is packet for packet the source and keeps the rotation and
  capture metadata; a merge of landscape, portrait, silent and HLG clips comes out upright, pillarboxed, 30 fps,
  BT.709, with silence and the first clip's metadata, at VMAF ≥ 93; two HLG clips stay 10-bit HLG. The LGPL build has
  no 10-bit HEVC software encoder (kvazaar is 8-bit, x265 is GPL), so that HLG output is AV1.
* **Media3** 1.11.1: the executor compiles in an APK; no device or emulator was available to run it.
* **AVFoundation**: the executor is written but not compiled; there is no macOS machine here.
* **WebCodecs**, Chrome 155 and Firefox 158 headless on Linux without a GPU: neither decodes HEVC (iPhone video) nor
  encodes AAC, Firefox has no H.264 without its OpenH264 plugin, and Chrome encodes no 10-bit AV1.

## Decision

We will plan once and execute per platform. One deterministic planner turns the edit decision list into a plan:
remux from the keyframe at or before the cut, or transcode under the merge rules of 11 §6.3, with the first clip's
capture time, location, make and model and never a pairing identifier. Executors only run plans. The planner is Dart
in the prototype (`app/packages/photolib_video`) and moves into the kernel with the EDL message (M8-01), so the
server runs the same rules. It also picks the codec and where a transcode runs, from the capabilities each device of
the library declares (design 04 §3: `video.encode.h264`, `video.encode.hevc10`, `video.encode.x265`,
`video.encode.av1`, `video.play.av1`) and whether the server or a trusted node can run it.

| Target | Engine | Notes |
|---|---|---|
| Android | Media3 Transformer | trims transmux (`setStartsAtKeyFrame`); merges are a `Composition` with `Presentation`, a forced audio track and an HDR mode; the muxer's metadata provider writes the plan's tags |
| iOS, macOS | AVFoundation | trims are passthrough exports; merges are an `AVMutableComposition` with a video composition whose colour properties keep HDR or tone-map it; no FFmpeg (ADR-0013) |
| Windows | LGPL FFmpeg | Media Foundation encoders (`h264_mf`, `hevc_mf`): Microsoft's licensed encoders, also without a GPU |
| Linux | LGPL FFmpeg | VA-API or NVENC, then OpenH264 (the system's libopenh264, or Cisco's binary downloaded at run time as Firefox does), then the server or the trusted node; Fedora strips H.264 and HEVC from Mesa's VA-API, so AMD there falls back |
| Server, trusted node | FFmpeg | the CLI in the sandboxed media worker; a GPL build with x264 and x265 is allowed there |
| Web | none in the browser | standard libraries send the EDL to the server; private libraries edit in the desktop app or on the trusted node |

OpenH264 is never compiled into our build, since Cisco's patent licence covers only Cisco's binaries: FFmpeg starts
without it, and Cisco's download is an outbound connection of the [privacy manifest](../admin/privacy.md), which the
app asks the user for first, like every connection there (the owner is asked to confirm this reading of "as Firefox
does"). Executors choose among their encoders by a one-frame test, as FFmpeg lists hardware encoders whether or not a
device exists.

A transcode that keeps HDR (11 §6.3) is encoded, in order, by:

1. a hardware 10-bit HEVC encoder;
2. the server (x265) for standard libraries, the trusted node for private ones;
3. on Linux, libx265 in an FFmpeg the user installed, run as a separate process (we do not distribute it);
4. 10-bit AV1 only when every device of the library declares AV1 playback;
5. otherwise tone-mapped SDR, and the user is told.

AV1 alone does not play on iPhones before the 15 Pro or Macs before M3. An SDR transcode is H.264 on the device, else
on the server or the trusted node.

Every executor runs the same fixtures (`testdata/edl/`) through one conformance suite, against FFmpeg's lossless
reference render of the same plan: duration ± 1 frame, A/V sync ± 20 ms, VMAF ≥ 93, colour and HDR tags, rotation,
metadata, no pairing identifier, and keyframe trims packet for packet. Until we build our own FFmpeg (ADR-0013), the
gate runs a pinned BtbN LGPL build (`tools/video/ffmpeg.sh`), a test tool that never ships; elsewhere it takes the
FFmpeg on `PATH` and refuses one built with `--enable-gpl`.

## Consequences

* One planner and one suite: the executors stay small, and a platform that drifts fails the same fixtures.
* A merge keeps HDR wherever a hardware HEVC encoder, the server or a trusted node exists; a standalone Linux desktop
  without them needs the user's libx265 or AV1 that every device plays, else the user gets SDR and a notice.
* A Linux desktop without VA-API, NVENC or the system's libopenh264 needs Cisco's download or a remote render for SDR.
* VA-API and NVENC are untested here (no GPU); M8-09 runs them on real machines.
* To verify on devices with M8-09: Media3's `FrameDropEffect` only drops frames, so a 25 fps clip may stay 25 fps in a
  30 fps merge; `AVAssetExportSession` writes the export time into `mvhd` (the capture time goes into
  `com.apple.quicktime.creationdate`) and chooses its own AAC settings, so exact 48 kHz stereo needs `AVAssetWriter`.
* Follow-ups: the planner in the kernel (M8-01, M8-09); lossless trims (keyframe and edit-list) as a remuxer in the
  kernel, packets copied, no codecs or patents, on every target (browser and private libraries included) and writing
  the plan's metadata (M8-09); the devices' declared capabilities, Cisco's OpenH264 download and the user's FFmpeg
  (M8-09); the server's executor in its media worker; our reproducible LGPL FFmpeg build; same-parameter merges by
  remux (M8-10).

## Options considered

* **FFmpeg everywhere** (ffmpeg-kit forks): their flagship builds are GPL, the vendor's binaries vanished once, and
  phones would carry codec patents that MediaCodec and VideoToolbox already license; ADR-0013 rules it out.
* **WebCodecs with Mediabunny (MPL-2.0) in the browser** for private libraries: iPhone HEVC cannot be decoded and AAC
  cannot be encoded in Chrome or Firefox on Linux. Chrome on Windows and macOS decodes HEVC through the GPU and Safari
  natively, so revisit when M8-09 runs on real machines.
* **Kept HDR always in AV1** (the provisional choice): iPhones before the 15 Pro and Macs before M3 cannot play it.
* **OpenH264 built into our FFmpeg** (the provisional fallback): Cisco's patent licence covers only Cisco's binaries.
* **pro_video_editor** (BSD-3, Media3 and AVFoundation): broad features under its own edit model, without control of
  the plan's metadata and HDR policy; a reference for M8-09, not evaluated in code here.
* **GStreamer editing services on Linux, `MediaComposition` on Windows**: a second engine to maintain, while FFmpeg
  is needed anyway for desktop playback and the server.
