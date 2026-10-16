// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! Model execution only. Document storage, visibility and RAG belong elsewhere.
use crate::CoreError;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EmbeddingProfile {
    /// Identity of weights, tokenizer, preprocessing and output convention.
    pub id: String,
    pub dimension: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum EmbeddingTask {
    RetrievalQuery,
    RetrievalDocument,
}

/// Ordered model inputs. Images and audio are encoded bytes supported by the
/// runtime, not paths or container documents. Hosts extract video frames.
#[derive(Clone, Debug, PartialEq)]
pub enum EmbeddingInput {
    Text(String),
    Image(Vec<u8>),
    Audio(Vec<u8>),
}

pub fn validate_embedding_inputs(inputs: &[EmbeddingInput]) -> Result<(), CoreError> {
    if inputs.is_empty() || inputs.len() > 128 {
        return Err(CoreError::InvalidRequest);
    }
    let mut bytes = 0usize;
    for input in inputs {
        let size = match input {
            EmbeddingInput::Text(text) => {
                if text.trim().is_empty() || text.contains('\0') {
                    return Err(CoreError::InvalidRequest);
                }
                text.len()
            }
            EmbeddingInput::Image(data) => {
                if data.len() > 8 * 1024 * 1024 {
                    return Err(CoreError::InvalidRequest);
                }
                crate::message::validate_image(data)?;
                data.len()
            }
            EmbeddingInput::Audio(data) => {
                crate::message::validate_wav(data)?;
                data.len()
            }
        };
        bytes = bytes.checked_add(size).ok_or(CoreError::InvalidRequest)?;
        if size == 0 || bytes > 64 * 1024 * 1024 {
            return Err(CoreError::InvalidRequest);
        }
    }
    Ok(())
}

pub trait EmbeddingModel {
    fn profile(&self) -> &EmbeddingProfile;
    fn generate_embedding(
        &mut self,
        text: &str,
        task: EmbeddingTask,
    ) -> Result<Vec<f32>, CoreError>;

    /// Unsupported encoders reject media explicitly rather than discarding it.
    fn generate_multimodal_embedding(
        &mut self,
        inputs: &[EmbeddingInput],
        task: EmbeddingTask,
    ) -> Result<Vec<f32>, CoreError> {
        validate_embedding_inputs(inputs)?;
        match inputs {
            [EmbeddingInput::Text(text)] => self.generate_embedding(text, task),
            _ => Err(CoreError::BackendFailure(
                "multimodal-embedding-unsupported".into(),
            )),
        }
    }
}

/// An explicitly releasable encoder with a host-supplied reload factory.
/// Exclusive mutable access prevents unloading during embedding execution.
/// Reload must preserve weights, tokenizer and output profile identity.
pub struct ReloadableEmbeddingModel<M> {
    model: Option<M>,
    profile: EmbeddingProfile,
    reload: Box<dyn FnMut() -> Result<M, CoreError> + Send>,
}
impl<M: EmbeddingModel> ReloadableEmbeddingModel<M> {
    pub fn new(model: M, reload: impl FnMut() -> Result<M, CoreError> + Send + 'static) -> Self {
        Self {
            profile: model.profile().clone(),
            model: Some(model),
            reload: Box::new(reload),
        }
    }
    /// Drops a resident encoder, returning whether a model was actually released.
    /// Does not delete artifacts or promise that the OS immediately reclaims RAM.
    pub fn release(&mut self) -> bool {
        self.model.take().is_some()
    }
}
impl<M: EmbeddingModel> EmbeddingModel for ReloadableEmbeddingModel<M> {
    fn profile(&self) -> &EmbeddingProfile {
        &self.profile
    }
    fn generate_embedding(
        &mut self,
        text: &str,
        task: EmbeddingTask,
    ) -> Result<Vec<f32>, CoreError> {
        if self.model.is_none() {
            let model = (self.reload)()?;
            if model.profile() != &self.profile {
                return Err(CoreError::BackendFailure(
                    "embedding-reload-profile-mismatch".into(),
                ));
            }
            self.model = Some(model);
        }
        self.model
            .as_mut()
            .expect("encoder restored")
            .generate_embedding(text, task)
    }

    fn generate_multimodal_embedding(
        &mut self,
        inputs: &[EmbeddingInput],
        task: EmbeddingTask,
    ) -> Result<Vec<f32>, CoreError> {
        validate_embedding_inputs(inputs)?;
        if self.model.is_none() {
            let model = (self.reload)()?;
            if model.profile() != &self.profile {
                return Err(CoreError::BackendFailure(
                    "embedding-reload-profile-mismatch".into(),
                ));
            }
            self.model = Some(model);
        }
        self.model
            .as_mut()
            .expect("encoder restored")
            .generate_multimodal_embedding(inputs, task)
    }
}

/// Admits embedding execution using a host-supplied gate, independent of runtime.
/// This does not own document storage or impose a process-wide scheduler.
pub struct AdmittedEmbeddingModel<M> {
    model: M,
    admission: crate::execution::ExecutionAdmission,
    wait: std::time::Duration,
}
impl<M: EmbeddingModel> AdmittedEmbeddingModel<M> {
    /// Wraps an already loaded model without acquiring a loading slot.
    pub fn new(
        model: M,
        admission: crate::execution::ExecutionAdmission,
        wait: std::time::Duration,
    ) -> Self {
        Self {
            model,
            admission,
            wait,
        }
    }
    /// Admits native initialization and releases its slot before returning ownership.
    pub fn load(
        admission: crate::execution::ExecutionAdmission,
        wait: std::time::Duration,
        load: impl FnOnce() -> Result<M, CoreError>,
    ) -> Result<Self, CoreError> {
        let permit = admission
            .acquire(&std::sync::atomic::AtomicBool::new(false), wait)
            .map_err(|error| CoreError::BackendFailure(error.to_string()))?;
        let model = load()?;
        drop(permit);
        Ok(Self::new(model, admission, wait))
    }
    /// Observes cancellation while awaiting admission, not during native embedding.
    /// The underlying synchronous embedding contract has no interruption handle.
    pub fn generate_embedding_cancellable(
        &mut self,
        text: &str,
        task: EmbeddingTask,
        cancel: &std::sync::atomic::AtomicBool,
    ) -> Result<Vec<f32>, CoreError> {
        let _permit = self
            .admission
            .acquire(cancel, self.wait)
            .map_err(|error| CoreError::BackendFailure(error.to_string()))?;
        self.model.generate_embedding(text, task)
    }
}
impl<M: EmbeddingModel> EmbeddingModel for AdmittedEmbeddingModel<M> {
    fn profile(&self) -> &EmbeddingProfile {
        self.model.profile()
    }
    fn generate_embedding(
        &mut self,
        text: &str,
        task: EmbeddingTask,
    ) -> Result<Vec<f32>, CoreError> {
        self.generate_embedding_cancellable(text, task, &std::sync::atomic::AtomicBool::new(false))
    }

    fn generate_multimodal_embedding(
        &mut self,
        inputs: &[EmbeddingInput],
        task: EmbeddingTask,
    ) -> Result<Vec<f32>, CoreError> {
        validate_embedding_inputs(inputs)?;
        let _permit = self
            .admission
            .acquire(&std::sync::atomic::AtomicBool::new(false), self.wait)
            .map_err(|error| CoreError::BackendFailure(error.to_string()))?;
        self.model.generate_multimodal_embedding(inputs, task)
    }
}

/// Validate the final vector without altering the model's pooled output.
pub fn validate_final(vector: &[f32], dimension: usize) -> Result<(), CoreError> {
    if vector.len() != dimension
        || dimension == 0
        || vector.iter().any(|v| !v.is_finite())
        || !vector.iter().any(|v| *v != 0.0)
    {
        return Err(CoreError::BackendFailure("invalid-embedding-output".into()));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn media_is_bounded_and_unsupported_encoders_never_drop_it() {
        assert!(validate_embedding_inputs(&[]).is_err());
        assert!(validate_embedding_inputs(&[EmbeddingInput::Image(vec![])]).is_err());
        assert!(validate_embedding_inputs(&[EmbeddingInput::Audio(vec![])]).is_err());
        assert!(validate_embedding_inputs(&[EmbeddingInput::Text("\0".into())]).is_err());
        let mut model = spy(Arc::new(AtomicUsize::new(0)));
        let mut png = b"\x89PNG\r\n\x1a\n\0\0\0\rIHDR".to_vec();
        png.extend(1u32.to_be_bytes());
        png.extend(1u32.to_be_bytes());
        png.resize(33, 0);
        assert!(
            matches!(model.generate_multimodal_embedding(&[EmbeddingInput::Image(png)], EmbeddingTask::RetrievalDocument), Err(CoreError::BackendFailure(code)) if code == "multimodal-embedding-unsupported")
        );
    }
    use crate::execution::ExecutionAdmission;
    use std::{
        sync::{
            atomic::{AtomicBool, AtomicUsize, Ordering},
            Arc,
        },
        time::{Duration, Instant},
    };
    struct Spy {
        profile: EmbeddingProfile,
        calls: Arc<AtomicUsize>,
    }
    impl EmbeddingModel for Spy {
        fn profile(&self) -> &EmbeddingProfile {
            &self.profile
        }
        fn generate_embedding(
            &mut self,
            text: &str,
            _: EmbeddingTask,
        ) -> Result<Vec<f32>, CoreError> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            if text == "panic" {
                panic!("test native embedding panic");
            }
            if text.is_empty() {
                return Err(CoreError::InvalidRequest);
            }
            Ok(vec![3.0, 4.0])
        }
    }
    fn spy(calls: Arc<AtomicUsize>) -> Spy {
        Spy {
            profile: EmbeddingProfile {
                id: "unchanged-profile".into(),
                dimension: 2,
            },
            calls,
        }
    }
    #[test]
    fn embedding_admission_preserves_vectors_and_releases_on_failure() {
        let gate = ExecutionAdmission::new(1, 0).unwrap();
        let calls = Arc::new(AtomicUsize::new(0));
        let mut model = AdmittedEmbeddingModel::load(gate.clone(), Duration::ZERO, || {
            assert_eq!(gate.snapshot().unwrap().active, 1);
            Ok(spy(calls.clone()))
        })
        .unwrap();
        assert_eq!(model.profile().id, "unchanged-profile");
        let permit = gate
            .acquire(&AtomicBool::new(false), Duration::ZERO)
            .unwrap();
        for task in [
            EmbeddingTask::RetrievalQuery,
            EmbeddingTask::RetrievalDocument,
        ] {
            assert!(
                matches!(model.generate_embedding("text", task), Err(CoreError::BackendFailure(code)) if code == "execution-busy")
            );
        }
        assert_eq!(calls.load(Ordering::SeqCst), 0);
        assert!(
            matches!(AdmittedEmbeddingModel::load(gate.clone(), Duration::ZERO, || -> Result<Spy, CoreError> { panic!("rejected loader") }), Err(CoreError::BackendFailure(code)) if code == "execution-busy")
        );
        drop(permit);
        assert_eq!(
            model
                .generate_embedding("text", EmbeddingTask::RetrievalQuery)
                .unwrap(),
            [3.0, 4.0]
        );
        assert_eq!(
            model
                .generate_embedding("", EmbeddingTask::RetrievalDocument)
                .unwrap_err(),
            CoreError::InvalidRequest
        );
        assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _ = model.generate_embedding("panic", EmbeddingTask::RetrievalDocument);
        }))
        .is_err());
        assert_eq!(gate.snapshot().unwrap().active, 0);
        assert!(matches!(
            AdmittedEmbeddingModel::load(
                gate.clone(),
                Duration::ZERO,
                || -> Result<Spy, CoreError> { Err(CoreError::InvalidRequest) }
            ),
            Err(CoreError::InvalidRequest)
        ));
        assert_eq!(gate.snapshot().unwrap().active, 0);
    }
    #[test]
    fn cancelled_queued_embedding_never_invokes_runtime() {
        let gate = ExecutionAdmission::new(1, 1).unwrap();
        let calls = Arc::new(AtomicUsize::new(0));
        let cancel = Arc::new(AtomicBool::new(false));
        let mut model =
            AdmittedEmbeddingModel::new(spy(calls.clone()), gate.clone(), Duration::from_secs(5));
        let permit = gate
            .acquire(&AtomicBool::new(false), Duration::ZERO)
            .unwrap();
        let thread_cancel = cancel.clone();
        let thread = std::thread::spawn(move || {
            model.generate_embedding_cancellable(
                "text",
                EmbeddingTask::RetrievalQuery,
                &thread_cancel,
            )
        });
        let deadline = Instant::now() + Duration::from_secs(5);
        while gate.snapshot().unwrap().waiting != 1 {
            assert!(Instant::now() < deadline, "embedding did not queue");
            std::thread::yield_now();
        }
        cancel.store(true, Ordering::SeqCst);
        assert!(
            matches!(thread.join().unwrap(), Err(CoreError::BackendFailure(code)) if code == "generation-cancelled")
        );
        assert_eq!(calls.load(Ordering::SeqCst), 0);
        assert_eq!(gate.snapshot().unwrap().waiting, 0);
        drop(permit);
        assert_eq!(gate.snapshot().unwrap().active, 0);
    }
    #[test]
    fn queued_embedding_runs_after_inference_capacity_is_released() {
        let gate = ExecutionAdmission::new(1, 1).unwrap();
        let calls = Arc::new(AtomicUsize::new(0));
        let mut model =
            AdmittedEmbeddingModel::new(spy(calls.clone()), gate.clone(), Duration::from_secs(5));
        let permit = gate
            .acquire(&AtomicBool::new(false), Duration::ZERO)
            .unwrap();
        let thread = std::thread::spawn(move || {
            model.generate_embedding("text", EmbeddingTask::RetrievalDocument)
        });
        let deadline = Instant::now() + Duration::from_secs(5);
        while gate.snapshot().unwrap().waiting != 1 {
            assert!(Instant::now() < deadline, "embedding did not queue");
            std::thread::yield_now();
        }
        drop(permit);
        assert_eq!(thread.join().unwrap().unwrap(), [3.0, 4.0]);
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        assert_eq!(gate.snapshot().unwrap().active, 0);
    }
    #[test]
    fn validates_without_renormalizing_graph_output() {
        let vector = vec![3.0, 4.0];
        assert!(validate_final(&vector, 2).is_ok());
        assert_eq!(vector, [3.0, 4.0]);
        for invalid in [vec![0.0, 0.0], vec![f32::NAN, 1.0], vec![1.0]] {
            assert!(validate_final(&invalid, 2).is_err());
        }
    }
    #[test]
    fn released_encoder_reloads_once_and_preserves_profile() {
        let calls = Arc::new(AtomicUsize::new(0));
        let loads = Arc::new(AtomicUsize::new(0));
        let reloads = loads.clone();
        let reload_calls = calls.clone();
        let mut model = ReloadableEmbeddingModel::new(spy(calls.clone()), move || {
            reloads.fetch_add(1, Ordering::SeqCst);
            Ok(spy(reload_calls.clone()))
        });
        assert!(model.release());
        assert!(!model.release());
        assert_eq!(model.profile().id, "unchanged-profile");
        assert_eq!(loads.load(Ordering::SeqCst), 0);
        for _ in 0..2 {
            assert_eq!(
                model
                    .generate_embedding("text", EmbeddingTask::RetrievalQuery)
                    .unwrap(),
                [3.0, 4.0]
            );
        }
        assert_eq!(loads.load(Ordering::SeqCst), 1);
        assert_eq!(calls.load(Ordering::SeqCst), 2);
    }
    #[test]
    fn release_actually_drops_the_native_model_owner() {
        struct Owned(Spy, Arc<AtomicUsize>);
        impl Drop for Owned {
            fn drop(&mut self) {
                self.1.fetch_add(1, Ordering::SeqCst);
            }
        }
        impl EmbeddingModel for Owned {
            fn profile(&self) -> &EmbeddingProfile {
                self.0.profile()
            }
            fn generate_embedding(
                &mut self,
                text: &str,
                task: EmbeddingTask,
            ) -> Result<Vec<f32>, CoreError> {
                self.0.generate_embedding(text, task)
            }
        }
        let drops = Arc::new(AtomicUsize::new(0));
        let reloaded_drops = drops.clone();
        let mut model = ReloadableEmbeddingModel::new(
            Owned(spy(Arc::new(AtomicUsize::new(0))), drops.clone()),
            move || {
                Ok(Owned(
                    spy(Arc::new(AtomicUsize::new(0))),
                    reloaded_drops.clone(),
                ))
            },
        );
        assert!(model.release());
        assert_eq!(drops.load(Ordering::SeqCst), 1);
        assert!(!model.release());
        model
            .generate_embedding("text", EmbeddingTask::RetrievalQuery)
            .unwrap();
        drop(model);
        assert_eq!(drops.load(Ordering::SeqCst), 2);
    }
    #[test]
    fn failed_reload_remains_released_and_does_not_change_profile() {
        let attempts = Arc::new(AtomicUsize::new(0));
        let observed = attempts.clone();
        let mut model =
            ReloadableEmbeddingModel::new(spy(Arc::new(AtomicUsize::new(0))), move || {
                if observed.fetch_add(1, Ordering::SeqCst) == 0 {
                    return Err(CoreError::InvalidModelPath);
                }
                let mut other = spy(Arc::new(AtomicUsize::new(0)));
                other.profile.id = "different-weights".into();
                Ok(other)
            });
        model.release();
        assert_eq!(
            model
                .generate_embedding("text", EmbeddingTask::RetrievalQuery)
                .unwrap_err(),
            CoreError::InvalidModelPath
        );
        assert!(
            matches!(model.generate_embedding("text", EmbeddingTask::RetrievalQuery), Err(CoreError::BackendFailure(code)) if code == "embedding-reload-profile-mismatch")
        );
        assert!(!model.release());
        assert_eq!(model.profile().id, "unchanged-profile");
    }
}
