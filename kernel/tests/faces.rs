//! Faces (design 09 §7, ADR-0389): what the kernel prepares for YuNet and SFace and reads from them, with outputs made
//! here cell by cell, so that every number is the arithmetic of YuNet's decoding and nothing else.

#![allow(
    clippy::cast_precision_loss,
    reason = "pixel positions of pictures a few hundred pixels across"
)]

use photolib_kernel::call;
use photolib_kernel::proto::kernel::v1::{
    AlignFaceRequest, AlignFaceResponse, CallError, CallErrorCode::InvalidRequest, CallResponse, DecodeFacesRequest,
    DecodeFacesResponse, Face, Method, NormalizeFaceEmbeddingRequest, NormalizeFaceEmbeddingResponse,
    PrepareFaceDetectionRequest, PrepareFaceDetectionResponse, call_response,
};
use prost::Message;

fn ask<Q: Message, R: Message + Default>(method: Method, request: &Q) -> Result<R, CallError> {
    let answer = CallResponse::decode(call(method as u32, &request.encode_to_vec()).as_slice()).unwrap();
    match answer.result.unwrap() {
        call_response::Result::Response(r) => Ok(R::decode(r.as_slice()).unwrap()),
        call_response::Result::Error(e) => Err(e),
    }
}

fn floats(values: &[f32]) -> Vec<u8> {
    values.iter().flat_map(|v| v.to_le_bytes()).collect()
}

/// YuNet's twelve outputs for a tensor of `width` × `height`, all zero but for what `set` puts in `(stride, cell)`.
struct Outputs {
    width: u32,
    height: u32,
    tensors: Vec<Vec<f32>>,
}

const STRIDES: [u32; 3] = [8, 16, 32];

impl Outputs {
    fn new(width: u32, height: u32) -> Self {
        let cells = |s: u32| ((width / s) * (height / s)) as usize;
        let tensors = [1, 1, 4, 10]
            .into_iter()
            .flat_map(|per| STRIDES.map(|s| vec![0.0; cells(s) * per]))
            .collect();
        Self { width, height, tensors }
    }

    /// A face in the cell at `(column, row)` of `stride`: class and objectness scores, the box's offsets and the
    /// landmarks' offsets from the cell.
    fn face(mut self, stride: u32, column: u32, row: u32, scores: (f32, f32), bbox: [f32; 4], kps: [f32; 10]) -> Self {
        let s = STRIDES.iter().position(|&s| s == stride).unwrap();
        let cell = (row * (self.width / stride) + column) as usize;
        self.tensors[s][cell] = scores.0;
        self.tensors[3 + s][cell] = scores.1;
        self.tensors[6 + s][cell * 4..cell * 4 + 4].copy_from_slice(&bbox);
        self.tensors[9 + s][cell * 10..cell * 10 + 10].copy_from_slice(&kps);
        self
    }

    fn request(&self) -> DecodeFacesRequest {
        DecodeFacesRequest {
            width: self.width,
            height: self.height,
            outputs: self.tensors.iter().map(|t| floats(t)).collect(),
            ..Default::default()
        }
    }
}

fn decode(request: &DecodeFacesRequest) -> Result<Vec<Face>, CallError> {
    ask::<_, DecodeFacesResponse>(Method::DecodeFaces, request).map(|r| r.faces)
}

fn close(a: f32, b: f32) -> bool {
    (a - b).abs() <= 1e-5 * a.abs().max(b.abs()).max(1.0)
}

const NO_KPS: [f32; 10] = [0.0; 10];
/// A box one cell of stride 16 wide and high, centred in the cell.
const SQUARE: [f32; 4] = [0.5, 0.5, 0.0, 0.0];

fn field(error: &CallError) -> Option<&str> {
    assert_eq!(error.code(), InvalidRequest);
    error.params.get("field").map(String::as_str)
}

fn scores(request: &DecodeFacesRequest) -> Vec<f32> {
    decode(request).unwrap().iter().map(|f| f.score).collect()
}

