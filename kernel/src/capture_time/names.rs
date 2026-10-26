//! The file-name registry (design doc 13 §5, research §5.4) and folder dates. The most specific matching rule, the
//! one matching most of the name (on a tie, the lower id), dates a name; generic rules (F52 to F56) only when no
//! vendor rule matches, so a counter or an id is never read as a time.

use super::{Claim, Family, P};
use crate::proto::kernel::v1::{ClaimVerdict, TimeEvent};
use regex_lite::{Captures, Regex};
use std::cmp::Reverse;
use std::sync::LazyLock;

const CAPTURE: TimeEvent = TimeEvent::Capture;
const RECEIVE: TimeEvent = TimeEvent::Receive;
const SAVE: TimeEvent = TimeEvent::Save;
const TRANSFER: TimeEvent = TimeEvent::Transfer;

/// (id, prior in per mille, event, pattern). Groups: Y (or y, two digits), M, D, h (H: one or two digits), m, s, f
/// (milliseconds), p (AM or PM), E (Unix seconds or milliseconds), and a and b for a day and month in either order.
/// A pattern without them marks names that carry no date. F34 and F50 have no pattern (LINE needs samples first;
/// Takeout's shortened names are the host's to restore), nor F45, which needs the scanner's make (`epson_scan`).
const RULES: &[(&str, u32, TimeEvent, &str)] = &[
    ("F01", 900, CAPTURE, r"^(?:IMG|VID)_{Y}{M}{D}_{h}{m}{s}(?:[_.~(-]|$)"),
    (
        "F02",
        900,
        CAPTURE,
        r"^(?:MVIMG|PANO|IMG)_{Y}{M}{D}_{h}{m}{s}(?:{f}(?:_BURST\d{3})?)?",
    ),
    ("F03", 950, CAPTURE, r"^PXL_{Y}{M}{D}_{h}{m}{s}{f}"),
    (
        "F04",
        850,
        CAPTURE,
        r"^\d+[A-Za-z]+_\d+_BURST(?:{Y}{M}{D}{h}{m}{s}{f}?|(?P<E>\d{13}))(?:\D|$)",
    ),
    ("F05", 900, CAPTURE, r"^{Y}{M}{D}_{h}{m}{s}(?:_\d{3})?(?:\(\d+\))?\."),
    ("F06", 900, CAPTURE, r"^IMG_{Y}{M}{D}_{h}{m}{s}_BURST\d{3}(?:_COVER)?"),
    ("F07", 850, CAPTURE, r"^(?:IMG|VID){Y}{M}{D}{h}{m}{s}(?:_\d+)?\."),
    ("F08", 850, CAPTURE, r"^(?:IMG|VID)_{Y}{M}{D}_{h}{m}{s}{f}(?:[_.]|$)"),
    ("F09", 850, CAPTURE, r"^DSC_\d+_BURST{Y}{M}{D}{h}{m}{s}{f}(?:_COVER)?"),
    ("F10", 0, CAPTURE, r"^IMG_[EO]?\d{4}\."),
    ("F11", 850, CAPTURE, r"^WIN_{Y}{M}{D}_{h}_{m}_{s}_Pro"),
    (
        "F12",
        970,
        CAPTURE,
        r"^Screenshot_{Y}{M}{D}-{h}{m}{s}(?:-display-\d+)?\.",
    ),
    (
        "F13",
        970,
        CAPTURE,
        r"^Screenshot_{Y}{M}{D}[-_]{h}{m}{s}(?:_[^.]+?)?(?:-edited)?\.",
    ),
    (
        "F14",
        970,
        CAPTURE,
        r"^Screenshot_{Y}-{M}-{D}-{h}-{m}-{s}(?:-(?P<f>\d{2,3}))?_[A-Za-z0-9_.]+\.",
    ),
    ("F15", 950, CAPTURE, r"^screen-{Y}{M}{D}-{h}{m}{s}\.mp4$"),
    (
        "F16",
        950,
        CAPTURE,
        r"^Screen_Recording_{Y}{M}{D}[-_]{h}{m}{s}(?:_[^.]+)?\.",
    ),
    ("F17", 950, CAPTURE, r"^Screenrecorder-{Y}-{M}-{D}-{h}-{m}-{s}(?:-{f})?"),
    ("F18", 800, CAPTURE, r"^RPReplay_Final(?P<E>\d{10})\."),
    (
        "F19",
        970,
        CAPTURE,
        r"^(?:Screenshot|Screen Shot) {Y}-{M}-{D} at {H}\.{m}\.{s}(?: ?{p})?(?: \(\d+\))?\.",
    ),
    (
        "F20",
        950,
        CAPTURE,
        r"^Screen Recording {Y}-{M}-{D} at {H}\.{m}\.{s}(?: ?{p})?",
    ),
    ("F21", 900, CAPTURE, r"^Screenshot {Y}-{M}-{D} {h}{m}{s}\."),
    (
        "F22",
        970,
        CAPTURE,
        r"^Screen(?:shot|cast) [Ff]rom {Y}-{M}-{D} {h}-{m}-{s}(?:-\d+)?\.",
    ),
    ("F23", 950, CAPTURE, r"^Screenshot_{Y}{M}{D}_{h}{m}{s}\.png$"),
    ("F24", 900, CAPTURE, r"^{Y}-{M}-{D}_{h}-{m}(?:_\d+)?\.png$"),
    ("F25", 500, RECEIVE, r"^(?:IMG|VID|AUD|PTT|STK|DOC)-{Y}{M}{D}-WA\d+"),
    (
        "F26",
        500,
        RECEIVE,
        r"^WhatsApp (?:Image|Video|Audio) {Y}-{M}-{D} at {H}\.{m}\.{s}(?: ?{p})?",
    ),
    (
        "F27",
        600,
        SAVE,
        r"^(?:IMG|VID)_{Y}{M}{D}_{h}{m}{s}_{f}\.(?i:jpg|jpeg|mp4)$",
    ),
    ("F28", 500, SAVE, r"^[a-z]+_{Y}-{M}-{D}_{h}-{m}-{s}(?: \(\d+\))?\."),
    (
        "F29",
        500,
        RECEIVE,
        r"^(?:photo|video|file)_\d+@{D}-{M}-{Y}_{h}-{m}-{s}",
    ),
    ("F30", 500, RECEIVE, r"^signal-{Y}-{M}-{D}-{h}-?{m}-?{s}(?:-{f})?"),
    ("F31", 0, CAPTURE, r"^(?:IMG|VID)-[0-9a-f]{16,}-V\."),
    ("F32", 400, SAVE, r"^mmexport(?P<E>\d{13})\."),
    ("F32", 800, CAPTURE, r"^wx_camera_(?P<E>\d{13})\."),
    (
        "F33",
        400,
        SAVE,
        r"^KakaoTalk_(?:Photo_)?{Y}-?{M}-?{D}[-_]{h}-?{m}-?{s}{f}?",
    ),
    ("F35", 300, SAVE, r"^FB_IMG_(?P<E>\d{13})\."),
    ("F36", 300, TRANSFER, r"/{Y}{M}/\d{8,}\.(?:jpg|mp4|webp)$"),
    ("F37", 0, CAPTURE, r"^Snapchat-\d+\."),
    ("F38", 850, CAPTURE, r"^DJI_{Y}{M}{D}{h}{m}{s}_\d{4}_[A-Z]\."),
    ("F39", 0, CAPTURE, r"^DJI_\d{4}\."),
    (
        "F40",
        850,
        CAPTURE,
        r"^dji_fly_{Y}{M}{D}_{h}{m}{s}_\d{4}_\d{13}_(?:photo|video)\.",
    ),
    (
        "F40",
        850,
        TRANSFER,
        r"^dji_fly_\d{8}_\d{6}_\d{4}_(?P<E>\d{13})_(?:photo|video)\.",
    ),
    ("F41", 0, CAPTURE, r"^(?:GOPR|GP\d{2}|G[HXS]\d{2})\d{4}\."),
    (
        "F42",
        850,
        CAPTURE,
        r"^(?:IMG|VID|LRV)_{Y}{M}{D}_{h}{m}{s}_\d{2}_\d{3}\.(?i:insp|insv|lrv|mp4|jpg|dng)$",
    ),
    (
        "F43",
        0,
        CAPTURE,
        r"^(?:IMG_|_MG_|MVI_|DSC_|_DSC|DSCN|DSC|DSCF|IMGP)\d{4,5}\.",
    ),
    ("F44", 300, CAPTURE, r"^P[1-9ABC]{D}\d{4}\.(?i:jpg|orf|mov)$"),
    ("F46", 0, TimeEvent::Scan, r"^CamScanner {a}-{b}-{Y} {h}\.{m}"),
    ("F47", 850, CAPTURE, r"^{Y}-{M}-{D} {h}\.{m}\.{s}(?:-\d+)?\."),
    ("F48", 700, CAPTURE, r"^{Y}{M}{D}_{h}{m}{s}{f}_iOS\."),
    ("F49", 850, CAPTURE, r"^(?:\S+ )?{y}-{M}-{D} {h}-{m}-{s} \d+\."),
    (
        "F51",
        700,
        CAPTURE,
        r"^(?:Photo|Movie) on {a}-{b}-(?:{Y}|{y}) at {H}\.{m}(?: ?{p})?",
    ),
    (
        "F52",
        600,
        CAPTURE,
        r"(?:^|\D)(?P<Y>(?:19|20)\d{2})[-_.]?(?P<M>0[1-9]|1[0-2])[-_.]?(?P<D>0[1-9]|[12]\d|3[01])[ T_-]?(?P<h>[01]\d|2[0-3])[-_.:]?(?P<m>[0-5]\d)[-_.:]?(?P<s>[0-5]\d)(?:\D|$)",
    ),
    (
        "F53",
        450,
        CAPTURE,
        r"(?:^|\D)(?P<Y>(?:19|20)\d{2})(?P<M>0[1-9]|1[0-2])(?P<D>0[1-9]|[12]\d|3[01])(?P<h>[01]\d|2[0-3])(?P<m>[0-5]\d)(?P<s>[0-5]\d)\d*(?:\D|$)",
    ),
    (
        "F54",
        400,
        CAPTURE,
        r"(?:^|\D)(?P<Y>(?:19|20)\d{2})[-_.](?P<M>0[1-9]|1[0-2])[-_.](?P<D>0[1-9]|[12]\d|3[01])(?:\D|$)",
    ),
    ("F55", 300, CAPTURE, r"(?:^|\D)(?P<E>1\d{9}|1\d{12})(?:\D|$)"),
    (
        "F56",
        400,
        CAPTURE,
        r"(?:^|\D)(?P<a>\d{2})[-_.](?P<b>\d{2})[-_.](?P<Y>(?:19|20)\d{2})(?:\D|$)",
    ),
];

