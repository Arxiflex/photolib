//! ThumbHash encoding (ADR-0070): the one encoder of the server and the device indexers; clients decode themselves.

use crate::invalid_request;
use crate::proto::kernel::v1::{CallError, EncodeThumbHashRequest, EncodeThumbHashResponse};

pub(crate) fn encode(r: &EncodeThumbHashRequest) -> Result<EncodeThumbHashResponse, CallError> {
    let side = |n: u32| usize::try_from(n).ok().filter(|n| (1..=100).contains(n));
    let (Some(w), Some(h)) = (side(r.width), side(r.height)) else {
        return Err(invalid_request("rgba"));
    };
    if w.checked_mul(h).and_then(|n| n.checked_mul(4)) != Some(r.rgba.len()) {
        return Err(invalid_request("rgba"));
    }
    Ok(EncodeThumbHashResponse {
        hash: thumbhash::rgba_to_thumb_hash(w, h, &r.rgba),
    })
}
