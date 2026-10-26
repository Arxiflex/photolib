//! The media corpus (testdata/corpus) through the kernel's ABI: ReadMetadata on every file, compared field by field
//! with the golden records for the formats it reads. Capture-time resolution and file-name claims belong to the
//! resolver (M1-07).
#![allow(clippy::disallowed_methods, clippy::disallowed_types)]

use photolib_kernel::call;
use photolib_kernel::proto::kernel::v1::{
    CallResponse, CaptureTimeFlag, ClaimVerdict, FileRange, LivePhotoPart, Method, Pace, PairLivePhotosRequest,
    PairLivePhotosResponse, ReadMetadataRequest, ReadMetadataResponse, ResolveCaptureTimeRequest,
    ResolveCaptureTimeResponse, StereoMode, TimeClaim, TimeEvent, TimeZone, ZoneOffset, ZoneSource, call_response,
};
use photolib_kernel::proto::model::v1::{CaptureTime, CaptureTimePrecision};
use prost::Message;
use prost_types::Timestamp;
use serde_json::{Value, json};
use std::{fs, path::Path};

const CORPUS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../testdata/corpus");
const FORMATS: [&str; 26] = [
    "jpeg", "insp", "thm", "png", "apng", "gif", "webp", "tiff", "dng", "cr2", "cr3", "nef", "arw", "orf", "rw2",
    "pef", "heic", "avif", "raf", "mp4", "mov", "3gp", "lrv", "lrf", "insv", "avi",
];
/// The corpus's videos do not store the make and model their records name.
const VIDEOS: [&str; 6] = ["mp4", "mov", "3gp", "lrv", "lrf", "insv"];

fn read(ranges: Vec<FileRange>, size: usize) -> ReadMetadataResponse {
    let request = ReadMetadataRequest {
        ranges,
        size: size as u64,
    };
    kernel(Method::ReadMetadata, request)
}

fn kernel<Response: Message + Default>(method: Method, request: impl Message) -> Response {
    let answer = call(method as u32, &request.encode_to_vec());
    match CallResponse::decode(answer.as_slice()).unwrap().result {
        Some(call_response::Result::Response(bytes)) => Response::decode(bytes.as_slice()).unwrap(),
        other => panic!("expected a response, got {other:?}"),
    }
}

fn whole(data: &[u8]) -> Vec<FileRange> {
    vec![FileRange {
        offset: 0,
        data: data.to_vec(),
    }]
}

/// Every golden record with the bytes of its file.
fn corpus() -> Vec<(Value, Vec<u8>)> {
    let mut found = Vec::new();
    let mut dirs = vec![Path::new(CORPUS).join("golden")];
    while let Some(dir) = dirs.pop() {
        for entry in fs::read_dir(dir).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                dirs.push(path);
            } else {
                let record: Value = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
                let file = Path::new(CORPUS).join("files").join(record["path"].as_str().unwrap());
                found.push((record, fs::read(file).unwrap()));
            }
        }
    }
    found.sort_by(|a, b| a.0["path"].as_str().cmp(&b.0["path"].as_str()));
    assert!(found.len() > 300, "the corpus is missing: {CORPUS}");
    found
}

/// Those of the record's quirks that are among these.
fn quirks<'r>(record: &'r Value, among: &[&str]) -> Vec<&'r str> {
    let all = record["quirks"].as_array().unwrap().iter();
    all.filter_map(Value::as_str).filter(|q| among.contains(q)).collect()
}

fn in_scope(record: &Value) -> bool {
    FORMATS.contains(&record["format"].as_str().unwrap())
}

