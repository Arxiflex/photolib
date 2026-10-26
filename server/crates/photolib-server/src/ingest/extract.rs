//! The kernel's metadata reader and capture-time resolver over a file read in ranges: the calls every client makes,
//! so that the server's metadata is the clients' (ADR-0066).

use std::{fs::File, os::unix::fs::FileExt};

use photolib_kernel::proto::kernel::v1::{
    CallResponse, FileFormat, FileRange, Method, ReadMetadataRequest, ReadMetadataResponse, ResolveCaptureTimeRequest,
    ResolveCaptureTimeResponse, call_response,
};
use prost::Message;
use prost_types::Timestamp;

/// What the kernel says about a file.
#[derive(Default)]
pub struct Extraction {
    pub metadata: ReadMetadataResponse,
    pub capture: ResolveCaptureTimeResponse,
}

/// The first range read; most files hold all their metadata in it.
const FIRST: u64 = 64 << 10;
/// What the reader may ask for in all, and in how many rounds: a hostile file costs at most this much.
const MAX_READ: u64 = 64 << 20;
const MAX_ROUNDS: usize = 32;
/// The largest sidecar read: darktable's, with its history, run to hundreds of KiB.
const SIDECAR: u64 = 4 << 20;

/// Reads `file` of `size` bytes, named by its `path` below the source's root, as resolved at `now` (Unix seconds).
pub fn extract(file: &File, size: u64, path: &str, now: i64) -> Result<Extraction, String> {
    let mut ranges = vec![range(file, 0, FIRST.min(size))?];
    let mut read = ranges[0].data.len() as u64;
    let metadata = loop {
        let request = ReadMetadataRequest {
            ranges: ranges.clone(),
            size,
        };
        let metadata: ReadMetadataResponse = kernel(Method::ReadMetadata, &request)?;
        let spans: Vec<_> = (metadata.missing.iter())
            .filter(|s| s.offset < size)
            .map(|s| (s.offset, s.length.min(size - s.offset)))
            .filter(|&(at, len)| !ranges.iter().any(|r| r.offset == at && r.data.len() as u64 == len))
            .collect();
        let wanted = spans.iter().map(|s| s.1).sum::<u64>();
        if spans.is_empty() || ranges.len() > MAX_ROUNDS || read + wanted > MAX_READ {
            break metadata;
        }
        for (at, len) in spans {
            ranges.push(range(file, at, len)?);
        }
        read += wanted;
    };
    Ok(Extraction {
        capture: kernel(Method::ResolveCaptureTime, &resolve(ranges, size, path, now))?,
        metadata,
    })
}

/// The capture time that `path`'s name and folder alone give, reading no byte of the file: how a file that is no photo
/// or video is dated (ADR-0066).
pub fn named(path: &str, now: i64) -> Result<Extraction, String> {
    Ok(Extraction {
        capture: kernel(Method::ResolveCaptureTime, &resolve(vec![], 0, path, now))?,
        ..Extraction::default()
    })
}

fn resolve(ranges: Vec<FileRange>, size: u64, path: &str, now: i64) -> ResolveCaptureTimeRequest {
    let (folder, file_name) = path.rsplit_once('/').unwrap_or(("", path));
    ResolveCaptureTimeRequest {
        ranges,
        size,
        file_name: file_name.into(),
        folder: folder.into(),
        resolved_at: Some(Timestamp { seconds: now, nanos: 0 }),
        ..Default::default()
    }
}

/// What `file`, an XMP sidecar of `size` bytes, says; none when it is no XMP packet or larger than [`SIDECAR`].
pub fn sidecar(file: &File, size: u64) -> Result<Option<ReadMetadataResponse>, String> {
    if size > SIDECAR {
        return Ok(None);
    }
    let request = ReadMetadataRequest {
        ranges: vec![range(file, 0, size)?],
        size,
    };
    let metadata: ReadMetadataResponse = kernel(Method::ReadMetadata, &request)?;
    Ok((metadata.format() == FileFormat::Xmp).then_some(metadata))
}

fn range(file: &File, offset: u64, length: u64) -> Result<FileRange, String> {
    let mut data = vec![0; length as usize];
    file.read_exact_at(&mut data, offset)
        .map_err(|e| format!("cannot read {length} bytes at {offset}: {e}"))?;
    Ok(FileRange { offset, data })
}

/// Calls a kernel function; a panic on hostile input fails this file only.
pub fn kernel<R: Message + Default>(method: Method, request: &impl Message) -> Result<R, String> {
    let request = request.encode_to_vec();
    let answer = std::panic::catch_unwind(|| photolib_kernel::call(method as u32, &request))
        .map_err(|_| format!("the kernel panicked in {method:?}"))?;
    let answer = CallResponse::decode(answer.as_slice()).map_err(|e| e.to_string())?;
    match answer.result {
        Some(call_response::Result::Response(bytes)) => R::decode(bytes.as_slice()).map_err(|e| e.to_string()),
        other => Err(format!("{method:?} failed: {other:?}")),
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::ingest::sniff::tests::corpus;

    const NOW: i64 = 1_792_108_800;

    /// XMP fixtures, in a file of their own: their namespaces are identifiers, not endpoints (`check_outbound.py`).
    pub(crate) mod xmp;

    /// What a client computes from the whole file in memory.
    pub fn client_side(data: &[u8], path: &str) -> Extraction {
        let (folder, file_name) = path.rsplit_once('/').unwrap_or(("", path));
        let whole = vec![FileRange {
            offset: 0,
            data: data.to_vec(),
        }];
        let size = data.len() as u64;
        let request = ReadMetadataRequest { ranges: whole, size };
        let resolve = ResolveCaptureTimeRequest {
            head: data.to_vec(),
            file_name: file_name.into(),
            folder: folder.into(),
            resolved_at: Some(Timestamp { seconds: NOW, nanos: 0 }),
            ..Default::default()
        };
        Extraction {
            metadata: kernel(Method::ReadMetadata, &request).unwrap(),
            capture: kernel(Method::ResolveCaptureTime, &resolve).unwrap(),
        }
    }

    /// The server reads every corpus file in ranges and gets exactly what a client gets from the whole file.
    #[test]
    fn ranged_extraction_is_the_clients_on_the_corpus() {
        let dir = tempfile::tempdir().unwrap();
        for (record, data) in corpus() {
            let path = record["path"].as_str().unwrap();
            let copy = dir.path().join("file");
            std::fs::write(&copy, &data).unwrap();
            let file = File::open(&copy).unwrap();
            let got = extract(&file, data.len() as u64, path, NOW).unwrap();
            let want = client_side(&data, path);
            assert_eq!(got.metadata, want.metadata, "{path}");
            assert_eq!(got.capture, want.capture, "{path}");
        }
    }
}
