//! A motion photo's video: where its markers or its container say it is, once a movie is found there, since markers
//! outlive a video that an editor stripped.

use super::containers::boxes;
use super::file::{File, uint};
use crate::proto::kernel::v1::{ByteSpan, FileFormat, MotionPhotoMarkers};

/// Where the video starts and how long it is, from the first place that holds one: Google's Container directory,
/// the legacy MicroVideoOffset, HEIF's mpvd box, then a Samsung camera's SEF trailer. `size` is the file's length.
pub fn locate(
    file: &File,
    size: u64,
    format: FileFormat,
    markers: Option<&MotionPhotoMarkers>,
    samsung: bool,
) -> Option<ByteSpan> {
    if size == 0 || format == FileFormat::Quicktime {
        return None;
    }
    // The video item is the last in the file (Android's motion photo format 1.0).
    let from_end = |length: u64| {
        let start = size.checked_sub(length).filter(|_| length > 0);
        start.map(|start| (start, length))
    };
    let markers = markers.cloned().unwrap_or_default();
    let item = markers.items.iter().find(|item| item.semantic == "MotionPhoto");
    let candidates = [
        item.filter(|_| markers.motion_photo)
            .and_then(|item| from_end(item.length_bytes)),
        from_end(markers.micro_video_offset_bytes).filter(|_| markers.micro_video),
        (format == FileFormat::Heif)
            .then(|| boxes(file, 0, size).find(|b| &b.0 == b"mpvd"))
            .flatten()
            .map(|(_, start, end)| (start, end - start)),
        samsung.then(|| sef(file, size, b"MotionPhoto_Data")).flatten(),
    ];
    for (offset, length) in candidates.into_iter().flatten() {
        match file.get(offset.checked_add(4)?, 4) {
            Some(b"ftyp") => return Some(ByteSpan { offset, length }),
            Some(_) => {}
            // Unread yet: the host sends it and calls again, so that a later place never wins over this one.
            None => return None,
        }
    }
    None
}

/// The data of the block `name` of Samsung's SEF trailer: a SEFH directory, its length and "SEFT" end the file, and
/// each entry counts back from the directory to a block of a type, a name and the data.
pub(super) fn sef(file: &File, size: u64, name: &[u8]) -> Option<(u64, u64)> {
    let le = |bytes: &[u8]| uint(bytes, false);
    let tail = file.get(size.checked_sub(8)?, 8)?;
    if &tail[4..] != b"SEFT" {
        return None;
    }
    let at = (size - 8).checked_sub(le(&tail[..4]))?;
    let directory = file.get(at, size - 8 - at)?;
    let count = le(directory.get(8..12)?) as usize;
    let entries = directory.get(12..)?.as_chunks::<12>().0.iter().take(count);
    entries.into_iter().find_map(|entry| {
        let (start, length) = (at.checked_sub(le(&entry[4..8]))?, le(&entry[8..12]));
        let name_length = le(file.get(start + 4, 4)?);
        let skip = 8 + name_length;
        (file.get(start + 8, name_length.min(64))? == name).then_some((start + skip, length.checked_sub(skip)?))
    })
}