/// The golden metadata fields this reader decides, as JSON, for one file.
fn fields(got: &ReadMetadataResponse) -> Value {
    let pano = got.panorama.as_ref().map(|p| {
        let cropped = (p.cropped_width, p.cropped_height) != (p.full_width, p.full_height);
        let mut pano = json!({"projection": p.projection, "cropped": cropped});
        if let Some(heading) = p.pose_heading_degrees {
            pano["heading"] = json!(heading);
        }
        pano
    });
    let fields = json!({
        "width": got.width,
        "height": got.height,
        "orientation": got.orientation,
        "make": got.make,
        "model": got.model,
        "gps": got.location.as_ref().map(|at| json!({"lat": at.latitude, "lon": at.longitude})),
        "pano": pano,
        "duration_ms": got.duration_ms,
        "codec": got.codec,
    });
    let unset = |v: &Value| v.is_null() || v == 0 || v == "";
    Value::Object(
        fields
            .as_object()
            .unwrap()
            .clone()
            .into_iter()
            .filter(|(_, v)| !unset(v))
            .collect(),
    )
}

fn same(want: &Value, got: &Value) -> bool {
    match (want, got) {
        (Value::Number(a), Value::Number(b)) => (a.as_f64().unwrap() - b.as_f64().unwrap()).abs() < 1e-6,
        (Value::Object(a), Value::Object(b)) => {
            a.len() == b.len() && a.iter().all(|(k, v)| b.get(k).is_some_and(|w| same(v, w)))
        }
        _ => want == got,
    }
}

/// The golden claim sources this reader extracts, for a time it found.
fn claim_sources(time: &CaptureTime) -> Vec<&'static str> {
    match (time.source.as_str(), time.offset_minutes) {
        ("exif:DateTimeOriginal", Some(_)) => vec!["exif_dto_with_offset", "exif_dto_no_offset"],
        ("exif:DateTimeOriginal", None) => vec!["exif_dto_no_offset"],
        ("exif:CreateDate", _) => vec!["exif_createdate"],
        ("exif:GPSDateTime", _) => vec!["gps_datetime"],
        (source, Some(_)) if source.starts_with("xmp-") => vec!["xmp_date_with_offset"],
        ("quicktime:CreationDate", _) => vec!["qt_keys_creationdate"],
        ("quicktime:CreateDate", _) => vec!["qt_mvhd_phone", "qt_mvhd_camera"],
        _ => vec![],
    }
}

fn offset_minutes(text: &str) -> i32 {
    let sign = if text.starts_with('-') { -1 } else { 1 };
    sign * (text[1..3].parse::<i32>().unwrap() * 60 + text[4..6].parse::<i32>().unwrap())
}

/// Whether a time found matches a golden claim: same value (a UTC one ends in Z), offset and precision.
fn claimed(claim: &Value, time: &CaptureTime) -> bool {
    let source = claim["source"].as_str().unwrap();
    let precision = match CaptureTimePrecision::try_from(time.precision) {
        Ok(CaptureTimePrecision::Millisecond) => "ms",
        Ok(CaptureTimePrecision::Second) => "s",
        Ok(CaptureTimePrecision::Minute) => "min",
        Ok(CaptureTimePrecision::Day) => "day",
        Ok(CaptureTimePrecision::Month) => "month",
        Ok(CaptureTimePrecision::Year) => "year",
        _ => "",
    };
    let value = match time.local_datetime.as_str() {
        "" => Value::Null,
        local if ["gps_datetime", "qt_mvhd_phone"].contains(&source) => format!("{local}Z").into(),
        local => local.into(),
    };
    let offset = match (source, claim["offset"].as_str()) {
        ("exif_dto_no_offset", _) => true,
        (_, Some(text)) => time.offset_minutes == Some(offset_minutes(text)),
        (_, None) => time.offset_minutes.is_none() || source == "gps_datetime",
    };
    claim_sources(time).contains(&source)
        && claim["value"] == value
        && claim["precision"].as_str().unwrap_or("") == precision
        && offset
}

