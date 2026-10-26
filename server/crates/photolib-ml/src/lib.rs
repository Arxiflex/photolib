//! The server's inference (ADR-0245, design 09 §3.2): ONNX Runtime through `ort`, from the library the administrator
//! installs, on each execution provider it has that first reproduces every model's golden outputs.

use std::{fmt, path::Path};

use photolib_models::{Fill, GoldenInput};
use serde::{Deserialize, Serialize};

mod check;
pub mod faces;
mod memory;
pub mod ocr;
mod onnx;
mod pool;
#[cfg(feature = "testing")]
pub mod testing;

pub use check::{Cost, FileReport, Verdict, self_test};
pub use memory::{peak, reset_peak, rss};
pub use onnx::Ort;
pub use pool::{IDLE, Pool};

/// The resident memory the ML role's default profile stays under: 2 GB (design 09 §3.2).
pub const MEMORY: u64 = 2_000_000_000;

/// glibc's settings for a process that runs models: without them, its per-thread arenas keep what ONNX Runtime frees,
/// hundreds of MiB per unloaded model (ADR-0245); they only apply from the process's start.
pub const MALLOC: [(&str, &str); 3] = [
    ("MALLOC_ARENA_MAX", "2"),
    ("MALLOC_MMAP_THRESHOLD_", "131072"),
    ("MALLOC_TRIM_THRESHOLD_", "131072"),
];

/// An execution provider of ONNX Runtime.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Backend {
    /// NVIDIA GPUs
    Cuda,
    /// Intel CPUs, GPUs and NPUs
    OpenVino,
    /// AMD GPUs, through the MIGraphX provider
    Rocm,
    /// Apple's Neural Engine and GPUs
    CoreMl,
    /// What always works
    Cpu,
}

impl Backend {
    /// The order a model's backends are preferred in; the CPU always works.
    pub const ORDER: [Self; 5] = [Self::Cuda, Self::OpenVino, Self::Rocm, Self::CoreMl, Self::Cpu];

    /// The cosine to the golden sample a backend must reach: an accelerator 0.99 (design 09 §3.2), the CPU, whose
    /// fp32 outputs the sample is, 0.999 (§12.3), so that a runtime upgrade that changes them stops the model.
    pub fn min_cosine(self) -> f32 {
        if self == Self::Cpu { 0.999 } else { 0.99 }
    }
}

impl fmt::Display for Backend {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Cuda => "cuda",
            Self::OpenVino => "openvino",
            Self::Rocm => "rocm",
            Self::CoreMl => "coreml",
            Self::Cpu => "cpu",
        })
    }
}

/// A named input tensor.
#[derive(Debug, Clone, PartialEq)]
pub struct Input {
    /// The model's name for it
    pub name: String,
    /// Its dimensions, the batch first
    pub shape: Vec<i64>,
    /// Its values, row-major
    pub data: Data,
}

/// Tensor values.
#[derive(Debug, Clone, PartialEq)]
pub enum Data {
    /// Pixels and the like
    F32(Vec<f32>),
    /// Token ids
    I64(Vec<i64>),
}

impl Data {
    fn len(&self) -> usize {
        match self {
            Self::F32(values) => values.len(),
            Self::I64(values) => values.len(),
        }
    }
}

/// Every output of a run by name, flattened.
pub type Outputs = Vec<(String, Vec<f32>)>;

/// A model loaded on one backend.
pub trait Session: Send {
    /// Whether every input's first dimension is free, so that items run in batches.
    fn batched(&self) -> bool;
    /// Runs one batch.
    fn run(&mut self, inputs: &[Input]) -> Result<Outputs, String>;
}

/// What loads models: ONNX Runtime, or a fake in tests.
pub trait Runtime: Send + Sync {
    /// The backends it has, in `Backend::ORDER`.
    fn backends(&self) -> Vec<Backend>;
    /// Loads a model file on `backend`, failing if `backend` cannot start.
    fn load(&self, model: &Path, backend: Backend) -> Result<Box<dyn Session>, String>;
}

/// The synthetic picture of `app/packages/photolib_ml/test/spike.dart`, channel-first: smooth waves with a disc and a
/// bar, so it has the edges and flat areas of a photo; values in [0, 1] times `scale` plus `offset`.
#[allow(
    clippy::suboptimal_flops,
    clippy::cast_precision_loss,
    clippy::cast_possible_truncation,
    reason = "computes as the Dart that made the golden samples, in f64 of a few thousand pixels, for f32 inputs"
)]
pub fn picture(size: usize, scale: f64, offset: f64) -> Vec<f32> {
    let s = size as f64;
    let mut values = Vec::with_capacity(size.saturating_mul(size).saturating_mul(3));
    for c in 0..3 {
        let c = f64::from(c);
        for y in 0..size {
            let y = y as f64;
            for x in 0..size {
                let x = x as f64;
                let value = if (x - s * 0.6).powi(2) + (y - s * 0.4).powi(2) < (s * 0.2).powi(2) {
                    0.15 + 0.3 * c
                } else if (x - s * 0.25).abs() < s * 0.1 && y > s * 0.55 {
                    0.9 - 0.3 * c
                } else {
                    0.5 + 0.25 * (x * 12.0 / s + 1.3 * c).sin() * (y * 9.0 / s - 0.7 * c).cos()
                };
                values.push((offset + scale * value) as f32);
            }
        }
    }
    values
}

