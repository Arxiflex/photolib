//! Conformance cases of ReadHeif: the coded images of a grid with its thumbnail, an AV1 still, a codec nobody here
//! decodes, and what is no HEIF file.

use super::{Outcome, call_case};
use crate::builder::{HVCC, Item, be16, built, bx, ispe};
use photolib_kernel::proto::kernel::v1::{
    ByteSpan, FileRange, HeifClap, HeifCodec, HeifImage, HeifPicture, HeifStatus, Method, ReadHeifRequest,
    ReadHeifResponse,
};
use prost::Message;
use serde_json::Value;

#[allow(clippy::too_many_lines)] // one case after another, each with its typed response
pub(crate) fn heif_cases() -> Vec<Value> {
    let read = |name: &str, file: &[u8], response: ReadHeifResponse| {
        let request = ReadHeifRequest {
            ranges: vec![FileRange {
                offset: 0,
                data: file.to_vec(),
            }],
            size: file.len() as u64,
        };
        let outcome: Outcome = Ok(response.encode_to_vec());
        call_case(name, Method::ReadHeif as u32, request.encode_to_vec(), outcome)
    };
    // Where a run of the same byte is in the file.
    let span = |file: &[u8], fill: u8, length: usize| {
        let run = vec![fill; length];
        let offset = file.windows(length).rposition(|w| w == run).unwrap() as u64;
        ByteSpan {
            offset,
            length: length as u64,
        }
    };
    let image = |codec: HeifCodec, codec_string: &str, config: &[u8], width, height, spans| HeifImage {
        codec: codec.into(),
        codec_string: codec_string.into(),
        config: config.to_vec(),
        width,
        height,
        spans: vec![spans],
    };

    let props = vec![
        ispe(256, 192),
        ispe(128, 192),
        bx(b"hvcC", &HVCC),
        ispe(64, 48),
        bx(b"irot", &[1]),
        bx(b"imir", &[1]),
        bx(
            b"clap",
            &[200u32, 1, 100, 1, 0, 1, 0, 1]
                .iter()
                .flat_map(|n| n.to_be_bytes())
                .collect::<Vec<_>>(),
        ),
    ];
    // Version, flags, rows and columns less one, then the output's width and height.
    let grid = [vec![0, 0, 0, 1], be16(256).to_vec(), be16(192).to_vec()].concat();
    let items = [
        Item(1, b"grid", vec![1, 5, 6, 7], grid),
        Item(2, b"hvc1", vec![2, 3], vec![9; 7]),
        Item(3, b"hvc1", vec![2, 3], vec![8; 5]),
        Item(4, b"hvc1", vec![4, 3], vec![7; 3]),
    ];
    let file = built(&items, &props, &[(b"dimg", 1, vec![2, 3]), (b"thmb", 4, vec![1])], 1);
    let hevc = |width, height, fill, length| {
        image(
            HeifCodec::Hevc,
            "hvc1.1.6.L93.B0",
            &HVCC,
            width,
            height,
            span(&file, fill, length),
        )
    };
    let grid_response = ReadHeifResponse {
        status: HeifStatus::Ok.into(),
        picture: Some(HeifPicture {
            width: 256,
            height: 192,
            rows: 1,
            columns: 2,
            tiles: vec![hevc(128, 192, 9, 7), hevc(128, 192, 8, 5)],
            clap: Some(HeifClap {
                width_num: 200,
                width_den: 1,
                height_num: 100,
                height_den: 1,
                x_den: 1,
                y_den: 1,
                ..Default::default()
            }),
            rotation: 1,
            mirror: Some(1),
            ..Default::default()
        }),
        thumbnail: Some(HeifPicture {
            width: 64,
            height: 48,
            image: Some(hevc(64, 48, 7, 3)),
            ..Default::default()
        }),
        ..Default::default()
    };

    let av1 = built(
        &[Item(1, b"av01", vec![1, 2], vec![5; 4])],
        &[ispe(16, 8), bx(b"av1C", &[0x81, 0x04, 0x4C, 0])],
        &[],
        1,
    );
    let av1_response = ReadHeifResponse {
        status: HeifStatus::Ok.into(),
        picture: Some(HeifPicture {
            width: 16,
            height: 8,
            image: Some(image(
                HeifCodec::Av1,
                "av01.0.04M.10",
                &[0x81, 0x04, 0x4C, 0],
                16,
                8,
                span(&av1, 5, 4),
            )),
            ..Default::default()
        }),
        ..Default::default()
    };

    let jpeg = built(&[Item(1, b"jpeg", vec![1], vec![1, 2])], &[ispe(16, 8)], &[], 1);
    let other = ReadHeifResponse {
        status: HeifStatus::UnsupportedCodec.into(),
        item_type: "jpeg".into(),
        ..Default::default()
    };
    let none = ReadHeifResponse {
        // The brands box is asked for: a host with the file sends it.
        missing: vec![ByteSpan { offset: 0, length: 8 }],
        status: HeifStatus::NotHeif.into(),
        ..Default::default()
    };
    vec![
        read(
            "a grid of two HEVC tiles, cropped, turned and mirrored, with its HEVC thumbnail",
            &file,
            grid_response,
        ),
        read("an AV1 still", &av1, av1_response),
        read(
            "a primary item in a codec that is none of HEVC, AV1 and AVC",
            &jpeg,
            other,
        ),
        read("no bytes are no HEIF file", &[], none),
    ]
}
