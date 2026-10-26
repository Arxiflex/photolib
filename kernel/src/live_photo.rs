//! Live Photo pairing (design doc 08 §3.4): which still and which video are one Live Photo.

use crate::proto::kernel::v1::{LivePhotoPair, LivePhotoPart, PairLivePhotosRequest, PairLivePhotosResponse};
use std::collections::BTreeMap;

/// The longest clip, and the farthest apart capture times, that pair without equal content identifiers.
const CLIP_MS: u64 = 4000;
const APART_MS: u64 = 2000;

pub fn pair(request: &PairLivePhotosRequest) -> PairLivePhotosResponse {
    let files = &request.files;
    let (mut by_id, mut by_name) = (BTreeMap::<&str, Vec<_>>::new(), BTreeMap::<_, Vec<_>>::new());
    for (i, file) in files.iter().enumerate().filter(|(_, f)| f.video) {
        by_id.entry(file.content_identifier.as_str()).or_default().push(i);
        by_name.entry(name(&file.path)).or_default().push(i);
    }
    // Rank, milliseconds apart, still and video: equal identifiers first, then the closest in time.
    let mut candidates = vec![];
    for (still, file) in files.iter().enumerate().filter(|(_, f)| !f.video) {
        let id = file.content_identifier.as_str();
        if !id.is_empty() {
            let videos = by_id.get(id).into_iter().flatten();
            candidates.extend(videos.map(|&video| (0, 0, still, video)));
        }
        for &video in by_name.get(&name(&file.path)).into_iter().flatten() {
            let clip: &LivePhotoPart = &files[video];
            let apart = file.captured_ms.zip(clip.captured_ms).map(|(a, b)| a.abs_diff(b));
            let identified = !id.is_empty() && !clip.content_identifier.is_empty();
            if let Some(ms) = apart.filter(|&ms| ms <= APART_MS)
                && !identified
                && (1..=CLIP_MS).contains(&clip.duration_ms)
            {
                candidates.push((1, ms, still, video));
            }
        }
    }
    candidates.sort_unstable();
    let mut taken = vec![false; files.len()];
    let mut pairs = vec![];
    for (_, _, still, video) in candidates {
        if !taken[still] && !taken[video] {
            (taken[still], taken[video]) = (true, true);
            pairs.push(LivePhotoPair {
                still: still as u32,
                video: video as u32,
            });
        }
    }
    pairs.sort_unstable_by_key(|pair| pair.still);
    PairLivePhotosResponse { pairs }
}

/// The folder and the file name up to its first dot, in lower case: "DCIM/IMG_1.MP.mp4" is "dcim/img_1".
fn name(path: &str) -> String {
    let (folder, file) = path.rsplit_once('/').unwrap_or(("", path));
    let stem = file.split('.').next().unwrap_or_default();
    format!("{folder}/{stem}").to_lowercase()
}
