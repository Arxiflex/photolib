//! Adaptive streaming (photolib-design docs/08 §5.1, §5.4, §5.8; ADR-0246): every video with R1 gets an HLS ladder of
//! fMP4 segments on one grid of source time, a 2 s segment and then 4 s ones, so that players switch rungs anywhere.
//! R1 is the stored proxy, served in slices by the index its render kept; the other rungs, and R1 of an original that
//! is its own, are encoded on demand by one sandboxed FFmpeg per video and rung into a segment cache on local disk:
//! the saver rung from R1, which decodes cheaply and is SDR already, R2 from the original.

use std::{
    collections::{HashMap, HashSet},
    fmt::Write,
    io::SeekFrom,
    ops::Range,
    path::{Path, PathBuf},
    sync::{Arc, Mutex, MutexGuard, PoisonError},
    time::{Duration, Instant},
};

use axum::{
    body::{Body, Bytes},
    http::StatusCode,
};
use futures::{StreamExt, stream};
use nix::{
    sys::signal::{Signal, killpg},
    unistd::Pid,
};
use photolib_storage::{Hash, Local, journal::Journal};
use serde_json::{Value, json};
use sqlx::PgPool;
use tokio::{
    io::{AsyncReadExt, AsyncSeekExt},
    process::Child,
};
use tokio_util::sync::CancellationToken;
use uuid::Uuid;

use crate::{
    external::{self, Libraries},
    video::{Ffmpeg, Ladder, R1, Source, fit, ratio},
};

/// The rungs, lowest first: playback starts on the lowest (docs/08 §5.1).
#[rustfmt::skip]
pub const RUNGS: [(&str, Ladder); 3] = [
    ("saver", Ladder { short: 480, bit_rate: 1_000_000, audio_bit_rate: 96_000, ..R1 }),
    ("r1", R1),
    ("r2", Ladder { short: 1080, bit_rate: 6_000_000, audio_bit_rate: 160_000, ..R1 }),
];

/// The HDR rung's pieces, which its muxer cut at the original's key frames, are its segments.
const HDR: Ladder = Ladder {
    gop_ms: 4000,
    segment_ms: 4000,
    ..R1
};

/// How many pieces a session makes beyond the furthest one asked for before it pauses: three segments.
const AHEAD: u32 = 6;
/// How long a request waits for a piece before it hears 503.
const WAIT: Duration = Duration::from_secs(10);
/// How long a rung whose FFmpeg failed is not tried again.
const COOL: Duration = Duration::from_secs(30);
/// H.264 High at level 4.1 or below, and AAC-LC.
const CODECS: [&str; 2] = ["avc1.640029", "mp4a.40.2"];

/// A video as the ladder sees it.
#[derive(Clone)]
pub struct Video {
    /// Its asset.
    pub asset: Uuid,
    library: Uuid,
    original: File,
    /// R1 when it is stored apart from the original.
    stored: Option<Stored>,
    /// What R1's render found of the original.
    pub source: Source,
}

/// A file of a video.
#[derive(Clone)]
struct File {
    id: Uuid,
    storage: String,
    key: String,
    hash: Option<Vec<u8>>,
    size: i64,
}

/// A file's row, store, key, hash and size, as the database gives them.
type FileRow = (Uuid, String, String, Option<Vec<u8>>, i64);

impl From<FileRow> for File {
    fn from((id, storage, key, hash, size): FileRow) -> Self {
        Self {
            id,
            storage,
            key,
            hash,
            size,
        }
    }
}

#[derive(Clone)]
struct Stored {
    file: File,
    init: u64,
    /// Each piece's offset, length and milliseconds.
    pieces: Vec<[u64; 3]>,
    /// The file in the cache that holds them, instead of `file` in a store (the HDR rung's).
    local: Option<PathBuf>,
}

/// A rung of a video: stored slices of R1, or encoded on demand into `dir`.
#[derive(Clone)]
struct Rung {
    name: &'static str,
    ladder: Ladder,
    stored: Option<Stored>,
    /// What it is encoded from, unless stored: R1 for the saver rung where R1 is stored, else the original.
    input: File,
    /// What its paths carry, so that a new original or recipe never meets a kept segment.
    version: String,
    dir: PathBuf,
    /// Each piece's milliseconds.
    pieces: Vec<u64>,
}

/// What the ladder may use.
pub struct Room {
    /// The cache's directory, which the ladder empties.
    pub dir: PathBuf,
    /// The most the cache holds.
    pub bytes: u64,
    /// How many sessions encode at once.
    pub sessions: usize,
    /// How long after the last request a session stops.
    pub idle: Duration,
}

/// The ladder of every video: its playlists, its stored R1 and its sessions and segment cache.
pub struct Hls {
    pool: PgPool,
    journal: Arc<Journal>,
    libraries: Arc<Libraries>,
    ffmpeg: Option<Ffmpeg>,
    room: Room,
    state: Mutex<State>,
    /// Held while a session starts, which may copy its input first.
    starting: tokio::sync::Mutex<()>,
}

