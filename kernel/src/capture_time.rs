//! Capture-time resolution (design doc 13 §4). Every piece of evidence is a claim: the file's own dates, the host's, the
//! file name's and the folders'. Claims are checked (calendar, sentinels, plausible window, offsets on the 15-minute
//! grid) and rated (a prior per source, lowered for receive dates, epoch names and names that contradict the file);
//! claims that agree form groups and the most confident group wins. Its best claim gives the wall clock, the first
//! evidence that fixes it gives the zone (else the host's default, assumed), and every claim is reported with its
//! verdict, for "why this date?".

mod names;

use crate::metadata;
use crate::proto::kernel::v1::{
    CaptureTimeFlag, CaptureTimeRule, ClaimVerdict, ResolveCaptureTimeRequest, ResolveCaptureTimeResponse, TimeClaim,
    TimeEvent, TimeZone, ZoneSource,
};
use crate::proto::model::v1::{CaptureTime, CaptureTimePrecision as P};
use prost_types::Timestamp;

const SECOND: i64 = 1000;
const MINUTE: i64 = 60 * SECOND;
const HOUR: i64 = 60 * MINUTE;
const DAY: i64 = 24 * HOUR;

/// Placeholder dates of cameras and encoders (doc 13 §4.5), as prefixes of the wall clock.
const SENTINELS: [&str; 6] = [
    "1904-01-01",
    "1970-01-01",
    "1980-01-01T00:00",
    "2000-01-01",
    "2002-12-08T12:00",
    "2036-01-01T23:59:59",
];

/// The claim sources the resolver knows (doc 13 §4.2): prior in per mille with an offset and without, family, and
/// whether offset 0 marks a UTC reading. Other dates, such as ModifyDate, are no capture claims.
const SOURCES: [(&str, u32, u32, Family, bool); 10] = [
    ("exif:DateTimeOriginal", 950, 850, Family::Embedded, false),
    ("xmp-exif:DateTimeOriginal", 930, 850, Family::Embedded, false),
    ("xmp-photoshop:DateCreated", 930, 850, Family::Embedded, false),
    ("iptc:DateCreated", 930, 850, Family::Embedded, false),
    ("quicktime:creationdate", 930, 850, Family::Embedded, false),
    ("xmp-xmp:CreateDate", 930, 850, Family::Embedded, false),
    ("exif:CreateDate", 600, 600, Family::Embedded, false),
    ("exif:GPSDateTime", 600, 600, Family::Embedded, true),
    ("quicktime:mvhd", 800, 550, Family::Embedded, true),
    ("takeout:photoTakenTime", 880, 880, Family::Host, true),
];

/// Makers whose cameras write their own clock in mvhd, which is UTC by the specification and on phones (doc 13 §4.2).
const CAMERA_MAKERS: [&str; 12] = [
    "canon",
    "dji",
    "fujifilm",
    "gopro",
    "insta360",
    "leica",
    "nikon",
    "olympus",
    "panasonic",
    "pentax",
    "ricoh",
    "sony",
];

/// A movie's own date under the source a host gives it.
fn movie_time(mut time: CaptureTime, camera: bool) -> CaptureTime {
    match time.source.as_str() {
        "quicktime:CreationDate" => time.source = "quicktime:creationdate".into(),
        "quicktime:CreateDate" => {
            time.source = "quicktime:mvhd".into();
            time.offset_minutes = (!camera).then_some(0);
        }
        _ => {}
    }
    time
}

/// Where a claim comes from, in the order its wall clock is preferred among agreeing claims.
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum Family {
    Embedded,
    Host,
    Name,
    Folder,
}

struct Claim {
    /// As reported: the text read, normalised once checked, and the confidence once rated.
    time: CaptureTime,
    event: TimeEvent,
    verdict: ClaimVerdict,
    family: Family,
    prior: u32,
    /// A UTC reading: an instant without a wall clock.
    utc: bool,
    epoch: bool,
    since: i64,
    precision: P,
    local: Option<i64>,
    instant: Option<i64>,
    /// Per mille.
    confidence: u32,
}

impl Claim {
    fn new(source: &str, text: String, offset: Option<i32>, event: TimeEvent, prior: u32, family: Family) -> Claim {
        Claim {
            time: CaptureTime {
                local_datetime: text,
                offset_minutes: offset,
                source: source.into(),
                ..Default::default()
            },
            event,
            verdict: ClaimVerdict::Unspecified,
            family,
            prior,
            utc: false,
            epoch: false,
            since: 1826,
            precision: P::Unspecified,
            local: None,
            instant: None,
            confidence: 0,
        }
    }