static COMPILED: LazyLock<Vec<Regex>> = LazyLock::new(|| {
    let groups = [
        ("{Y}", r"(?P<Y>\d{4})"),
        ("{y}", r"(?P<y>\d{2})"),
        ("{M}", r"(?P<M>\d{2})"),
        ("{D}", r"(?P<D>\d{2})"),
        ("{h}", r"(?P<h>\d{2})"),
        ("{H}", r"(?P<h>\d{1,2})"),
        ("{m}", r"(?P<m>\d{2})"),
        ("{s}", r"(?P<s>\d{2})"),
        ("{f}", r"(?P<f>\d{3})"),
        ("{p}", r"(?P<p>[AP]M)"),
        ("{a}", r"(?P<a>\d{1,2})"),
        ("{b}", r"(?P<b>\d{1,2})"),
    ];
    let expand = |pattern: &str| groups.iter().fold(pattern.to_string(), |p, (k, v)| p.replace(k, v));
    RULES
        .iter()
        .map(|rule| Regex::new(&expand(rule.3)).expect("a valid rule"))
        .collect()
});

/// The claims a file name and its folders make: the best rule's, then the folders' date.
pub fn read(name: &str, folder: &str) -> Vec<Claim> {
    let path = format!("{folder}/{name}");
    let matches = |generic: bool| -> Vec<(usize, Captures<'_>)> {
        (0..RULES.len())
            .filter(|&i| (RULES[i].0 >= "F52") == generic)
            .filter_map(|i| {
                let text = if RULES[i].0 == "F36" { &path } else { name };
                COMPILED[i].captures(text).map(|c| (i, c))
            })
            .collect()
    };
    let mut found = matches(false);
    if found.is_empty() {
        found = matches(true);
    }
    let length = |c: &Captures| c.get(0).map_or(0, |m| m.len());
    let best = found
        .iter()
        .min_by_key(|(i, c)| (Reverse(length(c)), *i))
        .map(|(i, _)| RULES[*i].0);
    found
        .iter()
        .filter(|(i, _)| Some(RULES[*i].0) == best)
        .filter_map(|(i, captures)| claim(RULES[*i], captures))
        .chain(folder_date(folder))
        .collect()
}

