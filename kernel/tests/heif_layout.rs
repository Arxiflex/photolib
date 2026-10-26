//! ReadHeif on files built here box by box: a grid with its thumbnail and transforms, the codec strings of HEVC, AV1
//! and AVC configurations, and the damage a host must tell from a good file.
#![allow(clippy::disallowed_methods, clippy::disallowed_types)]

use photolib_kernel::call;
use photolib_kernel::proto::kernel::v1::{
    CallResponse, FileRange, HeifCodec, HeifStatus, Method, ReadHeifRequest, ReadHeifResponse, call_response,
};
use prost::Message;

#[path = "support/heif_builder.rs"]
mod builder;
use builder::{HVCC, Item, be16, built, bx, ispe};

fn of(data: &[u8]) -> ReadHeifResponse {
    let request = ReadHeifRequest {
        ranges: vec![FileRange {
            offset: 0,
            data: data.to_vec(),
        }],
        size: data.len() as u64,
    };
    let answer = call(Method::ReadHeif as u32, &request.encode_to_vec());
    match CallResponse::decode(answer.as_slice()).unwrap().result {
        Some(call_response::Result::Response(bytes)) => ReadHeifResponse::decode(bytes.as_slice()).unwrap(),
        other => panic!("expected a response, got {other:?}"),
    }
}

#[test]
fn a_grid_with_its_thumbnail_and_transforms_is_laid_out_as_the_file_says() {
    // 1: a grid of 2 and 3 (128 x 192 each), turned once and mirrored; 4: its 64 x 48 thumbnail.
    let props = vec![
        ispe(256, 192),
        ispe(128, 192),
        bx(b"hvcC", &HVCC),
        ispe(64, 48),
        bx(b"irot", &[1]),
        bx(b"imir", &[1]),
    ];
    // Version, flags, rows less one, columns less one, then the output's width and height in 16 bits.
    let descriptor = [vec![0, 0, 0, 1], be16(256).to_vec(), be16(192).to_vec()].concat();
    let items = [
        Item(1, b"grid", vec![1, 5, 6], descriptor),
        Item(2, b"hvc1", vec![2, 3], vec![9; 7]),
        Item(3, b"hvc1", vec![2, 3], vec![8; 5]),
        Item(4, b"hvc1", vec![4, 3], vec![7; 3]),
    ];
    let file = built(&items, &props, &[(b"dimg", 1, vec![2, 3]), (b"thmb", 4, vec![1])], 1);
    let got = of(&file);
    assert_eq!(got.status(), HeifStatus::Ok);
    let picture = got.picture.unwrap();
    assert_eq!(
        (picture.width, picture.height, picture.rows, picture.columns),
        (256, 192, 1, 2)
    );
    assert_eq!((picture.rotation, picture.mirror), (1, Some(1)));
    let tiles: Vec<_> = picture
        .tiles
        .iter()
        .map(|t| (t.width, t.height, t.spans.len(), t.spans[0].length))
        .collect();
    assert_eq!(tiles, [(128, 192, 1, 7), (128, 192, 1, 5)]);
    assert_eq!(picture.tiles[0].codec_string, "hvc1.1.6.L93.B0");
    assert_eq!(picture.tiles[0].config, HVCC);
    // The tiles' bytes are where the spans say.
    let span = &picture.tiles[1].spans[0];
    assert_eq!(&file[span.offset as usize..][..span.length as usize], [8; 5]);
    let image = got.thumbnail.unwrap().image.unwrap();
    assert_eq!((image.width, image.height, image.spans[0].length), (64, 48, 3));
    // A grid with fewer tiles than it says is damaged.
    let short = built(&items, &props, &[(b"dimg", 1, vec![2])], 1);
    assert_eq!(of(&short).status(), HeifStatus::NotHeif);
}

#[test]
fn codec_strings_follow_the_configuration_of_hevc_av1_and_avc() {
    let one = |kind: &'static [u8; 4], config_kind: &[u8], config: &[u8]| {
        let props = vec![ispe(8, 8), bx(config_kind, config)];
        let file = built(&[Item(1, kind, vec![1, 2], vec![1, 2, 3])], &props, &[], 1);
        let image = of(&file).picture.unwrap().image.unwrap();
        (image.codec(), image.codec_string)
    };
    assert_eq!(
        one(b"hvc1", b"hvcC", &HVCC),
        (HeifCodec::Hevc, "hvc1.1.6.L93.B0".into())
    );
    // Profile space 1, high tier, profile 2, compatibility flags 0x30000000 (bits 2 and 3 from the top: reversed 0x0C), level 123.
    let rext = [1, 0x40 | 0x20 | 2, 0x30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 123];
    assert_eq!(one(b"hev1", b"hvcC", &rext), (HeifCodec::Hevc, "hev1.A2.C.H123".into()));
    assert_eq!(
        one(b"av01", b"av1C", &[0x81, 0x04, 0x4C, 0]),
        (HeifCodec::Av1, "av01.0.04M.10".into())
    );
    assert_eq!(
        one(b"av01", b"av1C", &[0x81, 0x28, 0xEC, 0]),
        (HeifCodec::Av1, "av01.1.08H.12".into())
    );
    assert_eq!(
        one(b"avc1", b"avcC", &[1, 0x64, 0, 0x28, 0xFF]),
        (HeifCodec::Avc, "avc1.640028".into())
    );
}

#[test]
fn a_configuration_too_short_for_its_codec_has_none() {
    let props = vec![ispe(8, 8), bx(b"hvcC", &HVCC[..5])];
    let file = built(&[Item(1, b"hvc1", vec![1, 2], vec![1])], &props, &[], 1);
    assert_eq!(of(&file).status(), HeifStatus::NoConfig);
}