#[derive(Default)]
struct State {
    running: HashMap<PathBuf, Session>,
    /// What the cache holds, by path: bytes, and when last used.
    held: HashMap<PathBuf, (u64, Instant)>,
    failed: HashMap<PathBuf, Instant>,
    /// The cache directories of HDR copies being made.
    copying: HashSet<PathBuf>,
}

/// One FFmpeg making the pieces of one rung from `from` on.
struct Session {
    child: Child,
    from: u32,
    /// The first piece not yet made.
    next: u32,
    /// The furthest piece asked for.
    wanted: u32,
    paused: bool,
    asked: Instant,
    /// Whether FFmpeg has exited, and how.
    ended: Option<bool>,
    /// The copy in the cache it reads, if one.
    input: Option<PathBuf>,
    said: Arc<Mutex<Vec<u8>>>,
}

impl Session {
    fn signal(&self, signal: Signal) {
        if let Some(group) = self.child.id().and_then(|pid| i32::try_from(pid).ok()) {
            // It may have exited already.
            killpg(Pid::from_raw(group), signal).ok();
        }
    }
}

impl Drop for Session {
    fn drop(&mut self) {
        self.signal(Signal::SIGKILL);
    }
}

/// What a request finds of a piece.
enum Watch {
    Coming,
    Start,
    /// The rung ends before it.
    Ended,
    Failed,
}

impl Hls {
    /// The ladder within `room`; without `ffmpeg`, R1 alone where it is stored.
    pub fn new(
        pool: PgPool,
        journal: Arc<Journal>,
        libraries: Arc<Libraries>,
        ffmpeg: Option<Ffmpeg>,
        room: Room,
    ) -> std::io::Result<Self> {
        match std::fs::remove_dir_all(&room.dir) {
            Err(e) if e.kind() != std::io::ErrorKind::NotFound => return Err(e),
            _ => std::fs::create_dir_all(room.dir.join("sources"))?,
        }
        Ok(Self {
            pool,
            journal,
            libraries,
            ffmpeg,
            room,
            state: Mutex::default(),
            starting: tokio::sync::Mutex::const_new(()),
        })
    }

    fn state(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(PoisonError::into_inner)
    }

    /// Whether every session is encoding.
    fn busy(&self) -> bool {
        self.state().running.values().filter(|s| s.ended.is_none()).count() >= self.room.sessions
    }

    /// Looks after the sessions and the cache until `shutdown`, then stops every session.
    pub async fn run(self: Arc<Self>, shutdown: CancellationToken) {
        while !shutdown.is_cancelled() {
            self.tick();
            tokio::select! {
                () = shutdown.cancelled() => {}
                () = tokio::time::sleep(Duration::from_millis(100)) => {}
            }
        }
        self.state().running.clear();
    }

    /// Notes the pieces each session made, pauses one that is far enough ahead and resumes one that is not, stops
    /// those nobody asks anything of, and keeps the cache within its budget, least recently used first.
    fn tick(&self) {
        let mut state = self.state();
        let State {
            running, held, failed, ..
        } = &mut *state;
        let now = Instant::now();
        running.retain(|dir, session| {
            while let Ok(meta) = std::fs::metadata(piece(dir, session.next)) {
                let (bytes, _) = held.entry(dir.clone()).or_insert((0, now));
                *bytes = bytes.saturating_add(meta.len());
                session.next = session.next.saturating_add(1);
            }
            if session.next > session.from {
                promote(dir, session.from);
            }
            if session.ended.is_none()
                && let Ok(Some(status)) = session.child.try_wait()
            {
                session.ended = Some(status.success());
                if !status.success() {
                    let said = session.said.lock().map(|s| String::from_utf8_lossy(&s).into_owned());
                    tracing::warn!(dir = %dir.display(), %status, said = said.unwrap_or_default(), "a rung failed");
                    failed.insert(dir.clone(), now);
                    return false;
                }
            }
            let ahead = session.next > session.wanted.saturating_add(AHEAD);
            if session.ended.is_none() && ahead != session.paused {
                session.signal(if ahead { Signal::SIGSTOP } else { Signal::SIGCONT });
                session.paused = ahead;
            }
            session.asked.elapsed() < self.room.idle
        });
        failed.retain(|_, at| at.elapsed() < COOL);
        let mut total: u64 = held.values().map(|(bytes, _)| bytes).sum();
        while total > self.room.bytes {
            let in_use =
                |path: &PathBuf| running.contains_key(path) || running.values().any(|s| s.input.as_ref() == Some(path));
            let Some(oldest) = (held.iter())
                .filter(|(path, _)| !in_use(path))
                .min_by_key(|(_, (_, used))| *used)
                .map(|(path, _)| path.clone())
            else {
                break;
            };
            let bytes = held.remove(&oldest).map_or(0, |(bytes, _)| bytes);
            std::fs::remove_dir_all(&oldest).ok();
            total = total.saturating_sub(bytes);
        }
    }

