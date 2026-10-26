# ADR-0085 — Video renditions: FFmpeg in the sandbox on `worker:transcode`, the original as its own R1

* **Status**: **Proposed — owner to confirm** (roadmap M2-10).
* **Requirements**: F-12, R-APP-5. **Design**:
  media pipeline §4.1, §5.1–§5.3, §5.6, §8,
  editing and video §5.

## Context

Every video needs a poster for the grids, sprites for scrubbing and a rendition every browser and player decodes: the
original when it meets design 08's baseline, else the 720p proxy R1. The design leaves open how the server's FFmpeg is
built (M7-02), how HDR is tone-mapped before libplacebo (M7-03), where a video's renditions run and are stored, how an
original that is already R1 is recorded, and how anything proves that the corpus plays.

## Decision

1. **Jobs.** The reconciler queues a video's renditions as `transcode` jobs, which `worker:transcode` runs (two at a
   time, each FFmpeg on half the cores: by default its decoders and filters each start a thread per core, which a pid
   limit can refuse) with the `ffmpeg` and `ffprobe` of `ffmpeg_dir`; unset, videos get no renditions.
   Images keep `render`. Each rendition is a render spec whose id hashes its recipe and generator version.
2. **Renditions.** The poster frame (past the first tenth, at most 10 s in, the frame closest to three seconds'
   average) as `thumb_s` and `thumb_m` (WebP) and `preview` (JPEG) at the image renditions' sizes; 160 px frames
   every second or more (at most 1,000) in 10 × 10 WebP `sprite` sheets, their layout in each sheet's render spec;
   and `video_proxy_720`: H.264 High (x264 at CRF 23 in a GPL build, else OpenH264), short side 720, ≤ 30 fps
   constant, 2.5 Mb/s, a key frame every 2 s, AAC-LC 128 kb/s stereo at 48 kHz, fragmented MP4. All are deinterlaced,
   upright, square-pixelled, SDR BT.709 and carry no metadata of the original.
3. **R1 is the original** when the file is complete and meets the baseline (H.264 ≤ High 4.1, 8-bit 4:2:0, SDR,
   progressive, ≤ 1080p, ≤ 60 fps, ≤ 5 Mb/s, AAC-LC, MP3 or no audio, MP4 or MOV): its `video_proxy_720` row points at
   the original's key with `original: true` in its render spec. Completeness is a stream copy of every packet.
4. **HDR** (PQ, HLG, Dolby Vision) is tone-mapped on the CPU with zscale and Hable's curve, after scaling, so that
   zimg's float frames stay small enough for the sandbox's 3 GiB.
5. **Sandbox.** ffprobe and FFmpeg run once per step as `photolibd media-child` tools: reading only the original (a
   copy in the job's scratch directory when it is on an object store), writing only the job's output directory,
   `-protocol_whitelist file`, 3 GiB, a wall clock of three times the duration plus a minute. Each output is probed
   before it counts; R1 must itself meet the baseline, keep its sound and last as long as the original.
6. **Storage.** Renditions go beside the original, in its store, under `derived/<library>/<asset>/`, through the
   journal; a put settles in the job's transaction.
7. **Proof.** `tests/video.rs` renders every corpus video as a decodable twin (container, codec, size, rotation,
   frame rate, HDR signalling and interlacing of its golden record); `tools/video/play.mjs` plays each one's
   original or R1 in headless Chrome and Firefox, the latter with the pinned LGPL FFmpeg's libraries on Linux.

## Consequences

* ✅ All 72 corpus videos play in Chrome and Firefox through their original or R1; posters and sprites exist for all.
* ⚠️ Safari, iOS, Android and the desktop players are not run here: R1 is the profile they all decode, and the
  six-target smoke tests must play it.
* ⚠️ CPU tone mapping is slow and only roughly matches libplacebo (M7-03 gates it by ΔE); no hardware encoding
  (M7-02). The pinned LGPL FFmpeg encodes R1 with OpenH264, whose rate control is coarser than x264's.
* ⚠️ Not yet: library proxy policies (`needed`, `always`, `never`), slow-motion flattening, the 12 h and 8K limits,
  a stall watchdog, terminal failure records (a broken file retries five times a day), clip proxies of Live and motion
  photos, a separate derived store, and deleting renditions a new spec replaces.
* ⚠️ A job holds a pooled database connection while FFmpeg runs, though no transaction id.

## Options considered

* **Renditions in `render` jobs beside images**: a long transcode would hold the slots thumbnails need.
* **Always a proxy** (design 08 open question 2): about 1 GiB per hour of footage for videos that already play.
* **Tone mapping before scaling**: zimg's float frames at 4K exceed the sandbox's memory.
* **Seeking for the poster**: an MPEG-TS seek lands after the key frame and decodes nothing.
* **Checking the corpus files themselves**: their payloads do not decode; only twins can play.
