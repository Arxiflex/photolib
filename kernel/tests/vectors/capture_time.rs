//! Conformance cases of ResolveCaptureTime: one per rule of the file-name registry (F01 to F56) and folder date, and
//! one per resolution behaviour of design doc 13 §4: claims, plausibility, agreement, zones, conflicts and bounds.

use super::call_case;
use super::metadata::{self, EXIF_IFD, Field, GPS_IFD, keys, movie, sample};
use photolib_kernel::proto::kernel::v1::{
    CaptureTimeFlag, CaptureTimeRule, ClaimVerdict, FileRange, Method, ResolveCaptureTimeRequest,
    ResolveCaptureTimeResponse, TimeClaim, TimeEvent, TimeZone, ZoneOffset, ZoneSource,
};
use photolib_kernel::proto::model::v1::{CaptureTime, CaptureTimePrecision as P};
use prost::Message;
use prost_types::Timestamp;
use serde_json::Value;

const ORIGINAL: u16 = 0x9003;
const CREATE: u16 = 0x9004;
const OFFSET: u16 = 0x9011;
const SUBSEC: u16 = 0x9291;
const MAKE: u16 = 0x010f;

/// A JPEG head holding an EXIF segment: IFD0 points to an Exif IFD with the given ASCII tags.
fn jpeg(big_endian: bool, tags: &[(u16, &'static str)]) -> Vec<u8> {
    exif(big_endian, vec![], tags)
}

fn exif(big_endian: bool, mut ifd0: Vec<(u16, Field)>, tags: &[(u16, &'static str)]) -> Vec<u8> {
    let tags = tags.iter().map(|&(t, text)| (t, Field::Text(text))).collect();
    ifd0.push((EXIF_IFD, Field::Ifd(tags)));
    metadata::jpeg(&[metadata::exif(metadata::tiff(big_endian, ifd0))])
}

/// EXIF DateTimeOriginal, with an offset when given, and a GPS fix at `gps` ("YYYY:MM:DD", [h, m, s]).
fn with_gps(local: &'static str, offset: Option<&'static str>, gps: (&'static str, [u32; 3])) -> Vec<u8> {
    let (date, [h, m, s]) = gps;
    let fix: &'static [(u32, u32)] = Box::leak(Box::new([(h, 1), (m, 1), (s, 1)]));
    let ifd = vec![(0x0007, Field::Rationals(fix)), (0x001d, Field::Text(date))];
    let mut tags = vec![(ORIGINAL, local)];
    tags.extend(offset.map(|o| (OFFSET, o)));
    exif(false, vec![(GPS_IFD, Field::Ifd(ifd))], &tags)
}

fn at(text: &str) -> Timestamp {
    let n = |range: std::ops::Range<usize>| text[range].parse::<i64>().unwrap();
    let (y, m, d) = (n(0..4), n(5..7), n(8..10));
    // Days from 1970-01-01 in the proleptic Gregorian calendar (Howard Hinnant's days_from_civil).
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * ((m + 9) % 12) + 2) / 5 + d - 1;
    let days = era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719_468;
    let millis = text.get(20..23).map_or(0, |ms| ms.parse::<i32>().unwrap());
    Timestamp {
        seconds: days * 86_400 + n(11..13) * 3600 + n(14..16) * 60 + n(17..19),
        nanos: millis * 1_000_000,
    }
}

fn zone(name: &str, offsets: &[(&str, i32)]) -> Option<TimeZone> {
    let offsets = offsets.iter().map(|&(starts, offset_minutes)| ZoneOffset {
        starts_at: Some(at(starts)),
        offset_minutes,
    });
    Some(TimeZone {
        name: name.into(),
        offsets: offsets.collect(),
    })
}

fn paris() -> Option<TimeZone> {
    let summer = [("2024-03-31T01:00:00Z", 120), ("2024-10-27T01:00:00Z", 60)];
    zone("Europe/Paris", &[&[("1970-01-01T00:00:00Z", 60)][..], &summer].concat())
}

fn los_angeles() -> Option<TimeZone> {
    let summer = [("2023-03-12T10:00:00Z", -420), ("2023-11-05T09:00:00Z", -480)];
    zone(
        "America/Los_Angeles",
        &[&[("1970-01-01T00:00:00Z", -480)][..], &summer].concat(),
    )
}

fn named(file_name: &str) -> ResolveCaptureTimeRequest {
    ResolveCaptureTimeRequest {
        file_name: file_name.into(),
        ..Default::default()
    }
}

fn file(head: Vec<u8>, file_name: &str) -> ResolveCaptureTimeRequest {
    ResolveCaptureTimeRequest {
        head,
        ..named(file_name)
    }
}

fn hosted(claims: Vec<CaptureTime>, file_name: &str) -> ResolveCaptureTimeRequest {
    ResolveCaptureTimeRequest {
        claims,
        ..named(file_name)
    }
}

/// A claim the host read, such as a QuickTime or Takeout time.
fn host(source: &str, local: &str, offset: Option<i32>) -> CaptureTime {
    CaptureTime {
        local_datetime: local.into(),
        offset_minutes: offset,
        source: source.into(),
        ..Default::default()
    }
}

/// A movie with these QuickTime keys; its mvhd time is 2023-06-01T15:30:00.
fn film(pairs: &[(&str, &str)]) -> Vec<u8> {
    movie(sample(b"avc1", 1920, 1080, &[]), [1, 0, 0, 1], &[], &[keys(pairs)])
}

/// A claim as the resolver reports it: a capture time that won, unless changed.
fn claim(source: &str, local: &str, precision: P, confidence: u32) -> TimeClaim {
    TimeClaim {
        time: Some(CaptureTime {
            local_datetime: local.into(),
            precision: precision.into(),
            source: source.into(),
            confidence,
            ..Default::default()
        }),
        event: TimeEvent::Capture.into(),
        verdict: ClaimVerdict::Won.into(),
    }
}

trait Judged {
    fn offset(self, minutes: i32) -> Self;
    /// A UTC reading: offset 0.
    fn utc(self) -> Self;
    fn event(self, event: TimeEvent) -> Self;
    fn verdict(self, verdict: ClaimVerdict) -> Self;
}

impl Judged for TimeClaim {
    fn offset(mut self, minutes: i32) -> Self {
        self.time.as_mut().unwrap().offset_minutes = Some(minutes);
        self
    }
    fn utc(self) -> Self {
        self.offset(0)
    }
    fn event(mut self, event: TimeEvent) -> Self {
        self.event = event.into();
        self
    }
    fn verdict(mut self, verdict: ClaimVerdict) -> Self {
        self.verdict = verdict.into();
        self
    }
}

/// A rejected claim: confidence 0.
fn rejected(source: &str, local: &str, precision: P, verdict: ClaimVerdict) -> TimeClaim {
    claim(source, local, precision, 0).verdict(verdict)
}

/// The winning claim's wall clock, source and precision, with the resolved offset, zone and confidence.
fn won(
    claims: Vec<TimeClaim>,
    offset: Option<i32>,
    zone: ZoneSource,
    taken_at: Option<&str>,
    confidence: u32,
) -> ResolveCaptureTimeResponse {
    let winner = claims.iter().find(|c| c.verdict == ClaimVerdict::Won as i32).unwrap();
    let source = winner.time.as_ref().unwrap();
    let upper_bound = [TimeEvent::Receive, TimeEvent::Save, TimeEvent::Transfer]
        .iter()
        .any(|e| winner.event == *e as i32);
    ResolveCaptureTimeResponse {
        capture_time: Some(CaptureTime {
            offset_minutes: offset,
            zone: None,
            confidence,
            ..source.clone()
        }),
        taken_at: taken_at.map(at),
        zone_source: zone.into(),
        upper_bound,
        flags: vec![],
        claims,
        rule: CaptureTimeRule::Agreement.into(),
    }
}

/// A wall clock that floats: no zone, no instant.
fn floating(claims: Vec<TimeClaim>, confidence: u32) -> ResolveCaptureTimeResponse {
    won(claims, None, ZoneSource::Unspecified, None, confidence)
}

/// An instant whose zone nothing tells: no wall clock.
fn instant(claims: Vec<TimeClaim>, taken_at: &str, confidence: u32) -> ResolveCaptureTimeResponse {
    let mut response = won(claims, None, ZoneSource::Unspecified, Some(taken_at), confidence);
    response.capture_time.as_mut().unwrap().local_datetime.clear();
    response
}

fn unknown(claims: Vec<TimeClaim>) -> ResolveCaptureTimeResponse {
    ResolveCaptureTimeResponse {
        capture_time: Some(CaptureTime {
            source: "unknown".into(),
            ..Default::default()
        }),
        claims,
        rule: CaptureTimeRule::NoEvidence.into(),
        ..Default::default()
    }
}

fn disputed(response: ResolveCaptureTimeResponse, flags: &[CaptureTimeFlag]) -> ResolveCaptureTimeResponse {
    ResolveCaptureTimeResponse {
        rule: CaptureTimeRule::MostConfident.into(),
        ..flagged(response, flags)
    }
}

fn flagged(response: ResolveCaptureTimeResponse, flags: &[CaptureTimeFlag]) -> ResolveCaptureTimeResponse {
    ResolveCaptureTimeResponse {
        flags: flags.iter().map(|&f| f.into()).collect(),
        ..response
    }
}

fn zoned(mut response: ResolveCaptureTimeResponse, name: &str, local: &str) -> ResolveCaptureTimeResponse {
    let time = response.capture_time.as_mut().unwrap();
    time.zone = Some(name.into());
    time.local_datetime = local.into();
    response
}

fn case(name: &str, request: ResolveCaptureTimeRequest, response: ResolveCaptureTimeResponse) -> Value {
    call_case(
        name,
        Method::ResolveCaptureTime as u32,
        request.encode_to_vec(),
        Ok(response.encode_to_vec()),
    )
}

/// One file-name rule: the name alone dates the file, its wall clock floating.
fn local_name(name: &str, rule: &str, local: &str, precision: P, confidence: u32) -> Value {
    let source = format!("filename:{rule}");
    let shown = confidence.min(80);
    let response = floating(vec![claim(&source, local, precision, confidence)], shown);
    case(&format!("{rule}: {name}"), named(name), response)
}

/// A rule whose name is a UTC reading: only the instant is known.
fn utc_name(name: &str, rule: &str, utc: &str, precision: P, confidence: u32) -> Value {
    let source = format!("filename:{rule}");
    let response = instant(
        vec![claim(&source, utc, precision, confidence).utc()],
        &format!("{utc}Z"),
        confidence.min(80),
    );
    case(&format!("{rule}: {name}"), named(name), response)
}

/// A messenger or app name: the file was received, saved or transferred then, so taken on or before.
fn bound_name(name: &str, rule: &str, local: &str, precision: P, event: TimeEvent, confidence: u32) -> Value {
    let source = format!("filename:{rule}");
    let claims = vec![claim(&source, local, precision, confidence).event(event)];
    case(&format!("{rule}: {name}"), named(name), floating(claims, confidence))
}

/// A name a rule matches that carries no date: nothing dates the file.
fn dateless(name: &str, rule: &str) -> Value {
    case(&format!("{rule}: {name} has no date"), named(name), unknown(vec![]))
}

pub fn filename_cases() -> Vec<Value> {
    use ClaimVerdict::{AmbiguousOrder, Bound, Invalid, NoYear, OutOfRange, ScanTime, Sentinel};
    use TimeEvent::{Receive, Save, Scan, Transfer};
    let mut cases = vec![
        local_name("IMG_20190509_154733.jpg", "F01", "2019-05-09T15:47:33", P::Second, 90),
        local_name("VID_20231231_235959~2.mp4", "F01", "2023-12-31T23:59:59", P::Second, 90),
        local_name(
            "IMG_20190509_154737(1).jpg",
            "F01",
            "2019-05-09T15:47:37",
            P::Second,
            90,
        ),
        local_name("MVIMG_20190215_193501.jpg", "F02", "2019-02-15T19:35:01", P::Second, 90),
        local_name(
            "IMG_20190221_112113042_BURST001.jpg",
            "F02",
            "2019-02-21T11:21:13.042",
            P::Millisecond,
            90,
        ),
        utc_name(
            "PXL_20231026_210642603.jpg",
            "F03",
            "2023-10-26T21:06:42.603",
            P::Millisecond,
            95,
        ),
        utc_name(
            "00001IMG_00001_BURST1723801037429_COVER.jpg",
            "F04",
            "2024-08-16T09:37:17.429",
            P::Millisecond,
            43,
        ),
        local_name(
            "00000PORTRAIT_00000_BURST20190828181853475.jpg",
            "F04",
            "2019-08-28T18:18:53.475",
            P::Millisecond,
            85,
        ),
        local_name("20231207_101606_001.jpg", "F05", "2023-12-07T10:16:06", P::Second, 90),
        local_name(
            "IMG_20231014_183246_BURST001_COVER.jpg",
            "F06",
            "2023-10-14T18:32:46",
            P::Second,
            90,
        ),
        local_name("IMG20231231123456.jpg", "F07", "2023-12-31T12:34:56", P::Second, 85),
        local_name(
            "IMG_20231231_123456789.jpg",
            "F08",
            "2023-12-31T12:34:56.789",
            P::Millisecond,
            85,
        ),
        local_name(
            "DSC_0002_BURST20230115120000123_COVER.JPG",
            "F09",
            "2023-01-15T12:00:00.123",
            P::Millisecond,
            85,
        ),
        dateless("IMG_E1234.JPG", "F10"),
        local_name(
            "WIN_20231231_12_34_56_Pro.jpg",
            "F11",
            "2023-12-31T12:34:56",
            P::Second,
            85,
        ),
        local_name(
            "Screenshot_20201215-090626.png",
            "F12",
            "2020-12-15T09:06:26",
            P::Second,
            97,
        ),
        local_name(
            "Screenshot_20231027_123303_Facebook.jpg",
            "F13",
            "2023-10-27T12:33:03",
            P::Second,
            97,
        ),
        local_name(
            "Screenshot_2019-04-16-11-19-37-232_com.google.android.youtube.jpg",
            "F14",
            "2019-04-16T11:19:37.232",
            P::Millisecond,
            97,
        ),
        local_name(
            "screen-20240131-142530.mp4",
            "F15",
            "2024-01-31T14:25:30",
            P::Second,
            95,
        ),
        local_name(
            "Screen_Recording_20231231-123456_Chrome.mp4",
            "F16",
            "2023-12-31T12:34:56",
            P::Second,
            95,
        ),
        local_name(
            "Screenrecorder-2023-12-31-12-34-56-789.mp4",
            "F17",
            "2023-12-31T12:34:56.789",
            P::Millisecond,
            95,
        ),
        utc_name(
            "RPReplay_Final1612345678.MP4",
            "F18",
            "2021-02-03T09:47:58",
            P::Second,
            40,
        ),
        local_name(
            "Screen Shot 2017-05-21 at 4.45.52 PM.png",
            "F19",
            "2017-05-21T16:45:52",
            P::Second,
            97,
        ),
        local_name(
            "Screenshot 2019-05-21 at 10.45.52.png",
            "F19",
            "2019-05-21T10:45:52",
            P::Second,
            97,
        ),
        local_name(
            "Screen Recording 2023-12-31 at 12.34.56.mov",
            "F20",
            "2023-12-31T12:34:56",
            P::Second,
            95,
        ),
        local_name(
            "Screenshot 2023-12-31 123456.png",
            "F21",
            "2023-12-31T12:34:56",
            P::Second,
            90,
        ),
        local_name(
            "Screenshot from 2023-12-31 12-34-57-1.png",
            "F22",
            "2023-12-31T12:34:57",
            P::Second,
            97,
        ),
        local_name(
            "Screenshot_20231231_123456.png",
            "F23",
            "2023-12-31T12:34:56",
            P::Second,
            95,
        ),
        local_name("2023-12-31_12-34.png", "F24", "2023-12-31T12:34", P::Minute, 90),
        bound_name("IMG-20191120-WA0001.jpg", "F25", "2019-11-20", P::Day, Receive, 30),
        bound_name(
            "WhatsApp Video 2023-05-14 at 4.22.31 PM (1).mp4",
            "F26",
            "2023-05-14T16:22:31",
            P::Second,
            Receive,
            30,
        ),
        bound_name(
            "IMG_20231231_123456_789.jpg",
            "F27",
            "2023-12-31T12:34:56.789",
            P::Millisecond,
            Save,
            36,
        ),
        bound_name(
            "photo_2023-12-31_12-34-56.jpg",
            "F28",
            "2023-12-31T12:34:56",
            P::Second,
            Save,
            30,
        ),
        bound_name(
            "photo_1@31-12-2023_12-34-56.jpg",
            "F29",
            "2023-12-31T12:34:56",
            P::Second,
            Receive,
            30,
        ),
        bound_name(
            "signal-2024-01-30-09-57-18-123.jpg",
            "F30",
            "2024-01-30T09:57:18.123",
            P::Millisecond,
            Receive,
            30,
        ),
        dateless("IMG-0a1b2c3d4e5f60718293a4b5c6d7e8f9-V.jpg", "F31"),
        case(
            "F32: mmexport1703999999999.jpg",
            named("mmexport1703999999999.jpg"),
            instant(
                vec![
                    claim("filename:F32", "2023-12-31T05:19:59.999", P::Millisecond, 12)
                        .utc()
                        .event(Save),
                ],
                "2023-12-31T05:19:59.999Z",
                12,
            ),
        ),
        utc_name(
            "wx_camera_1703999999999.mp4",
            "F32",
            "2023-12-31T05:19:59.999",
            P::Millisecond,
            40,
        ),
        bound_name(
            "KakaoTalk_20231231_123456789.jpg",
            "F33",
            "2023-12-31T12:34:56.789",
            P::Millisecond,
            Save,
            24,
        ),
        case(
            "F34: LINE names have no rule yet",
            named("LINE_ALBUM_trip_231231_1.jpg"),
            unknown(vec![]),
        ),
        case(
            "F35: FB_IMG_1703999999999.jpg",
            named("FB_IMG_1703999999999.jpg"),
            instant(
                vec![
                    claim("filename:F35", "2023-12-31T05:19:59.999", P::Millisecond, 9)
                        .utc()
                        .event(Save),
                ],
                "2023-12-31T05:19:59.999Z",
                9,
            ),
        ),
        case(
            "F36: an Instagram export's month folder",
            ResolveCaptureTimeRequest {
                folder: "instagram/media/posts/202312".into(),
                ..named("17912345678901234.jpg")
            },
            floating(vec![claim("filename:F36", "2023-12", P::Month, 18).event(Transfer)], 18),
        ),
        dateless("Snapchat-1234567890.jpg", "F37"),
        local_name(
            "DJI_20240225080944_0032_D.JPG",
            "F38",
            "2024-02-25T08:09:44",
            P::Second,
            85,
        ),
        dateless("DJI_0005.JPG", "F39"),
        case(
            "F40: dji_fly_20240225_080944_0032_1708850908777_photo.jpg",
            named("dji_fly_20240225_080944_0032_1708850908777_photo.jpg"),
            floating(
                vec![
                    claim("filename:F40", "2024-02-25T08:09:44", P::Second, 85),
                    claim("filename:F40", "2024-02-25T08:48:28.777", P::Millisecond, 26)
                        .utc()
                        .event(Transfer)
                        .verdict(Bound),
                ],
                80,
            ),
        ),
        dateless("GX010002.MP4", "F41"),
        local_name(
            "VID_20201031_094049_00_188.insv",
            "F42",
            "2020-10-31T09:40:49",
            P::Second,
            85,
        ),
        dateless("_DSC0001.NEF", "F43"),
        case(
            "F44: an Olympus name has a month and day but no year",
            named("PC310001.JPG"),
            unknown(vec![rejected("filename:F44", "", P::Unspecified, NoYear)]),
        ),
        case(
            "F45: an Epson scan's CreateDate is the scan time",
            file(
                exif(
                    false,
                    vec![(MAKE, Field::Text("EPSON"))],
                    &[(CREATE, "2023:06:18 14:20:05")],
                ),
                "photo-name_a.jpg",
            ),
            unknown(vec![
                rejected("exif:CreateDate", "2023-06-18T14:20:05", P::Second, ScanTime).event(Scan),
            ]),
        ),
        case(
            "F46: a scanner app's name is the scan time",
            named("CamScanner 12-31-2023 12.34.jpg"),
            unknown(vec![
                rejected("filename:F46", "2023-12-31T12:34", P::Minute, ScanTime).event(Scan),
            ]),
        ),
        local_name("2023-12-31 12.34.56.jpg", "F47", "2023-12-31T12:34:56", P::Second, 85),
        utc_name(
            "20231231_123456000_iOS.jpg",
            "F48",
            "2023-12-31T12:34:56.000",
            P::Millisecond,
            70,
        ),
        local_name(
            "Photo 22-04-06 15-21-03 2160.jpg",
            "F49",
            "2022-04-06T15:21:03",
            P::Second,
            85,
        ),
        case(
            "F50: a Takeout name the host restored from its JSON title",
            named("IMG_20190510_101112_a_very_long_descriptive_title_that_gets_cut.jpg"),
            floating(vec![claim("filename:F01", "2019-05-10T10:11:12", P::Second, 90)], 80),
        ),
        local_name(
            "Photo on 12-31-23 at 12.34 PM.jpg",
            "F51",
            "2023-12-31T12:34",
            P::Minute,
            70,
        ),
        case(
            "F51: Photo Booth's day and month either way round",
            named("Photo on 4-5-2019 at 9.15.jpg"),
            unknown(vec![rejected("filename:F51", "", P::Unspecified, AmbiguousOrder)]),
        ),
        local_name("2023-12-31_12-34-56.jpg", "F52", "2023-12-31T12:34:56", P::Second, 60),
        local_name("201801261147521000.jpg", "F53", "2018-01-26T11:47:52", P::Second, 45),
        local_name("2019-07-23.jpg", "F54", "2019-07-23", P::Day, 40),
        utc_name(
            "image_1703999999999.png",
            "F55",
            "2023-12-31T05:19:59.999",
            P::Millisecond,
            15,
        ),
        local_name("31.12.2023.jpg", "F56", "2023-12-31", P::Day, 40),
        case(
            "F56: day and month either way round",
            named("04.05.2019.jpg"),
            unknown(vec![rejected("filename:F56", "", P::Unspecified, AmbiguousOrder)]),
        ),
        case(
            "a date that does not exist",
            named("IMG_20230230_101010.jpg"),
            unknown(vec![rejected(
                "filename:F01",
                "2023-02-30T10:10:10",
                P::Second,
                Invalid,
            )]),
        ),
        case(
            "a camera's reset clock",
            named("IMG_19800101_000000.jpg"),
            unknown(vec![rejected(
                "filename:F01",
                "1980-01-01T00:00:00",
                P::Second,
                Sentinel,
            )]),
        ),
        case(
            "a WhatsApp name before WhatsApp",
            named("IMG-20051120-WA0001.jpg"),
            unknown(vec![
                rejected("filename:F25", "2005-11-20", P::Day, OutOfRange).event(Receive),
            ]),
        ),
        case(
            "an epoch after the resolver runs",
            ResolveCaptureTimeRequest {
                resolved_at: Some(at("2026-10-16T00:00:00Z")),
                ..named("image_1999999999999.png")
            },
            unknown(vec![
                rejected("filename:F55", "2033-05-18T03:33:19.999", P::Millisecond, OutOfRange).utc(),
            ]),
        ),
    ];
    for (folder, source, local, precision) in [
        ("2019/05/09", "path:ymd", "2019-05-09", P::Day),
        ("Photos/2019/05", "path:ym", "2019-05", P::Month),
        ("2019", "path:y", "2019", P::Year),
        ("Imports/2015-01-14 Wedding", "path:ymd", "2015-01-14", P::Day),
    ] {
        cases.push(case(
            &format!("a folder date: {folder}"),
            ResolveCaptureTimeRequest {
                folder: folder.into(),
                ..named("photo.jpg")
            },
            floating(vec![claim(source, local, precision, 30)], 30),
        ));
    }
    cases
}

pub fn capture_time_cases() -> Vec<Value> {
    use CaptureTimeFlag::{AssumedZone, CaptureAfterReceive, DstAmbiguous, NeedsReview, ZoneMismatch};
    use ClaimVerdict::UnknownSource;
    use ClaimVerdict::{Agrees, Bound, Conflicts, Invalid, OutOfRange, Outvoted, Sentinel, Stale};
    use ZoneSource::{DefaultZone, DeviceZone, ExplicitOffset, GpsDelta, GpsZone, PairedUtcDelta};
    let dto = |local, precision, confidence| claim("exif:DateTimeOriginal", local, precision, confidence);
    let full = [(ORIGINAL, "2025:07:14 16:03:09"), (SUBSEC, "25"), (OFFSET, "+02:00")];
    let explicit = || {
        won(
            vec![dto("2025-07-14T16:03:09.250", P::Millisecond, 95).offset(120)],
            Some(120),
            ExplicitOffset,
            Some("2025-07-14T14:03:09.250Z"),
            95,
        )
    };
    let mut after_jfif = jpeg(false, &full);
    after_jfif.splice(
        2..2,
        [0xff, 0xe0, 0, 16]
            .iter()
            .chain(b"JFIF\0\x01\x02\0\0\x01\0\x01\0\0")
            .copied(),
    );
    let only = |tags: &[(u16, &'static str)]| file(jpeg(false, tags), "x.jpg");
    let pixel_video = || hosted(vec![host("quicktime:mvhd", "2023-10-26T21:06:42", Some(0))], "x.mp4");
    let mvhd = |confidence| claim("quicktime:mvhd", "2023-10-26T21:06:42", P::Second, confidence).utc();
    vec![
        case(
            "EXIF with sub-seconds and an offset",
            file(jpeg(false, &full), "x.jpg"),
            explicit(),
        ),
        case("big-endian EXIF", file(jpeg(true, &full), "x.jpg"), explicit()),
        case("EXIF after a JFIF segment", file(after_jfif, "x.jpg"), explicit()),
        case(
            "a quarter-hour offset",
            only(&[(ORIGINAL, "2019:05:09 15:47:33"), (OFFSET, "+05:45")]),
            won(
                vec![dto("2019-05-09T15:47:33", P::Second, 95).offset(345)],
                Some(345),
                ExplicitOffset,
                Some("2019-05-09T10:02:33Z"),
                95,
            ),
        ),
        case(
            "no offset: the wall clock floats",
            only(&[(ORIGINAL, "2019:05:09 15:47:33")]),
            floating(vec![dto("2019-05-09T15:47:33", P::Second, 85)], 80),
        ),
        case(
            "an offset off the 15-minute grid is ignored",
            only(&[(ORIGINAL, "2019:05:09 15:47:33"), (OFFSET, "-05:59")]),
            floating(
                vec![
                    rejected("exif:DateTimeOriginal", "2019-05-09T15:47:33", P::Second, Invalid).offset(-359),
                    dto("2019-05-09T15:47:33", P::Second, 85),
                ],
                80,
            ),
        ),
        case(
            "an offset beyond +14:00 is ignored",
            only(&[(ORIGINAL, "2019:05:09 15:47:33"), (OFFSET, "+14:15")]),
            floating(
                vec![
                    rejected("exif:DateTimeOriginal", "2019-05-09T15:47:33", P::Second, OutOfRange).offset(855),
                    dto("2019-05-09T15:47:33", P::Second, 85),
                ],
                80,
            ),
        ),
        case(
            "long sub-seconds are cut to milliseconds",
            only(&[(ORIGINAL, "2019:05:09 15:47:33"), (SUBSEC, "123456")]),
            floating(vec![dto("2019-05-09T15:47:33.123", P::Millisecond, 85)], 80),
        ),
        case(
            "hour 24 is the next midnight",
            only(&[(ORIGINAL, "2019:12:31 24:00:00")]),
            floating(vec![dto("2020-01-01T00:00:00", P::Second, 85)], 80),
        ),
        case(
            "second 60 is a leap second",
            only(&[(ORIGINAL, "2016:12:31 23:59:60")]),
            floating(vec![dto("2016-12-31T23:59:59", P::Second, 85)], 80),
        ),
        case(
            "EXIF CreateDate when nothing else dates the file",
            only(&[(CREATE, "2015:06:01 10:00:00")]),
            floating(vec![claim("exif:CreateDate", "2015-06-01T10:00:00", P::Second, 60)], 60),
        ),
        case(
            "EXIF and a file name that disagree: EXIF wins, for review",
            file(
                jpeg(true, &[(ORIGINAL, "2024:02:29 23:59:59")]),
                "IMG_20200101_000000.jpg",
            ),
            disputed(
                floating(
                    vec![
                        dto("2024-02-29T23:59:59", P::Second, 85),
                        claim("filename:F01", "2020-01-01T00:00:00", P::Second, 63).verdict(Conflicts),
                    ],
                    68,
                ),
                &[NeedsReview],
            ),
        ),
        case(
            "EXIF and a file name that agree",
            file(
                jpeg(false, &[(ORIGINAL, "2019:02:15 19:35:01")]),
                "MVIMG_20190215_193501.jpg",
            ),
            floating(
                vec![
                    dto("2019-02-15T19:35:01", P::Second, 85),
                    claim("filename:F02", "2019-02-15T19:35:01", P::Second, 90).verdict(Agrees),
                ],
                80,
            ),
        ),
        case(
            "a zero date is a sentinel: the file name dates the file",
            file(
                jpeg(false, &[(ORIGINAL, "0000:00:00 00:00:00")]),
                "IMG_20190509_154733.jpg",
            ),
            floating(
                vec![
                    rejected("exif:DateTimeOriginal", "0000-00-00T00:00:00", P::Second, Sentinel),
                    claim("filename:F01", "2019-05-09T15:47:33", P::Second, 90),
                ],
                80,
            ),
        ),
        case(
            "an impossible date in EXIF",
            file(jpeg(false, &[(ORIGINAL, "2023:02:29 10:00:00")]), "photo.jpg"),
            unknown(vec![rejected(
                "exif:DateTimeOriginal",
                "2023-02-29T10:00:00",
                P::Second,
                Invalid,
            )]),
        ),
        case(
            "a date too far in the future: the Pixel name dates the file",
            ResolveCaptureTimeRequest {
                resolved_at: Some(at("2026-10-16T00:00:00Z")),
                ..file(
                    jpeg(false, &[(ORIGINAL, "2099:01:01 00:00:00")]),
                    "PXL_20231026_210642603.jpg",
                )
            },
            instant(
                vec![
                    rejected("exif:DateTimeOriginal", "2099-01-01T00:00:00", P::Second, OutOfRange),
                    claim("filename:F03", "2023-10-26T21:06:42.603", P::Millisecond, 95).utc(),
                ],
                "2023-10-26T21:06:42.603Z",
                80,
            ),
        ),
        case(
            "nothing dates the file",
            file(b"not a jpeg".to_vec(), "scan.png"),
            unknown(vec![]),
        ),
        case(
            "the GPS time gives the zone",
            file(
                with_gps("2019:05:09 15:47:33", None, ("2019:05:09", [5, 47, 33])),
                "x.jpg",
            ),
            won(
                vec![
                    dto("2019-05-09T15:47:33", P::Second, 85),
                    claim("exif:GPSDateTime", "2019-05-09T05:47:33", P::Second, 60)
                        .utc()
                        .verdict(Agrees),
                ],
                Some(600),
                GpsDelta,
                Some("2019-05-09T05:47:33Z"),
                94,
            ),
        ),
        case(
            "a camera on its home time abroad: the GPS time's offset fixes the instant, the position's zone the wall \
             clock, for review",
            ResolveCaptureTimeRequest {
                gps_zone: los_angeles(),
                ..file(
                    with_gps("2023:07:14 20:00:00", None, ("2023:07:14", [18, 0, 0])),
                    "x.jpg",
                )
            },
            flagged(
                zoned(
                    won(
                        vec![
                            dto("2023-07-14T20:00:00", P::Second, 85),
                            claim("exif:GPSDateTime", "2023-07-14T18:00:00", P::Second, 60)
                                .utc()
                                .verdict(Agrees),
                        ],
                        Some(-420),
                        GpsZone,
                        Some("2023-07-14T18:00:00Z"),
                        94,
                    ),
                    "America/Los_Angeles",
                    "2023-07-14T11:00:00",
                ),
                &[NeedsReview, ZoneMismatch],
            ),
        ),
        case(
            "an EXIF offset other than the position's zone then: that zone's wall clock, for review",
            ResolveCaptureTimeRequest {
                gps_zone: paris(),
                ..only(&[(ORIGINAL, "2024:01:02 09:05:44"), (OFFSET, "-05:00")])
            },
            flagged(
                zoned(
                    won(
                        vec![dto("2024-01-02T09:05:44", P::Second, 95).offset(-300)],
                        Some(60),
                        GpsZone,
                        Some("2024-01-02T14:05:44Z"),
                        95,
                    ),
                    "Europe/Paris",
                    "2024-01-02T15:05:44",
                ),
                &[NeedsReview, ZoneMismatch],
            ),
        ),
        case(
            "an EXIF offset the position's zone agrees with stays the camera's",
            ResolveCaptureTimeRequest {
                gps_zone: paris(),
                ..only(&[(ORIGINAL, "2024:07:14 12:00:00"), (OFFSET, "+02:00")])
            },
            won(
                vec![dto("2024-07-14T12:00:00", P::Second, 95).offset(120)],
                Some(120),
                ExplicitOffset,
                Some("2024-07-14T10:00:00Z"),
                95,
            ),
        ),
        case(
            "the device's zone never overrides a measured offset",
            ResolveCaptureTimeRequest {
                device_zone: paris(),
                ..only(&[(ORIGINAL, "2024:01:02 09:05:44"), (OFFSET, "-05:00")])
            },
            won(
                vec![dto("2024-01-02T09:05:44", P::Second, 95).offset(-300)],
                Some(-300),
                ExplicitOffset,
                Some("2024-01-02T14:05:44Z"),
                95,
            ),
        ),
        case(
            "a GPS time equal to the wall clock is one clock read twice: the position's zone places it",
            ResolveCaptureTimeRequest {
                gps_zone: paris(),
                ..file(
                    with_gps("2024:07:14 12:00:00", None, ("2024:07:14", [12, 0, 0])),
                    "x.jpg",
                )
            },
            zoned(
                won(
                    vec![
                        dto("2024-07-14T12:00:00", P::Second, 85),
                        claim("exif:GPSDateTime", "2024-07-14T12:00:00", P::Second, 60)
                            .utc()
                            .verdict(Agrees),
                    ],
                    Some(120),
                    GpsZone,
                    Some("2024-07-14T10:00:00Z"),
                    80,
                ),
                "Europe/Paris",
                "2024-07-14T12:00:00",
            ),
        ),
        case(
            "a GPS time equal to the wall clock where the zone is UTC gives the zone",
            ResolveCaptureTimeRequest {
                gps_zone: zone("Atlantic/Reykjavik", &[("1970-01-01T00:00:00Z", 0)]),
                ..file(
                    with_gps("2024:01:10 12:00:00", None, ("2024:01:10", [12, 0, 0])),
                    "x.jpg",
                )
            },
            won(
                vec![
                    dto("2024-01-10T12:00:00", P::Second, 85),
                    claim("exif:GPSDateTime", "2024-01-10T12:00:00", P::Second, 60)
                        .utc()
                        .verdict(Agrees),
                ],
                Some(0),
                GpsDelta,
                Some("2024-01-10T12:00:00Z"),
                94,
            ),
        ),
        case(
            "an older GPS time is a stale fix",
            file(
                with_gps("2022:04:02 11:30:00", Some("+02:00"), ("2021:07:14", [10, 15, 42])),
                "x.jpg",
            ),
            won(
                vec![
                    dto("2022-04-02T11:30:00", P::Second, 95).offset(120),
                    claim("exif:GPSDateTime", "2021-07-14T10:15:42", P::Second, 60)
                        .utc()
                        .verdict(Stale),
                ],
                Some(120),
                ExplicitOffset,
                Some("2022-04-02T09:30:00Z"),
                95,
            ),
        ),
        case(
            "a GPS time after the capture conflicts",
            file(
                with_gps("2023:05:01 10:00:00", Some("+02:00"), ("2023:05:01", [9, 0, 0])),
                "x.jpg",
            ),
            disputed(
                won(
                    vec![
                        dto("2023-05-01T10:00:00", P::Second, 95).offset(120),
                        claim("exif:GPSDateTime", "2023-05-01T09:00:00", P::Second, 60)
                            .utc()
                            .verdict(Conflicts),
                    ],
                    Some(120),
                    ExplicitOffset,
                    Some("2023-05-01T08:00:00Z"),
                    81,
                ),
                &[NeedsReview],
            ),
        ),
        case(
            "a Pixel name agrees with EXIF",
            file(
                jpeg(
                    false,
                    &[(ORIGINAL, "2024:06:12 12:30:15"), (SUBSEC, "603"), (OFFSET, "+03:00")],
                ),
                "PXL_20240612_093015603.jpg",
            ),
            won(
                vec![
                    dto("2024-06-12T12:30:15.603", P::Millisecond, 95).offset(180),
                    claim("filename:F03", "2024-06-12T09:30:15.603", P::Millisecond, 95)
                        .utc()
                        .verdict(Agrees),
                ],
                Some(180),
                ExplicitOffset,
                Some("2024-06-12T09:30:15.603Z"),
                100,
            ),
        ),
        case(
            "a Takeout time gives a file name its zone",
            hosted(
                vec![host("takeout:photoTakenTime", "2019-05-09T13:47:33", Some(0))],
                "IMG_20190509_154733.jpg",
            ),
            won(
                vec![
                    claim("takeout:photoTakenTime", "2019-05-09T13:47:33", P::Second, 88)
                        .utc()
                        .verdict(Agrees),
                    claim("filename:F01", "2019-05-09T15:47:33", P::Second, 90),
                ],
                Some(120),
                PairedUtcDelta,
                Some("2019-05-09T13:47:33Z"),
                80,
            ),
        ),
        case(
            "a Takeout time gives EXIF its zone",
            ResolveCaptureTimeRequest {
                head: jpeg(false, &[(ORIGINAL, "2024:07:29 04:45:00")]),
                ..hosted(
                    vec![host("takeout:photoTakenTime", "2024-07-28T19:45:00", Some(0))],
                    "x.jpg",
                )
            },
            won(
                vec![
                    dto("2024-07-29T04:45:00", P::Second, 85),
                    claim("takeout:photoTakenTime", "2024-07-28T19:45:00", P::Second, 88)
                        .utc()
                        .verdict(Agrees),
                ],
                Some(540),
                PairedUtcDelta,
                Some("2024-07-28T19:45:00Z"),
                98,
            ),
        ),
        case(
            "QuickTime keys carry the offset",
            hosted(
                vec![
                    host("quicktime:creationdate", "2022-08-14T17:42:10", Some(120)),
                    host("quicktime:mvhd", "2022-08-14T15:42:10", Some(0)),
                ],
                "IMG_2001.MOV",
            ),
            won(
                vec![
                    claim("quicktime:creationdate", "2022-08-14T17:42:10", P::Second, 93).offset(120),
                    claim("quicktime:mvhd", "2022-08-14T15:42:10", P::Second, 80)
                        .utc()
                        .verdict(Agrees),
                ],
                Some(120),
                ExplicitOffset,
                Some("2022-08-14T15:42:10Z"),
                99,
            ),
        ),
        case(
            "a camera's QuickTime clock floats",
            hosted(vec![host("quicktime:mvhd", "2019-05-09T15:47:33", None)], "canon.mov"),
            floating(vec![claim("quicktime:mvhd", "2019-05-09T15:47:33", P::Second, 55)], 55),
        ),
        case(
            "a phone's UTC time with no zone has no wall clock",
            pixel_video(),
            instant(vec![mvhd(80)], "2023-10-26T21:06:42Z", 80),
        ),
        case(
            "the GPS position's zone gives the wall clock",
            ResolveCaptureTimeRequest {
                gps_zone: los_angeles(),
                ..pixel_video()
            },
            zoned(
                won(vec![mvhd(80)], Some(-420), GpsZone, Some("2023-10-26T21:06:42Z"), 80),
                "America/Los_Angeles",
                "2023-10-26T14:06:42",
            ),
        ),
        case(
            "the device's zone journal gives the wall clock",
            ResolveCaptureTimeRequest {
                device_zone: paris(),
                ..hosted(vec![host("quicktime:mvhd", "2023-01-15T12:00:00", Some(0))], "x.mp4")
            },
            zoned(
                won(
                    vec![claim("quicktime:mvhd", "2023-01-15T12:00:00", P::Second, 80).utc()],
                    Some(60),
                    DeviceZone,
                    Some("2023-01-15T12:00:00Z"),
                    80,
                ),
                "Europe/Paris",
                "2023-01-15T13:00:00",
            ),
        ),
        case(
            "a phone's mvhd equal to its name's wall clock is its local clock: the device's zone places it",
            ResolveCaptureTimeRequest {
                device_zone: paris(),
                ..hosted(
                    vec![host("quicktime:mvhd", "2023-01-15T12:00:00", Some(0))],
                    "VID_20230115_120000.mp4",
                )
            },
            zoned(
                won(
                    vec![
                        claim("quicktime:mvhd", "2023-01-15T12:00:00", P::Second, 80)
                            .utc()
                            .verdict(Agrees),
                        claim("filename:F01", "2023-01-15T12:00:00", P::Second, 90),
                    ],
                    Some(60),
                    DeviceZone,
                    Some("2023-01-15T11:00:00Z"),
                    80,
                ),
                "Europe/Paris",
                "2023-01-15T12:00:00",
            ),
        ),
        case(
            "with no evidence of the zone, the default zone gives an assumed wall clock",
            ResolveCaptureTimeRequest {
                default_zone: los_angeles(),
                ..pixel_video()
            },
            flagged(
                zoned(
                    won(
                        vec![mvhd(80)],
                        Some(-420),
                        DefaultZone,
                        Some("2023-10-26T21:06:42Z"),
                        80,
                    ),
                    "America/Los_Angeles",
                    "2023-10-26T14:06:42",
                ),
                &[AssumedZone],
            ),
        ),
        case(
            "a floating wall clock takes its instant from the default zone",
            ResolveCaptureTimeRequest {
                default_zone: paris(),
                ..only(&[(ORIGINAL, "2024:05:09 15:47:33")])
            },
            zoned(
                won(
                    vec![dto("2024-05-09T15:47:33", P::Second, 85)],
                    Some(120),
                    DefaultZone,
                    Some("2024-05-09T13:47:33Z"),
                    80,
                ),
                "Europe/Paris",
                "2024-05-09T15:47:33",
            ),
        ),
        case(
            "the device's zone comes before the default zone",
            ResolveCaptureTimeRequest {
                device_zone: paris(),
                default_zone: los_angeles(),
                ..pixel_video()
            },
            zoned(
                won(vec![mvhd(80)], Some(60), DeviceZone, Some("2023-10-26T21:06:42Z"), 80),
                "Europe/Paris",
                "2023-10-26T22:06:42",
            ),
        ),
        case(
            "an offset in the file comes before the default zone",
            ResolveCaptureTimeRequest {
                default_zone: los_angeles(),
                ..file(jpeg(false, &full), "x.jpg")
            },
            explicit(),
        ),
        case(
            "a zero delta yields to the default zone too",
            ResolveCaptureTimeRequest {
                default_zone: paris(),
                ..hosted(
                    vec![host("quicktime:mvhd", "2023-01-15T12:00:00", Some(0))],
                    "VID_20230115_120000.mp4",
                )
            },
            zoned(
                won(
                    vec![
                        claim("quicktime:mvhd", "2023-01-15T12:00:00", P::Second, 80)
                            .utc()
                            .verdict(Agrees),
                        claim("filename:F01", "2023-01-15T12:00:00", P::Second, 90),
                    ],
                    Some(60),
                    DefaultZone,
                    Some("2023-01-15T11:00:00Z"),
                    80,
                ),
                "Europe/Paris",
                "2023-01-15T12:00:00",
            ),
        ),
        case(
            "a wall clock in the autumn overlap takes the earlier instant",
            ResolveCaptureTimeRequest {
                gps_zone: paris(),
                ..only(&[(ORIGINAL, "2024:10:27 02:30:00")])
            },
            flagged(
                zoned(
                    won(
                        vec![dto("2024-10-27T02:30:00", P::Second, 85)],
                        Some(120),
                        GpsZone,
                        Some("2024-10-27T00:30:00Z"),
                        80,
                    ),
                    "Europe/Paris",
                    "2024-10-27T02:30:00",
                ),
                &[DstAmbiguous],
            ),
        ),
        case(
            "a wall clock in the spring gap keeps the offset before it",
            ResolveCaptureTimeRequest {
                gps_zone: paris(),
                ..only(&[(ORIGINAL, "2024:03:31 02:30:00")])
            },
            flagged(
                zoned(
                    won(
                        vec![dto("2024-03-31T02:30:00", P::Second, 85)],
                        Some(60),
                        GpsZone,
                        Some("2024-03-31T01:30:00Z"),
                        80,
                    ),
                    "Europe/Paris",
                    "2024-03-31T02:30:00",
                ),
                &[DstAmbiguous],
            ),
        ),
        case(
            "taken after it was received",
            file(
                jpeg(false, &[(ORIGINAL, "2019:11:21 08:00:00")]),
                "IMG-20191120-WA0010.jpg",
            ),
            flagged(
                floating(
                    vec![
                        dto("2019-11-21T08:00:00", P::Second, 85),
                        claim("filename:F25", "2019-11-20", P::Day, 21)
                            .event(TimeEvent::Receive)
                            .verdict(Bound),
                    ],
                    40,
                ),
                &[NeedsReview, CaptureAfterReceive],
            ),
        ),
        case(
            "a folder date never overrides EXIF",
            ResolveCaptureTimeRequest {
                folder: "2019/05".into(),
                ..only(&[(ORIGINAL, "2018:08:20 09:30:15"), (OFFSET, "+02:00")])
            },
            ResolveCaptureTimeResponse {
                rule: CaptureTimeRule::MostConfident.into(),
                ..won(
                    vec![
                        dto("2018-08-20T09:30:15", P::Second, 95).offset(120),
                        claim("path:ym", "2019-05", P::Month, 30).verdict(Outvoted),
                    ],
                    Some(120),
                    ExplicitOffset,
                    Some("2018-08-20T07:30:15Z"),
                    95,
                )
            },
        ),
        case(
            "a movie's own dates: its keys' creation date with its offset, and mvhd in UTC",
            file(
                film(&[
                    ("com.apple.quicktime.make", "Apple"),
                    ("com.apple.quicktime.creationdate", "2023-06-01T08:30:00-0700"),
                ]),
                "IMG_0001.MOV",
            ),
            won(
                vec![
                    claim("quicktime:creationdate", "2023-06-01T08:30:00", P::Second, 93).offset(-420),
                    claim("quicktime:mvhd", "2023-06-01T15:30:00", P::Second, 80)
                        .utc()
                        .verdict(Agrees),
                ],
                Some(-420),
                ExplicitOffset,
                Some("2023-06-01T15:30:00Z"),
                99,
            ),
        ),
        case(
            "a camera maker's mvhd time is the camera's clock",
            file(film(&[("com.apple.quicktime.make", "Canon")]), "MVI_0001.MP4"),
            floating(vec![claim("quicktime:mvhd", "2023-06-01T15:30:00", P::Second, 55)], 55),
        ),
        case(
            "a host claim replaces the movie's own of the same source",
            ResolveCaptureTimeRequest {
                claims: vec![host("quicktime:mvhd", "2023-06-01T17:30:00", None)],
                ..file(film(&[]), "clip.mp4")
            },
            floating(vec![claim("quicktime:mvhd", "2023-06-01T17:30:00", P::Second, 55)], 55),
        ),
        case(
            "the file in the ranges ReadMetadata read, instead of a head",
            ResolveCaptureTimeRequest {
                ranges: {
                    let file = jpeg(false, &[(ORIGINAL, "2021:03:04 05:06:07")]);
                    let (start, rest) = file.split_at(10);
                    [(0, start), (10, rest)]
                        .map(|(offset, data)| FileRange {
                            offset,
                            data: data.to_vec(),
                        })
                        .into()
                },
                size: 4096,
                ..named("photo.jpg")
            },
            floating(vec![dto("2021-03-04T05:06:07", P::Second, 85)], 80),
        ),
        case(
            "a host claim from an unknown source",
            hosted(
                vec![host("icloud:originalCreationDate", "2020-01-01T10:00:00", Some(0))],
                "x.jpg",
            ),
            unknown(vec![
                rejected(
                    "icloud:originalCreationDate",
                    "2020-01-01T10:00:00",
                    P::Second,
                    UnknownSource,
                )
                .utc(),
            ]),
        ),
    ]
}
