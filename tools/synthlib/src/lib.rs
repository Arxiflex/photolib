mod png;

use std::{
    collections::HashSet,
    fmt,
    fs::{self, File},
    io::{self, BufWriter, Write},
    path::{Path, PathBuf},
};

pub struct Config {
    pub assets: u64,
    pub seed: u64,
    pub shape: Shape,
}

/// A realistic library, or one of the pathological libraries of the performance budgets (docs/10 §3.7, §13).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Shape {
    Library,
    /// Every asset in a series of 2 to 13 near-identical shots, a second apart.
    NearDuplicates,
    /// Every asset taken at the same instant.
    OneTimestamp,
    /// Every asset taken on the same day.
    OneDay,
    /// The assets spread over `FOLDERS` folders.
    Folders,
    /// `ALBUMS` more albums, sharing the assets between them.
    Albums,
}

pub const FOLDERS: u64 = 5_000;
pub const ALBUMS: u64 = 10_000;

const SHAPES: [(Shape, &str); 6] = [
    (Shape::Library, "library"),
    (Shape::NearDuplicates, "near-duplicates"),
    (Shape::OneTimestamp, "one-timestamp"),
    (Shape::OneDay, "one-day"),
    (Shape::Folders, "folders"),
    (Shape::Albums, "albums"),
];

impl std::str::FromStr for Shape {
    type Err = String;

    fn from_str(name: &str) -> Result<Shape, String> {
        SHAPES.iter().find(|(_, n)| *n == name).map(|(shape, _)| *shape).ok_or(format!("unknown shape {name}"))
    }
}

impl fmt::Display for Shape {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.write_str(SHAPES.iter().find(|(shape, _)| shape == self).unwrap().1)
    }
}

/// 2026-01-01T00:00:00Z: ids are UUIDv7 stamped from here on, one millisecond apart, so they never collide.
const INGEST_MS: u64 = 1_767_225_600_000;
const FIRST_YEAR: i64 = 1990;
const LAST_YEAR: i64 = 2025;
/// Each year holds this many times the photos of the year before.
const GROWTH: f64 = 1.12;

struct Camera {
    make: &'static str,
    model: &'static str,
    w: u64,
    h: u64,
    prefix: &'static str,
    ext: &'static str,
    video_ext: &'static str,
}

