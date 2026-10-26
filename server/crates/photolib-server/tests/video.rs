//! Every video of the media corpus gets its poster, sprites and a rendition that plays everywhere: the original, or R1.
//! The corpus' videos carry real containers and metadata around payloads that do not decode, so each runs as a twin:
//! a decodable clip FFmpeg makes with the same container, codec, picture size, rotation, frame rate class, HDR
//! signalling and interlacing, the audio such files carry, and metadata that no rendition may keep. Set
//! `PHOTOLIB_PLAYABLE` to a directory to collect what browsers must play (`tools/video/play.mjs`).

mod common;

use std::{
    os::unix::{ffi::OsStrExt, fs::PermissionsExt},
    panic::AssertUnwindSafe,
    path::{Path, PathBuf},
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    time::Duration,
};

use common::{AGAIN, FIXTURE, ffmpeg, run, tools};
use photolib_db::{
    migrate::{Upgrade, embedded, upgrade},
    testpg,
};
use photolib_jobs::{
    Handler, Job, NewJob, Timing, Worker,
    reconcile::{self, Profile},
};
use photolib_media::Failure;
use photolib_server::{
    external::Libraries,
    ingest::sniff::sniff,
    video::{Ffmpeg, Output, TRANSCODE, Transcode, renditions, spec},
};
use photolib_spawn::{Running, tool};
use photolib_storage::{
    BlobStore, Hash,
    fs::FsStore,
    journal::Journal,
    marker::{Candidate, Stores},
    testing::garage_store,
};
use serde_json::{Value, json};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

const PHOTOLIBD: &str = env!("CARGO_BIN_EXE_photolibd");
const CORPUS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../../../testdata/corpus");
/// The golden records of the corpus' videos.
fn videos() -> Vec<Value> {
    let mut found = vec![];
    let mut dirs = vec![Path::new(CORPUS).join("golden")];
    while let Some(dir) = dirs.pop() {
        for entry in std::fs::read_dir(dir).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                dirs.push(path);
            } else {
                let record: Value = serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
                if record["media"]["kind"] == "video" {
                    found.push(record);
                }
            }
        }
    }
    found.sort_by(|a, b| a["path"].as_str().cmp(&b["path"].as_str()));
    assert!(found.len() > 70, "the corpus is missing: {CORPUS}");
    found
}

fn has(record: &Value, quirk: &str) -> bool {
    record["quirks"].as_array().unwrap().iter().any(|q| q == quirk)
}

