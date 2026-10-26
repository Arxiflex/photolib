use photolib_synthlib::{ALBUMS, Config, FOLDERS, Shape, generate};
use std::{
    collections::{HashMap, HashSet},
    fs,
    path::{Path, PathBuf},
    sync::OnceLock,
    time::{Duration, Instant},
};

type Row = HashMap<String, String>;

/// An empty directory under the target directory, so that leftovers go with `cargo clean`.
fn scratch(name: &str) -> PathBuf {
    let dir = Path::new(env!("CARGO_TARGET_TMPDIR")).join(name);
    let _ = fs::remove_dir_all(&dir);
    dir
}

/// A fresh fixture in a scratch directory.
fn fixture(name: &str, assets: u64, seed: u64) -> PathBuf {
    shaped(name, assets, seed, Shape::Library)
}

fn shaped(name: &str, assets: u64, seed: u64, shape: Shape) -> PathBuf {
    let dir = scratch(name);
    generate(&Config { assets, seed, shape }, &dir).unwrap();
    dir
}

fn year(a: &Row) -> Option<i32> {
    a["taken_local"].get(..4).map(|y| y.parse().unwrap())
}

fn num(a: &Row, column: &str) -> u64 {
    a[column].parse().unwrap()
}

/// Header and rows of one CSV table; every row must have as many fields as the header.
fn table(dir: &Path, name: &str) -> (Vec<String>, Vec<Vec<String>>) {
    let text = fs::read_to_string(dir.join(format!("{name}.csv"))).unwrap();
    let mut lines = text.lines().map(|l| l.split(',').map(str::to_owned).collect::<Vec<_>>());
    let header = lines.next().unwrap();
    let rows: Vec<_> = lines.collect();
    for row in &rows {
        assert_eq!(row.len(), header.len(), "{name}.csv row {row:?}");
    }
    (header, rows)
}

#[test]
fn writes_exactly_the_requested_number_of_assets() {
    for n in [0, 1, 37] {
        let dir = fixture(&format!("count-{n}"), n, 7);
        let (header, rows) = table(&dir, "assets");
        assert_eq!(header[0], "id");
        assert_eq!(rows.len() as u64, n);
        let ids: HashSet<_> = rows.iter().map(|r| &r[0]).collect();
        assert_eq!(ids.len() as u64, n, "ids are unique");
        for id in ids {
            let b = id.as_bytes();
            assert!(b.len() == 36 && b[14] == b'7' && b"89ab".contains(&b[19]), "not a UUIDv7: {id}");
        }
        fs::remove_dir_all(&dir).unwrap();
    }
}

/// Every file of the fixture, by path relative to its directory.
fn files(dir: &Path) -> Vec<(PathBuf, Vec<u8>)> {
    let mut stack = vec![dir.to_path_buf()];
    let mut out = Vec::new();
    while let Some(d) = stack.pop() {
        for entry in fs::read_dir(&d).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                stack.push(path);
            } else {
                out.push((path.strip_prefix(dir).unwrap().to_owned(), fs::read(&path).unwrap()));
            }
        }
    }
    out.sort();
    out
}

#[test]
fn the_seed_alone_determines_the_bytes() {
    let (a, b, c) = (fixture("seed-a", 10_000, 42), fixture("seed-b", 10_000, 42), fixture("seed-c", 10_000, 43));
    let (fa, fb) = (files(&a), files(&b));
    assert!(fa.len() > 1, "only {} file(s)", fa.len());
    assert!(fa == fb, "same seed, different output");
    // Not just another manifest, which records the seed: other capture times.
    let times = |dir: &Path| {
        let (header, rows) = table(dir, "assets");
        let at = header.iter().position(|c| c == "taken_local").unwrap();
        rows.into_iter().map(|r| r[at].clone()).collect::<Vec<_>>()
    };
    assert!(times(&a) != times(&c), "another seed must give another library");
    for d in [a, b, c] {
        fs::remove_dir_all(d).unwrap();
    }
}

/// A 10k library generated once per process and shared by its tests that only read it. It is named after the test
/// that asks first: nextest runs each test in a process of its own, side by side.
fn library() -> &'static Path {
    static DIR: OnceLock<PathBuf> = OnceLock::new();
    DIR.get_or_init(|| fixture(&format!("library-{}", std::thread::current().name().unwrap()), 10_000, 1))
}

/// The assets by id.
fn assets_by_id() -> HashMap<String, Row> {
    records("assets").into_iter().map(|a| (a["id"].clone(), a)).collect()
}

/// The rows of a table of the shared library as maps from column name to value.
fn records(name: &str) -> Vec<Row> {
    records_in(library(), name)
}

