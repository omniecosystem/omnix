// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! Core executes models; adapters connect them to Knowledge retrieval.
use crate::{Embedder, EmbeddingProfile, KnowledgeError};
use omnix_core::embedding::{EmbeddingModel, EmbeddingTask};
use std::cell::RefCell;
use std::sync::Mutex;

/// Owns a model lease and serializes embedding execution for shared sessions.
/// Unlike the borrowed adapter, this can be registered in a long-lived native
/// context provider when its model is Send. No runtime is selected implicitly.
pub struct OwnedCoreEmbedder<M: EmbeddingModel + Send> {
    model: Mutex<M>,
    profile: EmbeddingProfile,
}
impl<M: EmbeddingModel + Send> OwnedCoreEmbedder<M> {
    pub fn new(model: M) -> Self {
        let profile = EmbeddingProfile {
            id: model.profile().id.clone(),
            dimension: model.profile().dimension,
        };
        Self {
            model: Mutex::new(model),
            profile,
        }
    }
    fn run(&self, text: &str, task: EmbeddingTask) -> Result<Vec<f32>, KnowledgeError> {
        self.model
            .lock()
            .map_err(|_| KnowledgeError::Backend("embedding provider poisoned".into()))?
            .generate_embedding(text, task)
            .map_err(|e| KnowledgeError::Backend(e.to_string()))
    }
}
impl<M: EmbeddingModel + Send> Embedder for OwnedCoreEmbedder<M> {
    fn profile(&self) -> Result<EmbeddingProfile, KnowledgeError> {
        Ok(self.profile.clone())
    }
    fn embed_document(&self, text: &str) -> Result<Vec<f32>, KnowledgeError> {
        self.run(text, EmbeddingTask::RetrievalDocument)
    }
    fn embed_query(&self, text: &str) -> Result<Vec<f32>, KnowledgeError> {
        self.run(text, EmbeddingTask::RetrievalQuery)
    }
}

impl<M: EmbeddingModel + Send>
    OwnedCoreEmbedder<omnix_core::embedding::ReloadableEmbeddingModel<M>>
{
    /// Never waits for an in-flight embedding. None means release was deferred.
    pub fn release_idle(&self) -> Result<Option<bool>, KnowledgeError> {
        match self.model.try_lock() {
            Ok(mut model) => Ok(Some(model.release())),
            Err(std::sync::TryLockError::WouldBlock) => Ok(None),
            Err(std::sync::TryLockError::Poisoned(_)) => Err(KnowledgeError::Backend(
                "embedding provider poisoned".into(),
            )),
        }
    }
}

