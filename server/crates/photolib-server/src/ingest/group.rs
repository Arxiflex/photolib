//! Which files are one asset (photolib-design docs/08 §3.4): a Live Photo's still and video, a RAW and the camera's
//! JPEG or HEIC. Motion photos are one file, and burst members stay assets of their own.

use photolib_kernel::proto::kernel::v1::{LivePhotoPart, Method, PairLivePhotosRequest, PairLivePhotosResponse};

use super::{
    extract::{Extraction, kernel},
    sniff::{Kind, Media},
};

/// A file of a batch to ingest.
pub struct Part<'a> {
    /// Below the source's root, folders separated by "/".
    pub path: &'a str,
    pub media: Media,
    pub extraction: &'a Extraction,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Role {
    Original,
    LiveMotion,
    OriginalAlt,
}

impl Role {
    pub fn as_str(self) -> &'static str {
        match self {
            Role::Original => "original",
            Role::LiveMotion => "live_motion",
            Role::OriginalAlt => "original_alt",
        }
    }
}

/// The assets the parts make: indexes into `parts` with their roles, the original first, in the order of originals.
pub fn group(parts: &[Part]) -> Result<Vec<Vec<(usize, Role)>>, String> {
    let mut partner = vec![None; parts.len()];
    let files = (parts.iter())
        .map(|p| LivePhotoPart {
            path: p.path.into(),
            video: p.media.kind == Kind::Video,
            content_identifier: p.extraction.metadata.content_identifier.clone(),
            captured_ms: p.extraction.capture.taken_at.as_ref().map(millis),
            duration_ms: p.extraction.metadata.duration_ms,
        })
        .collect();
    let live: PairLivePhotosResponse = kernel(Method::PairLivePhotos, &PairLivePhotosRequest { files })?;
    for pair in live.pairs {
        let (still, video) = (pair.still as usize, pair.video as usize);
        if parts[still].media.kind == Kind::Image {
            partner[still] = Some((video, Role::LiveMotion));
            partner[video] = Some((still, Role::LiveMotion));
        }
    }
    for raw in (0..parts.len()).filter(|&i| raw(&parts[i].media)) {
        let rendering = (0..parts.len())
            .find(|&i| partner[i].is_none() && partner[raw].is_none() && pairs_with_raw(&parts[i], &parts[raw]));
        if let Some(rendering) = rendering {
            partner[rendering] = Some((raw, Role::OriginalAlt));
            partner[raw] = Some((rendering, Role::OriginalAlt));
        }
    }
    // The still of a Live Photo and the rendering of a RAW are the originals; their partners are files of theirs.
    let original = |i: usize| match partner[i] {
        Some((_, Role::LiveMotion)) => parts[i].media.kind == Kind::Image,
        Some(_) => !raw(&parts[i].media),
        None => true,
    };
    Ok((0..parts.len())
        .filter(|&i| original(i))
        .map(|i| [(i, Role::Original)].into_iter().chain(partner[i]).collect())
        .collect())
}

/// A camera RAW: TIFF-based, Fujifilm's RAF or Canon's CR3.
pub fn raw(media: &Media) -> bool {
    matches!(media.container, "tiff" | "raf") || media.mime == "image/x-canon-cr3"
}

/// The camera's own rendering of a RAW: a JPEG or HEIC in the same folder with the same name up to the first dot, from
/// the same camera, taken within a second of it when that is known.
fn pairs_with_raw(rendering: &Part, raw: &Part) -> bool {
    let stem = |path: &str| {
        let (folder, name) = path.rsplit_once('/').unwrap_or(("", path));
        (
            folder.to_owned(),
            name.split('.').next().unwrap_or_default().to_lowercase(),
        )
    };
    let same = |a: &str, b: &str| a.is_empty() || b.is_empty() || a.eq_ignore_ascii_case(b);
    let (a, b) = (&rendering.extraction, &raw.extraction);
    // Wall clocks first: a camera writes the same one to both, but may give only one of them its zone.
    let wall = |e: &Extraction| clock(&e.capture.capture_time.as_ref()?.local_datetime);
    let at = |e: &Extraction| e.capture.taken_at.as_ref().map(millis);
    let apart = (wall(a).zip(wall(b)))
        .or_else(|| at(a).zip(at(b)))
        .map(|(a, b)| a.abs_diff(b));
    ["image/jpeg", "image/heic"].contains(&rendering.media.mime)
        && stem(rendering.path) == stem(raw.path)
        && same(&a.metadata.make, &b.metadata.make)
        && same(&a.metadata.model, &b.metadata.model)
        && apart.is_none_or(|ms| ms <= 1000)
}