#[test]
fn a_box_that_overlaps_a_better_one_is_dropped_and_a_far_one_kept() {
    // Twice a cell each way, so that a box and the next cell's share half of their width.
    let double = [0.5, 0.5, 2f32.ln(), 2f32.ln()];
    let outputs = Outputs::new(128, 64)
        .face(16, 2, 1, (0.95, 0.95), double, NO_KPS)
        // One cell to the right: half of each box is shared, a third of the union, above the default 0.3.
        .face(16, 3, 1, (0.9, 0.9), double, NO_KPS)
        .face(16, 6, 1, (0.8, 0.8), double, NO_KPS);
    let kept = scores(&outputs.request());
    assert_eq!(kept.len(), 2, "{kept:?}");
    assert!(close(kept[0], 0.95) && close(kept[1], 0.8), "{kept:?}");
    // With a looser limit the neighbour stays.
    let loose = DecodeFacesRequest {
        max_overlap: 0.5,
        ..outputs.request()
    };
    assert_eq!(scores(&loose).len(), 3);
}

#[test]
fn faces_below_the_score_are_left_out_and_the_best_come_first_up_to_the_most() {
    let outputs = Outputs::new(128, 64)
        .face(16, 0, 0, (0.69, 0.69), SQUARE, NO_KPS)
        .face(16, 2, 0, (0.8, 0.8), SQUARE, NO_KPS)
        .face(16, 4, 0, (0.9, 0.9), SQUARE, NO_KPS)
        .face(16, 6, 0, (0.85, 0.85), SQUARE, NO_KPS);
    let near =
        |got: Vec<f32>, want: &[f32]| got.len() == want.len() && got.iter().zip(want).all(|(a, b)| close(*a, *b));
    assert!(near(scores(&outputs.request()), &[0.9, 0.85, 0.8]));
    let strict = DecodeFacesRequest {
        min_score: 0.88,
        ..outputs.request()
    };
    assert!(near(scores(&strict), &[0.9]));
    let most = DecodeFacesRequest {
        max_faces: 2,
        ..outputs.request()
    };
    assert!(near(scores(&most), &[0.9, 0.85]));
}

#[test]
fn a_box_over_the_edge_is_clipped_to_the_image_and_a_flat_one_is_dropped() {
    // The cell (0, 0) of stride 8 holds a box of 8 × exp(2.08) = 64 pixels each way, centred on (4, 4): most of it is
    // beyond the corner.
    let big = [0.5, 0.5, 8f32.ln(), 8f32.ln()];
    let outputs = Outputs::new(128, 64).face(8, 0, 0, (0.9, 0.9), big, NO_KPS);
    let face = &decode(&outputs.request()).unwrap()[0];
    // From (0, 0) to (4 + 32, 4 + 32) = (36, 36).
    assert!(face.x == 0.0 && face.y == 0.0, "{face:?}");
    assert!(
        close(face.width, 36.0 / 128.0) && close(face.height, 36.0 / 64.0),
        "{face:?}"
    );
    // A box the width of nothing (exp underflows to zero) is dropped.
    let flat = Outputs::new(128, 64).face(8, 0, 0, (0.9, 0.9), [0.5, 0.5, -200.0, -200.0], NO_KPS);
    assert_eq!(scores(&flat.request()), Vec::<f32>::new());
}

#[test]
fn outputs_that_are_not_finite_are_left_out() {
    let outputs = Outputs::new(64, 64)
        .face(8, 1, 1, (0.9, 0.9), [f32::NAN, 0.5, 0.0, 0.0], NO_KPS)
        .face(8, 4, 4, (0.9, 0.9), [0.5, 0.5, 1000.0, 0.0], NO_KPS)
        .face(8, 6, 6, (f32::NAN, 0.9), SQUARE, NO_KPS)
        .face(8, 2, 5, (0.9, 0.9), SQUARE, [f32::INFINITY; 10]);
    assert_eq!(scores(&outputs.request()), Vec::<f32>::new());
}

