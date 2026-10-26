//! PP-OCRv5 on a picture (design 09 §6): the detector finds lines of text, each recogniser of the three scripts reads
//! each line, and the reading that is surest of itself stands. The post-processing is the DB detector's: threshold the
//! map, take each blob, grow its box by `area × 1.5 / perimeter`.

#![allow(
    clippy::arithmetic_side_effects,
    clippy::indexing_slicing,
    clippy::cast_precision_loss,
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    reason = "pixel kernels over buffers whose sizes this module has just computed from the same dimensions"
)]

use std::sync::OnceLock;

use crate::{
    Data, Input, Outputs,
    ocr::{clean, decode_scored},
};

/// The detector's file, as the pool names it (`<id>@<revision>/<file>`).
pub const DETECTOR: &str = "ppocr-v5-det@1/det.onnx";

/// A picture of 8-bit RGB pixels, row by row.
pub struct Rgb {
    /// Its width in pixels
    pub width: usize,
    /// Its height in pixels
    pub height: usize,
    /// Its pixels, three bytes each, row by row
    pub pixels: Vec<u8>,
}

/// A recogniser and its character set: PP-OCRv5's Latin, East Slavic (Cyrillic) and Chinese-and-Japanese models.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Script {
    /// Latin script
    Latin,
    /// Cyrillic: Russian, Ukrainian, Belarusian, Bulgarian
    Eslav,
    /// Chinese and Japanese
    Chinese,
}

impl Script {
    /// Every script, in the order a line is read in
    pub const ALL: [Self; 3] = [Self::Latin, Self::Eslav, Self::Chinese];

    /// The recogniser's file, as the pool names it.
    pub const fn file(self) -> &'static str {
        match self {
            Self::Latin => "ppocr-v5-rec-latin@1/rec.onnx",
            Self::Eslav => "ppocr-v5-rec-eslav@1/rec.onnx",
            Self::Chinese => "ppocr-v5-rec-chinese@1/rec.onnx",
        }
    }

    /// Its characters: the dictionary's lines, then the space (class 0 is the blank).
    pub fn charset(self) -> &'static [String] {
        static SETS: [OnceLock<Vec<String>>; 3] = [OnceLock::new(), OnceLock::new(), OnceLock::new()];
        let (n, dictionary) = match self {
            Self::Latin => (0, include_str!("../../data/ocr/latin.txt")),
            Self::Eslav => (1, include_str!("../../data/ocr/eslav.txt")),
            Self::Chinese => (2, include_str!("../../data/ocr/chinese.txt")),
        };
        SETS[n].get_or_init(|| {
            let lines = dictionary.split('\n').filter(|line| !line.is_empty());
            lines.map(str::to_owned).chain([" ".to_owned()]).collect()
        })
    }
}

/// Runs the model `file` on one input; the pool's `run`, or a fake.
pub type Infer<'a> = dyn FnMut(&str, Input) -> Result<Outputs, String> + 'a;

/// The longest side the detector sees; larger pictures are shrunk to it.
const SIDE: usize = 1280;
/// The detector's map is a probability: a pixel is text above this, a blob of them is a line if it averages above
/// `BLOB`.
const PIXEL: f32 = 0.3;
const BLOB: f32 = 0.6;
/// The recognisers' input height, and the widest line they read.
const HEIGHT: usize = 48;
const WIDTH: usize = 3200;

#[derive(Clone, Copy, Debug, PartialEq)]
struct Box2 {
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
}

/// A line of text and where it is: the corners of its box as fractions of the picture's width and height.
#[derive(Clone, Debug, PartialEq)]
pub struct Line {
    /// The text read, as the recogniser surest of itself read it
    pub text: String,
    /// The left edge, 0 to 1
    pub x0: f32,
    /// The top edge, 0 to 1
    pub y0: f32,
    /// The right edge, 0 to 1
    pub x1: f32,
    /// The bottom edge, 0 to 1
    pub y1: f32,
}

/// The text of `image`, one line of it per line of text, cleaned: empty when it holds none.
pub fn read(infer: &mut Infer<'_>, image: &Rgb) -> Result<String, String> {
    let lines = read_lines(infer, image)?;
    Ok(clean(
        &lines.iter().map(|l| l.text.as_str()).collect::<Vec<_>>().join("\n"),
    ))
}