/// Epson FastFoto names its scans `<name>_a.jpg` (the enhanced scan) and `<name>_b.jpg` (the back of the print).
pub fn epson_scan(name: &str, make: &str) -> bool {
    let stem = name.strip_suffix(".jpg").or_else(|| name.strip_suffix(".jpeg"));
    make.to_ascii_uppercase().starts_with("EPSON") && stem.is_some_and(|s| s.ends_with("_a") || s.ends_with("_b"))
}

fn claim((id, prior, event, _): (&str, u32, TimeEvent, &str), c: &Captures) -> Option<Claim> {
    let number = |group: &str| c.name(group).and_then(|m| m.as_str().parse::<i64>().ok());
    let source = format!("filename:{id}");
    let made = |text: String| Claim::new(&source, text, None, event, prior, Family::Name);
    if let Some(epoch) = c.name("E") {
        let seconds = epoch.len() == 10;
        let millis = number("E")? * if seconds { 1000 } else { 1 };
        let precision = if seconds { P::Second } else { P::Millisecond };
        return Some(made(super::format(millis, precision)).utc().epoch());
    }
    let (month, day) = match (number("a"), number("b")) {
        (Some(a), Some(b)) if a > 12 && b <= 12 => (Some(b), Some(a)),
        (Some(a), Some(b)) if b > 12 && a <= 12 || a == b => (Some(a), Some(b)),
        (Some(_), Some(_)) => {
            return Some(made(String::new()).rejected(ClaimVerdict::AmbiguousOrder));
        }
        _ => (number("M"), number("D")),
    };
    let year = number("Y").or_else(|| number("y").map(|y| if y < 70 { 2000 + y } else { 1900 + y }));
    let Some(year) = year else {
        return day.map(|_| made(String::new()).rejected(ClaimVerdict::NoYear));
    };
    let hour = match (number("h"), c.name("p").map(|p| p.as_str())) {
        (Some(h), Some(p)) if (1..=12).contains(&h) => Some(h % 12 + if p == "PM" { 12 } else { 0 }),
        (Some(_), Some(_)) => Some(99),
        (h, _) => h,
    };
    let mut text = format!("{year:04}");
    for (value, joint) in [
        (month, "-"),
        (day, "-"),
        (hour, "T"),
        (number("m"), ":"),
        (number("s"), ":"),
    ] {
        let Some(value) = value else { break };
        text = format!("{text}{joint}{value:02}");
    }
    if let (Some(fraction), 19) = (c.name("f"), text.len()) {
        text = format!("{text}.{:0<3}", fraction.as_str());
    }
    let claim = made(text).since(if matches!(id, "F25" | "F26") { 2009 } else { 1826 });
    Some(if matches!(id, "F03" | "F48") {
        claim.utc()
    } else {
        claim
    })
}