    fn utc(mut self) -> Claim {
        self.utc = true;
        self.time.offset_minutes = Some(0);
        self
    }

    fn epoch(self) -> Claim {
        Claim { epoch: true, ..self }
    }

    fn since(self, year: i64) -> Claim {
        Claim { since: year, ..self }
    }

    fn rejected(self, verdict: ClaimVerdict) -> Claim {
        Claim { verdict, ..self }
    }

    /// Received, saved or transferred then: the file was taken before.
    fn bound(&self) -> bool {
        !matches!(self.event, TimeEvent::Capture | TimeEvent::Scan)
    }

    /// Bounds and folder dates never conflict with anything, and alone are never sure.
    fn weak(&self) -> bool {
        self.bound() || self.family == Family::Folder
    }
}

pub fn resolve(request: &ResolveCaptureTimeRequest) -> ResolveCaptureTimeResponse {
    let meta = match &request.ranges[..] {
        [] => metadata::read_pieces([(0, request.head.as_slice())], 0),
        ranges => metadata::read_pieces(ranges.iter().map(|r| (r.offset, r.data.as_slice())), request.size),
    };
    let scan = names::epson_scan(&request.file_name, &meta.make);
    let make = meta.make.to_lowercase();
    let camera = CAMERA_MAKERS.iter().any(|m| make.starts_with(m));
    let embedded = meta
        .times
        .into_iter()
        .map(|t| movie_time(t, camera))
        .filter(|t| !request.claims.iter().any(|c| c.source == t.source))
        .flat_map(|t| known(t, false));
    let hosted = request.claims.iter().cloned().flat_map(|t| known(t, true));
    let mut claims: Vec<Claim> = embedded
        .chain(hosted)
        .chain(names::read(&request.file_name, &request.folder))
        .collect();
    let now = request.resolved_at.as_ref().map(|t| t.seconds.saturating_mul(SECOND));
    for claim in &mut claims {
        if scan && claim.time.source.ends_with(":CreateDate") {
            claim.event = TimeEvent::Scan;
        }
        check(claim, now);
    }
    // A file name that contradicts the file's own capture time is the likelier to be wrong (doc 13 §4.5).
    let strong: Vec<usize> = live(&claims)
        .filter(|&i| claims[i].family == Family::Embedded && claims[i].prior >= 850)
        .collect();
    for i in live(&claims).collect::<Vec<_>>() {
        if claims[i].family == Family::Name && strong.iter().any(|&s| !agree(&claims[s], &claims[i])) {
            claims[i].confidence = claims[i].confidence * 7 / 10;
        }
    }
    let mut order: Vec<usize> = live(&claims).collect();
    order.sort_by_key(|&i| (u32::MAX - claims[i].confidence, claims[i].family, i));
    let mut groups: Vec<Vec<usize>> = vec![];
    for i in order {
        match groups.iter_mut().find(|g| agree(&claims[g[0]], &claims[i])) {
            Some(group) => group.push(i),
            None => groups.push(vec![i]),
        }
    }
    let score = |group: &Vec<usize>| {
        let missed = group
            .iter()
            .fold(1000, |m, &i| m * (1000 - claims[i].confidence.min(1000)) / 1000);
        let weak = group.iter().all(|&i| claims[i].weak());
        if weak { (1000 - missed).min(600) } else { 1000 - missed }
    };
    let best = groups
        .iter()
        .enumerate()
        .max_by_key(|(n, g)| (score(g), std::cmp::Reverse(*n)));
    let Some((_, winner)) = best else {
        return ResolveCaptureTimeResponse {
            capture_time: Some(CaptureTime {
                source: "unknown".into(),
                ..Default::default()
            }),
            claims: claims.into_iter().map(report).collect(),
            rule: CaptureTimeRule::NoEvidence.into(),
            ..Default::default()
        };
    };
    let mut members = winner.clone();
    members.sort_by_key(|&i| {
        let c = &claims[i];
        (c.weak(), c.local.is_none(), c.family, 1000 - c.confidence, i)
    });
    let found = place(&claims, &members, request);
    let source = &claims[members[0]];
    let measured = found.mismatch
        || matches!(
            found.zone_source,
            ZoneSource::ExplicitOffset | ZoneSource::GpsDelta | ZoneSource::PairedUtcDelta
        );
    let mut confidence = score(winner);
    if !(source.family < Family::Name && measured) {
        confidence = confidence.min(800);
    }
    let mut verdicts = vec![ClaimVerdict::Unspecified; claims.len()];
    for group in &groups {
        for &i in group {
            let c = &claims[i];
            verdicts[i] = if i == members[0] {
                ClaimVerdict::Won
            } else if group == winner {
                ClaimVerdict::Agrees
            } else if c.time.source == "exif:GPSDateTime"
                && found.instant.zip(c.instant).is_some_and(|(w, g)| g <= w + 2 * SECOND)
            {
                ClaimVerdict::Stale
            } else if c.bound() {
                ClaimVerdict::Bound
            } else if score(group) >= 500 && !c.weak() {
                ClaimVerdict::Conflicts
            } else {
                ClaimVerdict::Outvoted
            };
        }
    }
    let after = !source.bound()
        && (0..claims.len()).any(|i| {
            let b = &claims[i];
            let p = b.precision.min(source.precision);
            verdicts[i] == ClaimVerdict::Bound
                && match (found.local, b.local, found.instant, b.instant) {
                    (Some(w), Some(l), _, _) => format(w, p) > format(l, p),
                    (_, _, Some(w), Some(i)) => w > i + 2 * SECOND,
                    _ => false,
                }
        });
    let disputed = verdicts.contains(&ClaimVerdict::Conflicts);
    if disputed {
        confidence = confidence * 85 / 100;
    }
    if after {
        confidence /= 2;
    }
    let flags = [
        (disputed || after || found.mismatch, CaptureTimeFlag::NeedsReview),
        (after, CaptureTimeFlag::CaptureAfterReceive),
        (found.dst_ambiguous, CaptureTimeFlag::DstAmbiguous),
        (
            found.zone_source == ZoneSource::DefaultZone && source.local.is_none(),
            CaptureTimeFlag::AssumedZone,
        ),
        (found.mismatch, CaptureTimeFlag::ZoneMismatch),
    ];
    let flags = flags.into_iter().filter(|f| f.0).map(|f| f.1.into()).collect();
    let rule = if verdicts
        .iter()
        .any(|v| matches!(v, ClaimVerdict::Conflicts | ClaimVerdict::Outvoted))
    {
        CaptureTimeRule::MostConfident
    } else {
        CaptureTimeRule::Agreement
    };
    let upper_bound = source.bound();
    let capture_time = CaptureTime {
        local_datetime: found.local.map(|l| format(l, source.precision)).unwrap_or_default(),
        offset_minutes: found.offset,
        zone: found.zone,
        precision: source.precision.into(),
        source: source.time.source.clone(),
        confidence: (confidence + 5) / 10,
    };
    for (claim, verdict) in claims.iter_mut().zip(verdicts) {
        if verdict != ClaimVerdict::Unspecified {
            claim.verdict = verdict;
        }
    }
    ResolveCaptureTimeResponse {
        capture_time: Some(capture_time),
        taken_at: found.instant.map(|at| Timestamp {
            seconds: at.div_euclid(SECOND),
            nanos: (at.rem_euclid(SECOND) * 1_000_000) as i32,
        }),
        zone_source: found.zone_source.into(),
        upper_bound,
        flags,
        claims: claims.into_iter().map(report).collect(),
        rule: rule.into(),
    }
}

