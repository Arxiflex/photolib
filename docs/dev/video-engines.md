# Video engines spike report (M0-35)

Prototype executors for one shared edit decision list, built and measured on 2026-10-16 on Linux x86-64. The decision
is [ADR-0043](../adr/0043-video-editing-engines.md).

## What was built

* `testdata/edl/`: three edit decision lists in the JSON form of the design's `EditDecisionList`: a trim that starts
  inside a GOP (`trim.json`), a merge of landscape, portrait, silent and HLG clips (`merge.json`) and a merge of two
  HLG clips of different size and rate (`merge-hdr.json`).
* `app/packages/photolib_video`: `Plan.of` turns an EDL and what the executor probed into a plan, a remux from the
  keyframe at or before the cut or a transcode under design 11 §6.3. Three executors run plans behind one `Executor`
  interface: `Ffmpeg` (desktops, server) and, through one method channel, Media3 Transformer (Android) and
  AVFoundation (iOS, macOS).
* `test/ffmpeg_test.dart`: design 11 §9's conformance checks, against FFmpeg's lossless reference render of the same
  plan.

To rerun, `flutter test` in the package (the gate does): it runs the fixtures of `testdata/edl` through the FFmpeg
executor, with sources it generates and the LGPL FFmpeg that `tools/video/ffmpeg.sh` pins on Linux x86-64 (elsewhere an
FFmpeg with libopenh264 and libsvtav1 on `PATH`, refused when built with `--enable-gpl`).

## Executors

| Executor | State | Keyframe trim | Heterogeneous merge | HLG merge |
|---|---|---|---|---|
| FFmpeg | runs: BtbN LGPL n8.1.3 | every video packet identical; rotation, capture time and location kept; pairing id dropped | 320×180, 30 fps CFR, H.264 (OpenH264), BT.709, AAC 48 kHz stereo; portrait clip upright and pillarboxed, HLG clip tone-mapped, silence for the silent clip, first clip's metadata; VMAF 95.9 | 10-bit HLG, BT.2020, in AV1 (SVT-AV1); VMAF 98.2 |
| Media3 | compiles: Media3 1.11.1 in a debug APK, minSdk 30, no warnings | not run: no device or emulator (no KVM) | not run | not run |
| AVFoundation | written, not compiled: no macOS | not run | not run | not run |

Durations are within one frame and audio starts with video (± 20 ms) in every FFmpeg output.

## WebCodecs

`VideoDecoder`, `VideoEncoder` and `AudioEncoder.isConfigSupported` at 1280×720, headless on Linux x86-64:

| Browser | H.264 | HEVC | AV1 8-bit | AV1 10-bit | VP9 10-bit | AAC | Opus |
|---|---|---|---|---|---|---|---|
| Chrome 155 | decode, encode | no | decode, encode | decode | decode, encode | no encoder | encode |
| Firefox 158 | no | no | decode, encode | decode, encode (HLG too) | decode, encode | no encoder | encode |

Codec strings: `avc1.640028`, `avc1.42001f`, `hvc1.1.6.L120.B0`, `hvc1.2.4.L120.B0`, `av01.0.04M.08`, `av01.0.04M.10`,
`vp09.02.10.10`, `mp4a.40.2`, `opus`. Chrome's HEVC needs a hardware decoder this machine lacks; Firefox's H.264
needs the OpenH264 plugin, which a fresh profile does not have. A browser here cannot decode iPhone video or write AAC
in MP4, so no browser executor is proposed.

## Findings

* The LGPL build encodes H.264 only with OpenH264 (8-bit), HEVC only with kvazaar (8-bit) and 10-bit only in AV1
  (SVT-AV1, libaom, rav1e) or VP9; hardware encoders (VA-API, QSV, NVENC, AMF, Media Foundation) are built in but need
  a device.
* FFmpeg's default metadata copy drops `creation_time`, so executors write the plan's tags explicitly.
* A clip seeked into must restart its clock before `fps`, else the merge has a one-frame gap (75 frames in 2.53 s).
* SVT-AV1 starts about 100 threads and ignores `-threads`; `-svtav1-params lp=1` caps it. The tests run FFmpeg with
  one thread per stage, because shared machines cap each container's threads.
* Tone mapping uses `zscale` and `tonemap` on the CPU; `libplacebo` needs Vulkan.

## Not measured here

Media3 and AVFoundation on devices, frame-accurate edit-list trims (and whether AVFoundation's passthrough writes
them), speed and memory on phones, hardware and Media Foundation encoders, and Safari. M8-09 runs the same fixtures
on devices.