#[test]
fn a_request_that_does_not_fit_the_model_names_its_field() {
    let good = Outputs::new(64, 32).request();
    let named = |change: fn(&mut DecodeFacesRequest)| {
        let mut request = good.clone();
        change(&mut request);
        field(&decode(&request).unwrap_err()).unwrap().to_string()
    };
    assert_eq!(named(|r| r.width = 60), "width");
    assert_eq!(named(|r| r.height = 0), "height");
    assert_eq!(named(|r| r.width = 4096), "width");
    assert_eq!(named(|r| r.min_score = 1.5), "min_score");
    assert_eq!(named(|r| r.min_score = f32::NAN), "min_score");
    assert_eq!(named(|r| r.max_overlap = -0.1), "max_overlap");
    assert_eq!(named(|r| r.max_faces = 100_000), "max_faces");
    assert_eq!(named(|r| r.outputs.truncate(11)), "outputs");
    assert_eq!(named(|r| r.outputs[0] = vec![0; 3]), "outputs");
    assert_eq!(named(|r| r.height = 64), "outputs", "the grids of another size");
    assert_eq!(scores(&good), Vec::<f32>::new(), "nothing scores in a blank image");
}

fn rgba(width: u32, height: u32, pixel: impl Fn(u32, u32) -> [u8; 3]) -> Vec<u8> {
    (0..width * height)
        .flat_map(|i| {
            let [r, g, b] = pixel(i % width, i / width);
            [r, g, b, 7]
        })
        .collect()
}

fn tensor(bytes: &[u8]) -> Vec<f32> {
    bytes
        .chunks(4)
        .map(|b| f32::from_le_bytes(b.try_into().unwrap()))
        .collect()
}

fn prepare(request: &PrepareFaceDetectionRequest) -> Result<(u32, u32, Vec<f32>), CallError> {
    ask::<_, PrepareFaceDetectionResponse>(Method::PrepareFaceDetection, request)
        .map(|r| (r.width, r.height, tensor(&r.tensor)))
}

#[test]
fn detection_input_is_blue_green_and_red_planes_of_0_to_255_at_multiples_of_32() {
    // 100 × 50 rounds its long side up to 128 and keeps the proportions: 128 × 64.
    let request = PrepareFaceDetectionRequest {
        width: 100,
        height: 50,
        rgba: rgba(100, 50, |_, _| [10, 20, 30]),
        max_side: 0,
    };
    let (width, height, planes) = prepare(&request).unwrap();
    assert_eq!((width, height), (128, 64));
    assert_eq!(planes.len(), 3 * 128 * 64);
    let plane = 128 * 64;
    for (n, want) in [30.0, 20.0, 10.0].into_iter().enumerate() {
        assert!(
            planes[n * plane..(n + 1) * plane].iter().all(|v| close(*v, want)),
            "plane {n}"
        );
    }
}

#[test]
fn the_longer_side_never_passes_the_most_and_a_thin_image_keeps_at_least_32() {
    let sized = |width, height, max_side| {
        let request = PrepareFaceDetectionRequest {
            width,
            height,
            rgba: rgba(width, height, |x, _| [x as u8, 0, 0]),
            max_side,
        };
        prepare(&request).map(|(w, h, _)| (w, h))
    };
    assert_eq!(sized(1000, 500, 0).unwrap(), (640, 320), "640 unless asked otherwise");
    assert_eq!(sized(1000, 500, 256).unwrap(), (256, 128));
    assert_eq!(sized(500, 1000, 256).unwrap(), (128, 256));
    assert_eq!(sized(1000, 10, 256).unwrap(), (256, 32));
    assert_eq!(
        sized(40, 40, 640).unwrap(),
        (64, 64),
        "small images are not enlarged beyond the next multiple of 32"
    );
    assert_eq!(sized(1, 1, 640).unwrap(), (32, 32));
    for (width, height, max_side, expected) in [
        (0, 5, 0, "rgba"),
        (5, 0, 0, "rgba"),
        (5, 5, 31, "max_side"),
        (5, 5, 1281, "max_side"),
    ] {
        let error = sized(width, height, max_side).unwrap_err();
        assert_eq!(field(&error), Some(expected));
    }
    let short = PrepareFaceDetectionRequest {
        width: 4,
        height: 4,
        rgba: vec![0; 15],
        max_side: 0,
    };
    assert_eq!(field(&prepare(&short).unwrap_err()), Some("rgba"));
}

