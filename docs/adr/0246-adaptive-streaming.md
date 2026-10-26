# ADR-0246 — Adaptive streaming: one grid of 2 s pieces, R1 sliced, the other rungs encoded on demand

* **Status**: Accepted — 2026-10-23 (roadmap M7-01). The owner kept all six decisions as made: the saver rung from
  the stored R1, every R1 rendered again once, streaming for whoever may view, the position through
  `PUT /media/{asset}/position`, 2 sessions and 20 GiB by default, and H.264 for R2
  (photolib-design#708).
* **Requirements**: F-12. **Design**:
  media pipeline §5.1, §5.4, §5.8,
  editing and video §5,
  [ADR-0085](0085-video-renditions.md).

## Context

F-12 asks for video "in lower quality to view it faster": an HLS ladder with the 720p proxy (R1, ADR-0085) as the
rung that always plays, the saver and HD rungs encoded on demand into a segment cache, data saver, resume and a start
within 2 s on a 3 Mbit/s link. The design leaves open how segments of rungs and sessions made at different times line
up, what each rung encodes from, how R1 becomes byte-range HLS, how playlists are authorised for players that send no
headers, and where the resume position is written. No client plays server videos yet (M2-24, M2-25, M3-13).

## Decision

1. **One grid.** Every rung cuts its picture into pieces of one 2 s GOP of source time (key frames forced at
   `n × 2 s`), CMAF fMP4 with `frag_discont`, timestamps offset by `n × 2 s` plus the AAC encoder's priming (1,024
   samples), so that a piece of any session or rung has the same timestamps and init segment. HLS segments group them:
   the first piece alone, which starts playback sooner, then two at a time (4 s).
2. **R1 is sliced.** The proxy is written by FFmpeg's HLS muxer as one file (`single_file`), still a progressive fMP4;
   its render spec keeps the index of its pieces and the source's facts, so the ladder neither probes nor parses media.
   Its segments are ranges of the stored file, on any store. This changes R1's render spec: every proxy renders again.
3. **Rungs** (`hls::RUNGS`): saver (480p, 1 Mb/s, AAC 96 kb/s) encoded from R1, which decodes cheaply and is SDR
   already; R1 encoded from the original only when the original is its own R1; R2 (1080p, 6 Mb/s, AAC 160 kb/s) from
   the original, above 720p only. All H.264 High and AAC-LC stereo, ≤ 30 fps; HEVC R2 waits for M7-02's hardware.
4. **Sessions.** The `api` process runs one sandboxed FFmpeg per (video, rung) (`photolib_media::command`), started
   at the piece asked for, paused with `SIGSTOP` three segments beyond the furthest piece asked for, resumed when asked
   for more, restarted on a far seek, killed after 30 s without a request. A piece waits at most 10 s, then `503` with
   `Retry-After: 2`. At most `streaming.sessions` (2) encode at once; while none is free the master playlist offers only
   the stored R1. The master playlist starts the lowest rung's session while the player reads the playlists. A segment
   is sent piece by piece as the encoder makes them.
5. **Cache.** Pieces live in `work_dir/streaming/<rung>-<version>/`, the version a hash of the input file and the
   rung, so a path never meets other bytes and segments are `immutable`. Originals and R1 on object stores or external
   libraries are copied there once. Least recently used directories go beyond `streaming.cache_gib` (20); the cache
   is emptied at start.
6. **Authorisation.** `POST /media/{asset}/hls` signs `master.m3u8` for a viewer (`Action::View`, as streaming is
   showing); every URI in a playlist carries a token signed for the role `hls`, valid three times the video's length
   and at least an hour. `?saver=1` offers only the lowest rung (design 08 §5.8).
7. **Resume.** `PUT /media/{asset}/position` (`{"position_ms": n}`) keeps it in `asset_user_state`, which every device
   of the viewer syncs; playlists start there with `EXT-X-START`, unless within the first second or last 5 s.
8. **Proof.** `tests/hls.rs` plays every rung from segments fetched in any order as one unbroken timeline, R1 as the
   stored bytes; its ignored test plays the ladder with hls.js 1.7 in Chrome and Firefox through a proxy that carries
   3, then 8, then 1.5 Mbit/s with 40 ms round trips: start within 2 s, R1 on 8 Mbit/s, the saver rung on 1.5, no stall.

## Consequences

* ✅ A 3 Mbit/s link starts on the saver rung; the stored R1 plays on servers that cannot encode (`sessions: 0`).
* ⚠️ Every R1 renders again once. The quality selector, the data-saver setting (on cellular by default), saving the
  position and preloading the next video belong to the clients that will play server videos (M2-24, M2-25, M3-13):
  each needs only the master or a rung's playlist, `?saver=1`, the position endpoint, or the master of the next video.
* ⚠️ The session cap is a setting until M7-02's self-test measures the box; HDR rungs (M7-03), I-frame playlists and
  the remux rung (R0r) are not here. hls.js needs `maxMaxBufferLength` near 30 s, or it buffers 60 MB at the first rate.
* ⚠️ Rungs encoded from R1 are encoded twice; at 480p and 1 Mb/s the loss does not show.

## Options considered

* **Segments as separate files at ingest**: the stored proxy would no longer play progressively.
* **Parsing R1's boxes in the server for byte ranges**: media parsing outside the sandbox ([ADR-0024](0024-media-sandbox.md)).
* **Every rung from the original**: a 4K HEVC HDR original decodes and tone-maps on the CPU at a fraction of real time.
* **A rebased timeline per session** (`setpts=PTS-STARTPTS`): the AAC priming then moves the first session by 21 ms.
* **A Connect procedure or an outbox mutation for the position**: neither the media router nor the outbox carry
  mutations yet; the endpoint is replaceable without a schema change.