const fn cam(make: &'static str, model: &'static str, w: u64, h: u64, file: [&'static str; 3]) -> Camera {
    Camera { make, model, w, h, prefix: file[0], ext: file[1], video_ext: file[2] }
}

struct Era {
    from: i64,
    cameras: &'static [Camera],
    /// Shares of geotagged photos, videos, panoramas and bursts.
    shares: [f64; 4],
}

/// Film scans, compact cameras, phones, then phones that record the time zone (EXIF 2.31); the time model in
/// `Gen::asset` goes by the index.
const ERAS: [Era; 4] = [
    Era {
        from: FIRST_YEAR,
        cameras: &[cam("Epson", "Perfection V600", 3000, 2000, ["scan_", "jpg", ""])],
        shares: [0.0; 4],
    },
    Era {
        from: 2003,
        cameras: &[
            cam("Canon", "PowerShot A70", 2048, 1536, ["IMG_", "JPG", "AVI"]),
            cam("Nikon", "COOLPIX P5000", 3648, 2736, ["DSCN", "JPG", "MOV"]),
            cam("Sony", "DSC-W55", 3072, 2304, ["DSC0", "JPG", "MPG"]),
        ],
        shares: [0.0, 0.04, 0.005, 0.0],
    },
    Era {
        from: 2010,
        cameras: &[
            cam("Apple", "iPhone 4S", 3264, 2448, ["IMG_", "JPG", "MOV"]),
            cam("Samsung", "GT-I9300", 3264, 2448, ["IMG_", "jpg", "mp4"]),
        ],
        shares: [0.7, 0.07, 0.01, 0.006],
    },
    Era {
        from: 2016,
        cameras: &[
            cam("Apple", "iPhone 12", 4032, 3024, ["IMG_", "HEIC", "MOV"]),
            cam("Google", "Pixel 7", 4080, 3072, ["PXL_", "jpg", "mp4"]),
        ],
        shares: [0.9, 0.1, 0.01, 0.01],
    },
];

struct Place {
    name: &'static str,
    lat: f64,
    lon: f64,
    zone: &'static str,
    /// Standard offset from UTC in minutes.
    offset: i64,
    /// Summer time by the EU rule; every other zone here has kept one offset since 2016.
    eu_dst: bool,
}

const HOME: Place = Place { name: "Berlin", lat: 52.52, lon: 13.405, zone: "Europe/Berlin", offset: 60, eu_dst: true };

const fn place(name: &'static str, lat: f64, lon: f64, zone: &'static str, offset: i64, eu_dst: bool) -> Place {
    Place { name, lat, lon, zone, offset, eu_dst }
}

/// Includes half- and three-quarter-hour offsets, the southern hemisphere and both sides of UTC.
static TRIPS: [Place; 12] = [
    place("Lisbon", 38.72, -9.14, "Europe/Lisbon", 0, true),
    place("Rome", 41.9, 12.5, "Europe/Rome", 60, true),
    place("Athens", 37.98, 23.73, "Europe/Athens", 120, true),
    place("Reykjavik", 64.15, -21.94, "Atlantic/Reykjavik", 0, false),
    place("Tokyo", 35.68, 139.69, "Asia/Tokyo", 540, false),
    place("Bangkok", 13.76, 100.5, "Asia/Bangkok", 420, false),
    place("Kathmandu", 27.72, 85.32, "Asia/Kathmandu", 345, false),
    place("Mumbai", 19.08, 72.88, "Asia/Kolkata", 330, false),
    place("Nairobi", -1.29, 36.82, "Africa/Nairobi", 180, false),
    place("Brisbane", -27.47, 153.03, "Australia/Brisbane", 600, false),
    place("Honolulu", 21.31, -157.86, "Pacific/Honolulu", -600, false),
    place("Phoenix", 33.45, -112.07, "America/Phoenix", -420, false),
];
static EVENTS: [&str; 8] = ["Birthday", "Wedding", "Graduation", "Christmas", "Picnic", "Concert", "Hiking", "Party"];

static NAMES: [&str; 16] = [
    "Anna", "Ben", "Chloe", "David", "Elif", "Finn", "Grace", "Hiro", "Ines", "Jonas", "Kofi", "Lina", "Mateo", "Nina",
    "Oskar", "Priya",
];
static PALETTE: [u32; 8] = [0xc05a4b, 0x4b7fc0, 0x5aa06e, 0xd9a441, 0x8e6cb8, 0x4fa8a8, 0xb86c8e, 0x7a7a7a];
static PETS: [&str; 4] = ["Bella", "Milo", "Luna", "Rex"];

const USERS: [(&str, &str); 6] = [
    ("alex", "Alex Morgan"),
    ("sam", "Sam Okafor"),
    ("kim", "Kim Novak"),
    ("noor", "Noor Haddad"),
    ("lea", "Lea Schmidt"),
    ("omar", "Omar Farouk"),
];

/// SplitMix64: small, fast and fully determined by the seed.
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    /// Uniform in `0..n`.
    fn below(&mut self, n: u64) -> u64 {
        ((self.next() as u128 * n as u128) >> 64) as u64
    }

    fn f64(&mut self) -> f64 {
        (self.next() >> 11) as f64 / (1u64 << 53) as f64
    }

    fn chance(&mut self, p: f64) -> bool {
        self.f64() < p
    }

    fn pick<'a, T>(&mut self, items: &'a [T]) -> &'a T {
        &items[self.below(items.len() as u64) as usize]
    }

    /// `x` moved by up to `by` either way.
    fn jitter(&mut self, x: f64, by: f64) -> f64 {
        x + (self.f64() - 0.5) * 2.0 * by
    }
}

