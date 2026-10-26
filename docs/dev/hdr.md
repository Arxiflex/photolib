# HDR handling

[ADR-0390](../adr/0390-hdr-handling.md) decides how photolibd shows HDR: videos and stills tone-mapped to SDR for their
renditions, gain maps kept in JPEG previews, an HDR variant in the HLS ladder, an HDR leaf on the web. This page says
how the work is proved and how to review it by eye.

## The reference

`server/crates/photolib-server/tests/hdr.rs` makes its clips and stills from one frame of known light: eight grey
patches of 0, 5, 18, 50, 100, 203, 400 and 1,000 nits, eight colours of 100 nits (skin, the primaries and secondaries
of BT.2020, a grey card) and a ramp, coded as PQ or HLG, in 10-bit AV1 (the pinned FFmpeg has no HEVC encoder), as
HDR10, as HLG, with the primaries, matrix and range left unsaid, and with a Dolby Vision record of profile 8.1 and 8.4
added to the sample entry (profile 5 must be refused). A poster of each is measured: greys within 4 codes of grey,
black at most 6, 18 nits between 60 and 115, 100 nits at least 150, reference white at least 195, 1,000 nits at least
248, primaries keeping their channel. The zimg chain is compared with libplacebo's by CIE ΔE on the patches and the
ramp (mean at most 5, greys at most 3.5; measured 2.8 and 3.4 for PQ and HLG, greys 1.9 and 0.9), and stills with
videos (mean 4.0 and 4.3).

```sh
cargo test -p photolib-server --test hdr          # in server/; TEST_FFMPEG names a directory of ffmpeg and ffprobe
```

## The visual review

```sh
PHOTOLIB_HDR_REVIEW=/tmp/hdr cargo test -p photolib-server --test hdr -- --ignored
```

writes a sheet for each clip: the frame as a player without tone mapping shows it, as zimg converts it and as
libplacebo does. The committed sheets are in `docs/adr/assets/0390/`; each of them is a first frame of the clip named
in its file name, scaled to 1,280 px with FFmpeg.

## Gain maps

`PHOTOLIB_HDR_REVIEW=<dir> cargo test -p photolib-server --test renditions` also writes the preview of the corpus'
Ultra HDR JPEG, and with `PHOTOLIB_HEIF_SAMPLES=<dir of real files>` and `-- --ignored real_heif` the previews of every
HEIC, AVIF and JPEG in it, saying which kept its map. libultrahdr's `ultrahdr_app -m 1 -j <preview> -z <out>` is the
independent reader: it decodes a preview that carries a valid map and says "does not contain gainmap image" of one that
does not (build it from `github.com/google/libultrahdr`, v1.4.0, with CMake). Real files with maps are in
libavif's `tests/data` (Apple's JPEGs, AVIF `tmap` files) and pillow-heif's `tests/images` (an iPhone's and a
Galaxy's HEIC).

## Settings

`tone_mapping: auto | zimg | placebo` in photolibd's configuration. `auto` asks once, inside the sandbox, whether a
Vulkan device (a GPU, or llvmpipe from `mesa-vulkan-drivers`) turns a known grey into the right grey, and logs the
answer at info level; `zimg` never asks.

## Time

`cargo test -p photolib-server --test hdr 4k -- --ignored --nocapture` renders a poster, sprites and R1 of 10 s of 4K
HDR10 with each converter; ADR-0390 lists the numbers, also on two cores (`taskset -c 0,1`).