/// The corpus file itself when it decodes, else its twin, in `dir`.
fn twin(tools: &Path, record: &Value, dir: &Path) -> PathBuf {
    let path = record["path"].as_str().unwrap();
    let file = Path::new(CORPUS).join("files").join(path);
    if !record["notes"].as_str().unwrap_or("").starts_with("Placeholder") {
        return file;
    }
    let metadata = &record["metadata"];
    let (width, height) = (
        metadata["width"].as_u64().unwrap(),
        metadata["height"].as_u64().unwrap(),
    );
    let (muxer, extension, audio) = match record["media"]["mime"].as_str().unwrap() {
        "video/mp4" => ("mp4", "mp4", "aac"),
        "video/quicktime" => ("mov", "mov", "aac"),
        "video/mp2t" => ("mpegts", "mts", "ac3"),
        "video/webm" => ("webm", "webm", "libopus"),
        "video/x-matroska" => ("matroska", "mkv", "ac3"),
        "video/x-msvideo" => ("avi", "avi", "pcm_s16le"),
        "video/mpeg" => ("vob", "mpg", "mp2"),
        "video/x-flv" => ("flv", "flv", "libmp3lame"),
        "video/3gpp" => ("3gp", "3gp", "aac"),
        "video/x-ms-wmv" => ("asf", "wmv", "wmav2"),
        other => panic!("{path}: no twin for {other}"),
    };
    // One thread each for the graph and the encoders, which run several at a time: threads are a shared limit, and
    // an encoder that cannot start one fails, or hangs as kvazaar's pool does (photolib-design#444).
    let codec = match metadata["codec"].as_str().unwrap() {
        "h264" => "-c:v libopenh264 -b:v 4M",
        "hevc" => "-c:v libkvazaar -kvazaar-params preset=ultrafast,threads=0 -tag:v hvc1",
        "av1" => "-c:v libsvtav1 -preset 12 -svtav1-params lp=1",
        "vp8" => "-c:v libvpx -deadline realtime -b:v 1M",
        "vp9" => "-c:v libvpx-vp9 -deadline realtime -cpu-used 8 -b:v 1M",
        "mpeg2" => "-c:v mpeg2video -b:v 6M -flags +ildct+ilme -top 1",
        "dv" => "-c:v dvvideo -pix_fmt yuv420p",
        "xvid" => "-c:v mpeg4 -vtag XVID",
        "flv1" => "-c:v flv",
        "h263" => "-c:v h263",
        "wmv" => "-c:v wmv2",
        "prores" => "-c:v prores_ks",
        other => panic!("{path}: no encoder for {other}"),
    };
    let rate = match metadata["codec"].as_str().unwrap() {
        "dv" | "mpeg2" => "25",
        _ if has(record, "slow_motion") || has(record, "slow_motion_sef") => "120",
        _ if width * height > 1920 * 1088 => "10",
        _ => "30",
    };
    // Kvazaar encodes multiples of 8; HEVC's conformance window crops the rest, as cameras do.
    let hevc = metadata["codec"] == "hevc";
    let coded = if hevc {
        (width.next_multiple_of(8), height.next_multiple_of(8))
    } else {
        (width, height)
    };
    let source = format!("testsrc2=s={}x{}:r={rate}:d=2[v];sine=r=48000:d=2[a]", coded.0, coded.1);
    let encoded = dir.join(format!("encoded.{extension}"));
    let mut args = vec!["-filter_complex_threads", "1", "-filter_complex", &source];
    args.extend("-map [v] -map [a] -threads 1".split(' '));
    args.extend(codec.split(' '));
    args.extend(["-c:a", audio, "-ac", "2", "-shortest", "-f", muxer]);
    for tag in [
        "creation_time=2023-05-14T10:00:00Z",
        "location=+48.8584+002.2945/",
        "title=Ann at home",
    ] {
        args.extend(["-metadata", tag]);
    }
    if muxer == "mp4" || muxer == "mov" {
        args.extend(["-movflags", "+faststart"]);
    }
    args.push(encoded.to_str().unwrap());
    ffmpeg(tools, &args);
    let transfer = match () {
        _ if has(record, "hdr_hlg") || has(record, "dolby_vision") => Some(18),
        _ if has(record, "hdr_pq") => Some(16),
        _ => None,
    };
    let twin = dir.join(format!("twin.{extension}"));
    let rotation = match metadata["orientation"].as_u64() {
        Some(6) => Some("-90"),
        _ => None,
    };
    if !hevc && rotation.is_none() {
        std::fs::rename(&encoded, &twin).unwrap();
    } else {
        let mut colour = format!(
            "hevc_metadata=crop_right={}:crop_bottom={}",
            coded.0 - width,
            coded.1 - height
        );
        if let Some(t) = transfer {
            colour += &format!(":transfer_characteristics={t}:colour_primaries=9:matrix_coefficients=9");
        }
        let colour = hevc.then_some(colour);
        let mut args = vec![];
        if let Some(rotation) = rotation {
            args.extend(["-display_rotation", rotation]);
        }
        args.extend(["-i", encoded.to_str().unwrap(), "-map", "0", "-c", "copy"]);
        if let Some(colour) = &colour {
            args.extend(["-bsf:v", colour]);
        }
        args.push(twin.to_str().unwrap());
        ffmpeg(tools, &args);
    }
    if has(record, "truncated_file") {
        let bytes = std::fs::read(&twin).unwrap();
        std::fs::write(&twin, &bytes[..bytes.len() * 3 / 5]).unwrap();
    }
    twin
}

/// ffprobe's view of `file`, outside the sandbox.
fn probe(tools: &Path, file: &Path) -> Value {
    let json = run(
        tool(tools.join("ffprobe"))
            .args("-v error -print_format json -show_format -show_streams".split(' '))
            .arg(file),
        FIXTURE,
    );
    serde_json::from_slice(&json).unwrap()
}

/// The picture as shown: (width, height) turned by the display matrix.
fn shown(probe: &Value) -> (u64, u64) {
    let video = probe["streams"]
        .as_array()
        .unwrap()
        .iter()
        .find(|s| s["codec_type"] == "video")
        .unwrap();
    let turned = (video["side_data_list"].as_array().into_iter().flatten())
        .any(|d| d["rotation"].as_f64().is_some_and(|r| r.abs() == 90.0));
    let (width, height) = (video["width"].as_u64().unwrap(), video["height"].as_u64().unwrap());
    if turned { (height, width) } else { (width, height) }
}

/// The tags no rendition may carry: they could say where and when, and who is in the picture.
fn personal(probe: &Value) -> Vec<String> {
    let mut tagged = vec![&probe["format"]["tags"]];
    tagged.extend(probe["streams"].as_array().unwrap().iter().map(|s| &s["tags"]));
    (tagged.into_iter().filter_map(Value::as_object).flatten())
        .filter(|(key, _)| {
            let technical = "encoder handler_name vendor_id language major_brand minor_version compatible_brands";
            !technical.split(' ').any(|k| k == key.as_str())
        })
        .map(|(key, value)| format!("{key}={value}"))
        .collect()
}

/// Whether a render that failed so is tried again, as its job would be: a machine with no thread or time to spare
/// says nothing about the file, and the suites beside this one share both.
fn again(failure: &Failure) -> bool {
    matches!(failure, Failure::Transient(_) | Failure::Timeout(_))
}

