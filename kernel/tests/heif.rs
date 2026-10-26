//! ReadHeif through the kernel's ABI: the coded images of every HEIC and HEIF file of the corpus, against the golden
//! `tests/heif_golden.json` (`UPDATE_GOLDEN=1` writes it), and files damaged in the ways a host must tell apart.
#![allow(clippy::disallowed_methods, clippy::disallowed_types)]

use photolib_kernel::call;
use photolib_kernel::proto::kernel::v1::{
    ByteSpan, CallResponse, FileRange, HeifCodec, HeifImage, HeifPicture, HeifStatus, Method, ReadHeifRequest,
    ReadHeifResponse, call_response,
};
use prost::Message;
use serde_json::{Value, json};
use std::{fs, path::Path};

const CORPUS: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../testdata/corpus/files");
const GOLDEN: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/heif_golden.json");
/// The brands of the HEIC, HEIF and AVIF files: 18 HEIC and 5 AVIF in the corpus, not the 19 the work item counts.
const BRANDS: [&[u8]; 5] = [b"heic", b"heix", b"mif1", b"msf1", b"avif"];

fn read_heif(ranges: Vec<FileRange>, size: usize) -> ReadHeifResponse {
    let request = ReadHeifRequest {
        ranges,
        size: size as u64,
    };
    let answer = call(Method::ReadHeif as u32, &request.encode_to_vec());
    match CallResponse::decode(answer.as_slice()).unwrap().result {
        Some(call_response::Result::Response(bytes)) => ReadHeifResponse::decode(bytes.as_slice()).unwrap(),
        other => panic!("expected a response, got {other:?}"),
    }
}

fn of(data: &[u8]) -> ReadHeifResponse {
    read_heif(
        vec![FileRange {
            offset: 0,
            data: data.to_vec(),
        }],
        data.len(),
    )
}

/// Every HEIC and HEIF file of the corpus, by path.
fn files() -> Vec<(String, Vec<u8>)> {
    let mut found = Vec::new();
    let mut dirs = vec![Path::new(CORPUS).to_path_buf()];
    while let Some(dir) = dirs.pop() {
        for entry in fs::read_dir(dir).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                dirs.push(path);
            } else if let Ok(data) = fs::read(&path)
                && data.get(4..8) == Some(b"ftyp")
                && data.get(8..12).is_some_and(|b| BRANDS.contains(&b))
            {
                found.push((path.strip_prefix(CORPUS).unwrap().to_string_lossy().into_owned(), data));
            }
        }
    }
    found.sort();
    found
}

fn spans(spans: &[ByteSpan]) -> Value {
    json!(
        spans
            .iter()
            .map(|s| format!("{}+{}", s.offset, s.length))
            .collect::<Vec<_>>()
    )
}

fn image(image: &HeifImage) -> Value {
    json!({
        "codec": image.codec().as_str_name(),
        "codec_string": image.codec_string,
        "config": image.config.iter().map(|b| format!("{b:02x}")).collect::<Vec<_>>().concat(),
        "size": [image.width, image.height],
        "spans": spans(&image.spans),
    })
}

fn picture(p: &HeifPicture) -> Value {
    json!({
        "size": [p.width, p.height],
        "image": p.image.as_ref().map(image),
        "grid": [p.rows, p.columns],
        "tiles": p.tiles.iter().map(image).collect::<Vec<_>>(),
        "clap": p.clap.as_ref().map(|c| json!([
            [c.width_num, c.width_den], [c.height_num, c.height_den], [c.x_num, c.x_den], [c.y_num, c.y_den],
        ])),
        "rotation": p.rotation,
        "mirror": p.mirror,
    })
}

fn summary(got: &ReadHeifResponse) -> Value {
    json!({
        "status": got.status().as_str_name(),
        "picture": got.picture.as_ref().map(picture),
        "thumbnail": got.thumbnail.as_ref().map(picture),
    })
}

#[test]
fn the_tiles_of_the_corpus_match_the_golden_file() {
    let files = files();
    assert_eq!(files.len(), 23, "{:?}", files.iter().map(|f| &f.0).collect::<Vec<_>>());
    let got: serde_json::Map<String, Value> = files
        .iter()
        .map(|(path, data)| (path.clone(), summary(&of(data))))
        .collect();
    if std::env::var_os("UPDATE_GOLDEN").is_some() {
        fs::write(GOLDEN, serde_json::to_string_pretty(&got).unwrap() + "\n").unwrap();
    }
    let want: Value = serde_json::from_str(&fs::read_to_string(GOLDEN).expect("tests/heif_golden.json")).unwrap();
    for (path, data) in &files {
        assert_eq!(want[path], got[path], "{path}");
        let response = of(data);
        let pictures = response.picture.iter().chain(response.thumbnail.iter());
        for image in pictures.flat_map(|p| p.image.iter().chain(&p.tiles)) {
            assert!(!image.spans.is_empty() && !image.config.is_empty(), "{path}");
            for s in &image.spans {
                assert!(
                    s.offset + s.length <= data.len() as u64,
                    "{path}: {s:?} is outside the file"
                );
            }
        }
    }
}

