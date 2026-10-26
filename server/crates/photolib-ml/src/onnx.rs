//! ONNX Runtime through `ort`, loaded from a library file once per process.

use std::{borrow::Cow, path::Path, sync::OnceLock};

use ort::{
    environment::Environment,
    ep::{self, ArenaExtendStrategy, ExecutionProvider, ExecutionProviderDispatch},
    session::{Session as OrtSession, SessionInputValue},
    value::{TensorRef, ValueType},
};

use crate::{Backend, Data, Input, Outputs, Runtime, Session};

/// ONNX Runtime's library, loaded.
pub struct Ort(Environment);

static ORT: OnceLock<Result<Ort, String>> = OnceLock::new();

impl Ort {
    /// ONNX Runtime from `library`, such as `libonnxruntime.so.1.31.0`; the first call's library serves the process.
    pub fn load(library: &Path) -> Result<&'static Self, String> {
        let loaded = ORT.get_or_init(|| {
            let builder = ort::init_from(library).map_err(|e| e.to_string())?;
            builder
                .with_name("photolibd")
                .build()
                .map(Self)
                .map_err(|e| e.to_string())
        });
        loaded.as_ref().map_err(|error| format!("ONNX Runtime: {error}"))
    }
}

/// The CPU without an arena, whose memory would only grow (design 09 §3.2).
fn cpu() -> ExecutionProviderDispatch {
    ep::CPU::default().with_arena_allocator(false).build()
}

impl Runtime for Ort {
    fn backends(&self) -> Vec<Backend> {
        let has = |backend| match backend {
            Backend::Cuda => ep::CUDA::is_available(),
            Backend::OpenVino => ep::OpenVINO::is_available(),
            Backend::Rocm => ep::MIGraphX::is_available(),
            Backend::CoreMl => ep::CoreML::is_available(),
            Backend::Cpu => Ok(true),
        };
        Backend::ORDER
            .into_iter()
            .filter(|b| has(*b).unwrap_or(false))
            .collect()
    }

    fn load(&self, model: &Path, backend: Backend) -> Result<Box<dyn Session>, String> {
        let grows = ArenaExtendStrategy::SameAsRequested;
        let provider = match backend {
            Backend::Cuda => ep::CUDA::default().with_arena_extend_strategy(grows).build(),
            Backend::OpenVino => ep::OpenVINO::default().build(),
            Backend::Rocm => ep::MIGraphX::default().with_arena_extend_strategy(grows).build(),
            Backend::CoreMl => ep::CoreML::default().build(),
            Backend::Cpu => cpu(),
        };
        // ort would otherwise run the model on the CPU, silently, when the provider cannot start.
        let providers = [provider.error_on_failure(), cpu()];
        let failed = |e: &dyn std::fmt::Display| format!("{} on {backend}: {e}", model.display());
        let builder = OrtSession::builder(&self.0).map_err(|e| failed(&e))?;
        let mut builder = builder.with_execution_providers(providers).map_err(|e| failed(&e))?;
        let session = builder.commit_from_file(model).map_err(|e| failed(&e))?;
        Ok(Box::new(Loaded(session)))
    }
}

struct Loaded(OrtSession);

impl Session for Loaded {
    fn batched(&self) -> bool {
        self.0.inputs().iter().all(|input| match input.dtype() {
            ValueType::Tensor { shape, .. } => shape.first() == Some(&-1),
            _ => false,
        })
    }

    fn run(&mut self, inputs: &[Input]) -> Result<Outputs, String> {
        let values = inputs
            .iter()
            .map(|input| {
                let shape = input.shape.clone();
                let value: SessionInputValue<'_> = match &input.data {
                    Data::F32(values) => TensorRef::from_array_view((shape, values.as_slice()))?.into(),
                    Data::I64(values) => TensorRef::from_array_view((shape, values.as_slice()))?.into(),
                };
                Ok((Cow::from(input.name.as_str()), value))
            })
            .collect::<ort::Result<Vec<_>>>()
            .map_err(|e| e.to_string())?;
        let outputs = self.0.run(values).map_err(|e| e.to_string())?;
        outputs
            .iter()
            .map(|(name, value)| {
                let (_, values) = value.try_extract_tensor::<f32>().map_err(|e| format!("{name}: {e}"))?;
                Ok((name.to_string(), values.to_vec()))
            })
            .collect()
    }
}