/// Renders `role` into a new directory `out` as its `transcode` job would, trying a failure that says nothing about
/// the file again.
async fn render(
    ffmpeg: &Ffmpeg,
    role: &str,
    input: &Path,
    mime: &str,
    out: &Path,
) -> Result<Option<Vec<Output>>, Failure> {
    let mut pauses = AGAIN.iter();
    loop {
        std::fs::create_dir(out).unwrap();
        match (ffmpeg.render(role, input, mime, out).await, pauses.next()) {
            (Err(failure), Some(pause)) if again(&failure) => {
                eprintln!("{role} of {}, again in {pause:?}: {failure:?}", input.display());
                std::fs::remove_dir_all(out).unwrap();
                tokio::time::sleep(*pause).await;
            }
            (done, _) => return done,
        }
    }
}

/// Renders every role of one corpus video. Returns the file browsers must play, its picture as shown, and what is
/// wrong.
async fn check(ffmpeg: &Ffmpeg, tools: &Path, record: &Value, dir: &Path) -> (PathBuf, (u64, u64), Vec<String>) {
    let input = tokio::task::block_in_place(|| twin(tools, record, dir));
    let head = std::fs::read(&input).unwrap();
    let mime = sniff(&head[..head.len().min(4096)]).mime;
    let source = probe(tools, &input);
    let display = shown(&source);
    let sound = source["streams"]
        .as_array()
        .unwrap()
        .iter()
        .any(|s| s["codec_type"] == "audio");
    let mut problems = vec![];
    let mut proxy = None;
    for role in ["thumb_s", "thumb_m", "preview", "sprite", "video_proxy_720"] {
        let out = dir.join(role);
        let outputs = match render(ffmpeg, role, &input, mime, &out).await {
            Ok(outputs) => outputs,
            Err(failure) => {
                problems.push(format!("{role}: {failure:?}"));
                continue;
            }
        };
        if role == "video_proxy_720" {
            proxy = Some(
                outputs
                    .as_ref()
                    .map(|o| o.iter().map(|o| o.path.clone()).collect::<Vec<_>>()),
            );
        }
        for Output { path, .. } in outputs.iter().flatten() {
            let made = probe(tools, path);
            let leaked = personal(&made);
            if !leaked.is_empty() {
                problems.push(format!("{role} keeps {leaked:?}"));
            }
            let (width, height) = shown(&made);
            if role != "sprite" && (width > height) != (display.0 > display.1) {
                problems.push(format!("{role} is {width}x{height}, shown as {display:?}"));
            }
            if role == "video_proxy_720" {
                problems.extend(r1(&made, display, sound));
            }
        }
    }
    // What docs/08 §5.1 says plays everywhere, from the golden record rather than from ffprobe; a truncated file
    // plays only as far as it goes, and not at all in Firefox.
    let metadata = &record["metadata"];
    let (width, height) = (
        metadata["width"].as_u64().unwrap(),
        metadata["height"].as_u64().unwrap(),
    );
    let direct = ["video/mp4", "video/quicktime"].contains(&record["media"]["mime"].as_str().unwrap())
        && metadata["codec"] == "h264"
        && width.max(height) <= 1920
        && width.min(height) <= 1080
        && !has(record, "slow_motion")
        && !has(record, "truncated_file");
    let playable = match (direct, proxy) {
        (true, Some(None)) => input,
        (false, Some(Some(files))) if files.len() == 1 => files[0].clone(),
        (_, proxy) => {
            problems.push(format!("direct play {direct}, R1 {proxy:?}"));
            input
        }
    };
    let playable_shown = shown(&probe(tools, &playable));
    (playable, playable_shown, problems)
}

/// What R1 must be (docs/08 §5.1, §5.3): H.264 4:2:0, progressive, upright, SDR BT.709, a short side of 720 or less,
/// at most 30 frames a second, and AAC-LC stereo at 48 kHz if the original has sound.
fn r1(probe: &Value, display: (u64, u64), sound: bool) -> Vec<String> {
    let streams = probe["streams"].as_array().unwrap();
    let video = streams.iter().find(|s| s["codec_type"] == "video").unwrap();
    let audio = streams.iter().find(|s| s["codec_type"] == "audio");
    let (num, den) = video["avg_frame_rate"].as_str().unwrap().split_once('/').unwrap();
    let fps = num.parse::<f64>().unwrap() / den.parse::<f64>().unwrap();
    let ((width, height), short) = (shown(probe), display.0.min(display.1).min(720));
    let facts = [
        (
            video["codec_name"] == "h264" && video["pix_fmt"] == "yuv420p",
            "H.264 4:2:0",
        ),
        (video["field_order"] == "progressive", "progressive"),
        (video.get("side_data_list").is_none(), "no display matrix"),
        (
            video["color_transfer"] == "bt709" && video["color_primaries"] == "bt709",
            "BT.709",
        ),
        (width.min(height).abs_diff(short) <= 1, "a 720 short side"),
        (fps <= 30.0, "30 fps"),
        (
            match audio {
                Some(a) => {
                    sound
                        && a["codec_name"] == "aac"
                        && a["profile"] == "LC"
                        && a["sample_rate"] == "48000"
                        && a["channels"] == 2
                }
                None => !sound,
            },
            "AAC-LC stereo at 48 kHz, or silence",
        ),
    ];
    facts
        .into_iter()
        .filter(|(met, _)| !met)
        .map(|(_, fact)| format!("R1 is not {fact}: {video} {audio:?}"))
        .collect()
}

