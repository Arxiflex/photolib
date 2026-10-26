//! The golden-output self-test (design 09 §3.2): before a backend runs a model file, the file's golden input must
//! reproduce its golden sample there.

use std::path::Path;

use photolib_models::{Golden, Model, Target};
use serde::{Deserialize, Serialize};

use crate::{Backend, Runtime, cosine, fill, memory, sample};

/// What it takes to run a model file on the CPU, as its self-test measured.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Cost {
    /// Resident bytes at most while it loads
    pub load: u64,
    /// Resident bytes once loaded
    pub resident: u64,
    /// Resident bytes at most a run adds, per item
    pub item: u64,
}

/// What a backend did with a golden input.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Verdict {
    /// Its outputs are the model's
    Passed {
        /// To the golden sample
        cosine: f32,
    },
    /// It ran, but its outputs are not the model's
    Wrong {
        /// To the golden sample
        cosine: f32,
    },
    /// It did not load or run
    Failed {
        /// What ONNX Runtime said
        error: String,
    },
}

/// A model file's self-test.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct FileReport {
    /// `<id>@<revision>/<file>`
    pub name: String,
    /// What each backend did with the golden input, in `Backend::ORDER`; none without a golden
    pub backends: Vec<(Backend, Verdict)>,
    /// The first backend that passed: what the file runs on
    pub chosen: Option<Backend>,
    /// Measured on the CPU
    pub cost: Cost,
}

/// Tests every installed file that the server runs, on each backend of `runtime`, the CPU first: a backend runs a
/// file only once it reaches its `min_cosine` to the golden sample, and none does if the CPU does not.
pub fn self_test(runtime: &dyn Runtime, dir: &Path, models: &[Model]) -> Vec<FileReport> {
    let mut reports = Vec::new();
    for model in models {
        for file in model.files.iter().filter(|f| f.targets.contains(&Target::Server)) {
            let path = dir.join(model.name()).join(&file.name);
            if !path.is_file() {
                continue;
            }
            let mut report = FileReport {
                name: format!("{}/{}", model.name(), file.name),
                backends: vec![],
                chosen: None,
                cost: Cost::default(),
            };
            if let Some(golden) = &file.golden {
                test(runtime, &path, golden, &mut report);
            }
            reports.push(report);
        }
    }
    reports
}

fn test(runtime: &dyn Runtime, path: &Path, golden: &Golden, report: &mut FileReport) {
    let cpu = run(runtime, path, golden, Backend::Cpu, Some(&mut report.cost));
    let others = runtime.backends().into_iter().filter(|b| *b != Backend::Cpu);
    let tried: Vec<_> = match cpu {
        Verdict::Passed { .. } => others.map(|b| (b, run(runtime, path, golden, b, None))).collect(),
        _ => vec![],
    };
    report.backends = tried.into_iter().chain([(Backend::Cpu, cpu)]).collect();
    report.chosen = (report.backends.iter())
        .find(|(_, verdict)| matches!(verdict, Verdict::Passed { .. }))
        .map(|(backend, _)| *backend);
}

