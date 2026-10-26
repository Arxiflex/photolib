//! A file the reader sees only in the pieces the host supplied.

use std::borrow::Cow;
use std::cell::RefCell;

/// The longest span the reader asks for: metadata is smaller, and a corrupt length must not ask for the whole disk.
pub const MAX_SPAN: u64 = 1 << 22;
/// A corrupt file can point everywhere; the host fetches what is asked and calls again.
const MAX_MISSING: usize = 16;

pub struct File<'a> {
    ranges: Vec<(u64, Cow<'a, [u8]>)>,
    missing: RefCell<Vec<(u64, u64)>>,
}

impl<'a> File<'a> {
    /// The pieces may overlap and come in any order; touching ones are joined, so a read may span them.
    pub fn new(pieces: impl IntoIterator<Item = (u64, &'a [u8])>) -> File<'a> {
        let mut pieces: Vec<_> = pieces.into_iter().filter(|(_, d)| !d.is_empty()).collect();
        pieces.sort_by_key(|&(offset, _)| offset);
        let mut ranges: Vec<(u64, Cow<'a, [u8]>)> = Vec::new();
        for (offset, data) in pieces {
            match ranges.last_mut() {
                Some((start, bytes)) if offset <= end(*start, bytes) => {
                    let overlap = usize::try_from(end(*start, bytes) - offset).unwrap_or(usize::MAX);
                    if let Some(rest) = data.get(overlap..) {
                        bytes.to_mut().extend_from_slice(rest);
                    }
                }
                _ => ranges.push((offset, Cow::Borrowed(data))),
            }
        }
        File {
            ranges,
            missing: RefCell::default(),
        }
    }

    /// The `len` bytes at `offset`, or None, noting them as missing.
    pub fn get(&self, offset: u64, len: u64) -> Option<&[u8]> {
        let got = self.ranges.iter().find_map(|(start, bytes)| {
            let at = usize::try_from(offset.checked_sub(*start)?).ok()?;
            bytes.get(at..at.checked_add(usize::try_from(len).ok()?)?)
        });
        if got.is_none() && len <= MAX_SPAN && offset.checked_add(len).is_some() {
            let mut missing = self.missing.borrow_mut();
            if missing.len() < MAX_MISSING && !missing.contains(&(offset, len)) {
                missing.push((offset, len));
            }
        }
        got
    }

    /// Asks for a box whole, up to the longest span, so that the host sends it in one piece and not box by box.
    pub fn want(&self, offset: u64, len: u64) {
        self.get(offset, len.min(MAX_SPAN));
    }

    /// Up to `len` bytes at `offset`, as many as there are; nothing is missing.
    pub fn prefix(&self, offset: u64, len: usize) -> &[u8] {
        self.ranges
            .iter()
            .find_map(|(start, bytes)| bytes.get(usize::try_from(offset.checked_sub(*start)?).ok()?..))
            .map_or(&[], |rest| &rest[..len.min(rest.len())])
    }

    pub fn missing(self) -> Vec<(u64, u64)> {
        let mut missing = self.missing.into_inner();
        missing.sort_unstable();
        missing
    }
}

fn end(start: u64, bytes: &[u8]) -> u64 {
    start.saturating_add(bytes.len() as u64)
}

/// Big- or little-endian unsigned integers of 1 to 8 bytes.
pub fn uint(bytes: &[u8], big_endian: bool) -> u64 {
    let fold = |n: u64, &b: &u8| n << 8 | u64::from(b);
    if big_endian {
        bytes.iter().fold(0, fold)
    } else {
        bytes.iter().rev().fold(0, fold)
    }
}