pub struct CoreEmbedder<'a, M: EmbeddingModel> {
    model: RefCell<&'a mut M>,
}
impl<'a, M: EmbeddingModel> CoreEmbedder<'a, M> {
    pub fn new(model: &'a mut M) -> Self {
        Self {
            model: RefCell::new(model),
        }
    }
    fn run(&self, text: &str, task: EmbeddingTask) -> Result<Vec<f32>, KnowledgeError> {
        self.model
            .try_borrow_mut()
            .map_err(|_| KnowledgeError::Backend("embedding provider already borrowed".into()))?
            .generate_embedding(text, task)
            .map_err(|e| KnowledgeError::Backend(e.to_string()))
    }
}
impl<M: EmbeddingModel> Embedder for CoreEmbedder<'_, M> {
    fn profile(&self) -> Result<EmbeddingProfile, KnowledgeError> {
        let model = self
            .model
            .try_borrow()
            .map_err(|_| KnowledgeError::Backend("embedding provider already borrowed".into()))?;
        let profile = model.profile();
        Ok(EmbeddingProfile {
            id: profile.id.clone(),
            dimension: profile.dimension,
        })
    }
    fn embed_document(&self, text: &str) -> Result<Vec<f32>, KnowledgeError> {
        self.run(text, EmbeddingTask::RetrievalDocument)
    }
    fn embed_query(&self, text: &str) -> Result<Vec<f32>, KnowledgeError> {
        self.run(text, EmbeddingTask::RetrievalQuery)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Model {
        profile: omnix_core::embedding::EmbeddingProfile,
        tasks: Vec<EmbeddingTask>,
    }
    #[test]
    fn idle_release_never_waits_for_encoder_owner_and_reload_keeps_index_profile() {
        let make = || Model {
            profile: omnix_core::embedding::EmbeddingProfile {
                id: "stable".into(),
                dimension: 2,
            },
            tasks: vec![],
        };
        let adapter = OwnedCoreEmbedder::new(omnix_core::embedding::ReloadableEmbeddingModel::new(
            make(),
            move || Ok(make()),
        ));
        let owner = adapter.model.lock().unwrap();
        assert_eq!(adapter.release_idle().unwrap(), None);
        drop(owner);
        assert_eq!(adapter.release_idle().unwrap(), Some(true));
        assert_eq!(adapter.release_idle().unwrap(), Some(false));
        assert_eq!(adapter.embed_query("query").unwrap(), [1.0, 0.0]);
        assert_eq!(adapter.profile().unwrap().id, "stable");
        assert_eq!(adapter.release_idle().unwrap(), Some(true));
    }
    #[test]
    fn owned_adapter_is_shareable_and_preserves_retrieval_conventions() {
        fn assert_shared<T: Send + Sync>() {}
        assert_shared::<OwnedCoreEmbedder<Model>>();
        let adapter = std::sync::Arc::new(OwnedCoreEmbedder::new(Model {
            profile: omnix_core::embedding::EmbeddingProfile {
                id: "weights-tokenizer-convention".into(),
                dimension: 2,
            },
            tasks: vec![],
        }));
        let other = adapter.clone();
        std::thread::spawn(move || {
            other.embed_document("document").unwrap();
        })
        .join()
        .unwrap();
        adapter.embed_query("query").unwrap();
        assert_eq!(adapter.profile().unwrap().dimension, 2);
        assert_eq!(
            adapter.model.lock().unwrap().tasks,
            [
                EmbeddingTask::RetrievalDocument,
                EmbeddingTask::RetrievalQuery
            ]
        );
        assert!(adapter.embed_query("").is_err());
    }
    #[test]
    fn admitted_core_adapter_shares_capacity_without_changing_retrieval_tasks() {
        use omnix_core::{embedding::AdmittedEmbeddingModel, execution::ExecutionAdmission};
        use std::{sync::atomic::AtomicBool, time::Duration};
        let gate = ExecutionAdmission::new(1, 0).unwrap();
        let adapter = OwnedCoreEmbedder::new(AdmittedEmbeddingModel::new(
            Model {
                profile: omnix_core::embedding::EmbeddingProfile {
                    id: "profile".into(),
                    dimension: 2,
                },
                tasks: vec![],
            },
            gate.clone(),
            Duration::ZERO,
        ));
        let permit = gate
            .acquire(&AtomicBool::new(false), Duration::ZERO)
            .unwrap();
        assert_eq!(adapter.profile().unwrap().dimension, 2);
        assert!(
            matches!(adapter.embed_document("document"), Err(KnowledgeError::Backend(code)) if code.contains("execution-busy"))
        );
        assert!(
            matches!(adapter.embed_query("query"), Err(KnowledgeError::Backend(code)) if code.contains("execution-busy"))
        );
        drop(permit);
        assert_eq!(adapter.embed_document("document").unwrap(), [1.0, 0.0]);
        assert_eq!(adapter.embed_query("query").unwrap(), [1.0, 0.0]);
        assert_eq!(gate.snapshot().unwrap().active, 0);
    }
    impl EmbeddingModel for Model {
        fn profile(&self) -> &omnix_core::embedding::EmbeddingProfile {
            &self.profile
        }
        fn generate_embedding(
            &mut self,
            text: &str,
            task: EmbeddingTask,
        ) -> Result<Vec<f32>, omnix_core::CoreError> {
            if text.is_empty() {
                return Err(omnix_core::CoreError::InvalidRequest);
            }
            self.tasks.push(task);
            Ok(vec![1.0, 0.0])
        }
    }
    #[test]
    fn borrows_model_maps_profile_and_distinguishes_tasks() {
        let mut model = Model {
            profile: omnix_core::embedding::EmbeddingProfile {
                id: "weights-tokenizer-convention".into(),
                dimension: 2,
            },
            tasks: vec![],
        };
        {
            let adapter = CoreEmbedder::new(&mut model);
            assert_eq!(
                adapter.profile().unwrap(),
                EmbeddingProfile {
                    id: "weights-tokenizer-convention".into(),
                    dimension: 2
                }
            );
            assert_eq!(adapter.embed_document("document").unwrap(), [1.0, 0.0]);
            assert_eq!(adapter.embed_query("query").unwrap(), [1.0, 0.0]);
            assert!(adapter.embed_query("").is_err());
        }
        // The host retains its model when the adapter is dropped.
        assert_eq!(
            model.tasks,
            [
                EmbeddingTask::RetrievalDocument,
                EmbeddingTask::RetrievalQuery
            ]
        );
    }
}