#[test]
fn golden_metadata_matches_on_the_corpus() {
    let (mut total, mut mismatches) = (0, vec![]);
    for (record, data) in corpus() {
        let got = read(whole(&data), data.len());
        if !in_scope(&record) {
            continue;
        }
        let path = record["path"].as_str().unwrap();
        let want = &record["metadata"];
        let found = fields(&got);
        let video = VIDEOS.contains(&record["format"].as_str().unwrap());
        for name in [
            "width",
            "height",
            "orientation",
            "make",
            "model",
            "gps",
            "pano",
            "duration_ms",
            "codec",
        ] {
            let (want, got) = (&want[name], &found[name]);
            if want.is_null() && got.is_null() || video && ["make", "model"].contains(&name) {
                continue;
            }
            total += 1;
            if !same(want, got) {
                mismatches.push(format!("{path}: {name}: want {want}, got {got}"));
            }
        }
        for claim in record["capture_time"]["claims"].as_array().unwrap() {
            let source = claim["source"].as_str().unwrap();
            if !["exif_", "gps_", "xmp_", "qt_"].iter().any(|p| source.starts_with(p)) {
                continue;
            }
            total += 1;
            if !got.times.iter().any(|time| claimed(claim, time)) {
                mismatches.push(format!("{path}: claim {claim}, got {:?}", got.times));
            }
        }
    }
    let matched = total - mismatches.len();
    println!("{matched} of {total} golden fields match\n{}", mismatches.join("\n"));
    assert!(
        matched * 100 >= total * 99,
        "{matched} of {total} golden fields match, below 99%:\n{}",
        mismatches.join("\n")
    );
}

/// A host that starts with the first bytes of a file and reads what the reader says is missing ends with what the
/// whole file gives, in a few calls.
#[test]
fn missing_spans_lead_to_the_whole_file() {
    for (record, data) in corpus().iter().filter(|(record, _)| in_scope(record)) {
        let path = record["path"].as_str().unwrap();
        let want = ReadMetadataResponse {
            missing: vec![],
            ..read(whole(data), data.len())
        };
        let mut ranges = vec![FileRange {
            offset: 0,
            data: data[..data.len().min(512)].to_vec(),
        }];
        for calls in 1.. {
            let got = read(ranges.clone(), data.len());
            let more: Vec<_> = got
                .missing
                .iter()
                .filter(|span| span.offset < data.len() as u64)
                .map(|span| {
                    let start = span.offset as usize;
                    let end = data.len().min(start + span.length as usize);
                    FileRange {
                        offset: span.offset,
                        data: data[start..end].to_vec(),
                    }
                })
                .filter(|range| !ranges.contains(range))
                .collect();
            if more.is_empty() {
                assert_eq!(ReadMetadataResponse { missing: vec![], ..got }, want, "{path}");
                break;
            }
            assert!(
                calls < 50,
                "{path}: still missing {:?} after {calls} calls",
                got.missing
            );
            ranges.extend(more);
        }
    }
}

/// The ranges a host gathers: the first 512 bytes, then what the reader says is missing, until nothing more is.
fn gathered(data: &[u8]) -> Vec<FileRange> {
    let mut ranges = vec![FileRange {
        offset: 0,
        data: data[..data.len().min(512)].to_vec(),
    }];
    loop {
        let more: Vec<_> = read(ranges.clone(), data.len())
            .missing
            .iter()
            .filter(|span| span.offset < data.len() as u64)
            .map(|span| {
                let start = span.offset as usize;
                let end = data.len().min(start + span.length as usize);
                FileRange {
                    offset: span.offset,
                    data: data[start..end].to_vec(),
                }
            })
            .filter(|range| !ranges.contains(range))
            .collect();
        if more.is_empty() {
            return ranges;
        }
        ranges.extend(more);
    }
}

/// A host that resolves from the ranges it read for ReadMetadata gets what the whole file as the head gives.
#[test]
fn capture_times_from_ranges_match_the_whole_file() {
    for (record, data) in corpus() {
        let path = record["path"].as_str().unwrap();
        let (folder, file_name) = path.rsplit_once('/').unwrap();
        let request = ResolveCaptureTimeRequest {
            file_name: file_name.into(),
            folder: folder.into(),
            ..ResolveCaptureTimeRequest::default()
        };
        let whole: ResolveCaptureTimeResponse = kernel(
            Method::ResolveCaptureTime,
            ResolveCaptureTimeRequest {
                head: data.clone(),
                ..request.clone()
            },
        );
        let ranged: ResolveCaptureTimeResponse = kernel(
            Method::ResolveCaptureTime,
            ResolveCaptureTimeRequest {
                ranges: gathered(&data),
                size: data.len() as u64,
                ..request
            },
        );
        assert_eq!(ranged, whole, "{path}");
    }
}