/// The claims of a date from a known source: an offset off the 15-minute grid or beyond −12:00 to +14:00 is a
/// rejected claim of its own, beside the wall clock without it. A host's date from an unknown source is rejected, the
/// file's other dates ignored.
fn known(time: CaptureTime, host: bool) -> Vec<Claim> {
    let Some(&(source, with, without, family, utc)) = SOURCES.iter().find(|s| s.0 == time.source) else {
        let event = TimeEvent::Capture;
        let claim = Claim::new(
            &time.source,
            time.local_datetime,
            time.offset_minutes,
            event,
            0,
            Family::Host,
        );
        return host
            .then(|| claim.rejected(ClaimVerdict::UnknownSource))
            .into_iter()
            .collect();
    };
    let new = |offset, prior| {
        Claim::new(
            source,
            time.local_datetime.clone(),
            offset,
            TimeEvent::Capture,
            prior,
            family,
        )
    };
    match time.offset_minutes {
        Some(o) if !(-12 * 60..=14 * 60).contains(&o) => {
            vec![
                new(Some(o), with).rejected(ClaimVerdict::OutOfRange),
                new(None, without),
            ]
        }
        Some(o) if o % 15 != 0 => vec![new(Some(o), with).rejected(ClaimVerdict::Invalid), new(None, without)],
        Some(0) if utc => vec![new(Some(0), with).utc()],
        Some(o) => vec![new(Some(o), with)],
        None => vec![new(None, without)],
    }
}