fn records_in(dir: &Path, name: &str) -> Vec<Row> {
    let (header, rows) = table(dir, name);
    rows.into_iter().map(|r| header.iter().cloned().zip(r).collect()).collect()
}

#[test]
fn capture_times_span_decades_like_a_real_library() {
    let assets = records("assets");
    let in_years = |from, to| assets.iter().filter(|a| year(a).is_some_and(|y| (from..=to).contains(&y))).count();
    assert!(in_years(1990, 1994) > 0 && in_years(2024, 2025) > 0, "the library spans the 1990s to the 2020s");
    assert!(in_years(2020, 2025) > 5 * in_years(1990, 1995), "recent years hold more photos");
    for a in &assets {
        let (precision, source, offset, zone) =
            (&a["time_precision"], &a["time_source"], &a["tz_offset_min"], &a["tz_name"]);
        match year(a) {
            None => assert_eq!((precision.as_str(), source.as_str()), ("unspecified", "unknown")),
            Some(..=2002) => {
                assert!(["year", "month", "day"].contains(&precision.as_str()), "a scan: {a:?}");
                assert_eq!(source, "user");
            }
            Some(..=2015) => assert_eq!((precision.as_str(), offset.as_str()), ("second", ""), "{a:?}"),
            Some(_) => {
                assert_eq!(precision, "millisecond");
                assert!(!offset.is_empty() && !zone.is_empty(), "phones record the zone: {a:?}");
            }
        }
        if zone == "Europe/Berlin" {
            let month = &a["taken_local"][5..7];
            let expected = match month {
                "01" | "02" | "11" | "12" => Some("60"),
                "05" | "06" | "07" | "08" | "09" => Some("120"),
                _ => None,
            };
            assert!(expected.is_none_or(|e| e == offset), "CET/CEST: {a:?}");
        }
    }
    assert!(assets.iter().any(|a| a["time_source"] == "unknown"), "some assets have no date at all");
}

#[test]
fn assets_look_like_the_devices_of_their_time() {
    let assets = records("assets");
    let (mut videos, mut panoramas) = (0, 0);
    for a in &assets {
        assert!(num(a, "file_size") > 0 && num(a, "width") > 0 && num(a, "height") > 0, "{a:?}");
        assert!(a["original_filename"].contains('.'), "{a:?}");
        match a["media_kind"].as_str() {
            "video" => {
                videos += 1;
                assert!(num(a, "duration_ms") >= 1000, "{a:?}");
            }
            "image" => assert_eq!(a["duration_ms"], ""),
            other => panic!("media_kind {other}"),
        }
        if a["panorama"] == "true" {
            panoramas += 1;
            assert!(a["media_kind"] == "image" && num(a, "width") >= 2 * num(a, "height"), "{a:?}");
        }
        match year(a) {
            Some(..=2002) => {
                assert!(a["make"] == "Epson" && a["lat"].is_empty() && a["media_kind"] == "image", "{a:?}")
            }
            Some(2016..) => assert!(["Apple", "Google"].contains(&a["make"].as_str()), "{a:?}"),
            _ => {}
        }
        assert_eq!(a["lat"].is_empty(), a["lon"].is_empty());
    }
    let recent: Vec<_> = assets.iter().filter(|a| year(a).is_some_and(|y| y >= 2016)).collect();
    let located = recent.iter().filter(|a| !a["lat"].is_empty()).count();
    assert!(located * 10 > recent.len() * 8, "phones geotag most photos: {located} of {}", recent.len());
    assert!(videos * 100 > assets.len() * 3, "{videos} videos");
    assert!(panoramas > 10, "{panoramas} panoramas");
}

/// Milliseconds since midnight of a capture time.
fn clock(a: &Row) -> Option<u64> {
    let t = a["taken_local"].get(11..)?;
    let part = |r: std::ops::Range<usize>| t.get(r).map_or(0, |v| v.parse::<u64>().unwrap());
    Some(((part(0..2) * 60 + part(3..5)) * 60 + part(6..8)) * 1000 + part(9..12))
}

#[test]
fn bursts_are_stacks_of_frames_shot_within_a_second_or_two() {
    let assets = records("assets");
    let stacks = records("stacks");
    assert!(stacks.len() >= 20, "{} bursts", stacks.len());
    for s in &stacks {
        let frames: Vec<_> = assets.iter().filter(|a| a["stack_id"] == s["id"]).collect();
        assert!(frames.len() >= 3, "{s:?} has {} frames", frames.len());
        assert_eq!(s["kind"], "burst");
        assert!(frames.iter().any(|a| a["id"] == s["cover_asset_id"]), "the cover is a frame of {s:?}");
        assert!(frames.iter().all(|a| a["media_kind"] == "image" && year(a).is_none_or(|y| y >= 2010)));
        let times: Vec<_> = frames.iter().filter_map(|a| clock(a)).collect();
        assert!(times.iter().max().unwrap() - times.iter().min().unwrap() <= 2000, "{s:?}: {times:?}");
    }
}