/// ArcFace's template of the five landmarks in a 112 × 112 face, which SFace was trained on.
const TEMPLATE: [(f32, f32); 5] = [
    (38.2946, 51.6963),
    (73.5318, 51.5014),
    (56.0252, 71.7366),
    (41.5493, 92.3655),
    (70.7299, 92.2041),
];

fn align(width: u32, height: u32, rgba: Vec<u8>, landmarks: Vec<f32>) -> Result<Vec<f32>, CallError> {
    let request = AlignFaceRequest {
        width,
        height,
        rgba,
        landmarks,
        ..Default::default()
    };
    ask::<_, AlignFaceResponse>(Method::AlignFace, &request).map(|r| tensor(&r.tensor))
}

/// A picture whose pixel at `(x, y)` is a function of the position that no other position shares.
fn marked(x: u32, y: u32) -> [u8; 3] {
    [(x * 2) as u8, (y * 2) as u8, ((x + y) % 251) as u8]
}

#[test]
fn a_face_whose_landmarks_are_on_the_template_comes_out_as_it_was() {
    let landmarks = TEMPLATE.iter().flat_map(|&(x, y)| [x / 112.0, y / 112.0]).collect();
    let tensor = align(112, 112, rgba(112, 112, marked), landmarks).unwrap();
    assert_eq!(tensor.len(), 3 * 112 * 112);
    // Red, green and blue planes of 0 to 255: the pixel (40, 70) is [80, 140, 110].
    let at = |plane: usize, x: usize, y: usize| tensor[plane * 112 * 112 + y * 112 + x];
    let got = [at(0, 40, 70), at(1, 40, 70), at(2, 40, 70)];
    assert!(
        got.iter().zip([80.0, 140.0, 110.0]).all(|(g, w)| close(*g, w)),
        "{got:?}"
    );
    assert!(tensor.iter().all(|v| (0.0..=255.0).contains(v)));
}

#[test]
fn a_model_that_scales_its_input_gets_it_scaled_and_a_bad_scale_names_its_field() {
    let landmarks: Vec<f32> = TEMPLATE.iter().flat_map(|&(x, y)| [x / 112.0, y / 112.0]).collect();
    let scaled = |mean: Vec<f32>, std: Vec<f32>| {
        let request = AlignFaceRequest {
            width: 112,
            height: 112,
            rgba: rgba(112, 112, marked),
            landmarks: landmarks.clone(),
            mean,
            std,
        };
        ask::<_, AlignFaceResponse>(Method::AlignFace, &request).map(|r| tensor(&r.tensor))
    };
    // AuraFace takes (value - 127.5) / 127.5: the pixel (40, 70) of [80, 140, 110] is [-0.373, 0.098, -0.137].
    let tensor = scaled(vec![0.5; 3], vec![0.5; 3]).unwrap();
    let at = |plane: usize| tensor[plane * 112 * 112 + 70 * 112 + 40];
    for (plane, want) in [80.0f32, 140.0, 110.0].into_iter().enumerate() {
        assert!(close(at(plane), (want - 127.5) / 127.5), "plane {plane}: {}", at(plane));
    }
    // Per channel.
    let tensor = scaled(vec![0.0, 0.5, 1.0], vec![1.0, 0.5, 2.0]).unwrap();
    let at = |plane: usize| tensor[plane * 112 * 112 + 70 * 112 + 40];
    assert!(
        close(at(0), 80.0 / 255.0)
            && close(at(1), (140.0 / 255.0 - 0.5) / 0.5)
            && close(at(2), (110.0 / 255.0 - 1.0) / 2.0)
    );
    for (mean, std, expected) in [
        (vec![0.5; 3], vec![], "std"),
        (vec![], vec![0.5; 3], "mean"),
        (vec![0.5; 2], vec![0.5; 3], "mean"),
        (vec![0.5; 3], vec![0.5, 0.0, 0.5], "std"),
        (vec![0.5, f32::NAN, 0.5], vec![0.5; 3], "mean"),
    ] {
        assert_eq!(field(&scaled(mean, std).unwrap_err()), Some(expected));
    }
}