/// HDR as the corpus's quirks name it: PQ or HLG transfer characteristics, and Dolby Vision.
#[test]
fn hdr_signalling_matches_the_corpus_quirks() {
    for (record, data) in corpus() {
        let got = read(whole(&data), data.len());
        let quirks = quirks(&record, &["hdr_pq", "hdr_hlg", "dolby_vision"]);
        let transfer = match got.transfer {
            16 => Some("hdr_pq"),
            18 => Some("hdr_hlg"),
            _ => None,
        };
        let found: Vec<&str> = transfer
            .into_iter()
            .chain(got.dolby_vision.then_some("dolby_vision"))
            .collect();
        assert_eq!(found, quirks, "{}", record["path"]);
    }
}

/// Special media as the corpus's quirks name them (docs/08 §2.2), in the ranges a host reads: spatial photos and
/// videos, depth maps and portrait mattes, and slow motion.
#[test]
fn spatial_media_depth_and_slow_motion_match_the_corpus_quirks() {
    for (record, data) in corpus() {
        let got = read(gathered(&data), data.len());
        let (path, has) = (&record["path"], |among: &[&str]| !quirks(&record, among).is_empty());
        assert_eq!(got.spatial, has(&["spatial_photo", "spatial_video"]), "{path}");
        let depth = has(&["depth_apple", "depth_gdepth", "depth_dynamic", "depth_samsung"]);
        assert_eq!(got.depth, depth, "{path}");
        let slow = has(&["slow_motion", "slow_motion_sef"]);
        let pace = if slow { Pace::SlowMotion } else { Pace::Unspecified };
        assert_eq!(got.pace(), pace, "{path}");
    }
}

/// Gain maps as the corpus's quirks name them, but Samsung's, which no platform decoder applies.
#[test]
fn gain_maps_match_the_corpus_quirks() {
    for (record, data) in corpus() {
        let wanted = !quirks(&record, &["ultra_hdr", "gain_map_iso", "gain_map_apple"]).is_empty();
        assert_eq!(read(gathered(&data), data.len()).gain_map, wanted, "{}", record["path"]);
    }
}

/// Panoramas and 360° videos are found from metadata alone: every file's projection is its golden one, and none is
/// guessed from the aspect ratio (compound/pano/PANO_*.jpg is 12000 × 2000 and flat); stereo modes are the quirks'.
#[test]
fn panoramas_match_the_corpus() {
    for (record, data) in corpus() {
        let got = read(whole(&data), data.len());
        let path = &record["path"];
        assert_eq!(fields(&got)["pano"], record["metadata"]["pano"], "{path}");
        let stereo = match quirks(&record, &["stereo_top_bottom", "stereo_left_right"])[..] {
            ["stereo_top_bottom"] => StereoMode::TopBottom,
            ["stereo_left_right"] => StereoMode::LeftRight,
            _ => StereoMode::Unspecified,
        };
        assert_eq!(got.stereo_mode(), stereo, "{path}");
    }
}

/// A motion photo's video is found where its golden record says, in every file that has one, and nowhere else: not
/// where stale markers point (compound/motion/PXL_20230514_100000000.jpg), nor in other Samsung trailers.
#[test]
fn motion_photo_videos_match_the_corpus() {
    for (record, data) in corpus() {
        let got = read(whole(&data), data.len()).motion_video;
        let got = got.map(|span| json!({"offset": span.offset, "length": span.length}));
        assert_eq!(
            got.unwrap_or_default(),
            record["metadata"]["motion"],
            "{}",
            record["path"]
        );
    }
}

/// The RAW formats, whose embedded JPEG the reader finds.
const RAW: [&str; 9] = ["dng", "cr2", "cr3", "nef", "arw", "orf", "rw2", "pef", "raf"];

