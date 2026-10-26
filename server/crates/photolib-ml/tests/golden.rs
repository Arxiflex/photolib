//! The self-test on ONNX Runtime: the registry's golden samples on its CPU, and an accelerator that is wrong.

use std::path::Path;

use photolib_ml::{Backend, Outputs, Runtime, Session, Verdict, self_test};

#[test]
fn every_server_file_reproduces_its_golden_sample_on_the_cpu() {
    let (library, dir, models) = photolib_ml::testing::onnx();
    let ort = photolib_ml::Ort::load(&library).unwrap();
    assert_eq!(ort.backends().last(), Some(&Backend::Cpu));
    let reports = self_test(ort, dir.path(), &models);
    assert!(reports.len() >= 2, "{reports:?}");
    for report in reports {
        let cpu = report.backends.iter().find(|(b, _)| *b == Backend::Cpu);
        assert!(
            matches!(cpu, Some((_, Verdict::Passed { cosine })) if *cosine > 0.9999),
            "{report:?}"
        );
        assert!(report.chosen.is_some(), "{report:?}");
        assert!(
            report.cost.resident > 0 && report.cost.load >= report.cost.resident,
            "{report:?}"
        );
    }
}

/// ONNX Runtime's CPU, and an "OpenVINO" that is the CPU with every other output value negated.
struct Broken(&'static photolib_ml::Ort);

struct Negated(Box<dyn Session>);

impl Session for Negated {
    fn batched(&self) -> bool {
        self.0.batched()
    }

    fn run(&mut self, inputs: &[photolib_ml::Input]) -> Result<Outputs, String> {
        let mut outputs = self.0.run(inputs)?;
        for (_, values) in &mut outputs {
            values.iter_mut().step_by(2).for_each(|v| *v = -*v);
        }
        Ok(outputs)
    }
}

impl Runtime for Broken {
    fn backends(&self) -> Vec<Backend> {
        vec![Backend::OpenVino, Backend::Cpu]
    }

    fn load(&self, model: &Path, backend: Backend) -> Result<Box<dyn Session>, String> {
        let session = self.0.load(model, Backend::Cpu)?;
        Ok(if backend == Backend::Cpu {
            session
        } else {
            Box::new(Negated(session))
        })
    }
}

#[test]
fn an_accelerator_with_wrong_outputs_is_disabled_and_the_cpu_runs_every_model() {
    let (library, dir, models) = photolib_ml::testing::onnx();
    let ort = photolib_ml::Ort::load(&library).unwrap();
    for report in self_test(&Broken(ort), dir.path(), &models) {
        let [
            (Backend::OpenVino, Verdict::Wrong { cosine }),
            (Backend::Cpu, Verdict::Passed { .. }),
        ] = report.backends[..]
        else {
            panic!("{report:?}");
        };
        assert!(cosine < 0.99, "{report:?}");
        assert_eq!(report.chosen, Some(Backend::Cpu), "{report:?}");
    }
}