#[test]
fn a_face_in_a_larger_turned_picture_is_cut_scaled_and_turned_upright() {
    // The 112 × 112 picture enlarged to 224 × 224 and turned a quarter clockwise: its landmarks go with it.
    let big = 224u32;
    let turned = |x: u32, y: u32| {
        // The pixel at (x, y) of the turned picture came from (y, big - 1 - x) of the unturned one, halved.
        marked(y / 2, (big - 1 - x) / 2)
    };
    let landmarks: Vec<f32> = TEMPLATE
        .iter()
        // (u, v) of the unturned 112 picture is (u * 2, v * 2) enlarged, and (big - 1 - v * 2, u * 2) turned.
        .flat_map(|&(u, v)| [v.mul_add(-2.0, big as f32 - 1.0) / big as f32, (u * 2.0) / big as f32])
        .collect();
    let got = align(big, big, rgba(big, big, turned), landmarks).unwrap();
    let want = align(
        112,
        112,
        rgba(112, 112, marked),
        TEMPLATE.iter().flat_map(|&(x, y)| [x / 112.0, y / 112.0]).collect(),
    )
    .unwrap();
    // Enlarging and turning loses the detail between pixels, so the interior compares within a few levels.
    let wrong = got
        .iter()
        .zip(&want)
        .enumerate()
        .filter(|(i, (g, w))| {
            let (x, y) = (i % 112, i / 112 % 112);
            (8..104).contains(&x) && (8..104).contains(&y) && (**g - **w).abs() > 6.0
        })
        .count();
    assert!(wrong < 30, "{wrong} of the interior's values differ by more than 6");
}

#[test]
fn what_lies_beyond_the_picture_is_black_and_bad_landmarks_name_their_field() {
    // A 64 × 64 picture whose landmarks are the template's, 30 pixels up and left: the face's first 30 rows and
    // columns, and the ones from 94 on, lie beyond the picture.
    let landmarks: Vec<f32> = TEMPLATE
        .iter()
        .flat_map(|&(x, y)| [(x - 30.0) / 64.0, (y - 30.0) / 64.0])
        .collect();
    let tensor = align(64, 64, rgba(64, 64, |_, _| [200, 200, 200]), landmarks).unwrap();
    let at = |x: usize, y: usize| tensor[y * 112 + x];
    assert_eq!((at(0, 0), at(10, 60), at(111, 111), at(60, 100)), (0.0, 0.0, 0.0, 0.0));
    assert!(
        close(at(60, 60), 200.0) && close(at(35, 35), 200.0),
        "{} {}",
        at(60, 60),
        at(35, 35)
    );
    let pixels = rgba(8, 8, |_, _| [0; 3]);
    let nan = [vec![f32::NAN; 10], vec![0.5; 10], vec![0.5; 8], vec![0.5; 12]];
    for landmarks in nan {
        let error = align(8, 8, pixels.clone(), landmarks).unwrap_err();
        assert_eq!(field(&error), Some("landmarks"));
    }
    let error = align(8, 8, vec![0; 3], vec![0.5; 10]).unwrap_err();
    assert_eq!(field(&error), Some("rgba"));
}

fn normalize(values: Vec<f32>) -> Result<Vec<f32>, CallError> {
    ask::<_, NormalizeFaceEmbeddingResponse>(
        Method::NormalizeFaceEmbedding,
        &NormalizeFaceEmbeddingRequest { values },
    )
    .map(|r| r.values)
}