#[test]
fn trips_and_events_are_albums_and_some_are_shared() {
    let assets = assets_by_id();
    let (albums, items, members) = (records("albums"), records("album_items"), records("album_members"));
    let users: Vec<String> = records("users").into_iter().map(|u| u["id"].clone()).collect();
    let mut photos: HashMap<&str, Vec<&Row>> = HashMap::new();
    for i in &items {
        photos.entry(&i["album_id"]).or_default().push(&assets[&i["asset_id"]]);
    }
    let abroad = |a: &Row| !a["tz_name"].is_empty() && a["tz_name"] != "Europe/Berlin";
    let mut trips = 0;
    for album in &albums {
        let photos = &photos[album["id"].as_str()];
        assert!(photos.iter().any(|a| a["id"] == album["cover_asset_id"]), "{album:?}");
        assert!(album["owner_id"] == users[0] && !album["title"].is_empty());
        if photos.iter().any(|a| abroad(a)) {
            trips += 1;
            let days: HashSet<_> = photos.iter().map(|a| a["taken_local"].get(..10)).collect();
            assert!(days.len() >= 2, "a trip lasts days: {album:?}");
        }
    }
    assert!(trips >= 3, "{trips} trips abroad");
    let filed: HashSet<_> = items.iter().map(|i| &i["asset_id"]).collect();
    assert!(
        assets.values().filter(|a| abroad(a)).all(|a| filed.contains(&a["id"])),
        "photos abroad are in trip albums"
    );
    let shared: HashSet<_> = members.iter().map(|m| &m["album_id"]).collect();
    assert!(!shared.is_empty() && shared.len() < albums.len(), "{} of {} albums shared", shared.len(), albums.len());
    let mut pairs = HashSet::new();
    for m in &members {
        assert!(albums.iter().any(|a| a["id"] == m["album_id"]));
        assert!(users[1..].contains(&m["user_id"]) && ["viewer", "contributor"].contains(&m["role"].as_str()), "{m:?}");
        assert!(pairs.insert((&m["album_id"], &m["user_id"])), "shared twice: {m:?}");
    }
}

#[test]
fn faces_show_people_and_pets_with_family_far_ahead() {
    let assets = assets_by_id();
    let (people, faces) = (records("people"), records("faces"));
    let owner = &records("users")[0]["id"];
    assert!(people.iter().any(|p| p["kind"] == "pet"));
    for p in &people {
        assert!(["human", "pet"].contains(&p["kind"].as_str()) && !p["name"].is_empty() && &p["owner_id"] == owner);
    }
    let known: HashSet<_> = people.iter().map(|p| &p["id"]).collect();
    let mut per_person: HashMap<&str, usize> = HashMap::new();
    for f in &faces {
        assert_eq!(assets[&f["asset_id"]]["media_kind"], "image");
        assert!(known.contains(&f["person_id"]), "{f:?}");
        let [x, y, w, h] = ["x", "y", "w", "h"].map(|k| f[k].parse::<f64>().unwrap());
        assert!(x >= 0.0 && y >= 0.0 && w > 0.0 && h > 0.0 && x + w <= 1.0 + 1e-9 && y + h <= 1.0 + 1e-9, "{f:?}");
        *per_person.entry(&f["person_id"]).or_default() += 1;
    }
    let pictured: HashSet<_> = faces.iter().map(|f| &f["asset_id"]).collect();
    assert!(pictured.len() * 5 > assets.len(), "{} of {} assets show someone", pictured.len(), assets.len());
    let mut counts: Vec<_> = per_person.into_values().collect();
    counts.sort();
    assert!(counts[counts.len() - 1] > 5 * counts[counts.len() / 2], "family dominates: {counts:?}");
}

#[test]
fn every_asset_has_a_small_placeholder_of_its_shape() {
    let assets = records("assets");
    let mut used = HashSet::new();
    for a in &assets {
        let png = fs::read(library().join(&a["thumb"])).unwrap_or_else(|e| panic!("{a:?}: {e}"));
        assert_eq!(png[..16], *b"\x89PNG\r\n\x1a\n\0\0\0\x0dIHDR");
        let side = |at: usize| u32::from_be_bytes(png[at..at + 4].try_into().unwrap()) as u64;
        let (tw, th, w, h) = (side(16), side(20), num(a, "width"), num(a, "height"));
        assert_eq!(tw.max(th), 64, "{a:?}");
        assert!((tw * h).abs_diff(th * w) * 2 <= w.max(h), "{tw}x{th} placeholder for {w}x{h}");
        used.insert(&a["thumb"]);
    }
    let files = fs::read_dir(library().join("media")).unwrap().count();
    assert!(files == used.len() && files < 300, "{files} placeholder files, {} used", used.len());
}