/// Days since 1970-01-01 of a Gregorian date (Howard Hinnant's algorithm).
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let (era, yoe) = (y.div_euclid(400), y.rem_euclid(400));
    let doy = (153 * (m + if m > 2 { -3 } else { 9 }) + 2) / 5 + d - 1;
    era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719_468
}

fn civil_from_days(z: i64) -> (i64, i64, i64) {
    let z = z + 719_468;
    let (era, doe) = (z.div_euclid(146_097), z.rem_euclid(146_097));
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let (d, m) = (doy - (153 * mp + 2) / 5 + 1, if mp < 10 { mp + 3 } else { mp - 9 });
    (yoe + era * 400 + i64::from(m <= 2), m, d)
}

fn era(day: i64) -> usize {
    let year = civil_from_days(day).0;
    ERAS.iter().rposition(|e| year >= e.from).unwrap()
}

fn last_sunday(y: i64, m: i64) -> i64 {
    let last = days_from_civil(y, m + 1, 1) - 1;
    last - (last + 4).rem_euclid(7)
}

impl Place {
    /// The UTC offset on a day, for daytime photos (the EU switches at 01:00 UTC, before anyone is out shooting).
    fn offset_on(&self, day: i64) -> i64 {
        let y = civil_from_days(day).0;
        let summer = self.eu_dst && (last_sunday(y, 3)..last_sunday(y, 10)).contains(&day);
        self.offset + if summer { 60 } else { 0 }
    }
}

#[derive(Clone, Copy)]
struct Id(u64, u64);

impl fmt::Display for Id {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        let Id(ms, r) = *self;
        let (hi, lo) = (ms >> 16, ms & 0xffff);
        let (a, b, c) = (r >> 52, 0x8000 | (r >> 38) & 0x3fff, r & 0xffff_ffff_ffff);
        write!(f, "{hi:08x}-{lo:04x}-7{a:03x}-{b:04x}-{c:012x}")
    }
}

struct Table {
    name: &'static str,
    w: BufWriter<File>,
    rows: u64,
}

impl Table {
    fn create(dir: &Path, name: &'static str, header: &str) -> io::Result<Table> {
        let mut w = BufWriter::new(File::create(dir.join(format!("{name}.csv")))?);
        writeln!(w, "{header}")?;
        Ok(Table { name, w, rows: 0 })
    }

    fn row(&mut self, line: fmt::Arguments) -> io::Result<()> {
        self.rows += 1;
        self.w.write_fmt(line)?;
        self.w.write_all(b"\n")
    }
}

struct Gen {
    dir: PathBuf,
    shape: Shape,
    total: u64,
    /// Every asset so far, for `Shape::Albums`.
    all: Vec<Id>,
    /// The camera, size and placeholder of the stack being shot, which its frames share.
    frame: Option<(usize, u64, u64, String)>,
    /// Placeholder files written so far.
    media: HashSet<String>,
    rng: Rng,
    ids: u64,
    shots: u64,
    owner: Id,
    /// Everyone but the owner, who may be invited to shared albums.
    others: Vec<Id>,
    /// People and pets, the most photographed first.
    people: Vec<Id>,
    /// The assets of the album being shot, if any.
    album: Option<Vec<Id>>,
    assets: Table,
    stacks: Table,
    albums: Table,
    album_items: Table,
    album_members: Table,
    faces: Table,
}

impl Gen {
    fn id(&mut self) -> Id {
        self.ids += 1;
        Id(INGEST_MS + self.ids, self.rng.next())
    }