/// Checks a claim against the calendar, the sentinels and the plausible window, and rates it.
fn check(c: &mut Claim, now: Option<i64>) {
    let parsed = parse(&c.time.local_datetime);
    if let Some((_, precision)) = parsed {
        c.precision = precision;
    }
    if c.verdict != ClaimVerdict::Unspecified {
        return;
    }
    let Some((fields, precision)) = parsed else {
        c.verdict = ClaimVerdict::Invalid;
        return;
    };
    let at = match moment(fields) {
        Ok(at) => at,
        Err(verdict) => {
            c.verdict = verdict;
            return;
        }
    };
    c.time.local_datetime = format(at, precision);
    let instant = c.time.offset_minutes.map(|o| at - i64::from(o) * MINUTE);
    let late = now.is_some_and(|now| instant.unwrap_or(at) > now.saturating_add(2 * DAY));
    c.verdict = if SENTINELS.iter().any(|s| c.time.local_datetime.starts_with(s)) {
        ClaimVerdict::Sentinel
    } else if fields[0] < c.since || late {
        ClaimVerdict::OutOfRange
    } else if c.event == TimeEvent::Scan {
        ClaimVerdict::ScanTime
    } else {
        ClaimVerdict::Unspecified
    };
    if c.verdict != ClaimVerdict::Unspecified {
        return;
    }
    (c.local, c.instant) = (if c.utc { None } else { Some(at) }, instant);
    c.confidence = c.prior;
    if c.bound() {
        c.confidence = c.confidence * 6 / 10;
    }
    // An epoch in a name may be an id (doc 13 §5.3).
    if c.epoch {
        c.confidence /= 2;
    }
}

/// The claims not rejected: the candidates.
fn live(claims: &[Claim]) -> impl Iterator<Item = usize> + '_ {
    (0..claims.len()).filter(|&i| claims[i].verdict == ClaimVerdict::Unspecified)
}

/// Whether two claims read the same moment: the same wall clock or instant within 2 s or at the coarser precision,
/// or a wall clock and an instant a whole number of quarter hours apart, which is then the offset.
fn agree(a: &Claim, b: &Claim) -> bool {
    let p = a.precision.min(b.precision);
    let same = |x: i64, y: i64| {
        if p >= P::Second {
            (x - y).abs() <= 2 * SECOND
        } else {
            format(x, p) == format(y, p)
        }
    };
    match (a.local, b.local, a.instant, b.instant) {
        (Some(x), Some(y), _, _) | (_, _, Some(x), Some(y)) => same(x, y),
        (Some(local), None, _, Some(instant)) | (None, Some(local), Some(instant), _) => {
            if p >= P::Minute {
                delta(local, instant, p).is_some()
            } else {
                // Any zone: the wall clock lies within −12:00 and +14:00 of the instant.
                let shown = format(local, p);
                format(instant - 12 * HOUR, p) <= shown && shown <= format(instant + 14 * HOUR, p)
            }
        }
        _ => false,
    }
}

/// The offset in minutes between a wall clock and an instant read at the same moment, when it is a whole number of
/// quarter hours from −12:00 to +14:00.
fn delta(local: i64, instant: i64, p: P) -> Option<i32> {
    let d = local - instant;
    let quarters = (d + 15 * MINUTE / 2).div_euclid(15 * MINUTE) * 15 * MINUTE;
    let tolerance = if p >= P::Second { 2 * SECOND } else { MINUTE };
    let near = (d - quarters).abs() <= tolerance && (-12 * HOUR..=14 * HOUR).contains(&quarters);
    near.then_some((quarters / MINUTE) as i32)
}

#[derive(Default)]
struct Placed {
    local: Option<i64>,
    instant: Option<i64>,
    offset: Option<i32>,
    zone: Option<String>,
    zone_source: ZoneSource,
    dst_ambiguous: bool,
    /// A measured offset fixed the instant, and the zone at the GPS position, which differs, the wall clock.
    mismatch: bool,
}