/// The lines of text in `image` in reading order, each with its box; text as `read` gives it, a line at a time.
pub fn read_lines(infer: &mut Infer<'_>, image: &Rgb) -> Result<Vec<Line>, String> {
    if image.width == 0 || image.height == 0 || image.pixels.len() != image.width * image.height * 3 {
        return Err("not a picture of 8-bit RGB pixels".into());
    }
    let (w, h) = (image.width as f32, image.height as f32);
    let mut lines = Vec::new();
    for line in detect(infer, image)? {
        let crop = crop(image, line);
        let mut best = (String::new(), 0.0);
        for script in Script::ALL {
            let (text, surety) = recognise(infer, script, &crop)?;
            if surety > best.1 {
                best = (text, surety);
            }
        }
        let text = clean(&best.0);
        if !text.is_empty() {
            lines.push(Line {
                text,
                x0: line.x0 / w,
                y0: line.y0 / h,
                x1: line.x1 / w,
                y1: line.y1 / h,
            });
        }
    }
    Ok(lines)
}

/// The lines of text in reading order.
fn detect(infer: &mut Infer<'_>, image: &Rgb) -> Result<Vec<Box2>, String> {
    let scale = (SIDE as f32 / image.width.max(image.height) as f32).min(1.0);
    let fit = |n: usize| (((n as f32 * scale) / 32.0).round() as usize).max(1) * 32;
    let (w, h) = (fit(image.width), fit(image.height));
    let mean = [0.485, 0.456, 0.406];
    let std = [0.229, 0.224, 0.225];
    let data = planes(&resize(image, w, h), |c, v| (v / 255.0 - mean[c]) / std[c]);
    let input = Input {
        name: "x".into(),
        shape: vec![1, 3, dim(h), dim(w)],
        data: Data::F32(data),
    };
    let outputs = infer(DETECTOR, input)?;
    let map = outputs.first().map(|(_, map)| map).filter(|map| map.len() == w * h);
    let map = map.ok_or("the detector's map is not the picture's size")?;
    let mut seen = vec![false; w * h];
    let mut boxes = Vec::new();
    for start in 0..w * h {
        if seen[start] || map[start] <= PIXEL {
            continue;
        }
        let (mut x0, mut y0, mut x1, mut y1, mut sum, mut count) = (w, h, 0, 0, 0.0, 0);
        let mut stack = vec![start];
        seen[start] = true;
        while let Some(at) = stack.pop() {
            let (x, y) = (at % w, at / w);
            (x0, y0, x1, y1) = (x0.min(x), y0.min(y), x1.max(x), y1.max(y));
            sum += map[at];
            count += 1;
            for (nx, ny) in neighbours(x, y, w, h) {
                let next = ny * w + nx;
                if !seen[next] && map[next] > PIXEL {
                    seen[next] = true;
                    stack.push(next);
                }
            }
        }
        let (bw, bh) = ((x1 - x0 + 1) as f32, (y1 - y0 + 1) as f32);
        if bw.min(bh) < 3.0 || sum / count as f32 <= BLOB {
            continue;
        }
        let grow = bw * bh * 1.5 / (2.0 * (bw + bh));
        let (sx, sy) = (image.width as f32 / w as f32, image.height as f32 / h as f32);
        boxes.push(Box2 {
            x0: ((x0 as f32 - grow) * sx).max(0.0),
            y0: ((y0 as f32 - grow) * sy).max(0.0),
            x1: ((x1 as f32 + 1.0 + grow) * sx).min(image.width as f32),
            y1: ((y1 as f32 + 1.0 + grow) * sy).min(image.height as f32),
        });
    }
    Ok(reading_order(boxes))
}

fn neighbours(x: usize, y: usize, w: usize, h: usize) -> impl Iterator<Item = (usize, usize)> {
    let around = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)];
    around.into_iter().filter_map(move |(dx, dy): (isize, isize)| {
        let nx = x.checked_add_signed(dx).filter(|nx| *nx < w)?;
        let ny = y.checked_add_signed(dy).filter(|ny| *ny < h)?;
        Some((nx, ny))
    })
}

/// Top to bottom, and left to right among boxes whose tops are within half a box height of each other.
fn reading_order(mut boxes: Vec<Box2>) -> Vec<Box2> {
    boxes.sort_by(|a, b| a.y0.total_cmp(&b.y0).then(a.x0.total_cmp(&b.x0)));
    for i in 1..boxes.len() {
        for j in (1..=i).rev() {
            let (a, b) = (boxes[j - 1], boxes[j]);
            if (b.y0 - a.y0).abs() < (b.y1 - b.y0).min(a.y1 - a.y0) / 2.0 && b.x0 < a.x0 {
                boxes.swap(j - 1, j);
            } else {
                break;
            }
        }
    }
    boxes
}

