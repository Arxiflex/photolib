# Encrypted playback report (M0-33)

Seeking and CPU in a two-hour end-to-end encrypted video on each playback path, measured on 2026-10-16. The decision
is [ADR-0059](../adr/0059-encrypted-media-playback.md).

## How it is measured

`node tools/playback/bench.mjs`, run by the gate's `web` part when a branch changes playback code or no diff can tell
(ADR-0059), fails if a seek presents no frame or a path's median exceeds the 1 s of design 08 §6.3 (M6-06:
seeking in a 2-hour private video starts playback within 1 s on LAN). `MODES` and `BROWSERS` select comma-separated
subsets.

* **Video**: 854×480 VP9 at 25 fps and 2.5 Mb/s (R1's cap), 2 s GOPs, 2 hours, 2.28 GB. Chrome encodes one 4 s segment
  with WebCodecs; `stream.mjs` repeats it into an original (MP4 with its index in `moov`, ahead of the media) and a CMAF
  stream rendition (4 s fragments, segment table in the stream index), each one PLB envelope of 64 KiB chunks, sealed
  as it is read. VP9 rather than R1's H.264: headless Firefox on Linux has no H.264 decoder.
* **Server**: a stand-in for photolibd on loopback that answers byte ranges, so the network adds nothing; LAN latency
  would add one round trip per request.
* **Paths**: *plain* plays the original unencrypted (the baseline); *proxy* plays it through `MediaProxy.decrypted`
  with the kernel's C ABI, the browser's `<video>` standing in for a native player; *sw* through a Service Worker
  decrypting with the kernel's WebAssembly; *mse* plays the stream through MSE, fed segment by segment by a worker
  running the kernel's WebAssembly.
* **Seek**: ten jumps spread over the two hours, each timed from setting `currentTime` until a frame within 0.5 s of
  the target is presented (`requestVideoFrameCallback`). *Requests* are what the server received per seek.
* **CPU**: user and system time of the browser's processes and the proxy over 4 s of playback, as a share of one
  core (Linux only); *proxy* is the proxy's part of it.

Machine: Linux x64, Intel Core Ultra 7 356H, 16 threads, shared with other jobs; Chrome for Testing 155 and Firefox
158, headless, with software decoding.

## Results

| Browser | Path | Seek median (ms) | Seek max (ms) | Requests per seek | CPU (% of a core) | Proxy (%) |
|---|---|---|---|---|---|---|
| Chrome 155 | plain | 101 | 177 | 1.1 | 16 | — |
| Chrome 155 | proxy | 111 | 146 | 1.4 | 17 | 1 |
| Chrome 155 | sw | 81 | 105 | 1.4 | 17 | — |
| Chrome 155 | mse | 89 | 127 | 3.7 | 15 | — |
| Firefox 158 | plain | 89 | 159 | 1.0 | 23 | — |
| Firefox 158 | proxy | 154 | 217 | 4.4 | 21 | 2 |
| Firefox 158 | sw | 131 | 151 | 4.3 | 80 | — |
| Firefox 158 | mse | 126 | 176 | 3.7 | 56 | — |

No frame was dropped. The machine is shared, so runs vary: six passing runs gave medians of 49–246 ms in Chrome and
64–271 ms in Firefox, and Firefox's CPU on the web paths ranged from 41 to 116% (its unencrypted baseline from 19 to
38%). The proxy never used more than 7% of a core: the kernel decrypts 1,138 MB/s through the C ABI
([go/no-go report](kernel-go-no-go.md)), about 3,600 times this video's bitrate.

## Per platform

| Platform | Path (ADR-0059) | Measured |
|---|---|---|
| Linux | loopback proxy (libmpv) | proxy with Chrome's and Firefox's players; libmpv not run |
| Windows | loopback proxy (libmpv) | no: needs a Windows run of the benchmark |
| macOS, iOS, iPadOS | loopback proxy, HLS for stream renditions (AVPlayer) | no: needs Apple hardware; no browser here plays the playlist (below) |
| Android | ExoPlayer `DataSource`, or the proxy | no: M0-27's device lab |
| Web: Chrome, Firefox | MSE for streams, Service Worker for originals | yes, above |
| Web: Safari, iOS Safari | ManagedMediaSource, Service Worker | no: needs Apple hardware |

## Findings

* **Progressive players need the index ahead of the media.** In the first run the progressive paths played the CMAF
  stream, with a `sidx`. Firefox seeks such a file by reading its fragments in order: a median of 0.8 s unencrypted,
  3.7 s through the Service Worker and 5.7 s through the proxy, with 47–171 requests per seek, as each response stopped
  at a 1 MiB window. Chrome, which reads the `sidx`, stayed under 210 ms. The original seeks with one request.
* **Open-ended ranges stop at their window; closed ranges are whole.** Answering `bytes=N-` whole made Chrome's seeks
  through the proxy 227 ms instead of 90 ms, with 5.7 instead of 1.5 requests per seek: the proxy decrypted ahead into
  socket buffers that each seek threw away. HLS segments are closed ranges and need all their bytes.
* **No native HLS here.** Chrome 155 reports HLS support, but its built-in player refused the client-written CMAF
  playlist with byte-range segments, in VP9 and H.264 through the proxy and in H.264 unencrypted from its own origin;
  it read the media as open-ended ranges through its cache. AVPlayer, the path's real consumer, remains unmeasured.
* **No AES-128 HLS is needed** by any measured path.

## Against the criteria

| Criterion | Threshold | Result |
|---|---|---|
| Seek in a 2-hour private video on LAN | playback within 1 s on every target | pass in Chrome and Firefox on Linux on every path: medians up to 271 ms, no seek over 437 ms; other targets unmeasured |
| CPU of decryption | not set | at most 7% of a core for the proxy; the web paths' extra CPU in Firefox varies with load |