/// The wall clock, instant and zone of the winning group, whose best claim comes first: the zone from an offset
/// written with an agreeing wall clock, the GPS time, another UTC claim, the host's GPS zone, the device's zone and
/// the host's default, in that order (doc 13 §4.4), but a zero delta yields to the host's zone, and a GPS zone that
/// disagrees with a measured offset shows the wall clock there (ADR-0051). A date without a time of day stays a date.
fn place(claims: &[Claim], members: &[usize], request: &ResolveCaptureTimeRequest) -> Placed {
    let source = &claims[members[0]];
    let mut placed = Placed {
        local: source.local,
        instant: source.instant.filter(|_| source.local.is_none()),
        ..Default::default()
    };
    if source.precision < P::Minute {
        placed.instant = None;
        return placed;
    }
    let zones = [
        (&request.gps_zone, ZoneSource::GpsZone),
        (&request.device_zone, ZoneSource::DeviceZone),
        (&request.default_zone, ZoneSource::DefaultZone),
    ];
    let mut zones = zones
        .into_iter()
        .filter_map(|(zone, from)| zone.as_ref().filter(|z| !z.offsets.is_empty()).map(|z| (z, from)));
    let found = if let Some(local) = source.local {
        let group = members.iter().map(|&i| &claims[i]);
        let paired = |gps: bool| {
            let utc = members.iter().map(|&i| &claims[i]).filter(|c| c.local.is_none());
            utc.filter(|c| (c.time.source == "exif:GPSDateTime") == gps)
                .find_map(|c| delta(local, c.instant?, c.precision.min(source.precision)))
        };
        let explicit = group.filter(|c| c.local.is_some()).find_map(|c| c.time.offset_minutes);
        let hosted = zones.next().and_then(|(zone, from)| {
            let (offset, ambiguous) = wall_offset(zone, local)?;
            Some((offset, from, Some(zone.name.clone()), ambiguous))
        });
        // A zero delta may be one clock read twice (a phone's local mvhd, a GPS time written from the wall clock):
        // it measures nothing where the host's zone has another offset.
        let counts = |o: i32| (o != 0 || hosted.as_ref().is_none_or(|h| h.0 == 0)).then_some(o);
        let measured = if let Some(o) = explicit {
            Some((o, ZoneSource::ExplicitOffset))
        } else if let Some(o) = paired(true).and_then(counts) {
            Some((o, ZoneSource::GpsDelta))
        } else {
            paired(false).and_then(counts).map(|o| (o, ZoneSource::PairedUtcDelta))
        };
        match measured {
            None => hosted,
            Some((o, from)) => {
                let instant = local.saturating_sub(i64::from(o).saturating_mul(MINUTE));
                let there = request
                    .gps_zone
                    .as_ref()
                    .and_then(|z| Some((offset_at(z, instant)?, z)));
                match there {
                    // A camera left on home time, or a stale fix: the instant stands, the wall clock is the
                    // position's, for review.
                    Some((g, zone)) if g != o => {
                        (placed.local, placed.instant, placed.mismatch) = (None, Some(instant), true);
                        Some((g, ZoneSource::GpsZone, Some(zone.name.clone()), false))
                    }
                    _ => Some((o, from, None, false)),
                }
            }
        }
    } else {
        let instant = placed.instant.unwrap_or_default();
        zones
            .next()
            .and_then(|(zone, from)| Some((offset_at(zone, instant)?, from, Some(zone.name.clone()), false)))
    };
    if let Some((offset, from, zone, ambiguous)) = found {
        let shift = i64::from(offset) * MINUTE;
        match (placed.local, placed.instant) {
            (Some(local), _) => placed.instant = Some(local - shift),
            (None, Some(instant)) => placed.local = Some(instant + shift),
            _ => {}
        }
        (placed.offset, placed.zone_source, placed.zone) = (Some(offset), from, zone);
        placed.dst_ambiguous = ambiguous;
    }
    placed
}

/// The zone's offset at an instant.
fn offset_at(zone: &TimeZone, instant: i64) -> Option<i32> {
    let starts = |o: &&crate::proto::kernel::v1::ZoneOffset| {
        o.starts_at
            .as_ref()
            .map_or(i64::MIN, |t| t.seconds.saturating_mul(SECOND))
    };
    let offsets = &zone.offsets;
    let found = offsets.iter().rev().find(|o| starts(o) <= instant);
    found.or(offsets.first()).map(|o| o.offset_minutes)
}