    /// The video `asset` once it has R1: its source's facts, and R1's index where R1 is stored apart.
    pub async fn video(&self, asset: Uuid) -> Result<Option<Video>, sqlx::Error> {
        let row: Option<(Uuid, FileRow, FileRow, Value)> = sqlx::query_as(
            "SELECT a.library_id, (o.id, o.storage, o.key, o.content_hash, o.size),
               (p.id, p.storage, p.key, p.content_hash, p.size), p.render_spec
             FROM assets a
             JOIN asset_files o ON o.asset_id = a.id AND o.role = 'original' AND o.state = 'present'
             JOIN LATERAL (SELECT id, storage, key, content_hash, size, render_spec FROM asset_files
               WHERE asset_id = a.id AND role = 'video_proxy_720' AND state = 'present' AND render_spec ? 'source'
               ORDER BY created_at DESC, id DESC LIMIT 1) p ON true
             WHERE a.id = $1",
        )
        .bind(asset)
        .fetch_optional(&self.pool)
        .await?;
        let Some((library, original, proxy, spec)) = row else {
            return Ok(None);
        };
        let field = |path: &str| spec.pointer(path).cloned().unwrap_or_default();
        let Ok(source) = serde_json::from_value(field("/source")) else {
            return Ok(None);
        };
        let index = json!([field("/hls/init"), field("/hls/pieces")]);
        let stored = (serde_json::from_value::<(u64, Vec<[u64; 3]>)>(index).ok())
            .filter(|_| field("/original") != true)
            .map(|(init, pieces)| Stored {
                file: proxy.into(),
                init,
                pieces,
                local: None,
            });
        Ok(Some(Video {
            asset,
            library,
            original: original.into(),
            stored,
            source,
        }))
    }

    /// The rung `name` of `video`, when it has one.
    fn rung(&self, video: &Video, name: &str) -> Option<Rung> {
        if name == "hdr" {
            video.source.hdr_range()?;
            let stored = self.hdr_stored(video)?;
            let pieces = stored.pieces.iter().map(|[.., ms]| *ms).collect();
            let dir = self.hdr_dir(video);
            let version = dir.file_name()?.to_string_lossy().trim_start_matches("hdr-").to_owned();
            return Some(Rung {
                name: "hdr",
                ladder: HDR,
                stored: Some(stored),
                input: video.original.clone(),
                version,
                dir,
                pieces,
            });
        }
        let (name, ladder) = *RUNGS.iter().find(|(known, _)| *known == name)?;
        let stored = video.stored.clone().filter(|_| name == "r1");
        let short = video.source.width.min(video.source.height);
        let encodes = self.ffmpeg.is_some() && self.room.sessions > 0 && (name != "r2" || short > R1.short);
        if stored.is_none() && !encodes {
            return None;
        }
        let input = match &video.stored {
            Some(r1) if name != "r2" => r1.file.clone(),
            _ => video.original.clone(),
        };
        let hash = blake3::hash(json!([input.id, name, ladder]).to_string().as_bytes()).to_hex();
        let version: String = hash.chars().take(16).collect();
        let pieces = match &stored {
            Some(stored) => stored.pieces.iter().map(|[.., ms]| *ms).collect(),
            None => plan(video.source.duration, ladder.gop_ms),
        };
        Some(Rung {
            name,
            ladder,
            stored,
            input,
            dir: self.room.dir.join(format!("{name}-{version}")),
            version,
            pieces,
        })
    }