#[test]
fn an_embedding_becomes_a_unit_vector_and_what_cannot_is_refused() {
    let unit = normalize(vec![3.0, 0.0, 4.0]).unwrap();
    assert!(
        close(unit[0], 0.6) && close(unit[1], 0.0) && close(unit[2], 0.8),
        "{unit:?}"
    );
    let long = normalize((0..512u16).map(|i| f32::from(i % 7) - 3.0).collect()).unwrap();
    assert_eq!(long.len(), 512);
    assert!(close(long.iter().map(|v| v * v).sum::<f32>(), 1.0));
    // Large values do not overflow the sum of squares.
    let large = normalize(vec![1e30, 1e30]).unwrap();
    assert!(close(large[0], std::f32::consts::FRAC_1_SQRT_2), "{large:?}");
    for bad in [
        vec![],
        vec![0.0; 128],
        vec![1.0, f32::NAN],
        vec![f32::INFINITY, 1.0],
        vec![1.0; 5000],
    ] {
        assert_eq!(field(&normalize(bad).unwrap_err()), Some("values"));
    }
}

#[test]
fn a_shrunk_picture_averages_what_it_covers() {
    // Left half red 200, right half red 100: shrunk to a quarter of its width.
    let request = PrepareFaceDetectionRequest {
        width: 128,
        height: 32,
        rgba: rgba(128, 32, |x, _| [if x < 64 { 200 } else { 100 }, 0, 0]),
        max_side: 32,
    };
    let (width, height, planes) = prepare(&request).unwrap();
    assert_eq!((width, height), (32, 32));
    let red = &planes[2 * 1024..3 * 1024];
    assert!(close(red[0], 200.0) && close(red[31], 100.0), "{} {}", red[0], red[31]);
    assert!(
        close(red[14], 200.0) && close(red[17], 100.0),
        "{} {}",
        red[14],
        red[17]
    );
    assert!(
        red[14] > red[15] && red[15] > red[16] && red[16] > red[17],
        "an edge between: {:?}",
        &red[14..18]
    );
}

#[test]
fn a_cell_that_scores_high_decodes_to_a_box_and_landmarks_in_fractions_of_the_image() {
    // A 128 × 64 tensor; the face is in the cell (5, 2) of stride 16: its centre is (5 + 0.5) × 16 = 88 by
    // (2 + 0.25) × 16 = 36, its size exp(ln 2) × 16 = 32 by exp(ln 1) × 16 = 16 ... as the offsets say.
    let kps = [-1.0, -0.5, 1.0, -0.5, 0.0, 0.0, -0.5, 1.0, 0.5, 1.0];
    let outputs = Outputs::new(128, 64).face(16, 5, 2, (0.9, 0.81), [0.5, 0.25, 2f32.ln(), 0.0], kps);
    let faces = decode(&outputs.request()).unwrap();
    assert_eq!(faces.len(), 1);
    let face = &faces[0];
    // x = 88 - 16 = 72, y = 36 - 8 = 28, over 128 by 64.
    assert!(close(face.x, 72.0 / 128.0), "{}", face.x);
    assert!(close(face.y, 28.0 / 64.0), "{}", face.y);
    assert!(close(face.width, 32.0 / 128.0), "{}", face.width);
    assert!(close(face.height, 16.0 / 64.0), "{}", face.height);
    // The landmarks are (offset + cell) × stride, over the size.
    let expected: Vec<f32> = [(4.0, 1.5), (6.0, 1.5), (5.0, 2.0), (4.5, 3.0), (5.5, 3.0)]
        .iter()
        .flat_map(|&(x, y)| [x * 16.0 / 128.0, y * 16.0 / 64.0])
        .collect();
    assert_eq!(face.landmarks.len(), 10);
    assert!(
        face.landmarks.iter().zip(&expected).all(|(a, b)| close(*a, *b)),
        "{:?}",
        face.landmarks
    );
    // The score is the geometric mean of class and objectness: sqrt(0.9 × 0.81) = 0.8538.
    assert!(close(face.score, (0.9f32 * 0.81).sqrt()), "{}", face.score);
}
