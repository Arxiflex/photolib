//! The models loaded for work (design 09 §3.2): one session per file, on the backend its self-test chose; batches of
//! 1, 8 or 32 items only; one run at a time; and a limit on the process's resident memory that each load and batch
//! must fit by its self-tested cost, the least recently used file unloading to make room. A file unloads after
//! `IDLE` unused.

use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::Mutex,
    time::{Duration, Instant},
};

use crate::{Backend, Cost, Data, FileReport, Input, Outputs, Runtime, Session};

/// How long a file stays loaded unused.
pub const IDLE: Duration = Duration::from_mins(5);

const BUCKETS: [usize; 3] = [32, 8, 1];

struct File {
    path: PathBuf,
    backend: Backend,
    cost: Cost,
    session: Option<Box<dyn Session>>,
    used: Instant,
}

/// The loaded files.
pub struct Pool<'r> {
    runtime: &'r dyn Runtime,
    memory: u64,
    /// The process's resident memory now
    meter: fn() -> u64,
    files: Mutex<HashMap<String, File>>,
}

/// The largest bucket of `pending` items whose run fits in `room` bytes; 1 for a model of fixed batch size.
fn bucket(pending: usize, batched: bool, item: u64, room: u64) -> usize {
    let fits = |b: &usize| *b <= pending && (*b as u64).saturating_mul(item) <= room;
    BUCKETS.into_iter().filter(|_| batched).find(fits).unwrap_or(1)
}

/// The items' inputs, each of batch size 1, as one batch.
fn batch(items: &[Vec<Input>]) -> Vec<Input> {
    let first = items.first().map_or(&[][..], Vec::as_slice);
    let parts = |i: usize| {
        items
            .iter()
            .filter_map(move |item| item.get(i))
            .map(|input| &input.data)
    };
    (first.iter().enumerate())
        .map(|(i, input)| Input {
            name: input.name.clone(),
            shape: std::iter::once(i64::try_from(items.len()).unwrap_or(1))
                .chain(input.shape.iter().skip(1).copied())
                .collect(),
            data: match input.data {
                Data::F32(_) => Data::F32(
                    parts(i)
                        .flat_map(|d| if let Data::F32(v) = d { v.clone() } else { vec![] })
                        .collect(),
                ),
                Data::I64(_) => Data::I64(
                    parts(i)
                        .flat_map(|d| if let Data::I64(v) = d { v.clone() } else { vec![] })
                        .collect(),
                ),
            },
        })
        .collect()
}

/// A batch's outputs, item by item.
fn split(outputs: Outputs, n: usize) -> Vec<Outputs> {
    let mut items = vec![Outputs::new(); n];
    for (name, values) in outputs {
        for (item, chunk) in items
            .iter_mut()
            .zip(values.chunks(values.len().checked_div(n).unwrap_or(0).max(1)))
        {
            item.push((name.clone(), chunk.to_vec()));
        }
    }
    items
}

impl<'r> Pool<'r> {
    /// The files of `dir` that the self-test chose a backend for, keeping `meter` (`rss`) under `memory` bytes.
    pub fn new(runtime: &'r dyn Runtime, dir: &Path, reports: &[FileReport], memory: u64, meter: fn() -> u64) -> Self {
        let files = (reports.iter())
            .filter_map(|report| {
                let file = File {
                    path: dir.join(&report.name),
                    backend: report.chosen?,
                    cost: report.cost,
                    session: None,
                    used: Instant::now(),
                };
                Some((report.name.clone(), file))
            })
            .collect();
        Pool {
            runtime,
            memory,
            meter,
            files: Mutex::new(files),
        }
    }