    /// Spreads a year's photos over days at home, event days and trips of 2 to 10 days; events and trips get albums.
    fn year(&mut self, year: i64, mut quota: u64) -> io::Result<()> {
        let mean = (quota / 200).max(4);
        let first = days_from_civil(year, 1, 1);
        let len = days_from_civil(year + 1, 1, 1) - first;
        while quota > 0 {
            let day = first + self.rng.below(len as u64) as i64;
            let (place, days, title) = if self.rng.chance(0.03) {
                let place = self.rng.pick(&TRIPS);
                (place, 2 + self.rng.below(9) as i64, Some(format!("{} {year}", place.name)))
            } else if self.rng.chance(0.05) {
                let (_, m, d) = civil_from_days(day);
                (&HOME, 1, Some(format!("{} {year}-{m:02}-{d:02}", self.rng.pick(&EVENTS))))
            } else {
                (&HOME, 1, None)
            };
            self.album = title.is_some().then(Vec::new);
            for d in 0..days {
                if quota == 0 {
                    break;
                }
                let n = (1 + self.rng.below(2 * mean)).min(quota);
                self.day(day + d, place, n)?;
                quota -= n;
            }
            if let Some(title) = title {
                self.close_album(&title)?;
            }
        }
        Ok(())
    }

    /// The placeholder for a `w` x `h` asset: one colour, 64 px on the long side, written on first use.
    fn thumb(&mut self, w: u64, h: u64) -> io::Result<String> {
        let (tw, th) = if w >= h { (64, ((64 * h + w / 2) / w).max(1)) } else { (((64 * w + h / 2) / h).max(1), 64) };
        let colour = self.rng.below(PALETTE.len() as u64) as usize;
        let path = format!("media/{tw}x{th}-{colour}.png");
        if self.media.insert(path.clone()) {
            let [_, rgb @ ..] = PALETTE[colour].to_be_bytes();
            fs::write(self.dir.join(&path), png::solid(tw as u32, th as u32, rgb))?;
        }
        Ok(path)
    }

    /// Writes the album being shot; three in ten are shared with one to three others.
    fn close_album(&mut self, title: &str) -> io::Result<()> {
        let items = self.album.take().unwrap_or_default();
        let (id, owner) = (self.id(), self.owner);
        self.albums.row(format_args!("{id},{owner},{title},{}", items[0]))?;
        for item in items {
            self.album_items.row(format_args!("{id},{item}"))?;
        }
        if self.rng.chance(0.3) {
            let first = self.rng.below(self.others.len() as u64) as usize;
            for i in 0..=self.rng.below(3) as usize {
                let user = self.others[(first + i) % self.others.len()];
                let role = if self.rng.chance(0.3) { "contributor" } else { "viewer" };
                self.album_members.row(format_args!("{id},{user},{role}"))?;
            }
        }
        Ok(())
    }

    /// `n` photos taken between 08:00 and 23:00 local time; a burst is 3 to 12 frames at 10 per second.
    fn day(&mut self, day: i64, place: &Place, n: u64) -> io::Result<()> {
        let era = era(day);
        let mut ms = 8 * 3_600_000 + self.rng.below(4 * 3_600_000) as i64;
        let step = 11 * 3_600_000 / n;
        let mut left = n;
        while left > 0 {
            ms = (ms + self.rng.below(step) as i64).min(23 * 3_600_000);
            if left >= 3 && self.rng.chance(ERAS[era].shares[3]) {
                let frames = (3 + self.rng.below(10)).min(left);
                self.stack(day, ms, place, frames, 100, "burst")?;
                left -= frames;
            } else {
                self.asset(day, ms, place, None)?;
                left -= 1;
            }
        }
        Ok(())
    }

    /// `frames` shots `step` ms apart, stacked as `kind`.
    fn stack(&mut self, day: i64, ms: i64, place: &Place, frames: u64, step: i64, kind: &str) -> io::Result<()> {
        let (stack, owner) = (self.id(), self.owner);
        for i in 0..frames {
            let id = self.asset(day, ms + step * i as i64, place, Some(stack))?;
            if i == 0 {
                self.stacks.row(format_args!("{stack},{owner},{kind},{id}"))?;
            }
        }
        self.frame = None;
        Ok(())
    }