fn crop(image: &Rgb, line: Box2) -> Rgb {
    let (x0, y0) = (line.x0 as usize, line.y0 as usize);
    let (x1, y1) = (
        (line.x1.ceil() as usize).min(image.width),
        (line.y1.ceil() as usize).min(image.height),
    );
    let (width, height) = ((x1 - x0).max(1), (y1 - y0).max(1));
    let mut pixels = Vec::with_capacity(width * height * 3);
    for y in y0..y0 + height {
        let row = (y.min(image.height - 1) * image.width + x0.min(image.width - 1)) * 3;
        let take = (width * 3).min(image.pixels.len() - row);
        pixels.extend_from_slice(&image.pixels[row..row + take]);
        pixels.resize(pixels.len() + width * 3 - take, 255);
    }
    Rgb { width, height, pixels }
}

/// A line read by one recogniser, with the mean probability of the characters it chose.
fn recognise(infer: &mut Infer<'_>, script: Script, line: &Rgb) -> Result<(String, f32), String> {
    let width = (line.width * HEIGHT).div_ceil(line.height).clamp(8, WIDTH);
    let data = planes(&resize(line, width, HEIGHT), |_, v| (v / 255.0 - 0.5) / 0.5);
    let input = Input {
        name: "x".into(),
        shape: vec![1, 3, dim(HEIGHT), dim(width)],
        data: Data::F32(data),
    };
    let outputs = infer(script.file(), input)?;
    let (_, probabilities) = outputs.first().ok_or("the recogniser answered nothing")?;
    Ok(decode_scored(probabilities, script.charset()))
}

fn lerp(from: f32, to: f32, at: f32) -> f32 {
    (to - from).mul_add(at, from)
}

/// A dimension as a tensor's.
fn dim(n: usize) -> i64 {
    i64::try_from(n).unwrap_or(i64::MAX)
}

/// The picture bilinearly resized, pixel centres aligned as OpenCV does.
fn resize(image: &Rgb, width: usize, height: usize) -> Rgb {
    let mut pixels = Vec::with_capacity(width * height * 3);
    let (sx, sy) = (image.width as f32 / width as f32, image.height as f32 / height as f32);
    let at = |x: usize, y: usize, c: usize| f32::from(image.pixels[(y * image.width + x) * 3 + c]);
    for y in 0..height {
        let fy = (y as f32 + 0.5).mul_add(sy, -0.5).clamp(0.0, (image.height - 1) as f32);
        let (y0, wy) = (fy as usize, fy.fract());
        let y1 = (y0 + 1).min(image.height - 1);
        for x in 0..width {
            let fx = (x as f32 + 0.5).mul_add(sx, -0.5).clamp(0.0, (image.width - 1) as f32);
            let (x0, wx) = (fx as usize, fx.fract());
            let x1 = (x0 + 1).min(image.width - 1);
            for c in 0..3 {
                let top = lerp(at(x0, y0, c), at(x1, y0, c), wx);
                let bottom = lerp(at(x0, y1, c), at(x1, y1, c), wx);
                pixels.push(lerp(top, bottom, wy).round() as u8);
            }
        }
    }
    Rgb { width, height, pixels }
}