/// Milliseconds of a wall clock with a time of day, "YYYY-MM-DDThh:mm:ss[.fff]", on a scale of its own.
fn clock(local: &str) -> Option<i64> {
    let n = |range: std::ops::Range<usize>| local.get(range)?.parse::<i64>().ok();
    let (y, m, d) = (n(0..4)?, n(5..7)?, n(8..10)?);
    let (y, m) = if m <= 2 { (y - 1, m + 9) } else { (y, m - 3) };
    let days = y * 365 + y / 4 - y / 100 + y / 400 + (153 * m + 2) / 5 + d;
    let seconds = n(11..13)? * 3600 + n(14..16)? * 60 + n(17..19)?;
    Some((days * 86_400 + seconds) * 1000 + n(20..23).unwrap_or(0))
}

fn millis(at: &prost_types::Timestamp) -> i64 {
    at.seconds * 1000 + i64::from(at.nanos / 1_000_000)
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use serde_json::Value;

    use super::*;
    use crate::ingest::{
        extract::tests::client_side,
        sniff::{sniff, tests::corpus},
    };

    /// The corpus, one batch per folder, groups as its golden Live Photo and RAW+JPEG records say, and no other files
    /// group.
    /// A RAW pairs with its camera's JPEG by their wall clocks, even when only the JPEG knows its zone.
    #[test]
    fn a_raw_pairs_by_wall_clock_within_a_second() {
        use photolib_kernel::proto::{kernel::v1::ResolveCaptureTimeResponse, model::v1::CaptureTime};
        let taken = |local: &str, utc: Option<i64>| Extraction {
            metadata: Default::default(),
            capture: ResolveCaptureTimeResponse {
                capture_time: Some(CaptureTime {
                    local_datetime: local.into(),
                    ..Default::default()
                }),
                taken_at: utc.map(|seconds| prost_types::Timestamp { seconds, nanos: 0 }),
                ..Default::default()
            },
        };
        let jpeg = taken("2023-10-28T13:00:32", Some(1_698_490_832));
        let paired = |raw: &Extraction| {
            let jpg = Media {
                container: "jpeg",
                mime: "image/jpeg",
                kind: Kind::Image,
            };
            let nef = Media {
                container: "tiff",
                mime: "image/tiff",
                kind: Kind::Image,
            };
            let parts = [
                Part {
                    path: "DCIM/DSC_1.JPG",
                    media: jpg,
                    extraction: &jpeg,
                },
                Part {
                    path: "DCIM/DSC_1.NEF",
                    media: nef,
                    extraction: raw,
                },
            ];
            group(&parts).unwrap().len() == 1
        };
        assert!(paired(&taken("2023-10-28T13:00:33", None)));
        assert!(!paired(&taken("2023-10-28T13:00:34", None)));
    }

    #[test]
    fn the_corpus_groups_as_its_golden_records_say() {
        let mut folders = BTreeMap::<String, Vec<(Value, Vec<u8>)>>::new();
        for (record, data) in corpus() {
            let path = record["path"].as_str().unwrap();
            let folder = path.rsplit_once('/').map_or("", |p| p.0).to_owned();
            folders.entry(folder).or_default().push((record, data));
        }
        let (mut want, mut got) = (vec![], vec![]);
        for files in folders.values() {
            let extractions: Vec<_> = (files.iter())
                .map(|(r, data)| client_side(data, r["path"].as_str().unwrap()))
                .collect();
            let parts: Vec<_> = (files.iter().zip(&extractions))
                .map(|((record, data), extraction)| Part {
                    path: record["path"].as_str().unwrap(),
                    media: sniff(data),
                    extraction,
                })
                .collect();
            let path = |i: usize| files[i].0["path"].as_str().unwrap().to_owned();
            for asset in group(&parts).unwrap().into_iter().filter(|a| a.len() > 1) {
                got.push(asset.into_iter().map(|(i, role)| (path(i), role)).collect::<Vec<_>>());
            }
            let golden = |kind: &str, role: &str, key: &Value| -> Vec<usize> {
                (0..files.len())
                    .filter(|&i| {
                        let group = &files[i].0["group"];
                        group["kind"] == kind && group["role"] == role && (key.is_null() || &group["key"] == key)
                    })
                    .collect()
            };
            for (kind, role, other) in [
                ("live_photo", "live_motion", Role::LiveMotion),
                ("raw_jpeg", "raw_alt", Role::OriginalAlt),
            ] {
                for primary in golden(kind, "primary", &Value::Null) {
                    let key = &files[primary].0["group"]["key"];
                    let mut asset = vec![(path(primary), Role::Original)];
                    asset.extend(golden(kind, role, key).into_iter().map(|i| (path(i), other)));
                    want.push(asset);
                }
            }
        }
        want.sort();
        got.sort();
        assert_eq!(want.len(), 12);
        assert_eq!(got, want);
    }
}