    /// Writes one asset; a frame of a stack is always a plain photo, with the camera, size and placeholder of the
    /// first frame.
    fn asset(&mut self, day: i64, ms: i64, place: &Place, stack: Option<Id>) -> io::Result<Id> {
        let id = self.id();
        let owner = self.owner;
        let (y, m, d) = civil_from_days(day);
        let era = era(day);
        let Era { cameras, shares: [gps, video, pano, _], .. } = ERAS[era];
        let (video, pano) = if stack.is_some() { (0.0, 0.0) } else { (video, pano) };
        let template = stack.and(self.frame.clone());
        let camera = match &template {
            Some((c, ..)) => *c,
            None => self.rng.below(cameras.len() as u64) as usize,
        };
        let cam = &cameras[camera];
        self.shots += 1;
        let n = self.shots % 10_000;
        let (kind, panorama, name, w, h, duration, size) = if self.rng.chance(video) {
            let (w, h) = if era == 1 { (640, 480) } else { (1920, 1080) };
            let longest = 1 + self.rng.below(120_000);
            let ms = 1000 + self.rng.below(longest);
            ("video", false, format!("VID_{n:04}.{}", cam.video_ext), w, h, ms.to_string(), w * h * ms / 1000)
        } else {
            let panorama = self.rng.chance(pano);
            let (w, h) = match (&template, panorama) {
                (Some((_, w, h, _)), _) => (*w, *h),
                (_, true) => (cam.w * (2 + self.rng.below(3)), cam.h),
                _ if self.rng.chance(0.25) => (cam.h, cam.w),
                _ => (cam.w, cam.h),
            };
            let size = w * h / 4 * (6 + self.rng.below(9)) / 10;
            ("image", panorama, format!("{}{n:04}.{}", cam.prefix, cam.ext), w, h, String::new(), size)
        };
        let (lat, lon) = if self.rng.chance(gps) {
            (format!("{:.5}", self.rng.jitter(place.lat, 0.1)), format!("{:.5}", self.rng.jitter(place.lon, 0.1)))
        } else {
            Default::default()
        };
        let (hh, mi, ss, milli) = (ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000);
        let full = format!("{y:04}-{m:02}-{d:02}T{hh:02}:{mi:02}:{ss:02}");
        let (taken, offset, zone, precision, source, confidence) = match era {
            _ if era > 0 && self.rng.chance(0.003) => (String::new(), None, "", "unspecified", "unknown", 0),
            0 => match self.rng.below(3) {
                0 => (format!("{y:04}-01-01T00:00:00"), None, "", "year", "user", 30),
                1 => (format!("{y:04}-{m:02}-01T00:00:00"), None, "", "month", "user", 50),
                _ => (format!("{y:04}-{m:02}-{d:02}T00:00:00"), None, "", "day", "user", 70),
            },
            1 | 2 => (full, None, "", "second", "exif:DateTimeOriginal", 90),
            _ => (
                format!("{full}.{milli:03}"),
                Some(place.offset_on(day)),
                place.zone,
                "millisecond",
                "exif:DateTimeOriginal",
                100,
            ),
        };
        let offset = offset.map(|o| o.to_string()).unwrap_or_default();
        let Camera { make, model, .. } = cam;
        let thumb = match template {
            Some((.., thumb)) => thumb,
            None => self.thumb(w, h)?,
        };
        if stack.is_some() && self.frame.is_none() {
            self.frame = Some((camera, w, h, thumb.clone()));
        }
        let stack = stack.map(|s| s.to_string()).unwrap_or_default();
        let folder = match self.shape {
            Shape::Folders => format!("Folders/{:04}", (self.shots - 1) * FOLDERS / self.total),
            _ => format!("Pictures/{y:04}/{y:04}-{m:02}"),
        };
        if let Some(album) = &mut self.album {
            album.push(id);
        }
        if self.shape == Shape::Albums {
            self.all.push(id);
        }
        if kind == "image" && self.rng.chance(0.35) {
            for _ in 0..=self.rng.below(3) {
                // Cubing skews the pick towards the front of the list: family first, acquaintances rarely.
                let u = self.rng.f64();
                let person = self.people[(u * u * u * self.people.len() as f64) as usize];
                let (w, h) = (50 + self.rng.below(200), 50 + self.rng.below(200));
                let (x, y) = (self.rng.below(1001 - w), self.rng.below(1001 - h));
                let face = self.id();
                let [x, y, w, h] = [x, y, w, h].map(|v| v as f64 / 1000.0);
                self.faces.row(format_args!("{face},{id},{person},{x:.3},{y:.3},{w:.3},{h:.3}"))?;
            }
        }
        self.assets.row(format_args!(
            "{id},{owner},{folder},{name},{kind},{panorama},{w},{h},{duration},{size},{taken},{offset},{zone},\
             {precision},{source},{confidence},{lat},{lon},{make},{model},{stack},{thumb}"
        ))?;
        Ok(id)
    }
}

