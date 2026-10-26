//! HDR to SDR (photolib-design docs/08 §5.6, ADR-0390): reference clips of known light, HDR10, HLG and what files
//! leave unsaid, render as posters whose greys are grey, whose middle is not washed out and whose primaries stay
//! apart. A clip is a frame of patches whose light in nits is known, so that the review is a measurement: grey
//! patches of 0 to 1,000 nits, colours of 100 nits and a ramp. Set `PHOTOLIB_HDR_REVIEW` to a directory to collect
//! the posters for a visual review (`docs/dev/hdr.md`).

// The tests compute colours with the documents' own formulas and read patches of pictures by their coordinates.
#![allow(
    clippy::suboptimal_flops,
    clippy::cast_precision_loss,
    clippy::cast_sign_loss,
    clippy::many_single_char_names,
    clippy::too_many_lines,
    clippy::unreadable_literal
)]

mod common;

use std::path::{Path, PathBuf};

use common::{ffmpeg, tools};
use photolib_media::Failure;
use photolib_server::{
    tone::{Mapper, ToneMapping},
    video::Ffmpeg,
};

const PHOTOLIBD: &str = env!("CARGO_BIN_EXE_photolibd");
const WIDTH: usize = 640;
const HEIGHT: usize = 360;
/// The nits of the eight grey patches in the top row.
const GREYS: [f64; 8] = [0.0, 5.0, 18.0, 50.0, 100.0, 203.0, 400.0, 1000.0];

#[derive(Clone, Copy, PartialEq)]
enum Signal {
    Pq,
    Hlg,
}

impl Signal {
    /// The coded value (0 to 1) of `nits` of display light.
    fn code(self, nits: f64) -> f64 {
        match self {
            // SMPTE ST 2084.
            Self::Pq => {
                let y = (nits / 10_000.0).clamp(0.0, 1.0).powf(2610.0 / 16384.0);
                ((3424.0 / 4096.0 + 2413.0 / 4096.0 * 32.0 * y) / (1.0 + 2392.0 / 4096.0 * 32.0 * y))
                    .powf(2523.0 / 4096.0 * 128.0)
            }
            // ARIB STD-B67 on a 1,000 nit display: the inverse of its system gamma of 1.2, then the OETF.
            Self::Hlg => {
                let scene = (nits / 1000.0).clamp(0.0, 1.0).powf(1.0 / 1.2);
                let (a, b, c) = (0.178_832_77, 1.0 - 4.0 * 0.178_832_77, 0.559_910_73);
                if scene <= 1.0 / 12.0 {
                    (3.0 * scene).sqrt()
                } else {
                    a * (12.0 * scene - b).ln() + c
                }
            }
        }
    }

    /// Its code in H.273.
    fn number(self) -> u8 {
        match self {
            Self::Pq => 16,
            Self::Hlg => 18,
        }
    }
}

/// The reference frame as 16-bit RGB, coded as `signal` in BT.2020: 8 grey patches, 8 colours of 100 nits (skin, the
/// primaries and secondaries, a grey card) and a ramp from 0 to 1,000 nits.
fn frame(signal: Signal) -> Vec<u8> {
    let colours: [[f64; 3]; 8] = [
        [0.45, 0.30, 0.22],
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0],
        [0.0, 1.0, 1.0],
        [1.0, 0.0, 1.0],
        [1.0, 1.0, 0.0],
        [0.18, 0.18, 0.18],
    ];
    let mut bytes = Vec::with_capacity(WIDTH * HEIGHT * 6);
    for y in 0..HEIGHT {
        for x in 0..WIDTH {
            let rgb = match y / 120 {
                0 => [signal.code(GREYS[x / 80]); 3],
                1 => colours[x / 80].map(|c| signal.code(c * 100.0)),
                _ => {
                    let ramp = signal.code(1000.0 * x as f64 / (WIDTH - 1) as f64);
                    [ramp * 0.97, ramp, ramp]
                }
            };
            for channel in rgb {
                bytes.extend(((channel.clamp(0.0, 1.0) * 65535.0).round() as u16).to_le_bytes());
            }
        }
    }
    bytes
}