/// A golden input as a tensor.
pub fn fill(input: &GoldenInput) -> Result<Input, String> {
    let data = match (&input.fill, &input.shape[..]) {
        (Fill::Picture([scale, offset]), [1, 3, h, w]) if h == w => Data::F32(picture(
            usize::try_from(*w).unwrap_or(0),
            f64::from(*scale),
            f64::from(*offset),
        )),
        (Fill::Picture(_), _) => {
            return Err(format!(
                "{}: a picture is [1, 3, n, n], not {:?}",
                input.name, input.shape
            ));
        }
        (Fill::Tokens(tokens), shape) => {
            let mut ids = tokens.clone();
            ids.resize(
                usize::try_from(shape.iter().product::<i64>())
                    .unwrap_or(0)
                    .max(ids.len()),
                0,
            );
            Data::I64(ids)
        }
    };
    if i64::try_from(data.len()) != Ok(input.shape.iter().product()) {
        return Err(format!(
            "{}: {} values for the shape {:?}",
            input.name,
            data.len(),
            input.shape
        ));
    }
    Ok(Input {
        name: input.name.clone(),
        shape: input.shape.clone(),
        data,
    })
}

/// At most 1,024 evenly spaced values of `outputs`, one after another: what a golden keeps of them.
pub fn sample(outputs: &[&[f32]]) -> Vec<f32> {
    let all: Vec<f32> = outputs.concat();
    let n = all.len().min(1024);
    (0..n)
        .filter_map(|i| all.get(i.checked_mul(all.len())?.checked_div(n)?).copied())
        .collect()
}

/// 0 for samples of different lengths.
#[allow(clippy::cast_possible_truncation, reason = "a cosine is within [-1, 1]")]
pub fn cosine(a: &[f32], b: &[f32]) -> f32 {
    if a.len() != b.len() {
        return 0.0;
    }
    let (mut ab, mut aa, mut bb) = (0f64, 0f64, 0f64);
    for (x, y) in a.iter().zip(b).map(|(x, y)| (f64::from(*x), f64::from(*y))) {
        ab = x.mul_add(y, ab);
        aa = x.mul_add(x, aa);
        bb = y.mul_add(y, bb);
    }
    (ab / (aa * bb).sqrt()) as f32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn golden_inputs_fill_their_shapes() {
        let picture = GoldenInput {
            name: "data".into(),
            shape: vec![1, 3, 4, 4],
            fill: Fill::Picture([2.0, -1.0]),
        };
        let Data::F32(values) = fill(&picture).unwrap().data else {
            panic!("not f32")
        };
        assert_eq!(values.len(), 48);
        assert!(values.iter().all(|v| (-1.0..=1.0).contains(v)));
        let tokens = GoldenInput {
            name: "ids".into(),
            shape: vec![1, 4],
            fill: Fill::Tokens(vec![7, 1]),
        };
        assert_eq!(fill(&tokens).unwrap().data, Data::I64(vec![7, 1, 0, 0]));
        for shape in [vec![1, 3, 4, 5], vec![2, 3, 4, 4]] {
            assert!(
                fill(&GoldenInput {
                    shape,
                    ..picture.clone()
                })
                .is_err()
            );
        }
        assert!(
            fill(&GoldenInput {
                shape: vec![1, 1],
                ..tokens
            })
            .is_err()
        );
    }

    #[test]
    fn a_sample_keeps_at_most_1024_evenly_spaced_values() {
        let all: Vec<f32> = (0..4096u16).map(f32::from).collect();
        let kept = sample(&[&all[..2048], &all[2048..]]);
        assert_eq!((kept.len(), kept[1], kept[1023]), (1024, 4.0, 4092.0));
        assert_eq!(sample(&[&[1.0, 2.0]]), [1.0, 2.0]);
    }

    #[test]
    fn cosine_compares_directions() {
        assert!((cosine(&[1.0, 2.0], &[2.0, 4.0]) - 1.0).abs() < 1e-6);
        assert!(cosine(&[1.0, 0.0], &[0.0, 1.0]).abs() < 1e-6);
        assert_eq!(cosine(&[1.0], &[1.0, 2.0]), 0.0);
    }
}