#[tokio::test(flavor = "multi_thread")]
async fn every_corpus_video_gets_a_poster_sprites_and_a_rendition_that_plays_everywhere() {
    let tools = tools();
    // A few at a time, each on its share of the cores: threads are a limit shared with the suites beside this one.
    let ffmpeg = Arc::new(Ffmpeg::new(PHOTOLIBD.into(), tools.clone(), 4).unwrap());
    let scratch = tempfile::tempdir_in(env!("CARGO_TARGET_TMPDIR")).unwrap();
    let slots = Arc::new(tokio::sync::Semaphore::new(4));
    let mut checks = tokio::task::JoinSet::new();
    let videos = videos();
    for (n, record) in videos.iter().cloned().enumerate() {
        let (ffmpeg, tools, slots) = (ffmpeg.clone(), tools.clone(), slots.clone());
        let dir = scratch.path().join(n.to_string());
        checks.spawn(async move {
            let _slot = slots.acquire().await.unwrap();
            std::fs::create_dir(&dir).unwrap();
            (
                record["path"].as_str().unwrap().to_owned(),
                check(&ffmpeg, &tools, &record, &dir).await,
            )
        });
    }
    let (mut wrong, mut playable) = (vec![], vec![]);
    while let Some(done) = checks.join_next().await {
        match done {
            Ok((path, (file, shown, problems))) => {
                wrong.extend(problems.into_iter().map(|problem| format!("{path}: {problem}")));
                playable.push(json!({"path": path, "file": file, "width": shown.0, "height": shown.1}));
            }
            Err(error) => wrong.push(error.to_string()),
        }
    }
    assert!(wrong.is_empty(), "{} problems:\n{}", wrong.len(), wrong.join("\n"));
    assert_eq!(playable.len(), videos.len());
    if let Some(dir) = std::env::var_os("PHOTOLIB_PLAYABLE") {
        let dir = PathBuf::from(dir);
        for (n, entry) in playable.iter_mut().enumerate() {
            let file = PathBuf::from(entry["file"].as_str().unwrap());
            let name = format!("{n}.{}", file.extension().unwrap().to_str().unwrap());
            std::fs::copy(&file, dir.join(&name)).unwrap();
            entry["file"] = json!(name);
        }
        std::fs::write(dir.join("playable.json"), serde_json::to_vec_pretty(&playable).unwrap()).unwrap();
    }
}

/// The corpus records at `paths`, as twins in `dir`.
fn twins(tools: &Path, paths: &[&str], dir: &Path) -> Vec<PathBuf> {
    let videos = videos();
    (paths.iter().enumerate())
        .map(|(n, path)| {
            let record = videos.iter().find(|r| r["path"] == *path).unwrap();
            let dir = dir.join(n.to_string());
            std::fs::create_dir(&dir).unwrap();
            twin(tools, record, &dir)
        })
        .collect()
}

/// A library on `store` holding `videos` as assets, each original put through the journal.
async fn library(pool: &sqlx::PgPool, journal: &Journal, videos: &[PathBuf]) -> Vec<Uuid> {
    let (owner, library) = (Uuid::now_v7(), Uuid::now_v7());
    sqlx::query("INSERT INTO users (id, handle, display_name) VALUES ($1, 'ann', 'Ann')")
        .bind(owner)
        .execute(pool)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO libraries (id, owner_id, name, kind, privacy, root_uri, store)
         VALUES ($1, $2, 'Photos', 'managed', 'standard', 'photos', 'media')",
    )
    .bind(library)
    .bind(owner)
    .execute(pool)
    .await
    .unwrap();
    let mut assets = vec![];
    for video in videos {
        let (asset, bytes) = (Uuid::now_v7(), std::fs::read(video).unwrap());
        let (key, hash) = (format!("libraries/{library}/originals/{asset}"), Hash::of(&bytes));
        let op = journal.put("media", &key, video, hash).await.unwrap();
        let mut tx = pool.begin().await.unwrap();
        sqlx::query(
            "INSERT INTO assets (id, library_id, owner_id, source, media_kind) VALUES ($1, $2, $3, 'upload', 'video')",
        )
        .bind(asset)
        .bind(library)
        .bind(owner)
        .execute(&mut *tx)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO asset_files (id, asset_id, role, storage, key, mime, size, content_hash)
             VALUES ($1, $2, 'original', 'media', $3, $4, $5, $6)",
        )
        .bind(Uuid::now_v7())
        .bind(asset)
        .bind(&key)
        .bind(sniff(&bytes[..bytes.len().min(4096)]).mime)
        .bind(bytes.len() as i64)
        .bind(hash.0.to_vec())
        .execute(&mut *tx)
        .await
        .unwrap();
        op.settle(&mut tx).await.unwrap();
        tx.commit().await.unwrap();
        assets.push(asset);
    }
    assets
}