/// What a file says of its colours; `None` leaves the field out.
#[derive(Clone, Copy)]
struct Tags {
    /// Whether it names the transfer: Dolby Vision's files may name only their signal compatibility.
    transfer: bool,
    primaries: Option<&'static str>,
    matrix: Option<&'static str>,
    range: Option<&'static str>,
}

const TAGGED: Tags = Tags {
    transfer: true,
    primaries: Some("bt2020"),
    matrix: Some("bt2020nc"),
    range: Some("tv"),
};
/// A transfer and nothing else, as some phones and editors write.
const UNSAID: Tags = Tags {
    transfer: true,
    primaries: None,
    matrix: None,
    range: None,
};

/// Nothing: what a Dolby Vision file leaves to its configuration record.
const NOTHING: Tags = Tags {
    transfer: false,
    primaries: None,
    matrix: None,
    range: None,
};

/// A 1 s clip of the reference frame, 10-bit AV1 in MP4 (the pinned FFmpeg has no HEVC encoder) tagged as `tags`.
fn clip(tools: &Path, dir: &Path, name: &str, signal: Signal, tags: Tags) -> PathBuf {
    let raw = dir.join(format!("{name}.rgb"));
    std::fs::write(&raw, frame(signal)).unwrap();
    let out = dir.join(format!("{name}.mp4"));
    let mut args = vec![
        "-f",
        "rawvideo",
        "-pix_fmt",
        "rgb48le",
        "-s",
        "640x360",
        "-framerate",
        "10",
        "-stream_loop",
        "9",
        "-i",
        raw.to_str().unwrap(),
        "-vf",
        "scale=in_range=pc:out_color_matrix=bt2020nc:out_range=tv,format=yuv420p10le",
        "-c:v",
        "libsvtav1",
        "-preset",
        "12",
        "-crf",
        "12",
        "-svtav1-params",
        "lp=1",
    ];
    let coded = dir.join(format!("{name}-coded.mp4"));
    args.push(coded.to_str().unwrap());
    ffmpeg(tools, &args);
    // The encoder's wrapper drops the transfer and the primaries; the sequence header says them.
    let code = |said: Option<&str>, value: u8| said.map_or(2, |_| value);
    let colours = format!(
        "av1_metadata=color_primaries={}:transfer_characteristics={}:matrix_coefficients={}:color_range={}",
        code(tags.primaries, 9),
        if tags.transfer { signal.number() } else { 2 },
        code(tags.matrix, 9),
        tags.range.unwrap_or("tv"),
    );
    ffmpeg(
        tools,
        &[
            "-i",
            coded.to_str().unwrap(),
            "-c",
            "copy",
            "-bsf:v",
            &colours,
            out.to_str().unwrap(),
        ],
    );
    out
}