/// Channel-first floats in BGR order, as PaddleOCR's models were trained on (OpenCV's), each value through `scale`
/// with its channel's index in that order.
fn planes(image: &Rgb, scale: impl Fn(usize, f32) -> f32) -> Vec<f32> {
    let n = image.width * image.height;
    let mut out = Vec::with_capacity(n * 3);
    for c in 0..3 {
        out.extend((0..n).map(|i| scale(c, f32::from(image.pixels[i * 3 + (2 - c)]))));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn white(width: usize, height: usize) -> Rgb {
        Rgb {
            width,
            height,
            pixels: vec![255; width * height * 3],
        }
    }

    /// A detector that sees `rects` (x0, y0, x1, y1 on its map) and recognisers that each read the one character at
    /// `class` of their charset, as sure as `surety`; `seen` collects the files run.
    fn fake<'a>(
        rects: &'a [(usize, usize, usize, usize)],
        says: &'a [(Script, usize, f32)],
        seen: &'a mut Vec<String>,
    ) -> impl FnMut(&str, Input) -> Result<Outputs, String> + 'a {
        move |file, input| {
            seen.push(file.to_owned());
            let shape: Vec<usize> = input.shape.iter().map(|d| *d as usize).collect();
            if file == DETECTOR {
                let (h, w) = (shape[2], shape[3]);
                let mut map = vec![0.0; h * w];
                for &(x0, y0, x1, y1) in rects {
                    for y in y0..y1 {
                        map[y * w + x0..y * w + x1].fill(0.9);
                    }
                }
                return Ok(vec![("map".into(), map)]);
            }
            let (script, class, surety) = *says.iter().find(|(s, ..)| s.file() == file).unwrap();
            let classes = script.charset().len() + 1;
            let mut step = vec![0.0; classes];
            step[class] = surety;
            Ok(vec![("out".into(), [step, vec![0.0; classes]].concat())])
        }
    }

    #[test]
    fn a_line_is_read_by_the_recogniser_surest_of_itself() {
        let says = [
            (Script::Latin, 1, 0.5),
            (Script::Eslav, 2, 0.9),
            (Script::Chinese, 3, 0.7),
        ];
        let mut seen = vec![];
        let text = read(&mut fake(&[(4, 8, 28, 16)], &says, &mut seen), &white(32, 32)).unwrap();
        assert_eq!(text, Script::Eslav.charset()[1]);
        assert_eq!(seen.len(), 4, "the detector once and each recogniser once: {seen:?}");
    }

    #[test]
    fn each_line_comes_with_its_box_as_fractions_of_the_picture() {
        let says = [
            (Script::Latin, 1, 0.5),
            (Script::Eslav, 2, 0.9),
            (Script::Chinese, 3, 0.7),
        ];
        let mut seen = vec![];
        let lines = read_lines(&mut fake(&[(4, 8, 28, 16)], &says, &mut seen), &white(32, 32)).unwrap();
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].text, Script::Eslav.charset()[1]);
        // The detector's box grows by area × 1.5 / perimeter = 4.5 pixels and stops at the picture's edges.
        let [x0, y0, x1, y1] = [lines[0].x0, lines[0].y0, lines[0].x1, lines[0].y1];
        for (got, want) in [(x0, 0.0), (y0, 3.5 / 32.0), (x1, 1.0), (y1, 20.5 / 32.0)] {
            assert!((got - want).abs() < 1e-4, "{got} is not {want}");
        }
        // The same boxes on a picture twice as wide are half as wide in fractions of it.
        let wide = read_lines(&mut fake(&[(4, 8, 28, 16)], &says, &mut vec![]), &white(64, 32)).unwrap();
        assert!((wide[0].x1 - 32.5 / 64.0).abs() < 1e-4 && wide[0].x0 < 1e-4);
    }

    #[test]
    fn lines_come_top_to_bottom_and_left_to_right() {
        let at = |x0, y0, x1, y1| Box2 { x0, y0, x1, y1 };
        let order = reading_order(vec![
            at(40.0, 2.0, 60.0, 12.0),
            at(0.0, 30.0, 20.0, 40.0),
            at(0.0, 0.0, 20.0, 10.0),
        ]);
        let corners: Vec<_> = order.iter().map(|b| (b.x0, b.y0)).collect();
        assert_eq!(corners, [(0.0, 0.0), (40.0, 2.0), (0.0, 30.0)]);
    }

    #[test]
    fn pictures_without_text_and_malformed_ones_are_handled() {
        let says = [
            (Script::Latin, 1, 0.5),
            (Script::Eslav, 1, 0.5),
            (Script::Chinese, 1, 0.5),
        ];
        let mut seen = vec![];
        assert_eq!(read(&mut fake(&[], &says, &mut seen), &white(64, 64)).unwrap(), "");
        assert_eq!(seen, [DETECTOR], "no recogniser runs without a line");
        // A speck under 3 pixels wide is noise.
        let mut seen = vec![];
        assert_eq!(
            read(&mut fake(&[(4, 4, 6, 20)], &says, &mut seen), &white(32, 32)).unwrap(),
            ""
        );
        let bad = Rgb {
            width: 2,
            height: 2,
            pixels: vec![0; 5],
        };
        assert!(read(&mut fake(&[], &says, &mut vec![]), &bad).is_err());
        assert!(read(&mut fake(&[], &says, &mut vec![]), &white(0, 0)).is_err());
        let mut broken = |_: &str, _: Input| Err::<Outputs, _>("no session".to_owned());
        assert_eq!(read(&mut broken, &white(32, 32)), Err("no session".into()));
    }

    #[test]
    fn every_script_has_a_charset_of_the_size_its_model_answers() {
        // The dictionary's lines, the blank and the space: the models' last dimensions.
        let sizes: Vec<_> = Script::ALL.iter().map(|s| s.charset().len() + 1).collect();
        assert_eq!(sizes, [504, 519, 18385]);
    }
}