#[test]
fn the_tiles_of_a_grid_are_the_grids_rows_by_columns() {
    let files = files();
    let (_, data) = files.iter().find(|f| f.0 == "stills/grid.heic").unwrap();
    let picture = of(data).picture.unwrap();
    assert!(picture.image.is_none());
    assert_eq!(picture.tiles.len() as u32, picture.rows * picture.columns);
    assert!(picture.rows * picture.columns > 1);
    assert_eq!(picture.tiles[0].codec(), HeifCodec::Hevc);
}

#[test]
fn transforms_are_those_of_the_file() {
    let files = files();
    let by = |name: &str| of(&files.iter().find(|f| f.0 == name).unwrap().1).picture.unwrap();
    assert_eq!(by("stills/irot.heic").rotation, 3);
    assert_eq!(by("stills/imir.heic").mirror, Some(0));
    assert!(by("stills/clap.heic").clap.is_some());
    let plain = by("stills/iphone.heic");
    assert_eq!((plain.rotation, plain.mirror, plain.clap), (0, None, None));
}

fn replaced(data: &[u8], from: [u8; 4], to: [u8; 4]) -> Vec<u8> {
    let at = data
        .windows(4)
        .position(|w| w == from.as_slice())
        .expect("the file has the box");
    let mut data = data.to_vec();
    data[at..at + 4].copy_from_slice(&to);
    data
}

#[test]
fn a_primary_item_in_another_codec_or_without_a_configuration_says_so() {
    let files = files();
    let plain = &files.iter().find(|f| f.0 == "stills/iphone.heic").unwrap().1;
    let jpeg = of(&replaced(plain, *b"hvc1", *b"jpeg"));
    assert_eq!(
        (jpeg.status(), jpeg.item_type.as_str()),
        (HeifStatus::UnsupportedCodec, "jpeg")
    );
    assert!(jpeg.picture.is_none());
    let bare = of(&replaced(plain, *b"hvcC", *b"xxxx"));
    assert_eq!(bare.status(), HeifStatus::NoConfig);
}

#[test]
fn what_is_no_heif_or_not_all_there_is_not_heif_and_missing() {
    assert_eq!(of(b"not a picture at all").status(), HeifStatus::NotHeif);
    assert_eq!(of(&[]).status(), HeifStatus::NotHeif);
    let files = files();
    let plain = &files.iter().find(|f| f.0 == "stills/iphone.heic").unwrap().1;
    let cut = read_heif(
        vec![FileRange {
            offset: 0,
            data: plain[..40].to_vec(),
        }],
        plain.len(),
    );
    assert_eq!(cut.status(), HeifStatus::NotHeif);
    assert_ne!(cut.missing, []);
}

#[test]
fn an_image_beyond_the_end_of_a_truncated_file_is_not_offered() {
    let files = files();
    let plain = &files.iter().find(|f| f.0 == "stills/iphone.heic").unwrap().1;
    // The primary item is the 96 bytes at 322.
    assert_eq!(of(&plain[..417]).status(), HeifStatus::NotHeif);
    assert_eq!(of(&plain[..418]).status(), HeifStatus::Ok);
    assert_eq!(of(plain).status(), HeifStatus::Ok);
}

#[test]
fn the_avc_twins_are_grids_of_avc_tiles_with_a_thumbnail() {
    let twin = |name: &str| {
        let data = fs::read(Path::new(CORPUS).join("../twins/heif-avc").join(name)).unwrap();
        of(&data)
    };
    let grid = twin("all.heic");
    let picture = grid.picture.unwrap();
    assert_eq!((picture.rows, picture.columns, picture.tiles.len()), (2, 2, 4));
    assert_eq!((picture.width, picture.height), (256, 192));
    assert_eq!((picture.rotation, picture.mirror), (1, Some(1)));
    let clap = picture.clap.unwrap();
    assert_eq!(
        (clap.width_num, clap.height_num, clap.x_num, clap.y_num),
        (224, 160, -8, 8)
    );
    assert_eq!(picture.tiles[0].codec(), HeifCodec::Avc);
    assert_eq!(picture.tiles[0].codec_string, "avc1.42C01E");
    let thumbnail = grid.thumbnail.unwrap();
    assert_eq!((thumbnail.width, thumbnail.height, thumbnail.clap), (96, 64, None));
    let single = twin("single.heic").picture.unwrap();
    assert_eq!(single.image.unwrap().width, 256);
}
