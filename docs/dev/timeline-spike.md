# Timeline spike report (M0-30)

The timeline prototype in `app/lib/features/library/timeline/` over a 1M-asset synthetic library, measured against
NFR-PERF-1 and NFR-PERF-3 on 2026-10-16 with the code committed alongside it. The image pipeline chosen from it is
[ADR-0040](../adr/0040-timeline-image-pipeline.md).

## The prototype

* `TimelineBuckets` and `TimelineLayout`: day segments of a header and rows of square cells. Prefix sums over the day
  counts make a month's offset one lookup and an offset's row a binary search over the days.
* `SliverTimeline`: a sliver that places headers and rows from the layout, so a jump lays out only what it shows.
* `Thumbnails`: four decodes at once through a `ThumbnailSource` at the cell's tier (128, 256, 512 or 1024 px): the
  visible cells first, then ahead in the scroll direction, then behind at half the priority; a 256 MiB LRU of decoded
  images. Nothing decodes while the scrubber is dragged, and rows wait while
  `Scrollable.recommendDeferredLoadingForContext` says a fling is too fast. A row is one leaf that paints a
  placeholder colour (standing in for ThumbHash) or the image of each cell.
* `TimelineScrubber`: the thumb maps to an offset; year labels and a month bubble while dragged; a semantic slider.