    /// Runs `items` of the file named `<id>@<revision>/<file>`, each its inputs at batch size 1, and returns each
    /// item's outputs in order.
    pub fn run(&self, name: &str, items: &[Vec<Input>]) -> Result<Vec<Outputs>, String> {
        let mut files = self.files.lock().map_err(|_| "a run panicked")?;
        let file = files
            .get(name)
            .ok_or_else(|| format!("{name} has passed no self-test"))?;
        let (path, backend, cost) = (file.path.clone(), file.backend, file.cost);
        // What is resident, by the meter or, where it reads less, by the self-tested costs of the loaded files
        let used = |files: &HashMap<String, File>| {
            let held = files
                .values()
                .filter(|f| f.session.is_some())
                .map(|f| f.cost.resident)
                .sum::<u64>();
            held.max((self.meter)())
        };
        if file.session.is_none() {
            while used(&files).saturating_add(cost.load) > self.memory {
                let lru = (files.iter_mut())
                    .filter(|(other, f)| f.session.is_some() && *other != name)
                    .min_by_key(|(_, f)| f.used);
                let Some((_, lru)) = lru else { break };
                lru.session = None;
            }
            let session = self.runtime.load(&path, backend)?;
            files.get_mut(name).ok_or("unknown")?.session = Some(session);
        }
        let room = self.memory.saturating_sub(used(&files));
        let file = files.get_mut(name).ok_or("unknown")?;
        let Some(session) = file.session.as_mut() else {
            return Err(format!("{name} is not loaded"));
        };
        let mut outputs = Vec::with_capacity(items.len());
        let mut rest = items;
        while !rest.is_empty() {
            let n = bucket(rest.len(), session.batched(), cost.item, room);
            let (now, later) = rest.split_at(n.min(rest.len()));
            outputs.extend(split(session.run(&batch(now))?, now.len()));
            rest = later;
        }
        file.used = Instant::now();
        Ok(outputs)
    }

    /// Unloads the files unused for `IDLE` at `now`.
    pub fn unload_idle(&self, now: Instant) {
        if let Ok(mut files) = self.files.lock() {
            for file in files.values_mut().filter(|f| now.duration_since(f.used) >= IDLE) {
                file.session = None;
            }
        }
    }

    #[cfg(test)]
    fn loaded(&self) -> Vec<String> {
        let files = self.files.lock().map(|files| {
            let mut names: Vec<_> = files
                .iter()
                .filter(|(_, f)| f.session.is_some())
                .map(|(n, _)| n.clone())
                .collect();
            names.sort();
            names
        });
        files.unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex};

    use super::*;
    use crate::Verdict;

    /// Sessions that answer each item with its first value, and log the batch sizes they run.
    #[derive(Default)]
    struct Echo {
        log: Arc<Mutex<Vec<String>>>,
        batched: bool,
    }

    struct EchoSession(Arc<Mutex<Vec<String>>>, bool, String);

    impl Session for EchoSession {
        fn batched(&self) -> bool {
            self.1
        }

        fn run(&mut self, inputs: &[Input]) -> Result<Outputs, String> {
            let Data::F32(values) = &inputs[0].data else {
                return Err("not f32".into());
            };
            self.0
                .lock()
                .unwrap()
                .push(format!("{} x{}", self.2, inputs[0].shape[0]));
            Ok(vec![("out".into(), values.iter().step_by(2).copied().collect())])
        }
    }

    impl Runtime for Echo {
        fn backends(&self) -> Vec<Backend> {
            vec![Backend::Cpu]
        }

        fn load(&self, model: &Path, _: Backend) -> Result<Box<dyn Session>, String> {
            let name = model.file_name().unwrap().to_string_lossy().to_string();
            self.log.lock().unwrap().push(format!("load {name}"));
            Ok(Box::new(EchoSession(self.log.clone(), self.batched, name)))
        }
    }

    fn file(name: &str, cost: Cost, chosen: Option<Backend>) -> FileReport {
        FileReport {
            name: format!("m@1/{name}"),
            backends: vec![(Backend::Cpu, Verdict::Passed { cosine: 1.0 })],
            chosen,
            cost,
        }
    }

    const MB: u64 = 1 << 20;

    fn cost(resident: u64, item: u64) -> Cost {
        Cost {
            load: resident * 3 / 2,
            resident,
            item,
        }
    }

    /// Items of shape [1, 2] whose first value is their number.
    fn items(n: u16) -> Vec<Vec<Input>> {
        (0..n)
            .map(|i| {
                vec![Input {
                    name: "x".into(),
                    shape: vec![1, 2],
                    data: Data::F32(vec![f32::from(i), -1.0]),
                }]
            })
            .collect()
    }

    fn log(runtime: &Echo) -> Vec<String> {
        std::mem::take(&mut runtime.log.lock().unwrap())
    }