#[test]
fn files_sit_in_month_folders() {
    let assets = records("assets");
    for a in &assets {
        let (y, m) = (&a["folder"][9..13], &a["folder"][14..]);
        assert!(a["folder"].starts_with("Pictures/") && y.parse::<i32>().is_ok() && m.starts_with(y), "{a:?}");
        assert!(a["taken_local"].is_empty() || a["taken_local"].starts_with(y), "{a:?}");
    }
    let folders: HashSet<_> = assets.iter().map(|a| &a["folder"]).collect();
    assert!((100..432).contains(&folders.len()), "{} folders", folders.len());
}

/// The pathological libraries of the performance budgets (docs/10 §3.7, §13).
#[test]
fn shapes_concentrate_the_library() {
    let n = 2 * ALBUMS;
    let assets = |shape, name| {
        let dir = shaped(name, n, 3, shape);
        let tables = ["assets", "stacks", "albums", "album_items"].map(|t| records_in(&dir, t));
        fs::remove_dir_all(&dir).unwrap();
        assert_eq!(tables[0].len() as u64, n, "{name}");
        tables
    };
    let dated = |rows: &[Row], same: &dyn Fn(&Row) -> String| {
        let mut values: Vec<_> = rows.iter().filter(|a| !a["taken_local"].is_empty()).map(same).collect();
        let dated = values.len();
        values.dedup();
        assert!(dated * 100 >= rows.len() * 99, "only {dated} dated");
        values.len()
    };

    let [day, ..] = assets(Shape::OneDay, "one-day");
    assert_eq!(dated(&day, &|a| a["taken_local"][..10].to_owned()), 1, "one day");
    let times: HashSet<_> = day.iter().map(|a| &a["taken_local"]).collect();
    assert!(times.len() as u64 > n / 2, "spread over the day: {} times", times.len());

    let [instant, ..] = assets(Shape::OneTimestamp, "one-timestamp");
    assert_eq!(dated(&instant, &|a| format!("{} {}", a["taken_local"], a["tz_offset_min"])), 1, "one instant");

    let [assets_, stacks, ..] = assets(Shape::NearDuplicates, "near-duplicates");
    let mut series: HashMap<&str, Vec<&Row>> = HashMap::new();
    for a in &assets_ {
        series.entry(&a["stack_id"]).or_default().push(a);
    }
    assert!(!series.contains_key(""), "every asset is a near-duplicate");
    assert_eq!(stacks.len(), series.len());
    for s in &stacks {
        let frames = &series[s["id"].as_str()];
        assert!(s["kind"] == "similar_series" && frames.len() >= 2, "{s:?}: {} frames", frames.len());
        for f in frames {
            let same = ["make", "model", "width", "height", "thumb", "folder"].iter().all(|k| f[*k] == frames[0][*k]);
            assert!(same && f["media_kind"] == "image", "{f:?} is not like {:?}", frames[0]);
        }
        let times: Vec<_> = frames.iter().filter_map(|a| clock(a)).collect();
        assert!(times.iter().max().unwrap() - times.iter().min().unwrap() <= 12_000, "{s:?}: {times:?}");
    }

    let [folders, ..] = assets(Shape::Folders, "folders");
    let distinct: HashSet<_> = folders.iter().map(|a| &a["folder"]).collect();
    assert_eq!(distinct.len() as u64, FOLDERS);

    let [_, _, albums, items] = assets(Shape::Albums, "albums");
    let filled: HashSet<_> = items.iter().map(|i| &i["album_id"]).collect();
    assert!(albums.len() as u64 >= ALBUMS && filled.len() == albums.len(), "{} albums", albums.len());
}

/// The acceptance budget, met even by the unoptimised test build.
#[test]
fn a_million_assets_take_less_than_ten_minutes() {
    let started = Instant::now();
    let dir = fixture("million", 1_000_000, 2026);
    let elapsed = started.elapsed();
    let lines = fs::read(dir.join("assets.csv")).unwrap().iter().filter(|&&b| b == b'\n').count();
    fs::remove_dir_all(&dir).unwrap();
    assert_eq!(lines, 1 + 1_000_000);
    assert!(elapsed < Duration::from_secs(600), "took {elapsed:?}");
}