/// A rendition's row: asset, role, store, key, hash, size and render spec.
type Rendition = (Uuid, String, String, String, Vec<u8>, i64, Value);

/// A video that plays everywhere, one that does not (HEVC, portrait) and one that does not decode, on the filesystem
/// and on an object store: each gets its renditions in its original's store, readable there, with their render
/// specs; the first is its own R1, and the broken one's jobs fail with a reason until they are dead.
#[tokio::test(flavor = "multi_thread")]
async fn transcode_jobs_store_renditions_beside_the_original_on_every_kind_of_store() {
    let tools = tools();
    let scratch = tempfile::tempdir_in(env!("CARGO_TARGET_TMPDIR")).unwrap();
    let mut videos = twins(
        &tools,
        &["video/pixel.mp4", "video/iphone-portrait.mov"],
        scratch.path(),
    );
    let broken = Path::new(CORPUS).join("files/video/iphone.mov");
    videos.push(broken);
    let data = scratch.path().join("data");
    std::fs::create_dir(&data).unwrap();
    let stores: [Arc<dyn BlobStore>; 2] = [
        Arc::new(FsStore::open(&data, Duration::from_secs(30)).await.unwrap()),
        Arc::new(garage_store(Duration::from_secs(30))),
    ];
    for store in stores {
        let db = testpg::database().await;
        upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
        let candidate = Candidate {
            name: "media".into(),
            store: store.clone(),
            adopt: true,
        };
        let stores = Stores::check(&db.pool, Uuid::now_v7(), vec![candidate]).await;
        let journal = Arc::new(Journal::start(db.pool.clone(), stores).await.unwrap());
        let assets = library(&db.pool, &journal, &videos).await;
        let profile = Profile {
            renditions: renditions(),
            ..Profile::default()
        };
        let mut conn = db.pool.acquire().await.unwrap();
        assert_eq!(reconcile::assets(&mut conn, &profile, &assets).await.unwrap(), 15);
        let ffmpeg = Ffmpeg::new(PHOTOLIBD.into(), tools.clone(), 2).unwrap();
        let work = tempfile::tempdir_in(env!("CARGO_TARGET_TMPDIR")).unwrap();
        let handler = Transcode::new(journal.clone(), work.path(), ffmpeg, libraries()).unwrap();
        transcode(&db.pool, handler).await;

        let failed: Vec<(String, String)> = sqlx::query_as(
            "SELECT idempotency_key, status || ': ' || error FROM jobs WHERE status <> 'done' ORDER BY 1",
        )
        .fetch_all(&db.pool)
        .await
        .unwrap();
        assert_eq!(failed.len(), 5, "{failed:?}");
        for (key, error) in &failed {
            assert!(
                key.contains(&assets[2].to_string()) && error.starts_with("dead: DecoderCrash"),
                "{key}: {error}"
            );
        }
        let rows: Vec<Rendition> = sqlx::query_as(
            "SELECT asset_id, role, storage, key, content_hash, size, render_spec FROM asset_files
             WHERE role <> 'original' ORDER BY asset_id, role, key",
        )
        .fetch_all(&db.pool)
        .await
        .unwrap();
        let roles = |asset: Uuid| {
            let mut roles: Vec<&str> = rows.iter().filter(|r| r.0 == asset).map(|r| r.1.as_str()).collect();
            roles.dedup();
            roles
        };
        for asset in &assets[..2] {
            assert_eq!(
                roles(*asset),
                ["preview", "sprite", "thumb_m", "thumb_s", "video_proxy_720"]
            );
        }
        for (asset, role, storage, key, hash, size, render_spec) in &rows {
            assert_eq!(storage, "media");
            assert_eq!(render_spec["spec_id"], spec(role).unwrap()["spec_id"]);
            let bytes = store.get(key, None).await.unwrap();
            assert_eq!(
                (Hash::of(&bytes).0.to_vec(), bytes.len() as i64),
                (hash.clone(), *size),
                "{role}"
            );
            let original = role == "video_proxy_720" && *asset == assets[0];
            assert_eq!(key.starts_with("libraries/"), original, "{role} of {asset} is at {key}");
            assert_eq!(render_spec["original"] == true, original);
        }
        let sprite = &rows.iter().find(|r| r.0 == assets[1] && r.1 == "sprite").unwrap().6;
        let layout = ["sheet", "every_ms", "columns", "rows", "width", "height"].map(|k| sprite[k].as_u64());
        // The twin stores 1080 × 1920 turned a quarter, as its corpus record says: shown as 1920 × 1080.
        assert_eq!(layout.map(Option::unwrap), [0, 1000, 10, 10, 160, 90]);
        let open: i64 = sqlx::query_scalar("SELECT count(*) FROM file_intents WHERE state IN ('planned', 'switched')")
            .fetch_one(&db.pool)
            .await
            .unwrap();
        assert_eq!(open, 0);
    }
}