    #[test]
    fn items_run_in_batches_of_32_8_and_1_and_come_back_in_order() {
        let runtime = Echo {
            batched: true,
            ..Echo::default()
        };
        let pool = Pool::new(
            &runtime,
            Path::new("/m"),
            &[file("a.onnx", cost(MB, MB), Some(Backend::Cpu))],
            64 * MB,
            || 0,
        );
        let outputs = pool.run("m@1/a.onnx", &items(43)).unwrap();
        let firsts: Vec<f32> = outputs.iter().map(|item| item[0].1[0]).collect();
        assert_eq!(firsts, (0..43u16).map(f32::from).collect::<Vec<_>>());
        assert_eq!(outputs[42], [("out".to_string(), vec![42.0])]);
        assert_eq!(
            log(&runtime),
            [
                "load a.onnx",
                "a.onnx x32",
                "a.onnx x8",
                "a.onnx x1",
                "a.onnx x1",
                "a.onnx x1"
            ]
        );
    }

    #[test]
    fn batches_shrink_to_what_the_budget_leaves_and_fixed_models_run_one_by_one() {
        assert_eq!(bucket(100, true, 10, 1000), 32);
        assert_eq!(bucket(100, true, 10, 319), 8);
        assert_eq!(bucket(100, true, 10, 5), 1, "a single item runs whatever it costs");
        assert_eq!(bucket(7, true, 0, u64::MAX), 1);
        assert_eq!(bucket(100, false, 0, u64::MAX), 1);
        let runtime = Echo {
            batched: true,
            ..Echo::default()
        };
        // 40 MB loaded leaves 24 MB: 8 items of 2 MB fit, 32 do not
        let pool = Pool::new(
            &runtime,
            Path::new("/m"),
            &[file("a.onnx", cost(40 * MB, 2 * MB), Some(Backend::Cpu))],
            64 * MB,
            || 0,
        );
        pool.run("m@1/a.onnx", &items(16)).unwrap();
        assert_eq!(log(&runtime)[1..], ["a.onnx x8", "a.onnx x8"]);
        // where the process holds more than the costs say, what it holds counts
        let files = [file("a.onnx", cost(40 * MB, 2 * MB), Some(Backend::Cpu))];
        let pool = Pool::new(&runtime, Path::new("/m"), &files, 64 * MB, || 60 * MB);
        pool.run("m@1/a.onnx", &items(3)).unwrap();
        assert_eq!(log(&runtime)[1..], ["a.onnx x1", "a.onnx x1", "a.onnx x1"]);
    }

    #[test]
    fn a_file_that_does_not_fit_beside_the_others_unloads_the_least_recently_used() {
        let runtime = Echo::default();
        let files = [
            file("a.onnx", cost(20 * MB, 0), Some(Backend::Cpu)),
            file("b.onnx", cost(20 * MB, 0), Some(Backend::Cpu)),
            file("c.onnx", cost(24 * MB, 0), Some(Backend::Cpu)),
        ];
        let pool = Pool::new(&runtime, Path::new("/m"), &files, 64 * MB, || 0);
        for name in ["a", "b", "a"] {
            pool.run(&format!("m@1/{name}.onnx"), &items(1)).unwrap();
        }
        assert_eq!(pool.loaded(), ["m@1/a.onnx", "m@1/b.onnx"], "20 held + 30 to load fits");
        pool.run("m@1/c.onnx", &items(1)).unwrap();
        assert_eq!(
            pool.loaded(),
            ["m@1/a.onnx", "m@1/c.onnx"],
            "40 held + 36 to load does not; b was used least recently"
        );
        assert_eq!(log(&runtime).iter().filter(|l| l.starts_with("load")).count(), 3);
    }

    #[test]
    fn idle_files_unload_and_untested_files_never_run() {
        let runtime = Echo::default();
        let files = [
            file("a.onnx", cost(MB, 0), Some(Backend::Cpu)),
            file("b.onnx", cost(MB, 0), None),
        ];
        let pool = Pool::new(&runtime, Path::new("/m"), &files, 64 * MB, || 0);
        pool.run("m@1/a.onnx", &items(1)).unwrap();
        pool.unload_idle(Instant::now() + IDLE.saturating_sub(Duration::from_secs(1)));
        assert_eq!(pool.loaded(), ["m@1/a.onnx"]);
        pool.unload_idle(Instant::now() + IDLE);
        assert_eq!(pool.loaded(), Vec::<String>::new());
        for name in ["m@1/b.onnx", "m@1/z.onnx"] {
            assert!(pool.run(name, &items(1)).unwrap_err().contains("no self-test"));
        }
    }
}