Not in the prototype: ThumbHash, drift queries (the counts come from the library's CSV), density levels, per-cell
semantics and native decoders (M1-09, M1-10).

## How it is measured

`python3 tools/timeline_bench.py <linux|chrome|firefox> [--wasm]` builds `app/benchmark/timeline.dart` in profile mode,
runs it under Xvfb or in a headless browser and prints one JSON line. The library is `tools/synthlib` with
`--assets 1m --seed 42`: 1,000,000 assets on 5,569 days. The thumbnails are 64 photo-like 256 px JPEGs of 12.3 KB on
average, the size of `thumb_s`, reused across assets. The viewport is 1280 × 720 on Linux, 1280 × 881 in Chrome and
1366 × 682 in Firefox (headless, it keeps its own size), at a device pixel ratio of 1: 8 or 9 columns of 152–160 px
cells, decoded at the 256 px tier. Each pipeline runs:

* **drag**: 8,000 px at 1,000 px/s, slow enough that every row decodes;
* **fling**: three flings at Flutter's top speed, 8,000 px/s, each followed by waiting for the screen's thumbnails;
* **jump**: 20 jumps to random months, timed to the first frame (placeholders) and to the screen's last thumbnail;
* **scrub** (once): the scrubber dragged end to end in 3 s, a new screen every frame, decoding paused.

Frame time is build plus raster from `FrameTiming`, as p50 / p90 / p99 in ms; a janky frame takes over 16.7 ms. The
pipelines are:

* **codec**: the JPEG through `ui.instantiateImageCodecWithSize` at the tier, Flutter's codecs off the UI thread;
* **raw**: RGBA pixels copied into an `ImmutableBuffer` and built with `ImageDescriptor.raw`, the Flutter side of a
  platform decoder's handoff (docs/10 §3.4) without the platform's decode;
* **bitmap** (web): `createImageBitmap` with resizing, then `createImageFromImageBitmap`.

Machine: Linux x64, Intel Core Ultra 7 356H, 16 threads, **no GPU**: the Linux app rasterises in software under Xvfb,
Chrome with SwiftShader, Firefox with software WebGL. Other builds and browser tests shared it
(load average 20–43 on 16 threads). Flutter 3.47.7; Chrome for Testing 155 and Firefox 158, headless. Each target ran
three times; the tables show the median of the three runs, element by element.

## Results

### Frame times

Build plus raster in ms, p50 / p90 / p99, and the share of janky frames, all medians of three runs; the last column
shows how far single runs spread.

| Target | Compiler | Pipeline | Drag | Fling | Jump | Janky % (drag / fling / jump) | Drag janky %, each run |
|---|---|---|---|---|---|---|---|
| Linux | AOT | codec | 16.3 / 30.1 / 54.8 | 18.7 / 31.6 / 69.1 | 34.3 / 75.3 / 125.0 | 46 / 59 / 89 | 4, 72, 46 |
| Linux | AOT | raw | 10.2 / 22.9 / 48.2 | 16.4 / 40.3 / 110.6 | 30.8 / 59.4 / 92.5 | 22 / 49 / 84 | 20, 22, 66 |
| Chrome 155 | dart2js | codec | 19.6 / 24.5 / 33.5 | 22.4 / 32.4 / 52.2 | 23.2 / 35.2 / 50.0 | 93 / 97 / 95 | 67, 93, 95 |
| Chrome 155 | dart2js | raw | 29.4 / 41.4 / 52.5 | 16.4 / 24.0 / 35.5 | 20.2 / 26.5 / 33.2 | 100 / 48 / 89 | 100, 100, 100 |
| Chrome 155 | dart2js | bitmap | 24.3 / 32.1 / 39.4 | 20.0 / 27.7 / 35.9 | 21.9 / 30.9 / 42.2 | 97 / 87 / 92 | 51, 97, 100 |
| Chrome 155 | dart2wasm | codec | 21.7 / 34.3 / 42.1 | 16.8 / 23.9 / 32.2 | 17.8 / 24.5 / 37.2 | 88 / 52 / 60 | 92, 88, 88 |
| Chrome 155 | dart2wasm | raw | 27.1 / 38.9 / 49.2 | 17.9 / 27.4 / 41.9 | 19.1 / 30.7 / 52.0 | 100 / 61 / 72 | 100, 100, 47 |
| Chrome 155 | dart2wasm | bitmap | 23.5 / 37.9 / 57.2 | 21.6 / 30.7 / 42.8 | 21.1 / 31.1 / 43.8 | 92 / 82 / 81 | 96, 92, 23 |
| Firefox 158 | dart2js | codec | 15.7 / 24.0 / 52.2 | 12.8 / 51.5 / 82.4 | 37.9 / 70.5 / 112.9 | 41 / 39 / 86 | 33, 41, 61 |
| Firefox 158 | dart2js | raw | 24.6 / 41.2 / 78.1 | 9.0 / 40.5 / 79.4 | 31.3 / 54.0 / 73.3 | 95 / 25 / 84 | 95, 87, 97 |
| Firefox 158 | dart2js | bitmap | 51.7 / 55.6 / 79.5 | 9.3 / 34.9 / 97.0 | 37.3 / 65.4 / 85.2 | 100 / 21 / 80 | 100, 100, 100 |
| Android, mid-range | AOT | — | device lab | device lab | device lab | — | — |
| Android, 4 GB | AOT | — | device lab | device lab | device lab | — | — |
| iPhone | AOT | — | device lab | device lab | device lab | — | — |
| macOS | AOT | — | not run | not run | not run | — | — |
| Windows | AOT | — | not run | not run | not run | — | — |
| Safari | dart2js | — | not run | not run | not run | — | — |

*Device lab*: needs a phone (M0-27); none was available. *Not run*: needs a Mac or a Windows PC; the runner builds
Linux and the browsers only.

### Jumps and decodes

After a jump, the time to the first frame (*placeholders*) and to the screen's last thumbnail, p50 / p99 in ms; one
decode at a time, p50 / p99 in ms; decodes per second with four at once.

| Target | Compiler | Pipeline | Placeholders | Thumbnails | Decode | Decodes/s, each run |
|---|---|---|---|---|---|---|
| Linux | AOT | codec | 13.8 / 36.2 | 299.0 / 507.3 | 6.1 / 20.4 | 743, 202, 250 |
| Linux | AOT | raw | 16.4 / 30.5 | 300.5 / 395.8 | 5.2 / 30.0 | 811, 327, 229 |
| Chrome 155 | dart2js | codec | 9.0 / 38.3 | 1037.9 / 1716.0 | 1.0 / 2.4 | 3,673, 3,804, 3,066 |
| Chrome 155 | dart2js | raw | 6.3 / 37.8 | 501.8 / 709.3 | 1.5 / 72.5 | 1,218, 545, 879 |
| Chrome 155 | dart2js | bitmap | 7.0 / 42.4 | 836.1 / 1112.8 | 1.5 / 73.4 | 2,681, 1,242, 1,020 |
| Chrome 155 | dart2wasm | codec | 4.5 / 23.0 | 689.7 / 1111.2 | 1.1 / 6.4 | 2,832, 1,822, 2,220 |
| Chrome 155 | dart2wasm | raw | 3.9 / 33.6 | 548.9 / 1061.3 | 2.4 / 56.6 | 556, 667, 822 |
| Chrome 155 | dart2wasm | bitmap | 4.0 / 33.9 | 713.1 / 1054.5 | 2.2 / 65.4 | 602, 681, 528 |
| Firefox 158 | dart2js | codec | 10.2 / 95.3 | 1499.4 / 3105.2 | 5.4 / 12.0 | 336, 307, 597 |
| Firefox 158 | dart2js | raw | 5.8 / 55.9 | 690.6 / 1278.3 | 3.7 / 117.6 | 591, 414, 426 |
| Firefox 158 | dart2js | bitmap | 7.5 / 86.7 | 352.7 / 748.3 | 1.1 / 49.6 | 1,200, 1,056, 1,239 |

### Layout and scrubbing

The layout of all 5,569 days for one width; the scrub's frame times, p50 / p90 / p99 in ms, and its janky share; the
worst build p99 of any scenario in any run.

| Target | Compiler | Layout (ms) | Scrub | Scrub janky % | Build p99, worst run (ms) |
|---|---|---|---|---|---|
| Linux | AOT | 0.02 | 12.8 / 24.1 / 37.3 | 25 | 5.3 |
| Chrome 155 | dart2js | 0.06 | 19.8 / 26.4 / 44.5 | 88 | 14.7 |
| Chrome 155 | dart2wasm | 0.04 | 15.1 / 19.7 / 25.7 | 35 | 8.4 |
| Firefox 158 | dart2js | 0.05 | 10.2 / 14.6 / 25.6 | 8 | 18.2 |

## What the numbers say

* **The geometry holds at 1M assets.** A layout takes 0.02–0.06 ms, a month is one lookup away, and building a frame
  stays within 5.3 ms at p99 natively even under load; the browsers' worst runs reach 8–18 ms. Placeholders follow a
  jump within 4–16 ms at p50.
* **Frame budgets cannot be judged on this machine.** Raster in software on a shared CPU dominates every frame, and a
  single target's janky share moves by up to 73 points between runs. A slower pipeline even gains here, since flat
  placeholders rasterise faster than images.
* **No pipeline wins everywhere.** Natively, *codec* and *raw* are within each other's spread on every measure:
  handing over decoded pixels costs about what decoding the JPEG does. In Chrome, *codec* decodes the most per second
  in every run. In Firefox, *bitmap* fills the screen after a jump about four times sooner than *codec* in every
  run, but drags at about three to four times *codec*'s p50 frame time. [ADR-0040](../adr/0040-timeline-image-pipeline.md)
  chooses from this and from the design's reasons.

## Against the budgets

| Budget (docs/10 §3.7) | Threshold | Result here |
|---|---|---|
| Jump to any month | O(1) | pass: one map lookup and one prefix sum (`buckets_test.dart`, `layout_test.dart`) |
| Placeholders after a jump | ≤ 100 ms | pass: p99 23–95 ms; single runs reached 102 ms (Firefox) and 108 ms (Linux) |
| Thumbnails after a jump | ≤ 300 ms local, ≤ 600 ms LAN | unverified without a GPU: p50 299–301 ms, p99 396–507 ms on Linux; p50 353–1,499 ms in the browsers |
| Scrolling a 1M-asset library | ≥ 60 fps, ≤ 1 % janky, p99 ≤ 14 ms at 60 Hz | unverified without a GPU: 21–100 % janky frames in software raster |
| No blank cells | a placeholder until the image | pass by construction: a row paints each cell's placeholder until its image arrives |

The owner rated the frame and thumbnail budgets unverified, not failed, until a machine with a GPU in the test phase
(photolib-design#335). Open: every budget there, on phones, macOS, Windows and Safari (M0-27's devices and harness),
where test builds run this benchmark from Settings and copy its JSON
([ADR-0040](../adr/0040-timeline-image-pipeline.md)). Since then the benchmark lives in
`app/lib/features/library/timeline/benchmark.dart` and runs with the design's defaults, cores − 1 decodes at once
natively and T1 sized by RAM, so later runs are not comparable with these.

## The thumbnail pipeline (M1-09)

*pipeline* is [ADR-0070](../adr/0070-thumbnail-caches.md)'s pipeline
(`app/lib/features/library/timeline/benchmark_io.dart`): each asset's JPEG is a file, decoded at the tier with
Flutter's codecs (T4) and written back to a disk cache (T2), as a folder photo is when first seen, with the window and
cancellation of docs/10 §3.5. Three runs on Linux on 2026-10-16, on the
same machine (load average 21–27), medians as above:

| Pipeline | Drag | Fling | Jump | Janky % (drag / fling / jump) | Drag janky %, each run | Thumbnails after a jump | Decodes/s, each run |
|---|---|---|---|---|---|---|---|
| codec | 6.1 / 13.8 / 25.7 | 5.9 / 17.9 / 34.1 | 14.6 / 29.7 / 90.4 | 4 / 16 / 40 | 4, 4, 24 | 170.4 / 314.7 | 782, 779, 721 |
| raw | 4.8 / 7.5 / 16.3 | 4.6 / 13.1 / 33.4 | 11.8 / 21.0 / 62.4 | 1 / 5 / 20 | 0, 1, 35 | 133.7 / 264.0 | 822, 894, 637 |
| pipeline | 13.4 / 24.1 / 47.9 | 4.7 / 13.7 / 28.6 | 11.4 / 18.5 / 41.5 | 37 / 5 / 13 | 6, 37, 62 | 212.8 / 298.4 | 454, 230, 154 |

Placeholders followed a jump within 18 ms at p50 and a frame's build within 8.6 ms at p99 in every scenario. Besides
decoding, the pipeline reads a file and encodes the write-back on an isolate, so it decoded less per second than
*codec* on the loaded CPU; a second visit reads T2 instead. Its thumbnails filled the screen within 300 ms of a jump at
p99, but frame budgets still cannot be judged without a GPU.