/// A video of an external library renders before it is hashed: from a copy, never beside it in the library, but in
/// the data directory; where it plays everywhere, it is its own R1 where it lies.
#[tokio::test(flavor = "multi_thread")]
async fn an_external_video_renders_into_the_data_directory_before_it_is_hashed() {
    let tools = tools();
    let scratch = tempfile::tempdir_in(env!("CARGO_TARGET_TMPDIR")).unwrap();
    let video = twins(&tools, &["video/pixel.mp4"], scratch.path()).remove(0);
    let (nas, data) = (scratch.path().join("nas"), scratch.path().join("data"));
    for dir in [&nas, &data] {
        std::fs::create_dir(dir).unwrap();
    }
    std::fs::copy(&video, nas.join("clip.mp4")).unwrap();
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
    let candidate = Candidate {
        name: "local".into(),
        store: Arc::new(FsStore::open(&data, Duration::from_secs(30)).await.unwrap()),
        adopt: true,
    };
    let stores = Stores::check(&db.pool, Uuid::now_v7(), vec![candidate]).await;
    let journal = Arc::new(Journal::start(db.pool.clone(), stores).await.unwrap());
    let (owner, library, asset) = (Uuid::now_v7(), Uuid::now_v7(), Uuid::now_v7());
    let bytes = std::fs::read(&video).unwrap();
    sqlx::raw_sql(&format!(
        "INSERT INTO users (id, handle, display_name) VALUES ('{owner}', 'ann', 'Ann');
         INSERT INTO libraries (id, owner_id, name, kind, access, root_uri)
         VALUES ('{library}', '{owner}', 'NAS', 'external', 'ro', '{}');
         INSERT INTO assets (id, library_id, owner_id, source, media_kind)
         VALUES ('{asset}', '{library}', '{owner}', 'scan', 'video');
         INSERT INTO asset_files (id, asset_id, role, storage, key, mime, size)
         VALUES ('{}', '{asset}', 'original', 'external', 'clip.mp4', '{}', {})",
        nas.display(),
        Uuid::now_v7(),
        sniff(&bytes[..4096]).mime,
        bytes.len(),
    ))
    .execute(&db.pool)
    .await
    .unwrap();
    let profile = Profile {
        renditions: renditions(),
        ..Profile::default()
    };
    let mut conn = db.pool.acquire().await.unwrap();
    reconcile::assets(&mut conn, &profile, &[asset]).await.unwrap();
    std::fs::set_permissions(&nas, std::fs::Permissions::from_mode(0o555)).unwrap();
    let work = tempfile::tempdir_in(env!("CARGO_TARGET_TMPDIR")).unwrap();
    let ffmpeg = Ffmpeg::new(PHOTOLIBD.into(), tools, 2).unwrap();
    let handler = Transcode::new(journal, work.path(), ffmpeg, libraries()).unwrap();
    transcode(&db.pool, handler).await;

    let failed: Vec<String> = sqlx::query_scalar("SELECT coalesce(error, status) FROM jobs WHERE status <> 'done'")
        .fetch_all(&db.pool)
        .await
        .unwrap();
    assert_eq!(failed, Vec::<String>::new());
    type Row = (String, String, String, Option<Vec<u8>>, Value);
    let rows: Vec<Row> = sqlx::query_as(
        "SELECT role, storage, key, content_hash, render_spec FROM asset_files WHERE role <> 'original' ORDER BY role",
    )
    .fetch_all(&db.pool)
    .await
    .unwrap();
    let roles: Vec<&str> = rows.iter().map(|r| r.0.as_str()).collect();
    assert_eq!(roles, ["preview", "sprite", "thumb_m", "thumb_s", "video_proxy_720"]);
    for (role, storage, key, hash, spec) in &rows {
        if role == "video_proxy_720" {
            assert_eq!(
                (storage.as_str(), key.as_str(), hash, &spec["original"]),
                ("external", "clip.mp4", &None, &json!(true))
            );
        } else {
            let file = std::fs::read(data.join(key)).unwrap();
            assert_eq!(
                (storage.as_str(), hash),
                ("local", &Some(Hash::of(&file).0.to_vec())),
                "{role}"
            );
        }
    }
    let listed: Vec<_> = std::fs::read_dir(&nas)
        .unwrap()
        .map(|e| e.unwrap().file_name())
        .collect();
    assert_eq!(listed, ["clip.mp4"]);
}