/// Every RAW and every file the corpus says has an embedded preview has one, and a largest one: whole JPEGs, found
/// the same in the ranges a host reads, whose bytes are not asked for.
#[test]
fn embedded_previews_match_the_corpus() {
    let mut found = 0;
    for (record, data) in corpus() {
        let path = &record["path"];
        let got = read(whole(&data), data.len());
        let gathered = read(gathered(&data), data.len());
        assert_eq!(
            (&gathered.preview, &gathered.largest_preview),
            (&got.preview, &got.largest_preview),
            "{path}"
        );
        let wanted =
            RAW.contains(&record["format"].as_str().unwrap()) || !quirks(&record, &["embedded_preview"]).is_empty();
        match (got.preview, got.largest_preview) {
            (Some(small), Some(large)) => {
                for span in [small, large] {
                    let jpeg = &data[span.offset as usize..][..span.length as usize];
                    assert!(
                        jpeg.starts_with(&[0xff, 0xd8]) && jpeg.ends_with(&[0xff, 0xd9]),
                        "{path}: {span:?} is no JPEG"
                    );
                }
                assert!(small.length <= large.length, "{path}");
                found += 1;
            }
            (small, large) => assert!(!wanted && small.is_none() && large.is_none(), "{path}: no preview"),
        }
    }
    assert!(found >= 24, "{found} previews");
}

/// Milliseconds since 1970 of a golden "YYYY-MM-DDThh:mm:ss[.fff]Z".
fn instant(utc: &Value) -> Option<i64> {
    let text = utc.as_str()?;
    let number = |range: std::ops::Range<usize>| text[range].parse::<i64>().unwrap();
    let (year, month, day) = (number(0..4), number(5..7), number(8..10));
    // Days from 1970-01-01 to the date (Howard Hinnant's days_from_civil).
    let (year, month) = if month <= 2 {
        (year - 1, month + 9)
    } else {
        (year, month - 3)
    };
    let days = year * 365 + year / 4 - year / 100 + year / 400 + (153 * month + 2) / 5 + day - 1 - 719_468;
    let seconds = days * 86_400 + number(11..13) * 3600 + number(14..16) * 60 + number(17..19);
    let millis = if text.len() > 21 { number(20..23) } else { 0 };
    Some(seconds * 1000 + millis)
}

/// Live Photos are found on the whole corpus as its golden groups say: the still and the video of a group with a key
/// read that key as their content identifier, no other file reads one, and PairLivePhotos over every file, given the
/// golden capture instants, pairs exactly each group's primary with its live_motion.
#[test]
fn live_photo_pairs_match_the_corpus() {
    let corpus = corpus();
    let mut files = vec![];
    for (record, data) in &corpus {
        let got = read(whole(data), data.len());
        let group = &record["group"];
        let key = (group["kind"] == "live_photo").then(|| group["key"].as_str()).flatten();
        assert_eq!(got.content_identifier, key.unwrap_or(""), "{}", record["path"]);
        files.push(LivePhotoPart {
            path: record["path"].as_str().unwrap().into(),
            video: record["media"]["kind"] == "video",
            content_identifier: got.content_identifier,
            captured_ms: instant(&record["capture_time"]["resolved"]["utc"]),
            duration_ms: got.duration_ms,
        });
    }
    let response: PairLivePhotosResponse =
        kernel(Method::PairLivePhotos, PairLivePhotosRequest { files: files.clone() });
    let got: Vec<_> = response
        .pairs
        .iter()
        .map(|pair| {
            (
                files[pair.still as usize].path.as_str(),
                files[pair.video as usize].path.as_str(),
            )
        })
        .collect();
    let member = |role: &'static str| {
        corpus
            .iter()
            .map(|(record, _)| record)
            .filter(move |r| r["group"]["kind"] == "live_photo" && r["group"]["role"] == role)
    };
    let folder = |record: &Value| Path::new(record["path"].as_str().unwrap()).parent().unwrap().to_owned();
    let want: Vec<_> = member("primary")
        .flat_map(|still| {
            member("live_motion")
                .filter(|video| video["group"]["key"] == still["group"]["key"] && folder(video) == folder(still))
                .map(|video| (still["path"].as_str().unwrap(), video["path"].as_str().unwrap()))
        })
        .collect();
    assert_eq!(want.len(), 4);
    assert_eq!(got, want);
}