    /// The master playlist of `video`, its URIs ending in `query`, starting at `start` seconds, without rungs none:
    /// the stored ones, and the others while sessions are free; only the lowest for data saver (docs/08 §5.8). The
    /// lowest rung's session starts at once, while the player reads the playlists.
    pub async fn master(
        self: &Arc<Self>,
        video: &Video,
        saver: bool,
        hdr: bool,
        start: Option<f64>,
        query: &str,
    ) -> Option<String> {
        let busy = self.busy();
        let mut offered: Vec<Rung> = (RUNGS.iter())
            .filter_map(|(name, _)| self.rung(video, name))
            .filter(|rung| !busy || rung.stored.is_some())
            .collect();
        if saver {
            offered.truncate(1);
        }
        // A client that shows HDR gets the original's picture as it is, beside the SDR rungs (ADR-0390): as a variant
        // of its own, which players on HDR displays choose by its VIDEO-RANGE. Not for the data saver.
        let hdr = hdr && !saver && self.ensure_hdr(video).await;
        let lowest = offered.first()?;
        if lowest.stored.is_none() {
            let (hls, video, name) = (self.clone(), video.clone(), lowest.name);
            let at = start.map_or(0, ms);
            tokio::spawn(async move { hls.warm(&video, name, at).await });
        }
        let [h264, aac] = CODECS;
        let codecs = if video.source.audio {
            format!("{h264},{aac}")
        } else {
            h264.to_owned()
        };
        let mut text = format!(
            "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-INDEPENDENT-SEGMENTS\n{}",
            starting(start)
        );
        for rung in offered {
            let (width, height) = fit((video.source.width, video.source.height), rung.ladder.short, u32::MAX);
            let (peak, average) = rung.bandwidth(video.source.audio);
            let fps = ratio(&video.source.rate, '/')
                .unwrap_or(30.0)
                .min(f64::from(rung.ladder.fps));
            writeln!(
                text,
                "#EXT-X-STREAM-INF:BANDWIDTH={peak},AVERAGE-BANDWIDTH={average},CODECS=\"{codecs}\",\
                 RESOLUTION={width}x{height},FRAME-RATE={fps:.3}\n{}.m3u8{query}",
                rung.name,
            )
            .ok()?;
        }
        if hdr && let Some(rung) = self.rung(video, "hdr") {
            let range = video.source.hdr_range()?;
            let (peak, average) = rung.bandwidth(video.source.audio);
            let fps = ratio(&video.source.rate, '/').unwrap_or(30.0);
            let codecs = if video.source.audio {
                format!("{},{aac}", video.source.hls_codec)
            } else {
                video.source.hls_codec.clone()
            };
            writeln!(
                text,
                "#EXT-X-STREAM-INF:BANDWIDTH={peak},AVERAGE-BANDWIDTH={average},CODECS=\"{codecs}\",\
                 RESOLUTION={}x{},FRAME-RATE={fps:.3},VIDEO-RANGE={range}\n{}.m3u8{query}",
                video.source.width, video.source.height, rung.name,
            )
            .ok()?;
        }
        Some(text)
    }

    /// The media playlist of rung `name` of `video`.
    pub async fn playlist(
        self: &Arc<Self>,
        video: &Video,
        name: &str,
        start: Option<f64>,
        query: &str,
    ) -> Option<String> {
        if name == "hdr" && !self.ensure_hdr(video).await {
            return None;
        }
        let rung = self.rung(video, name)?;
        let lengths: Vec<u64> = (rung.segments().into_iter())
            .map(|range| rung.pieces.get(range).unwrap_or_default().iter().sum())
            .collect();
        let target = lengths.iter().map(|ms| ms.div_ceil(1000)).max().unwrap_or(1);
        let prefix = format!("{}/{}/", rung.name, rung.version);
        let mut text = format!(
            "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:{target}\n#EXT-X-MEDIA-SEQUENCE:0\n\
             #EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-INDEPENDENT-SEGMENTS\n{}#EXT-X-MAP:URI=\"{prefix}init.mp4{query}\"\n",
            starting(start),
        );
        for (n, ms) in lengths.into_iter().enumerate() {
            let seconds = Duration::from_millis(ms).as_secs_f64();
            writeln!(text, "#EXTINF:{seconds:.3},\n{prefix}{n}.m4s{query}").ok()?;
        }
        Some(text + "#EXT-X-ENDLIST\n")
    }

    /// The init segment of rung `name` of `video` at `version`, from a session that starts at `start` seconds when
    /// none runs.
    pub async fn init(
        self: &Arc<Self>,
        video: &Video,
        name: &str,
        version: &str,
        start: f64,
    ) -> Result<Bytes, StatusCode> {
        if name == "hdr" && !self.ensure_hdr(video).await {
            return Err(StatusCode::SERVICE_UNAVAILABLE);
        }
        let rung = (self.rung(video, name).filter(|r| r.version == version)).ok_or(StatusCode::NOT_FOUND)?;
        if let Some(stored) = &rung.stored {
            return self.slice(stored, 0..stored.init).await;
        }
        let asked = Instant::now();
        while !self.promote(&rung.dir) {
            if !self.state().running.contains_key(&rung.dir) {
                let first = rung.piece_at(ms(start));
                self.made(video, &rung, first, first).await?;
            } else if asked.elapsed() >= WAIT {
                return Err(StatusCode::SERVICE_UNAVAILABLE);
            } else {
                tokio::time::sleep(Duration::from_millis(50)).await;
            }
        }
        self.used(&rung.dir);
        let init = tokio::fs::read(rung.dir.join("init.mp4")).await;
        init.map(Bytes::from).map_err(|_| StatusCode::SERVICE_UNAVAILABLE)
    }