/// The golden input on `backend`, measuring into `cost`.
fn run(runtime: &dyn Runtime, path: &Path, golden: &Golden, backend: Backend, cost: Option<&mut Cost>) -> Verdict {
    let outcome = (|| {
        let inputs = golden.inputs.iter().map(fill).collect::<Result<Vec<_>, _>>()?;
        memory::reset_peak();
        let before = memory::rss();
        let mut session = runtime.load(path, backend)?;
        let (loaded, load_peak) = (memory::rss(), memory::peak());
        memory::reset_peak();
        let outputs = session.run(&inputs)?;
        if let Some(cost) = cost {
            *cost = Cost {
                load: load_peak.saturating_sub(before),
                resident: loaded.saturating_sub(before),
                item: memory::peak().saturating_sub(loaded),
            };
        }
        let compared = (golden.outputs.iter())
            .map(|name| {
                let output = outputs.iter().find(|(n, _)| n == name);
                output
                    .map(|(_, values)| values.as_slice())
                    .ok_or_else(|| format!("no output {name}"))
            })
            .collect::<Result<Vec<_>, _>>()?;
        Ok::<_, String>(cosine(&sample(&compared), &golden.sample))
    })();
    match outcome {
        Ok(cosine) if cosine >= backend.min_cosine() => Verdict::Passed { cosine },
        Ok(cosine) => Verdict::Wrong { cosine },
        Err(error) => Verdict::Failed { error },
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::*;
    use crate::testing::{Fake, GOLDEN, installed};

    fn report(backends: &[Backend], outputs: fn(Backend) -> Result<Vec<f32>, String>) -> FileReport {
        let (dir, model) = installed(true);
        let runtime = Fake {
            backends: backends.to_vec(),
            outputs,
        };
        let mut reports = self_test(&runtime, dir.path(), &[model]);
        assert_eq!(reports.len(), 1, "only the server's files: {reports:?}");
        reports.remove(0)
    }

    #[test]
    fn a_backend_with_wrong_outputs_is_disabled_and_the_cpu_runs_the_model() {
        let report = report(&[Backend::OpenVino, Backend::Cpu], |backend| match backend {
            Backend::OpenVino => Ok(GOLDEN.iter().rev().copied().collect()),
            _ => Ok(GOLDEN.to_vec()),
        });
        assert_eq!(report.name, "m@1/m.onnx");
        let [
            (Backend::OpenVino, Verdict::Wrong { cosine }),
            (Backend::Cpu, Verdict::Passed { .. }),
        ] = report.backends[..]
        else {
            panic!("{:?}", report.backends);
        };
        assert!(cosine < 0.99, "{cosine}");
        assert_eq!(report.chosen, Some(Backend::Cpu));
    }

    #[test]
    fn the_first_accelerator_that_passes_runs_the_model() {
        let report = report(
            &[Backend::Cuda, Backend::OpenVino, Backend::Cpu],
            |backend| match backend {
                Backend::Cuda => Err("no CUDA device".into()),
                // within an accelerator's 0.99, not the CPU's 0.999
                Backend::OpenVino => Ok(GOLDEN.iter().map(|v| v + 0.06).collect()),
                _ => Ok(GOLDEN.to_vec()),
            },
        );
        assert!(matches!(&report.backends[0], (Backend::Cuda, Verdict::Failed { error }) if error == "no CUDA device"));
        assert!(matches!(
            report.backends[1],
            (Backend::OpenVino, Verdict::Passed { .. })
        ));
        assert_eq!(report.chosen, Some(Backend::OpenVino));
    }

    #[test]
    fn a_cpu_that_drifts_from_the_golden_sample_stops_the_model_everywhere() {
        // 0.99 < cosine < 0.999: enough for an accelerator, not for the reference
        let report = report(&[Backend::Cuda, Backend::Cpu], |_| {
            Ok(GOLDEN.iter().map(|v| v + 0.06).collect())
        });
        let [(Backend::Cpu, Verdict::Wrong { cosine })] = report.backends[..] else {
            panic!("{:?}", report.backends);
        };
        assert!((0.99..0.999).contains(&cosine), "{cosine}");
        assert_eq!(report.chosen, None);
    }

    #[test]
    fn a_file_without_a_golden_runs_nowhere_and_missing_files_are_skipped() {
        let (dir, model) = installed(false);
        let runtime = Fake {
            backends: vec![Backend::Cpu],
            outputs: |_| Ok(GOLDEN.to_vec()),
        };
        let reports = self_test(&runtime, dir.path(), std::slice::from_ref(&model));
        assert_eq!((reports[0].backends.len(), reports[0].chosen), (0, None));
        assert_eq!(self_test(&runtime, &PathBuf::from("/nonexistent"), &[model]), []);
    }
}