/// Days since 1970-01-01 (Howard Hinnant's days_from_civil).
fn days(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let (era, yoe) = (y.div_euclid(400), y.rem_euclid(400));
    era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + (153 * ((m + 9) % 12) + 2) / 5 + d - 1 - 719_468
}

/// Milliseconds since 1970 of a golden "YYYY-MM-DDThh:mm:ss[.sss]Z".
fn millis(text: &str) -> i64 {
    let n = |at: usize, len: usize| text.get(at..at + len).map_or(0, |d| d.parse::<i64>().unwrap());
    let day = days(n(0, 4), n(5, 2), n(8, 2));
    ((day * 24 + n(11, 2)) * 60 + n(14, 2)) * 60_000 + n(17, 2) * 1000 + n(20, 3)
}

/// What a host's places pack gives for the corpus' GPS positions: the zone of the nearest of its four cities, with
/// their daylight-saving rules from 2000 to 2030.
fn zone_at(lat: f64, lon: f64) -> Option<TimeZone> {
    // The nth Sunday of a month, counting from its end when nth is 0; 1970-01-01 was a Thursday.
    let sunday = |y: i64, m: i64, nth: i64| {
        let from = if nth == 0 {
            days(y + m / 12, m % 12 + 1, 1) - 7
        } else {
            days(y, m, 1) + 7 * (nth - 1)
        };
        from + (7 - (from + 4).rem_euclid(7)) % 7
    };
    // (name, latitude, longitude, standard and summer offsets, summer's start and end as (month, nth, local hour)).
    let cities = [
        ("Europe/Paris", 48.86, 2.29, 60, 120, (3, 0, 2), (10, 0, 3)),
        ("Europe/Rome", 41.90, 12.50, 60, 120, (3, 0, 2), (10, 0, 3)),
        ("America/Los_Angeles", 37.77, -122.42, -480, -420, (3, 2, 2), (11, 1, 2)),
        ("Australia/Sydney", -33.87, 151.21, 600, 660, (10, 1, 2), (4, 1, 3)),
    ];
    let (name, _, _, standard, summer, start, end) = cities
        .into_iter()
        .find(|c| (c.1 - lat).abs() < 0.5 && (c.2 - lon).abs() < 0.5)?;
    let change = |y: i64, (m, nth, hour): (i64, i64, i64), before: i32, after: i32| ZoneOffset {
        starts_at: Some(Timestamp {
            seconds: (sunday(y, m, nth) * 24 + hour) * 3600 - i64::from(before) * 60,
            nanos: 0,
        }),
        offset_minutes: after,
    };
    let mut offsets: Vec<ZoneOffset> = (2000..=2030)
        .flat_map(|y| [change(y, start, standard, summer), change(y, end, summer, standard)])
        .collect();
    offsets.sort_by_key(|o| o.starts_at.as_ref().unwrap().seconds);
    Some(TimeZone {
        name: name.into(),
        offsets,
    })
}

/// The kernel's claim source under the corpus' name for it.
fn golden_source(claim: &TimeClaim) -> String {
    let time = claim.time.as_ref().unwrap();
    match (time.source.as_str(), time.offset_minutes) {
        ("exif:DateTimeOriginal", Some(_)) => "exif_dto_with_offset".into(),
        ("exif:DateTimeOriginal", None) => "exif_dto_no_offset".into(),
        ("exif:CreateDate", _) => "exif_createdate".into(),
        ("exif:GPSDateTime", _) => "gps_datetime".into(),
        ("quicktime:creationdate", _) => "qt_keys_creationdate".into(),
        ("quicktime:mvhd", Some(0)) => "qt_mvhd_phone".into(),
        ("quicktime:mvhd", _) => "qt_mvhd_camera".into(),
        ("takeout:photoTakenTime", _) => "takeout_photoTakenTime".into(),
        (source, _) if source.starts_with("xmp-") => "xmp_date_with_offset".into(),
        (source, _) => source.into(),
    }
}