/// Writes a library of `cfg.assets` assets into `out`, which must be empty or absent. The same seed and version give
/// the same bytes: only integer and basic IEEE arithmetic is used.
pub fn generate(cfg: &Config, out: &Path) -> io::Result<()> {
    if fs::read_dir(out).is_ok_and(|mut entries| entries.next().is_some()) {
        return Err(io::Error::new(io::ErrorKind::AlreadyExists, "the output directory is not empty"));
    }
    fs::create_dir_all(out.join("media"))?;
    let table = |name, header| Table::create(out, name, header);
    let mut g = Gen {
        dir: out.to_owned(),
        shape: cfg.shape,
        total: cfg.assets,
        all: Vec::new(),
        frame: None,
        media: HashSet::new(),
        rng: Rng(cfg.seed),
        ids: 0,
        shots: 0,
        owner: Id(0, 0),
        others: Vec::new(),
        people: Vec::new(),
        album: None,
        assets: table(
            "assets",
            "id,owner_id,folder,original_filename,media_kind,panorama,width,height,duration_ms,file_size,taken_local,\
             tz_offset_min,tz_name,time_precision,time_source,time_confidence,lat,lon,make,model,stack_id,thumb",
        )?,
        stacks: table("stacks", "id,owner_id,kind,cover_asset_id")?,
        albums: table("albums", "id,owner_id,title,cover_asset_id")?,
        album_items: table("album_items", "album_id,asset_id")?,
        album_members: table("album_members", "album_id,user_id,role")?,
        faces: table("faces", "id,asset_id,person_id,x,y,w,h")?,
    };
    let mut users = table("users", "id,handle,display_name")?;
    for (i, (handle, name)) in USERS.into_iter().enumerate() {
        let id = g.id();
        if i == 0 {
            g.owner = id;
        } else {
            g.others.push(id);
        }
        users.row(format_args!("{id},{handle},{name}"))?;
    }
    let mut people = table("people", "id,owner_id,kind,name")?;
    for i in 0..12 + cfg.assets as usize / 5000 {
        let (id, owner) = (g.id(), g.owner);
        let (kind, name) = if i % 7 == 6 {
            ("pet", PETS[i / 7 % PETS.len()].to_owned())
        } else {
            ("human", format!("{} {}.", NAMES[i % NAMES.len()], (b'A' + (i / NAMES.len() % 26) as u8) as char))
        };
        people.row(format_args!("{id},{owner},{kind},{name}"))?;
        g.people.push(id);
    }
    // Weights by repeated multiplication, not powi, so that every platform computes the same quotas.
    let mut weights = vec![1.0];
    for _ in FIRST_YEAR..LAST_YEAR {
        weights.push(weights[weights.len() - 1] * GROWTH);
    }
    let total: f64 = weights.iter().sum();
    let mut left = cfg.assets;
    let summer = days_from_civil(2024, 7, 14);
    match cfg.shape {
        Shape::OneDay | Shape::OneTimestamp => {
            for i in 0..cfg.assets {
                let ms = if cfg.shape == Shape::OneDay { i * 86_400_000 / cfg.assets } else { 12 * 3_600_000 };
                g.asset(summer, ms as i64, &HOME, None)?;
            }
        }
        Shape::NearDuplicates => {
            let first = days_from_civil(2016, 1, 1);
            while left > 0 {
                let mut frames = (2 + g.rng.below(11)).min(left);
                if left - frames == 1 {
                    frames += 1;
                }
                let day = first + g.rng.below((summer - first) as u64) as i64;
                let ms = 8 * 3_600_000 + g.rng.below(14 * 3_600_000) as i64;
                g.stack(day, ms, &HOME, frames, 1000, "similar_series")?;
                left -= frames;
            }
        }
        _ => {
            for (year, w) in (FIRST_YEAR..=LAST_YEAR).zip(weights) {
                let quota = if year == LAST_YEAR { left } else { (cfg.assets as f64 * w / total) as u64 };
                left -= quota;
                g.year(year, quota)?;
            }
        }
    }
    if cfg.shape == Shape::Albums {
        let all = std::mem::take(&mut g.all);
        for i in 0..ALBUMS {
            let items = &all[(i * cfg.assets / ALBUMS) as usize..((i + 1) * cfg.assets / ALBUMS) as usize];
            if !items.is_empty() {
                g.album = Some(items.to_vec());
                g.close_album(&format!("Album {:05}", i + 1))?;
            }
        }
    }
    let mut rows = Vec::new();
    for t in [
        &mut users,
        &mut people,
        &mut g.assets,
        &mut g.stacks,
        &mut g.albums,
        &mut g.album_items,
        &mut g.album_members,
        &mut g.faces,
    ] {
        t.w.flush()?;
        rows.push(format!("\"{}\": {}", t.name, t.rows));
    }
    let manifest = format!(
        "{{\"generator\": \"photolib-synthlib {}\", \"seed\": {}, \"assets\": {}, \"shape\": \"{}\", \"media\": {}, \
         \"rows\": {{{}}}}}\n",
        env!("CARGO_PKG_VERSION"),
        cfg.seed,
        cfg.assets,
        cfg.shape,
        g.media.len(),
        rows.join(", ")
    );
    fs::write(out.join("manifest.json"), manifest)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dates_round_trip_through_day_numbers() {
        assert_eq!(days_from_civil(1970, 1, 1), 0);
        assert_eq!(days_from_civil(2000, 3, 1), 11_017);
        for day in days_from_civil(1899, 12, 31)..days_from_civil(2101, 1, 1) {
            let (y, m, d) = civil_from_days(day);
            assert_eq!(days_from_civil(y, m, d), day);
        }
        assert_eq!(civil_from_days(days_from_civil(2024, 2, 28) + 1), (2024, 2, 29));
        assert_eq!(civil_from_days(days_from_civil(2025, 2, 28) + 1), (2025, 3, 1));
    }

    #[test]
    fn summer_time_follows_the_eu_rule() {
        let offset = |y, m, d| HOME.offset_on(days_from_civil(y, m, d));
        assert_eq!([offset(2024, 3, 30), offset(2024, 3, 31)], [60, 120]);
        assert_eq!([offset(2024, 10, 26), offset(2024, 10, 27)], [120, 60]);
        assert_eq!([offset(2025, 3, 29), offset(2025, 3, 30)], [60, 120]);
        assert_eq!([offset(2025, 10, 25), offset(2025, 10, 26)], [120, 60]);
        let tokyo = Place { name: "Tokyo", lat: 35.68, lon: 139.69, zone: "Asia/Tokyo", offset: 540, eu_dst: false };
        assert_eq!(tokyo.offset_on(days_from_civil(2024, 7, 1)), 540);
    }
}