fn libraries() -> Arc<Libraries> {
    Arc::new(Libraries::new(Duration::from_secs(30)))
}

/// Runs `handler` on the queued transcode jobs until each is done or dead, trying a failed one again within
/// seconds, where photolibd waits longer.
async fn transcode(pool: &sqlx::PgPool, handler: impl Handler + 'static) {
    let timing = Timing {
        poll_min: Duration::from_millis(10),
        poll_max: Duration::from_millis(50),
        retry: Duration::from_millis(250),
        ..Timing::default()
    };
    let shutdown = CancellationToken::new();
    let worker = Worker::new(pool.clone(), "test", 2, timing).handle(TRANSCODE, handler);
    let running = tokio::spawn(worker.run(shutdown.clone()));
    let pending = "SELECT count(*) FROM jobs WHERE status IN ('queued', 'running')";
    while sqlx::query_scalar::<_, i64>(pending).fetch_one(pool).await.unwrap() > 0 {
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    shutdown.cancel();
    running.await.unwrap();
}

/// A playlist posing as a video cannot make FFmpeg read another file, as it would outside the sandbox: the sandbox
/// lets it read its input only.
#[tokio::test(flavor = "multi_thread")]
async fn a_playlist_cannot_make_ffmpeg_read_another_file() {
    let tools = tools();
    let scratch = tempfile::tempdir_in(env!("CARGO_TARGET_TMPDIR")).unwrap();
    let elsewhere = twins(&tools, &["video/pixel.mp4"], scratch.path()).remove(0);
    let playlist = scratch.path().join("upload.mp4");
    let relative = elsewhere.strip_prefix(scratch.path()).unwrap().display();
    std::fs::write(&playlist, format!("ffconcat version 1.0\nfile '{relative}'\n")).unwrap();
    let unconfined = scratch.path().join("unconfined.webp");
    ffmpeg(
        &tools,
        &[
            "-i",
            playlist.to_str().unwrap(),
            "-frames:v",
            "1",
            unconfined.to_str().unwrap(),
        ],
    );
    assert!(
        std::fs::metadata(&unconfined).unwrap().len() > 0,
        "FFmpeg follows the playlist outside the sandbox"
    );
    let ffmpeg = Ffmpeg::new(PHOTOLIBD.into(), tools.clone(), 1).unwrap();
    let out = scratch.path().join("out");
    std::fs::create_dir(&out).unwrap();
    for role in ["thumb_s", "video_proxy_720"] {
        let rendered = ffmpeg.render(role, &playlist, "video/mp4", &out).await;
        assert!(rendered.is_err(), "{role}: {rendered:?}");
    }
    assert_eq!(std::fs::read_dir(&out).unwrap().count(), 0);
}

/// A fixture's command that fails, or outlives its limit and is killed, fails the test with its command line and
/// stderr.
#[test]
fn a_fixture_command_that_fails_or_hangs_fails_the_test_with_its_command_line_and_stderr() {
    let ffmpeg = tools().join("ffmpeg");
    let cases = [
        // In real time, a minute of video takes a minute.
        ("testsrc2=d=60", "timed out after 1s", "Input #0, lavfi"),
        ("nosuchsource", "exit status: 8", "No such filter: 'nosuchsource'"),
    ];
    for (input, status, stderr) in cases {
        let mut encode = tool(&ffmpeg);
        encode.args(["-nostdin", "-re", "-f", "lavfi", "-i", input, "-f", "null", "-"]);
        let start = Running::start();
        let failure =
            std::panic::catch_unwind(AssertUnwindSafe(|| run(&mut encode, Duration::from_secs(1)))).unwrap_err();
        let message = failure.downcast_ref::<String>().unwrap();
        assert!(
            start.elapsed() < Duration::from_secs(20),
            "the command ran {:?}",
            start.elapsed()
        );
        for part in [input, status, stderr] {
            assert!(message.contains(part), "{part} is not in: {message}");
        }
    }
}

/// A video that fades in from black gets a poster of its picture, not of the black.
#[tokio::test(flavor = "multi_thread")]
async fn the_poster_skips_a_fade_from_black() {
    let tools = tools();
    let scratch = tempfile::tempdir_in(env!("CARGO_TARGET_TMPDIR")).unwrap();
    let video = scratch.path().join("fade.mp4");
    let graph = "color=c=black:s=640x360:r=30:d=1,format=yuv420p[black];\
                 testsrc2=s=640x360:r=30:d=2,format=yuv420p[picture];[black][picture]concat=n=2";
    let args = [
        "-f",
        "lavfi",
        "-i",
        graph,
        "-c:v",
        "libopenh264",
        video.to_str().unwrap(),
    ];
    ffmpeg(&tools, &args);
    let ffmpeg = Ffmpeg::new(PHOTOLIBD.into(), tools.clone(), 1).unwrap();
    let out = scratch.path().join("out");
    std::fs::create_dir(&out).unwrap();
    let posters = ffmpeg
        .render("thumb_m", &video, "video/mp4", &out)
        .await
        .unwrap()
        .unwrap();
    let grey = run(
        tool(tools.join("ffmpeg"))
            .args(["-v", "error", "-i"])
            .arg(&posters[0].path)
            .args(["-f", "rawvideo", "-pix_fmt", "gray", "-"]),
        FIXTURE,
    );
    let mean = grey.iter().map(|&y| f64::from(y)).sum::<f64>() / grey.len() as f64;
    assert!(mean > 64.0, "the poster is dark: mean luma {mean}");
}

/// The most threads a process whose command line names `dir` had at once, sampled until `done`.
fn peak_threads(dir: &Path, done: &AtomicBool) -> usize {
    let name = dir.as_os_str().as_bytes();
    let mut peak = 0;
    while !done.load(Ordering::SeqCst) {
        for process in std::fs::read_dir("/proc").unwrap().flatten() {
            let cmdline = std::fs::read(process.path().join("cmdline")).unwrap_or_default();
            if cmdline.windows(name.len()).any(|part| part == name) {
                peak = peak.max(std::fs::read_dir(process.path().join("task")).map_or(0, Iterator::count));
            }
        }
        std::thread::sleep(Duration::from_millis(5));
    }
    peak
}

/// A render runs on its share of the cores, however many there are: FFmpeg's decoders and filters each start a thread
/// per core by default (51 threads for a sprite sheet on 16 cores), which the machine's pid limit can refuse.
#[tokio::test(flavor = "multi_thread")]
async fn a_render_runs_on_its_share_of_the_cores() {
    let tools = tools();
    let scratch = tempfile::tempdir_in(env!("CARGO_TARGET_TMPDIR")).unwrap();
    // Matroska, which R1 must replace.
    let video = scratch.path().join("clip.mkv");
    let mut args: Vec<&str> =
        "-f lavfi -i testsrc2=s=1920x1080:r=30:d=5 -f lavfi -i sine=d=5 -c:v libopenh264 -c:a aac"
            .split(' ')
            .collect();
    args.push(video.to_str().unwrap());
    ffmpeg(&tools, &args);
    let cores = std::thread::available_parallelism().unwrap().get();
    let ffmpeg = Ffmpeg::new(PHOTOLIBD.into(), tools, cores).unwrap();
    for role in ["thumb_s", "thumb_m", "preview", "sprite", "video_proxy_720"] {
        let (out, done) = (scratch.path().join(role), Arc::new(AtomicBool::new(false)));
        let peak = tokio::task::spawn_blocking({
            let (out, done) = (out.clone(), done.clone());
            move || peak_threads(&out, &done)
        });
        let rendered = render(&ffmpeg, role, &video, "video/x-matroska", &out).await;
        done.store(true, Ordering::SeqCst);
        assert!(rendered.unwrap().is_some(), "{role}");
        let peak = peak.await.unwrap();
        // A thread to decode, filter and encode each stream, one to demux and one to mux, beside the main one: 9 for
        // R1, which keeps the sound.
        assert!(
            (1..=9).contains(&peak),
            "{role} ran {peak} threads on one core of {cores}"
        );
    }
}

#[test]
fn a_render_is_tried_again_when_the_machine_had_no_thread_or_time_to_spare() {
    let again = |failure: fn(String) -> Failure| again(&failure(String::new()));
    assert!(again(Failure::Transient) && again(Failure::Timeout));
    assert!(!again(Failure::DecoderCrash) && !again(Failure::Unsupported) && !again(Failure::LimitExceeded));
}

/// A job that fails once, as a render may time out or a lease stall on a loaded machine, is tried again.
#[tokio::test(flavor = "multi_thread")]
async fn a_transcode_job_that_fails_once_is_tried_again() {
    struct Once(AtomicBool);
    #[async_trait::async_trait]
    impl Handler for Once {
        async fn run(&self, _: &Job, _: &mut sqlx::PgConnection) -> Result<(), String> {
            if self.0.swap(true, Ordering::SeqCst) {
                Ok(())
            } else {
                Err("Timeout".into())
            }
        }
    }
    let db = testpg::database().await;
    upgrade(&db.pool, &Upgrade::new(&embedded())).await.unwrap();
    let mut conn = db.pool.acquire().await.unwrap();
    photolib_jobs::enqueue(&mut conn, &NewJob::new(TRANSCODE, b"{}"))
        .await
        .unwrap();
    transcode(&db.pool, Once(AtomicBool::new(false))).await;
    let status: String = sqlx::query_scalar("SELECT status FROM jobs")
        .fetch_one(&db.pool)
        .await
        .unwrap();
    assert_eq!(status, "done");
}