fn precision_name(precision: i32) -> &'static str {
    match CaptureTimePrecision::try_from(precision) {
        Ok(CaptureTimePrecision::Millisecond) => "ms",
        Ok(CaptureTimePrecision::Second) => "s",
        Ok(CaptureTimePrecision::Minute) => "min",
        Ok(CaptureTimePrecision::Day) => "day",
        Ok(CaptureTimePrecision::Month) => "month",
        Ok(CaptureTimePrecision::Year) => "year",
        _ => "",
    }
}

/// The resolution as a golden `capture_time.resolved` record, its instant in milliseconds; null when nothing dates the
/// file.
fn resolved(got: &ResolveCaptureTimeResponse) -> Value {
    let time = got.capture_time.as_ref().unwrap();
    let Some(winner) = got.claims.iter().find(|c| c.verdict == ClaimVerdict::Won as i32) else {
        return Value::Null;
    };
    let precision = precision_name(time.precision);
    let utc = got
        .taken_at
        .as_ref()
        .map(|t| t.seconds * 1000 + i64::from(t.nanos / 1_000_000));
    let offset = time.offset_minutes.map(|o| {
        format!(
            "{}{:02}:{:02}",
            if o < 0 { '-' } else { '+' },
            o.abs() / 60,
            o.abs() % 60
        )
    });
    let tz = match ZoneSource::try_from(got.zone_source) {
        Ok(ZoneSource::ExplicitOffset) => "explicit_offset",
        Ok(ZoneSource::GpsDelta) => "gps_delta",
        Ok(ZoneSource::PairedUtcDelta) => "paired_utc_delta",
        Ok(ZoneSource::GpsZone) => "gps_polygon",
        _ if time.local_datetime.is_empty() => "device_default",
        _ => "floating",
    };
    let band = match time.confidence {
        85.. => "high",
        50.. => "medium",
        _ => "low",
    };
    let mut flags: Vec<&str> = got
        .flags
        .iter()
        .map(|f| match CaptureTimeFlag::try_from(*f) {
            Ok(CaptureTimeFlag::NeedsReview) => "needs_review",
            Ok(CaptureTimeFlag::CaptureAfterReceive) => "capture_after_receive",
            Ok(CaptureTimeFlag::ZoneMismatch) => "zone_mismatch",
            _ => "dst_ambiguous",
        })
        .collect();
    flags.sort();
    json!({
        "local": Some(&time.local_datetime).filter(|l| !l.is_empty()),
        "utc": utc,
        "offset": offset,
        "tz_source": tz,
        "precision": precision,
        "bound": if got.upper_bound { "upper" } else { "exact" },
        "source": golden_source(winner),
        "confidence_band": band,
        "flags": flags,
    })
}

/// Whether the resolver reported a golden claim of a file name or folder, or a golden rejection, as the record says.
fn reported(claim: &Value, got: &ResolveCaptureTimeResponse) -> bool {
    let source = claim["source"].as_str().unwrap();
    let verdict = match claim["rejected"].as_str() {
        Some("sentinel") => Some(ClaimVerdict::Sentinel),
        Some("invalid") => Some(ClaimVerdict::Invalid),
        Some("out_of_range") => Some(ClaimVerdict::OutOfRange),
        Some("ambiguous_order") => Some(ClaimVerdict::AmbiguousOrder),
        Some("no_year") => Some(ClaimVerdict::NoYear),
        _ => None,
    };
    let event = match claim["event"].as_str().unwrap() {
        "receive" => TimeEvent::Receive,
        "save" => TimeEvent::Save,
        "transfer" => TimeEvent::Transfer,
        "scan" => TimeEvent::Scan,
        _ => TimeEvent::Capture,
    };
    got.claims.iter().any(|c| {
        let time = c.time.as_ref().unwrap();
        let value = claim["value"].as_str().map(|v| v.trim_end_matches('Z'));
        golden_source(c) == source
            && c.event == event as i32
            && match verdict {
                Some(verdict) => c.verdict == verdict as i32,
                None => {
                    value == Some(time.local_datetime.as_str())
                        && claim["value"].as_str().unwrap().ends_with('Z') == (time.offset_minutes == Some(0))
                        && claim["precision"].as_str() == Some(precision_name(time.precision))
                }
            }
    })
}