/// `clip` with a Dolby Vision configuration record of `profile` and base layer signal `compat` in its sample entry:
/// the record a profile 8.1 (HDR10 base), 8.4 (HLG base) or 5 file carries, without the RPU that no encoder here
/// writes. Only the signalling reaches a tone mapper's decisions; the pictures stay those of the clip.
fn dolby(clip: &Path, profile: u8, compat: u8) -> PathBuf {
    let mut bytes = std::fs::read(clip).unwrap();
    // A box's offset and size, and where its children start.
    let find = |bytes: &[u8], from: usize, end: usize, kind: &[u8; 4]| -> (usize, usize) {
        let mut at = from;
        while at + 8 <= end {
            let size = u32::from_be_bytes(bytes[at..at + 4].try_into().unwrap()) as usize;
            if &bytes[at + 4..at + 8] == kind {
                return (at, size);
            }
            at += size;
        }
        panic!("no {} box", String::from_utf8_lossy(kind));
    };
    let mut record = vec![1u8, 0, profile << 1, 0b0000_0101, compat << 4];
    record.resize(24, 0);
    let mut entry = ((8 + record.len()) as u32).to_be_bytes().to_vec();
    entry.extend(if profile > 7 { *b"dvvC" } else { *b"dvcC" });
    entry.extend(&record);
    // moov, trak, mdia, minf, stbl, stsd (a full box with an entry count), then the av01 entry, whose children follow
    // 78 bytes of sample entry fields.
    let mut chain = vec![];
    let (mut from, mut end) = (0, bytes.len());
    for kind in [b"moov", b"trak", b"mdia", b"minf", b"stbl", b"stsd", b"av01"] {
        let (at, size) = find(&bytes, from, end, kind);
        chain.push(at);
        (from, end) = (at + 8, at + size);
        if kind == b"stsd" {
            from += 8;
        }
    }
    let mdat = find(&bytes, 0, bytes.len(), b"mdat").0;
    assert!(
        mdat < chain[0],
        "the sample tables must come after the media for offsets to hold"
    );
    let av01_end = end;
    bytes.splice(av01_end..av01_end, entry.iter().copied());
    for at in chain {
        let size = u32::from_be_bytes(bytes[at..at + 4].try_into().unwrap()) + entry.len() as u32;
        bytes[at..at + 4].copy_from_slice(&size.to_be_bytes());
    }
    let out = clip.with_file_name(format!(
        "{}-dv{profile}{compat}.mp4",
        clip.file_stem().unwrap().to_str().unwrap()
    ));
    std::fs::write(&out, bytes).unwrap();
    out
}

/// A poster of `clip` as 8-bit RGB, made by `mapper` (None: the one the machine has).
async fn poster(tools: &Path, clip: &Path, dir: &Path, tone_mapping: ToneMapping) -> Vec<u8> {
    let ffmpeg_ = Ffmpeg::new(PHOTOLIBD.into(), tools.to_path_buf(), 1)
        .unwrap()
        .with_tone_mapping(tone_mapping);
    let out = dir.join(format!(
        "out-{}-{tone_mapping:?}",
        clip.file_stem().unwrap().to_str().unwrap()
    ));
    std::fs::create_dir_all(&out).unwrap();
    let made = ffmpeg_
        .render("preview", clip, "video/mp4", &out)
        .await
        .unwrap()
        .unwrap();
    let rgb = dir.join(format!(
        "{}-{tone_mapping:?}.rgb",
        clip.file_stem().unwrap().to_str().unwrap()
    ));
    ffmpeg(
        tools,
        &[
            "-i",
            made[0].path.to_str().unwrap(),
            "-pix_fmt",
            "rgb24",
            "-f",
            "rawvideo",
            rgb.to_str().unwrap(),
        ],
    );
    if let Some(review) = std::env::var_os("PHOTOLIB_HDR_REVIEW") {
        let label = format!("{}-{tone_mapping:?}.png", clip.file_stem().unwrap().to_str().unwrap()).to_lowercase();
        std::fs::create_dir_all(&review).unwrap();
        ffmpeg(
            tools,
            &[
                "-i",
                made[0].path.to_str().unwrap(),
                Path::new(&review).join(label).to_str().unwrap(),
            ],
        );
    }
    std::fs::read(rgb).unwrap()
}

/// The mean colour of the middle of patch (`row`, `column`) of a poster.
fn patch(rgb: &[u8], row: usize, column: usize) -> [i32; 3] {
    let mut sum = [0i64; 3];
    let mut n = 0;
    for y in row * 120 + 40..row * 120 + 80 {
        for x in column * 80 + 20..column * 80 + 60 {
            for (c, total) in sum.iter_mut().enumerate() {
                *total += i64::from(rgb[(y * WIDTH + x) * 3 + c]);
            }
            n += 1;
        }
    }
    sum.map(|total| (total / n) as i32)
}

