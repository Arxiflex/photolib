//! PrepareImage, the input of image models on the server and every device (design 09 §2.2, ADR-0254).

use photolib_kernel::call;
use photolib_kernel::proto::kernel::v1::{
    CallError, CallErrorCode, CallResponse, Method, PrepareImageRequest, PrepareImageResponse, call_response,
};
use prost::Message;

fn prepare(request: &PrepareImageRequest) -> Result<Vec<f32>, CallError> {
    let answer = CallResponse::decode(call(Method::PrepareImage as u32, &request.encode_to_vec()).as_slice()).unwrap();
    match answer.result.unwrap() {
        call_response::Result::Response(r) => Ok(PrepareImageResponse::decode(r.as_slice())
            .unwrap()
            .tensor
            .chunks(4)
            .map(|b| f32::from_le_bytes(b.try_into().unwrap()))
            .collect()),
        call_response::Result::Error(e) => Err(e),
    }
}

fn request(width: u32, height: u32, size: u32, pixel: impl Fn(u32, u32) -> [u8; 3]) -> PrepareImageRequest {
    PrepareImageRequest {
        width,
        height,
        rgba: (0..width * height)
            .flat_map(|i| {
                let [r, g, b] = pixel(i % width, i / width);
                [r, g, b, 0]
            })
            .collect(),
        size,
        mean: vec![0.5; 3],
        std: vec![0.5; 3],
        crop: false,
    }
}

fn close(a: &[f32], b: &[f32]) -> bool {
    a.len() == b.len() && a.iter().zip(b).all(|(a, b)| (a - b).abs() < 1e-5)
}

#[test]
fn a_flat_colour_gives_flat_normalised_planes_whatever_the_alpha() {
    let tensor = prepare(&request(7, 5, 4, |_, _| [255, 0, 51])).unwrap();
    let plane = |v: f32| vec![v; 16];
    assert!(
        close(&tensor, &[plane(1.0), plane(-1.0), plane(-0.6)].concat()),
        "{tensor:?}"
    );
}

#[test]
fn each_channel_has_its_own_mean_and_std() {
    let tensor = prepare(&PrepareImageRequest {
        mean: vec![0.0, 0.25, 1.0],
        std: vec![1.0, 0.5, 0.25],
        ..request(2, 2, 1, |_, _| [255, 255, 255])
    })
    .unwrap();
    assert!(close(&tensor, &[1.0, 1.5, 0.0]), "{tensor:?}");
}

#[test]
fn the_whole_image_fills_the_square_as_siglip_2_expects() {
    // Columns of a 2:1 image alternate black and white, and rows of a 1:2 one. Squashed, each output blends two of
    // them into grey, 0 once normalised, but at the edges, where the filter has no pixels beyond the image.
    let wide = prepare(&request(8, 4, 4, |x, _| stripe(x))).unwrap();
    let tall = prepare(&request(4, 8, 4, |_, y| stripe(y))).unwrap();
    let line = [-1.0 / 7.0, 0.0, 0.0, 1.0 / 7.0];
    assert!(close(&wide, &line.repeat(12)), "{wide:?}");
    assert!(close(&tall, &line.map(|v| [v; 4]).concat().repeat(3)), "{tall:?}");
}

#[test]
fn a_cropping_model_gets_the_centre_of_a_wide_image_and_a_tall_one() {
    let crop = |width, height, pixel: &dyn Fn(u32, u32) -> [u8; 3]| {
        prepare(&PrepareImageRequest {
            crop: true,
            ..request(width, height, 4, pixel)
        })
        .unwrap()
    };
    // At its scale, the centre square of the stripes keeps them.
    let wide = crop(8, 4, &|x, _| stripe(x));
    assert!(close(&wide, &[-1.0, 1.0, -1.0, 1.0].repeat(12)), "{wide:?}");
    // Black at either end of the long side, beyond what the centre square's filter reaches, white between.
    let middle = |at: u32| [if (3..13).contains(&at) { 255 } else { 0 }; 3];
    let wide = crop(16, 8, &|x, _| middle(x));
    assert!(close(&wide, &[1.0; 48]), "{wide:?}");
    let tall = crop(8, 16, &|_, y| middle(y));
    assert!(close(&tall, &[1.0; 48]), "{tall:?}");
}

fn stripe(at: u32) -> [u8; 3] {
    [if at.is_multiple_of(2) { 0 } else { 255 }; 3]
}

#[test]
fn a_downscale_averages_what_each_output_pixel_covers() {
    // Columns alternate black and white: halving blends them to grey, 127.5 of 255, 0 after normalising, but at the
    // edges, where the filter has no pixels beyond the image.
    let tensor = prepare(&request(8, 8, 4, |x, _| [if x % 2 == 0 { 0 } else { 255 }; 3])).unwrap();
    let inner: Vec<f32> = tensor.chunks(4).flat_map(|row| [row[1], row[2]]).collect();
    assert!(close(&inner, &[0.0; 24]), "{tensor:?}");
}

#[test]
fn rows_are_laid_out_top_down_and_an_upscale_interpolates() {
    // Top row black, bottom row white, doubled: the outer rows keep their values, the inner ones blend them.
    let tensor = prepare(&request(2, 2, 4, |_, y| [255 * y as u8; 3])).unwrap();
    let rows: Vec<f32> = tensor[..16].chunks(4).map(|row| row[0]).collect();
    assert!(close(&rows, &[-1.0, -0.5, 0.5, 1.0]), "{rows:?}");
}

#[test]
fn malformed_requests_name_their_field() {
    let field = |change: fn(&mut PrepareImageRequest)| {
        let mut request = request(3, 2, 2, |_, _| [9; 3]);
        change(&mut request);
        let error = prepare(&request).unwrap_err();
        assert_eq!(error.code, CallErrorCode::InvalidRequest as i32);
        error.params["field"].clone()
    };
    assert_eq!(field(|r| r.rgba.truncate(23)), "rgba");
    assert_eq!(field(|r| (r.width, r.rgba) = (0, vec![])), "rgba");
    assert_eq!(field(|r| r.size = 0), "size");
    assert_eq!(field(|r| r.size = 1025), "size");
    assert_eq!(field(|r| r.mean.truncate(2)), "mean");
    assert_eq!(field(|r| r.std[1] = 0.0), "std");
    assert_eq!(field(|r| r.mean[1] = f32::NAN), "mean");
}

#[test]
fn a_long_thin_image_filters_only_the_lines_its_square_needs() {
    // 1 × 65535 pixels made 1024² would be 268 MB a channel if every row were filtered across first.
    for crop in [false, true] {
        let tensor = prepare(&PrepareImageRequest {
            crop,
            ..request(1, 65535, 1024, |_, y| [if y == 32767 { 255 } else { 0 }; 3])
        })
        .unwrap();
        assert_eq!(tensor.len(), 3 * 1024 * 1024);
        assert!(tensor.iter().any(|&v| v > -1.0));
    }
}