/// Records the resolver cannot match, with the reason.
const UNMATCHED: [(&str, &str); 1] = [(
    "names/IMG_20190221_112112042.jpg",
    "F02 or F08: names/IMG_20231231_123456789.jpg has the same shape and its record says F08",
)];

/// The corpus through ResolveCaptureTime, with this test as the host: the whole file as its head, the original name
/// and folder, the record's QuickTime and Takeout claims and, for formats ReadMetadata does not read, its EXIF ones
/// (their readers are M1-06 and M4-02), the zone at the GPS position, and 2026-10-16 as now. Every resolution must
/// match its golden record, and every file-name, folder and rejected claim must be reported as the record says.
#[test]
fn golden_capture_times_match_on_the_corpus() {
    let mut mismatches = vec![];
    let mut unmatched = vec![];
    let records = corpus();
    for (record, data) in &records {
        let path = record["path"].as_str().unwrap();
        let (folder, stored) = path.rsplit_once('/').unwrap_or(("", path));
        let unread = !in_scope(record);
        let host = |claim: &Value| {
            let value = claim["value"].as_str()?;
            let source = match claim["source"].as_str()? {
                "qt_keys_creationdate" => "quicktime:creationdate",
                "qt_mvhd_phone" | "qt_mvhd_camera" => "quicktime:mvhd",
                "takeout_photoTakenTime" => "takeout:photoTakenTime",
                "exif_dto_with_offset" | "exif_dto_no_offset" if unread => "exif:DateTimeOriginal",
                "gps_datetime" if unread => "exif:GPSDateTime",
                _ => return None,
            };
            let offset = claim["offset"].as_str().map(offset_minutes);
            Some(CaptureTime {
                local_datetime: value.trim_end_matches('Z').into(),
                offset_minutes: if value.ends_with('Z') { Some(0) } else { offset },
                source: source.into(),
                ..CaptureTime::default()
            })
        };
        let claims = record["capture_time"]["claims"].as_array().unwrap();
        let gps = &record["metadata"]["gps"];
        let request = ResolveCaptureTimeRequest {
            head: data.clone(),
            file_name: record["original_name"].as_str().unwrap_or(stored).into(),
            folder: folder.into(),
            claims: claims.iter().filter_map(host).collect(),
            gps_zone: gps["lat"].as_f64().and_then(|lat| zone_at(lat, gps["lon"].as_f64()?)),
            device_zone: None,
            resolved_at: Some(Timestamp {
                seconds: 1_792_108_800,
                nanos: 0,
            }),
            ..ResolveCaptureTimeRequest::default()
        };
        let response = call(Method::ResolveCaptureTime as u32, &request.encode_to_vec());
        let got = match CallResponse::decode(response.as_slice()).unwrap().result {
            Some(call_response::Result::Response(bytes)) => {
                ResolveCaptureTimeResponse::decode(bytes.as_slice()).unwrap()
            }
            other => panic!("{path}: expected a response, got {other:?}"),
        };
        let mut want = record["capture_time"]["resolved"].clone();
        if let Some(utc) = want["utc"].as_str() {
            want["utc"] = millis(utc).into();
        }
        let found = resolved(&got);
        if UNMATCHED.iter().any(|u| u.0 == path) {
            if want != found {
                unmatched.push(path);
            }
            continue;
        }
        if want != found {
            mismatches.push(format!("{path}:\n  want {want}\n  got  {found}"));
        }
        for claim in claims {
            let source = claim["source"].as_str().unwrap();
            let checked =
                source.starts_with("filename:") || source.starts_with("path:") || claim.get("rejected").is_some();
            if checked && !reported(claim, &got) {
                mismatches.push(format!("{path}: claim {claim} not reported: {:?}", got.claims));
            }
        }
    }
    assert!(
        mismatches.is_empty(),
        "{} of {} records differ:\n{}",
        mismatches.len(),
        records.len(),
        mismatches.join("\n")
    );
    assert_eq!(
        unmatched,
        UNMATCHED.map(|u| u.0),
        "a record listed as unmatched now matches or is gone"
    );
}