    /// Segment `n` of rung `name` of `video` at `version`: its pieces, each sent once made, so that the first goes
    /// over the link while the encoder makes the next.
    pub async fn segment(
        self: &Arc<Self>,
        video: &Video,
        name: &str,
        version: &str,
        n: usize,
    ) -> Result<Body, StatusCode> {
        if name == "hdr" && !self.ensure_hdr(video).await {
            return Err(StatusCode::SERVICE_UNAVAILABLE);
        }
        let rung = (self.rung(video, name).filter(|r| r.version == version)).ok_or(StatusCode::NOT_FOUND)?;
        let range = rung.segments().get(n).cloned().ok_or(StatusCode::NOT_FOUND)?;
        if let Some(stored) = &rung.stored {
            let pieces = stored.pieces.get(range).unwrap_or_default();
            let (Some([offset, ..]), Some([last, length, _])) = (pieces.first(), pieces.last()) else {
                return Err(StatusCode::NOT_FOUND);
            };
            return Ok(Body::from(
                self.slice(stored, *offset..last.saturating_add(*length)).await?,
            ));
        }
        let number = |n: usize| u32::try_from(n).unwrap_or(u32::MAX);
        let (start, last) = (number(range.start), number(range.end).saturating_sub(1));
        let first = self
            .made(video, &rung, start, last)
            .await?
            .ok_or(StatusCode::NOT_FOUND)?;
        let first = tokio::fs::read(first)
            .await
            .map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;
        let (hls, video) = (self.clone(), video.clone());
        let rest = stream::unfold(start.saturating_add(1), move |n| {
            let (hls, video, rung) = (hls.clone(), video.clone(), rung.clone());
            async move {
                let made = match hls.made(&video, &rung, n, last).await {
                    _ if n > last => return None,
                    Ok(Some(path)) => tokio::fs::read(path).await,
                    Ok(None) => return None,
                    Err(status) => Err(std::io::Error::other(status.to_string())),
                };
                let next = if made.is_ok() { n.saturating_add(1) } else { u32::MAX };
                Some((made.map(Bytes::from), next))
            }
        });
        Ok(Body::from_stream(
            stream::once(async { Ok(Bytes::from(first)) }).chain(rest),
        ))
    }

    async fn slice(&self, stored: &Stored, range: Range<u64>) -> Result<Bytes, StatusCode> {
        if let Some(path) = &stored.local {
            let unavailable = |error: std::io::Error| {
                tracing::warn!(%error, "the HDR copy cannot be read");
                StatusCode::SERVICE_UNAVAILABLE
            };
            let mut file = tokio::fs::File::open(path).await.map_err(unavailable)?;
            file.seek(SeekFrom::Start(range.start)).await.map_err(unavailable)?;
            let length = usize::try_from(range.end.saturating_sub(range.start)).map_err(|_| StatusCode::NOT_FOUND)?;
            let mut bytes = vec![0; length];
            file.read_exact(&mut bytes).await.map_err(unavailable)?;
            self.used(path.parent().unwrap_or(path));
            return Ok(Bytes::from(bytes));
        }
        let store = (self.journal.stores().get(&stored.file.storage)).map_err(|_| StatusCode::SERVICE_UNAVAILABLE)?;
        let bytes = store.get(&stored.file.key, Some(range)).await.map_err(|error| {
            tracing::warn!(%error, "R1 cannot be read");
            StatusCode::SERVICE_UNAVAILABLE
        })?;
        Ok(Bytes::from(bytes))
    }

    /// Where the HDR copy of `video` lives in the cache: named by the original, so that no other file meets it.
    fn hdr_dir(&self, video: &Video) -> PathBuf {
        let hash = blake3::hash(json!([video.original.id, "hdr"]).to_string().as_bytes()).to_hex();
        self.room.dir.join(format!("hdr-{}", &hash[..16]))
    }

    /// The HDR copy of `video` once it is made: its pieces' index, and the file they are ranges of.
    fn hdr_stored(&self, video: &Video) -> Option<Stored> {
        let dir = self.hdr_dir(video);
        let index: Value = serde_json::from_slice(&std::fs::read(dir.join("index.json")).ok()?).ok()?;
        let (init, pieces) = serde_json::from_value(json!([index.get("init"), index.get("pieces")])).ok()?;
        Some(Stored {
            file: video.original.clone(),
            init,
            pieces,
            local: Some(dir.join("hdr.mp4")),
        })
    }