/// The offset of a wall clock in a zone, and whether a daylight-saving change makes it ambiguous: in an overlap the
/// earlier instant, in a gap the offset before it.
fn wall_offset(zone: &TimeZone, local: i64) -> Option<(i32, bool)> {
    let mut offsets: Vec<i32> = zone.offsets.iter().map(|o| o.offset_minutes).collect();
    offsets.sort_unstable();
    offsets.dedup();
    let at = |o: i32| local - i64::from(o) * MINUTE;
    let valid: Vec<i32> = offsets
        .iter()
        .copied()
        .filter(|&o| offset_at(zone, at(o)) == Some(o))
        .collect();
    match valid.as_slice() {
        [one] => Some((*one, false)),
        [.., last] => Some((*last, true)),
        [] => Some((offset_at(zone, at(*offsets.last()?))?, true)),
    }
}

/// A claim as the response reports it; unrated claims keep confidence 0.
fn report(claim: Claim) -> TimeClaim {
    TimeClaim {
        time: Some(CaptureTime {
            precision: claim.precision.into(),
            confidence: (claim.confidence + 5) / 10,
            ..claim.time
        }),
        event: claim.event.into(),
        verdict: claim.verdict.into(),
    }
}

/// Year, month, day, hour, minute, second and millisecond of "YYYY[-MM[-DD[Thh:mm[:ss[.sss]]]]]", the form claims
/// take, with its precision; missing fields are the first of their range.
fn parse(text: &str) -> Option<([i64; 7], P)> {
    let b = text.as_bytes();
    let number = |at: usize, len: usize| {
        let digits = b.get(at..at + len)?;
        let valid = digits.iter().all(u8::is_ascii_digit);
        valid.then(|| digits.iter().fold(0, |n, d| n * 10 + i64::from(d - b'0')))
    };
    let mut fields = [number(0, 4)?, 1, 1, 0, 0, 0, 0];
    let (mut precision, mut end) = (P::Year, 4);
    let layout = [
        (b'-', P::Month),
        (b'-', P::Day),
        (b'T', P::Unspecified),
        (b':', P::Minute),
        (b':', P::Second),
    ];
    for (field, (separator, next)) in layout.into_iter().enumerate() {
        if b.get(end) != Some(&separator) {
            break;
        }
        fields[field + 1] = number(end + 1, 2)?;
        (precision, end) = (next, end + 3);
    }
    if precision == P::Second && b.get(end) == Some(&b'.') {
        fields[6] = number(end + 1, 3)?;
        (precision, end) = (P::Millisecond, end + 4);
    }
    (end == b.len() && precision != P::Unspecified).then_some((fields, precision))
}

/// Milliseconds since 1970 of a wall clock or instant, with hour 24 as the next midnight and a leap second as the one
/// before it (doc 13 §4.5).
fn moment([y, mo, d, h, mi, s, ms]: [i64; 7]) -> Result<i64, ClaimVerdict> {
    if y == 0 && mo == 0 {
        return Err(ClaimVerdict::Sentinel);
    }
    let leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0);
    let days = match mo {
        2 if leap => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        1..=12 => 31,
        _ => 0,
    };
    let midnight = h == 24 && mi == 0 && s == 0 && ms == 0;
    if !(1..=days).contains(&d) || !(h < 24 || midnight) || mi > 59 || s > 60 {
        return Err(ClaimVerdict::Invalid);
    }
    Ok(days_from_civil(y, mo, d) * DAY + h * HOUR + mi * MINUTE + s.min(59) * SECOND + ms)
}

/// Days since 1970-01-01 in the proleptic Gregorian calendar (Howard Hinnant's algorithm).
fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * ((m + 9) % 12) + 2) / 5 + d - 1;
    era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719_468
}

/// ISO 8601 without a zone, cut to the precision: "2019", "2019-05", ... "2019-05-09T15:47:33.250".
fn format(at: i64, precision: P) -> String {
    let (days, ms) = (at.div_euclid(DAY), at.rem_euclid(DAY));
    let z = days + 719_468;
    let (era, doe) = (z.div_euclid(146_097), z.rem_euclid(146_097));
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let (d, m) = (doy - (153 * mp + 2) / 5 + 1, if mp < 10 { mp + 3 } else { mp - 9 });
    let y = yoe + era * 400 + i64::from(m <= 2);
    let (h, mi, s, f) = (ms / HOUR, ms / MINUTE % 60, ms / SECOND % 60, ms % SECOND);
    let full = format!("{y:04}-{m:02}-{d:02}T{h:02}:{mi:02}:{s:02}.{f:03}");
    let len = match precision {
        P::Year => 4,
        P::Month => 7,
        P::Day => 10,
        P::Minute => 16,
        P::Second => 19,
        _ => 23,
    };
    full.get(..len).unwrap_or(&full).to_string()
}