/// The date of the deepest folder that names one: `2019/05/09`, `2019/05`, `2019` or `2015-01-14 Wedding`. A folder
/// date is weak: it bounds the others and dates the file only when nothing else does.
fn folder_date(folder: &str) -> Option<Claim> {
    let digits = |p: &str| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit());
    let year = |p: &str| p.len() == 4 && digits(p) && ["18", "19", "20"].contains(&&p[..2]);
    let day = |p: &str| {
        let d = p.get(..10).filter(|d| d.is_ascii())?;
        let b = d.as_bytes();
        let shaped = year(&d[..4]) && b[4] == b'-' && b[7] == b'-' && digits(&d[5..7]) && digits(&d[8..]);
        let rest = &p[10..];
        (shaped && (rest.is_empty() || rest.starts_with([' ', '_']))).then(|| d.to_string())
    };
    let parts: Vec<&str> = folder.split('/').collect();
    let text = parts.iter().enumerate().rev().find_map(|(i, &part)| {
        day(part).or_else(|| {
            let next = |j: usize| {
                parts
                    .get(j)
                    .filter(|p| p.len() <= 2 && digits(p))
                    .map(|p| format!("-{p:0>2}"))
            };
            let month = next(i + 1);
            let day = month.as_ref().and_then(|_| next(i + 2));
            year(part).then(|| format!("{part}{}{}", month.unwrap_or_default(), day.unwrap_or_default()))
        })
    })?;
    let source = ["path:y", "path:ym", "path:ymd"][(text.len() - 4) / 3];
    Some(Claim::new(source, text, None, CAPTURE, 300, Family::Folder))
}