    /// Whether `video` has its HDR copy: made by one sandboxed FFmpeg, which copies the original's pictures into pieces
    /// at its key frames, once, in the cache. A request waits for it up to 10 s, then does without; the copy goes on.
    async fn ensure_hdr(self: &Arc<Self>, video: &Video) -> bool {
        if self.ffmpeg.is_none() || video.source.hdr_range().is_none() {
            return false;
        }
        let dir = self.hdr_dir(video);
        let asked = Instant::now();
        loop {
            if dir.join("index.json").exists() {
                self.used(&dir);
                return true;
            }
            let starts = {
                let mut state = self.state();
                if state.failed.contains_key(&dir) {
                    return false;
                }
                state.copying.insert(dir.clone())
            };
            if starts {
                let (hls, video, dir) = (self.clone(), video.clone(), dir.clone());
                tokio::spawn(async move {
                    let made = hls.copy_hdr(&video, &dir).await;
                    let mut state = hls.state();
                    state.copying.remove(&dir);
                    if !made {
                        state.failed.insert(dir, Instant::now());
                    }
                });
            }
            if asked.elapsed() >= WAIT {
                return false;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    }

    /// Makes the HDR copy of `video` in `dir`.
    async fn copy_hdr(&self, video: &Video, dir: &Path) -> bool {
        let Some(ffmpeg) = &self.ffmpeg else {
            return false;
        };
        let Ok((input, _copy)) = self.local(video.library, &video.original).await else {
            return false;
        };
        let part = dir.with_extension("part");
        std::fs::remove_dir_all(&part).ok();
        if let Err(error) = std::fs::create_dir_all(&part) {
            tracing::warn!(%error, "the HDR copy cannot start");
            return false;
        }
        let made = match ffmpeg.remux(&video.source, &input, &part).await {
            Ok(index) => std::fs::write(part.join("index.json"), index.to_string()).map_err(|e| e.to_string()),
            Err(failure) => Err(format!("{failure:?}")),
        };
        let bytes = std::fs::metadata(part.join("hdr.mp4")).map_or(0, |m| m.len());
        if let Err(why) = made.and_then(|()| std::fs::rename(&part, dir).map_err(|e| e.to_string())) {
            tracing::warn!(why, "the HDR copy failed");
            std::fs::remove_dir_all(&part).ok();
            return false;
        }
        self.state().held.insert(dir.to_path_buf(), (bytes, Instant::now()));
        true
    }

    /// Starts the session of rung `name` at `at` milliseconds unless one runs, as a player will soon ask for it.
    async fn warm(&self, video: &Video, name: &str, at: u64) {
        if let Some(rung) = self.rung(video, name) {
            let first = rung.piece_at(at);
            // A player that asks for the piece hears what went wrong.
            self.made(video, &rung, first, first).await.ok();
        }
    }

    /// The file of piece `n` of `rung` once it is made, asked for with pieces up to `last`, by the session that makes
    /// it or one started there; none when the rung ends before it, and 503 after 10 s or when no session is free.
    async fn made(&self, video: &Video, rung: &Rung, n: u32, last: u32) -> Result<Option<PathBuf>, StatusCode> {
        let asked = Instant::now();
        loop {
            let path = piece(&rung.dir, n);
            if path.exists() {
                self.used(&rung.dir);
                return Ok(Some(path));
            }
            match self.watch(&rung.dir, n, last) {
                Watch::Coming => {}
                Watch::Ended => return Ok(None),
                Watch::Failed => return Err(StatusCode::SERVICE_UNAVAILABLE),
                Watch::Start => {
                    let _starting = self.starting.lock().await;
                    if matches!(self.watch(&rung.dir, n, last), Watch::Start) {
                        self.start(video, rung, n, last).await?;
                    }
                }
            }
            if asked.elapsed() >= WAIT {
                return Err(StatusCode::SERVICE_UNAVAILABLE);
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
    }

    /// What becomes of piece `first` of the rung in `dir`, asked for with pieces up to `last`: the session that
    /// makes it is resumed; one that is elsewhere is stopped, for a new one to start there.
    fn watch(&self, dir: &Path, first: u32, last: u32) -> Watch {
        let mut state = self.state();
        if state.failed.contains_key(dir) {
            return Watch::Failed;
        }
        let Some(session) = state.running.get_mut(dir) else {
            return Watch::Start;
        };
        session.asked = Instant::now();
        if !(session.from..=session.next.saturating_add(AHEAD)).contains(&first) {
            state.running.remove(dir);
            return Watch::Start;
        }
        if session.ended.is_some() {
            return if first >= session.next {
                Watch::Ended
            } else {
                Watch::Coming
            };
        }
        session.wanted = session.wanted.max(last);
        if session.paused {
            session.signal(Signal::SIGCONT);
            session.paused = false;
        }
        Watch::Coming
    }

    /// Starts a session of `rung` at piece `from`, which pieces up to `wanted` are asked of.
    async fn start(&self, video: &Video, rung: &Rung, from: u32, wanted: u32) -> Result<(), StatusCode> {
        let unavailable = StatusCode::SERVICE_UNAVAILABLE;
        let ffmpeg = self.ffmpeg.as_ref().ok_or(StatusCode::NOT_FOUND)?;
        if self.busy() {
            return Err(unavailable);
        }
        let (input, copy) = self.local(video.library, &rung.input).await?;
        tokio::fs::create_dir_all(&rung.dir).await.map_err(|_| unavailable)?;
        // R1 is upright and SDR, and lasts as long as its pieces.
        let source = match &video.stored {
            Some(r1) if rung.input.id == r1.file.id => Source {
                hdr: false,
                tone: None,
                duration: Duration::from_millis(r1.pieces.iter().map(|[.., ms]| ms).sum()).as_secs_f64(),
                ..video.source.clone()
            },
            _ => video.source.clone(),
        };
        let mut child = (ffmpeg.rung(&rung.ladder, &source, &input, from, &rung.dir).await).map_err(|failure| {
            tracing::warn!(?failure, "a rung cannot start");
            unavailable
        })?;
        let said: Arc<Mutex<Vec<u8>>> = Arc::default();
        if let Some(mut stderr) = child.stderr.take() {
            let said = said.clone();
            tokio::spawn(async move {
                let mut buffer = [0; 4096];
                while let Ok(n @ 1..) = stderr.read(&mut buffer).await {
                    let mut said = said.lock().unwrap_or_else(PoisonError::into_inner);
                    let room = buffer.len().saturating_sub(said.len());
                    said.extend(buffer.iter().take(n.min(room)));
                }
            });
        }
        let session = Session {
            child,
            from,
            next: from,
            wanted,
            paused: false,
            asked: Instant::now(),
            ended: None,
            input: copy,
            said,
        };
        self.state().running.insert(rung.dir.clone(), session);
        Ok(())
    }

    /// `file` of a video in `library` as a local file, and the copy in the cache it is, if one: an object's or an
    /// external file's, copied once and kept while the cache has room.
    async fn local(&self, library: Uuid, file: &File) -> Result<(PathBuf, Option<PathBuf>), StatusCode> {
        let unavailable = |error: String| {
            tracing::warn!(%error, "a video cannot be read");
            StatusCode::SERVICE_UNAVAILABLE
        };
        let copies = self.room.dir.join("sources").join(file.id.to_string());
        let copied = |dir: &Path| Some(std::fs::read_dir(dir).ok()?.next()?.ok()?.path());
        if let Some(copy) = copied(&copies) {
            self.used(&copies);
            return Ok((copy, Some(copies)));
        }
        let part = copies.with_extension("part");
        std::fs::remove_dir_all(&part).ok();
        std::fs::create_dir_all(&part).map_err(|e| unavailable(e.to_string()))?;
        let local = if file.storage == external::STORE {
            let mut conn = self.pool.acquire().await.map_err(|e| unavailable(e.to_string()))?;
            let copy = self.libraries.copy(&mut conn, library, &file.key, file.size, &part);
            copy.await.map_err(unavailable)?
        } else {
            let hash = file.hash.clone().unwrap_or_default().try_into();
            let hash = Hash(hash.map_err(|_| unavailable("no hash".into()))?);
            let local = self.journal.local(&file.storage, &file.key, hash, &part).await;
            local.map_err(|e| unavailable(e.to_string()))?
        };
        if let Local::InPlace(original) = local {
            std::fs::remove_dir_all(&part).ok();
            return Ok((original, None));
        }
        std::fs::rename(&part, &copies).map_err(|e| unavailable(e.to_string()))?;
        let size = u64::try_from(file.size).unwrap_or_default();
        self.state().held.insert(copies.clone(), (size, Instant::now()));
        let copy = copied(&copies).ok_or_else(|| unavailable("the copy went".into()))?;
        Ok((copy, Some(copies)))
    }

    /// Whether the rung in `dir` has its init segment, made whole by the session that runs there.
    fn promote(&self, dir: &Path) -> bool {
        let from = self.state().running.get(dir).map(|s| s.from);
        dir.join("init.mp4").exists() || from.is_some_and(|from| piece(dir, from).exists() && promote(dir, from))
    }

    fn used(&self, path: &Path) {
        if let Some((_, used)) = self.state().held.get_mut(path) {
            *used = Instant::now();
        }
    }
}

impl Rung {
    /// The pieces of each segment: the first alone, which starts playback sooner, then a segment's worth at a time.
    fn segments(&self) -> Vec<Range<usize>> {
        let per = self
            .ladder
            .segment_ms
            .checked_div(self.ladder.gop_ms)
            .unwrap_or(1)
            .max(1);
        let per = usize::try_from(per).unwrap_or(1);
        let mut segments: Vec<_> = (!self.pieces.is_empty()).then_some(0..1).into_iter().collect();
        while let Some(at) = segments.last().map(|s| s.end).filter(|at| *at < self.pieces.len()) {
            segments.push(at..at.saturating_add(per).min(self.pieces.len()));
        }
        segments
    }

    /// The piece that holds `ms`, the first when none does.
    fn piece_at(&self, ms: u64) -> u32 {
        let mut end = 0u64;
        let found = self.pieces.iter().position(|length| {
            end = end.saturating_add(*length);
            end > ms
        });
        found.and_then(|n| u32::try_from(n).ok()).unwrap_or(0)
    }

    /// The peak and average bits a second of its segments: measured where it is stored, else the caps.
    fn bandwidth(&self, audio: bool) -> (u64, u64) {
        let Some(stored) = &self.stored else {
            let sound = if audio { self.ladder.audio_bit_rate } else { 0 };
            let rate = u64::from(self.ladder.bit_rate.saturating_add(sound));
            return (rate.saturating_mul(6) / 5, rate);
        };
        let rate = |pieces: &[[u64; 3]]| {
            let (bytes, ms) = (pieces.iter()).fold((0u64, 0u64), |(b, m), [_, length, ms]| {
                (b.saturating_add(*length), m.saturating_add(*ms))
            });
            bytes.saturating_mul(8000).checked_div(ms).unwrap_or(0)
        };
        let peak = (self.segments().into_iter())
            .map(|range| rate(stored.pieces.get(range).unwrap_or_default()))
            .max()
            .unwrap_or(0);
        (peak, rate(&stored.pieces))
    }
}

/// Puts the init segment of the session that started at `from` in place, once its first piece is whole, as every
/// session writes the same; whether it is.
fn promote(dir: &Path, from: u32) -> bool {
    let init = dir.join("init.mp4");
    init.exists() || std::fs::rename(dir.join(format!("init-{from}.mp4")), &init).is_ok()
}

/// The piece `n` of the rung in `dir`.
fn piece(dir: &Path, n: u32) -> PathBuf {
    dir.join(format!("{n}.m4s"))
}

/// `seconds` in whole milliseconds.
fn ms(seconds: f64) -> u64 {
    Duration::try_from_secs_f64(seconds).map_or(0, |d| u64::try_from(d.as_millis()).unwrap_or(u64::MAX))
}

/// The milliseconds of each GOP of `gop_ms` in `duration` seconds of picture; a last fraction shorter than a tenth
/// of a second, which FFmpeg may or may not make, is left out.
fn plan(duration: f64, gop_ms: u32) -> Vec<u64> {
    let (total, gop) = (ms(duration), u64::from(gop_ms).max(1));
    let count = total.saturating_sub(100).div_ceil(gop).max(1);
    (0..count)
        .map(|n| total.saturating_sub(n.saturating_mul(gop)).min(gop))
        .collect()
}

fn starting(start: Option<f64>) -> String {
    start.map_or_else(String::new, |s| {
        format!("#EXT-X-START:TIME-OFFSET={s:.3},PRECISE=YES\n")
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn file() -> File {
        File {
            id: Uuid::nil(),
            storage: String::new(),
            key: String::new(),
            hash: None,
            size: 0,
        }
    }

    fn rung(pieces: Vec<u64>, stored: Option<Vec<[u64; 3]>>) -> Rung {
        Rung {
            name: "r1",
            ladder: R1,
            stored: stored.map(|pieces| Stored {
                file: file(),
                init: 100,
                pieces,
                local: None,
            }),
            input: file(),
            version: "v".into(),
            dir: PathBuf::new(),
            pieces,
        }
    }

    #[test]
    fn pieces_of_two_seconds_make_a_first_segment_of_two_then_segments_of_four() {
        assert_eq!(plan(10.0, 2000), [2000, 2000, 2000, 2000, 2000]);
        assert_eq!(plan(10.05, 2000), [2000, 2000, 2000, 2000, 2000]);
        assert_eq!(plan(10.5, 2000), [2000, 2000, 2000, 2000, 2000, 500]);
        assert_eq!(plan(0.04, 2000), [40]);
        let segments = |count| rung(vec![2000; count], None).segments();
        assert_eq!(segments(1), std::iter::once(0..1).collect::<Vec<_>>());
        assert_eq!(segments(2), [0..1, 1..2]);
        assert_eq!(segments(6), [0..1, 1..3, 3..5, 5..6]);
        let r = rung(plan(10.5, 2000), None);
        assert_eq!(
            [0, 1999, 2000, 9999, 10_000, 10_499, 99_999].map(|ms| r.piece_at(ms)),
            [0, 0, 1, 4, 5, 5, 0]
        );
    }

    #[test]
    fn bandwidth_is_measured_where_r1_is_stored_and_the_caps_otherwise() {
        assert_eq!(rung(vec![], None).bandwidth(true), (3_153_600, 2_628_000));
        assert_eq!(rung(vec![], None).bandwidth(false), (3_000_000, 2_500_000));
        // 2 s of 500 kB, then 4 s of 1.5 MB, then 1 s of 0.1 MB.
        let pieces = vec![
            [100, 500_000, 2000],
            [500_100, 1_000_000, 2000],
            [1_500_100, 500_000, 2000],
            [2_000_100, 100_000, 1000],
        ];
        let r = rung(vec![2000, 2000, 2000, 1000], Some(pieces));
        assert_eq!(r.bandwidth(true), (3_000_000, 2_400_000));
    }
}