/// What a poster of any HDR clip owes: greys are grey, black is black, the middle is not washed out, light climbs, and
/// the primaries stay apart.
fn assert_correct(name: &str, rgb: &[u8]) {
    let greys: Vec<[i32; 3]> = (0..8).map(|c| patch(rgb, 0, c)).collect();
    for (nits, [r, g, b]) in GREYS.iter().zip(&greys) {
        assert!(
            (r - g).abs() <= 4 && (b - g).abs() <= 4,
            "{name}: {nits} nits is not grey but {r},{g},{b}: a cast"
        );
    }
    let level = |c: usize| greys[c][1];
    assert!(level(0) <= 6, "{name}: black is {}", level(0));
    assert!(
        (60..=115).contains(&level(2)),
        "{name}: a grey card of 18 nits shows as {}",
        level(2)
    );
    assert!(level(4) >= 150, "{name}: 100 nits shows as {}: washed out", level(4));
    assert!(level(5) >= 195, "{name}: reference white shows as {}", level(5));
    assert!(level(7) >= 248, "{name}: 1,000 nits shows as {}", level(7));
    for c in 1..6 {
        assert!(
            level(c) >= level(c - 1) + 8,
            "{name}: patch {c} is not brighter than patch {}",
            c - 1
        );
    }
    let [skin_r, skin_g, skin_b] = patch(rgb, 1, 0);
    assert!(
        skin_r >= 110 && skin_r > skin_g + 15 && skin_g > skin_b + 5,
        "{name}: skin is {skin_r},{skin_g},{skin_b}"
    );
    // A primary keeps its channel and little of the others.
    for (column, own) in [(1, 0), (2, 1), (3, 2)] {
        let colour = patch(rgb, 1, column);
        let floor = if own == 2 { 100 } else { 140 };
        assert!(colour[own] >= floor, "{name}: primary {column} is {colour:?}");
        for other in (0..3).filter(|c| *c != own) {
            assert!(colour[other] <= 60, "{name}: primary {column} is {colour:?}");
        }
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn hdr10_and_hlg_clips_make_neutral_posters_that_are_not_washed_out() {
    let tools = tools();
    let dir = tempfile::tempdir().unwrap();
    for (name, signal) in [("hdr10", Signal::Pq), ("hlg", Signal::Hlg)] {
        let clip = clip(&tools, dir.path(), name, signal, TAGGED);
        assert_correct(name, &poster(&tools, &clip, dir.path(), ToneMapping::Auto).await);
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn a_clip_that_leaves_its_primaries_matrix_and_range_unsaid_has_no_red_cast_and_still_renders() {
    let tools = tools();
    let dir = tempfile::tempdir().unwrap();
    for (name, signal) in [("untagged-pq", Signal::Pq), ("untagged-hlg", Signal::Hlg)] {
        let clip = clip(&tools, dir.path(), name, signal, UNSAID);
        assert_correct(name, &poster(&tools, &clip, dir.path(), ToneMapping::Zimg).await);
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn dolby_vision_8_1_and_8_4_clips_are_mapped_through_their_base_layers() {
    let tools = tools();
    let dir = tempfile::tempdir().unwrap();
    // Profile 8.4: HLG, said by the record alone in one file and by the transfer too in the other. Profile 8.1: HDR10.
    let cases = [
        ("dv84-said", Signal::Hlg, TAGGED, 4),
        ("dv84-record-only", Signal::Hlg, NOTHING, 4),
        ("dv81-record-only", Signal::Pq, NOTHING, 1),
    ];
    for (name, signal, tags, compat) in cases {
        let plain = clip(&tools, dir.path(), name, signal, tags);
        let clip = dolby(&plain, 8, compat);
        let probe = common::run(
            photolib_spawn::tool(tools.join("ffprobe")).args(["-v", "error", "-show_streams", clip.to_str().unwrap()]),
            common::FIXTURE,
        );
        assert!(
            String::from_utf8_lossy(&probe).contains("DOVI configuration record"),
            "{name}: no record"
        );
        assert_correct(name, &poster(&tools, &clip, dir.path(), ToneMapping::Auto).await);
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn dolby_vision_profile_5_makes_no_poster_rather_than_a_green_and_purple_one() {
    let tools = tools();
    let dir = tempfile::tempdir().unwrap();
    let plain = clip(&tools, dir.path(), "dv5", Signal::Pq, NOTHING);
    let p5 = dolby(&plain, 5, 0);
    let ffmpeg_ = Ffmpeg::new(PHOTOLIBD.into(), tools.clone(), 1).unwrap();
    let out = dir.path().join("out-dv5");
    std::fs::create_dir_all(&out).unwrap();
    let refused = ffmpeg_.render("preview", &p5, "video/mp4", &out).await;
    assert!(
        matches!(&refused, Err(Failure::Unsupported(why)) if why.contains("profile 5")),
        "{refused:?}"
    );
}

/// The visual review's sheets (`docs/dev/hdr.md`): each reference clip's first frame as a player without tone mapping
/// shows it, as zimg converts it and as libplacebo does, side by side. Run by hand:
/// `PHOTOLIB_HDR_REVIEW=<dir> cargo test -p photolib-server --test hdr -- --ignored`.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "writes the review's sheets into PHOTOLIB_HDR_REVIEW"]
async fn the_visual_review_sheets_show_each_reference_clip_before_and_after() {
    let review = PathBuf::from(std::env::var_os("PHOTOLIB_HDR_REVIEW").expect("PHOTOLIB_HDR_REVIEW names a directory"));
    std::fs::create_dir_all(&review).unwrap();
    let tools = tools();
    let dir = tempfile::tempdir().unwrap();
    let plain = [
        ("hdr10", Signal::Pq, TAGGED),
        ("hlg", Signal::Hlg, TAGGED),
        ("untagged-hdr10", Signal::Pq, UNSAID),
        ("untagged-hlg", Signal::Hlg, UNSAID),
    ];
    let mut clips: Vec<(String, PathBuf)> = vec![];
    for (name, signal, tags) in plain {
        clips.push((name.into(), clip(&tools, dir.path(), name, signal, tags)));
    }
    let dv84 = clip(&tools, dir.path(), "dv84", Signal::Hlg, NOTHING);
    clips.push(("dolby-vision-8.4".into(), dolby(&dv84, 8, 4)));
    let dv81 = clip(&tools, dir.path(), "dv81", Signal::Pq, NOTHING);
    clips.push(("dolby-vision-8.1".into(), dolby(&dv81, 8, 1)));
    for (name, clip) in clips {
        let naive = review.join(format!("{name}-naive.png"));
        ffmpeg(
            &tools,
            &[
                "-i",
                clip.to_str().unwrap(),
                "-frames:v",
                "1",
                "-vf",
                "format=rgb24",
                naive.to_str().unwrap(),
            ],
        );
        for mapping in [ToneMapping::Zimg, ToneMapping::Auto] {
            poster(&tools, &clip, dir.path(), mapping).await;
        }
        let stem = clip.file_stem().unwrap().to_str().unwrap().to_lowercase();
        let label = |text: &str| {
            format!("drawtext=text='{text}':x=8:y=8:fontsize=20:fontcolor=white:box=1:boxcolor=black@0.7:boxborderw=4")
        };
        let graph = format!(
            "[0]{}[a];[1]{}[b];[2]{}[c];[a][b][c]hstack=inputs=3,scale=1280:-2",
            label("without tone mapping"),
            label("zimg"),
            label("libplacebo"),
        );
        let sheet = review.join(format!("{name}.jpg"));
        ffmpeg(
            &tools,
            &[
                "-i",
                naive.to_str().unwrap(),
                "-i",
                review.join(format!("{stem}-zimg.png")).to_str().unwrap(),
                "-i",
                review.join(format!("{stem}-auto.png")).to_str().unwrap(),
                "-filter_complex",
                &graph,
                "-frames:v",
                "1",
                "-q:v",
                "4",
                sheet.to_str().unwrap(),
            ],
        );
    }
}

/// The reference frame as a 10-bit AVIF coded as `signal` in BT.2020, and its JPEG preview as 8-bit RGB.
async fn still(tools: &Path, dir: &Path, name: &str, signal: Signal) -> Vec<u8> {
    use photolib_media::{
        Worker,
        render::{Format, Output, Request},
    };
    let raw = dir.join(format!("{name}.rgb"));
    std::fs::write(&raw, frame(signal)).unwrap();
    let avif = dir.join(format!("{name}.avif"));
    let trc = match signal {
        Signal::Pq => "smpte2084",
        Signal::Hlg => "arib-std-b67",
    };
    ffmpeg(
        tools,
        &[
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb48le",
            "-s",
            "640x360",
            "-i",
            raw.to_str().unwrap(),
            "-vf",
            "scale=in_range=pc:out_color_matrix=bt2020nc:out_range=tv,format=yuv420p10le",
            "-frames:v",
            "1",
            "-c:v",
            "libaom-av1",
            "-cpu-used",
            "8",
            "-crf",
            "10",
            "-still-picture",
            "1",
            "-color_primaries",
            "bt2020",
            "-color_trc",
            trc,
            "-colorspace",
            "bt2020nc",
            "-f",
            "avif",
            avif.to_str().unwrap(),
        ],
    );
    let (input, out) = (dir.join(format!("{name}-in")), dir.join(format!("{name}-out")));
    std::fs::create_dir_all(&input).unwrap();
    std::fs::create_dir_all(&out).unwrap();
    // The encoder's wrapper drops the transfer and the primaries, so the file's colr box (nclx, then the primaries, the
    // transfer, the matrix and the range, 2 bytes each but the range) says them afresh.
    let mut bytes = std::fs::read(&avif).unwrap();
    let at = bytes.windows(8).position(|w| w == b"colrnclx").expect("a colr box") + 8;
    bytes[at..at + 2].copy_from_slice(&9u16.to_be_bytes());
    bytes[at + 2..at + 4].copy_from_slice(&u16::from(signal.number()).to_be_bytes());
    std::fs::write(input.join("original"), bytes).unwrap();
    let outputs = vec![Output {
        file: "preview.jpg".into(),
        format: Format::Jpeg,
        short: 0,
        long: 2160,
        quality: 90,
        wide: false,
    }];
    let mut worker = Worker::renderer(PHOTOLIBD.into(), input.clone(), out.clone());
    let request = Request {
        input: input.join("original"),
        mime: "image/avif".into(),
        orientation: None,
        outputs,
        edit: None,
    };
    let rendered = worker.render(&request).await.unwrap();
    assert_eq!(rendered.outputs[0], (Format::Jpeg, 640, 360));
    let rgb = dir.join(format!("{name}-preview.rgb"));
    ffmpeg(
        tools,
        &[
            "-i",
            out.join("preview.jpg").to_str().unwrap(),
            "-pix_fmt",
            "rgb24",
            "-f",
            "rawvideo",
            rgb.to_str().unwrap(),
        ],
    );
    if let Some(review) = std::env::var_os("PHOTOLIB_HDR_REVIEW") {
        let label = format!("still-{name}.png");
        ffmpeg(
            tools,
            &[
                "-i",
                out.join("preview.jpg").to_str().unwrap(),
                Path::new(&review).join(label).to_str().unwrap(),
            ],
        );
    }
    std::fs::read(rgb).unwrap()
}

/// A PQ or HLG still (AVIF, HEIC) is tone-mapped like a video frame: its preview is no washed-out picture of the
/// signal's own values.
#[tokio::test(flavor = "multi_thread")]
async fn hdr_stills_render_neutral_previews_that_are_not_washed_out() {
    let tools = tools();
    let dir = tempfile::tempdir().unwrap();
    for (name, signal) in [("hdr10-still", Signal::Pq), ("hlg-still", Signal::Hlg)] {
        let preview = still(&tools, dir.path(), name, signal).await;
        assert_correct(name, &preview);
        // The picture of a still is the picture of the same frame as a video's: within the converters' own difference.
        let clip = clip(&tools, dir.path(), name, signal, TAGGED);
        let video = poster(&tools, &clip, dir.path(), ToneMapping::Zimg).await;
        let (mean, largest, greys) = delta_e(&preview, &video);
        eprintln!("{name}: still against video: mean ΔE {mean:.2}, largest {largest:.2}, greys {greys:.2}");
        assert!(
            mean <= 5.0 && greys <= 3.5,
            "{name}: ΔE {mean:.2} {largest:.2} {greys:.2}"
        );
    }
}

/// How long each rendition of a 4K HDR10 clip of `PHOTOLIB_HDR_SECONDS` seconds (10) takes with each converter, which
/// `docs/dev/hdr.md` records, also under `taskset -c 0,1` as a stand-in for a weak machine. By hand:
/// `cargo test -p photolib-server --test hdr -- --ignored --nocapture 4k`.
#[tokio::test(flavor = "multi_thread")]
#[ignore = "measures the time of renditions of a 4K clip"]
async fn the_renditions_of_a_4k_hdr_clip_take_this_long() {
    let tools = tools();
    let dir = tempfile::tempdir().unwrap();
    let seconds = std::env::var("PHOTOLIB_HDR_SECONDS").unwrap_or_else(|_| "10".into());
    let coded = dir.path().join("coded.mp4");
    let clip = dir.path().join("clip4k.mp4");
    let source = format!("testsrc2=s=3840x2160:r=30:d={seconds}[v];sine=r=48000:d={seconds}[a]");
    ffmpeg(
        &tools,
        &[
            "-filter_complex",
            &source,
            "-map",
            "[v]",
            "-map",
            "[a]",
            "-c:v",
            "libsvtav1",
            "-preset",
            "12",
            "-g",
            "60",
            "-pix_fmt",
            "yuv420p10le",
            "-c:a",
            "aac",
            coded.to_str().unwrap(),
        ],
    );
    let colours = "av1_metadata=color_primaries=9:transfer_characteristics=16:matrix_coefficients=9";
    ffmpeg(
        &tools,
        &[
            "-i",
            coded.to_str().unwrap(),
            "-c",
            "copy",
            "-bsf:v",
            colours,
            clip.to_str().unwrap(),
        ],
    );
    let cores = std::thread::available_parallelism().map_or(1, usize::from);
    for tone_mapping in [ToneMapping::Zimg, ToneMapping::Placebo] {
        let ffmpeg_ = Ffmpeg::new(PHOTOLIBD.into(), tools.clone(), 1)
            .unwrap()
            .with_tone_mapping(tone_mapping);
        for role in ["preview", "sprite", "video_proxy_720"] {
            let out = dir.path().join(format!("{role}-{tone_mapping:?}"));
            std::fs::create_dir_all(&out).unwrap();
            let started = std::time::Instant::now();
            let made = ffmpeg_.render(role, &clip, "video/mp4", &out).await;
            let took = started.elapsed().as_secs_f64();
            eprintln!(
                "{seconds} s of 4K HDR10, {cores} cores, {tone_mapping:?}: {role} in {took:.1} s ({})",
                made.map_or_else(
                    |failure| format!("{failure:?}").chars().take(400).collect::<String>(),
                    |_| "made".to_owned()
                )
            );
        }
    }
}

/// The CIE 1976 Lab of an sRGB colour.
fn lab([r, g, b]: [i32; 3]) -> [f64; 3] {
    let linear = |c: i32| {
        let c = f64::from(c) / 255.0;
        if c <= 0.04045 {
            c / 12.92
        } else {
            ((c + 0.055) / 1.055).powf(2.4)
        }
    };
    let (r, g, b) = (linear(r), linear(g), linear(b));
    let xyz = [
        (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047,
        0.2126 * r + 0.7152 * g + 0.0722 * b,
        (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883,
    ];
    let f = |t: f64| {
        if t > 0.008856 {
            t.cbrt()
        } else {
            7.787 * t + 16.0 / 116.0
        }
    };
    let [x, y, z] = xyz.map(f);
    [116.0 * y - 16.0, 500.0 * (x - y), 200.0 * (y - z)]
}

/// The ΔE of two posters over the 16 patches and 11 points of the ramp: the mean, the largest and the greys' mean.
fn delta_e(a: &[u8], b: &[u8]) -> (f64, f64, f64) {
    let point = |rgb: &[u8], x: usize| [0, 1, 2].map(|c| i32::from(rgb[(300 * WIDTH + x) * 3 + c]));
    let mut pairs: Vec<([i32; 3], [i32; 3])> = (0..16)
        .map(|n| (patch(a, n / 8, n % 8), patch(b, n / 8, n % 8)))
        .collect();
    pairs.extend((0..11).map(|n| (point(a, 20 + n * 60), point(b, 20 + n * 60))));
    let all: Vec<f64> = (pairs.iter())
        .map(|(x, y)| {
            let (x, y) = (lab(*x), lab(*y));
            ((x[0] - y[0]).powi(2) + (x[1] - y[1]).powi(2) + (x[2] - y[2]).powi(2)).sqrt()
        })
        .collect();
    let greys = all[..8].iter().sum::<f64>() / 8.0;
    (
        all.iter().sum::<f64>() / all.len() as f64,
        all.iter().copied().fold(0.0, f64::max),
        greys,
    )
}

#[tokio::test(flavor = "multi_thread")]
async fn the_cpu_conversion_stays_within_a_small_colour_difference_of_libplacebos() {
    let tools = tools();
    let dir = tempfile::tempdir().unwrap();
    let auto = Ffmpeg::new(PHOTOLIBD.into(), tools.clone(), 1).unwrap();
    let forced = Ffmpeg::new(PHOTOLIBD.into(), tools.clone(), 1)
        .unwrap()
        .with_tone_mapping(ToneMapping::Placebo);
    if auto.mapper(false).await != Ok(Mapper::Placebo) {
        // No Vulkan device works inside the sandbox: Auto is zimg, and asking for libplacebo says why it cannot.
        assert_eq!(auto.mapper(false).await, Ok(Mapper::Zimg));
        assert!(
            matches!(forced.mapper(false).await, Err(Failure::Unsupported(why)) if why.contains("libplacebo")),
            "libplacebo neither runs nor says why"
        );
        return;
    }
    assert_eq!(forced.mapper(false).await, Ok(Mapper::Placebo));
    // The software device is slow for video: `auto` gives a stream to zimg, `placebo` to libplacebo.
    assert_eq!(auto.mapper(true).await, Ok(Mapper::Zimg));
    assert_eq!(forced.mapper(true).await, Ok(Mapper::Placebo));
    for (name, signal) in [("ref-pq", Signal::Pq), ("ref-hlg", Signal::Hlg)] {
        let clip = clip(&tools, dir.path(), name, signal, TAGGED);
        let placebo = poster(&tools, &clip, dir.path(), ToneMapping::Placebo).await;
        assert_correct(&format!("{name} by libplacebo"), &placebo);
        let zimg = poster(&tools, &clip, dir.path(), ToneMapping::Zimg).await;
        let (mean, largest, greys) = delta_e(&zimg, &placebo);
        eprintln!("{name}: zimg against libplacebo: mean ΔE {mean:.2}, largest {largest:.2}, greys {greys:.2}");
        assert!(
            mean <= 5.0 && largest <= 20.0 && greys <= 3.5,
            "{name}: ΔE {mean:.2} {largest:.2} {greys:.2}"
        );
    }
}
