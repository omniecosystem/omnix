//! Shared native Knowledge composition for Rust hosts and the root bridge.
use crate::core::embedding::{AdmittedEmbeddingModel, ReloadableEmbeddingModel};
use crate::knowledge::{core::OwnedCoreEmbedder, qdrant::QdrantKnowledgeStore};
use crate::{core::litertlm_embedding::LiteRtLmEmbeddingModel, knowledge::*, session::*};
use std::{path::Path, sync::Mutex};

/// Owns one index lease and one encoder, serializing retrieval across sessions.
pub struct NativeLocalKnowledge(
    Mutex<
        LocalKnowledge<
            QdrantKnowledgeStore,
            OwnedCoreEmbedder<
                ReloadableEmbeddingModel<AdmittedEmbeddingModel<LiteRtLmEmbeddingModel>>,
            >,
        >,
    >,
);
impl NativeLocalKnowledge {
    /// Opens existing absolute paths; the host must first release other index owners.
    pub fn open(
        model_path: &Path,
        store_path: &Path,
        options: SearchOptions,
    ) -> Result<Self, SessionError> {
        Self::open_internal(model_path, store_path, options, None, false)
    }
    /// Uses the root engine's gate for encoder initialization and query embeddings.
    pub fn open_with_engine(
        model_path: &Path,
        store_path: &Path,
        options: SearchOptions,
        engine: &Omnix,
    ) -> Result<Self, SessionError> {
        Self::open_internal(model_path, store_path, options, Some(engine), false)
    }
    /// Explicitly allows a new profile-bound index in a host-selected directory.
    pub fn create_with_engine(
        model_path: &Path,
        store_path: &Path,
        options: SearchOptions,
        engine: &Omnix,
    ) -> Result<Self, SessionError> {
        Self::open_internal(model_path, store_path, options, Some(engine), true)
    }
    fn open_internal(
        model_path: &Path,
        store_path: &Path,
        options: SearchOptions,
        engine: Option<&Omnix>,
        create: bool,
    ) -> Result<Self, SessionError> {
        if !model_path.is_absolute()
            || !model_path.is_file()
            || !store_path.is_absolute()
            || (!create
                && (!store_path.is_dir()
                    || !store_path.join("omnix-vector-profile.json").is_file()))
            || options.top_k == 0
            || options.top_k > 16
            || !options.threshold.is_finite()
            || !(-1.0..=1.0).contains(&options.threshold)
        {
            return Err(SessionError::InvalidRequest);
        }
        let (admission, wait) = match engine {
            Some(engine) => (engine.embedding_admission(), engine.embedding_wait()),
            None => (
                crate::core::execution::ExecutionAdmission::new(1, 0)
                    .map_err(|e| SessionError::Retrieval(e.to_string()))?,
                std::time::Duration::ZERO,
            ),
        };
        let path = model_path
            .canonicalize()
            .map_err(|_| SessionError::InvalidRequest)?;
        let metadata = path.metadata().map_err(|_| SessionError::InvalidRequest)?;
        let identity = (metadata.len(), metadata.modified().ok());
        let reload = move || {
            let metadata = path
                .metadata()
                .map_err(|_| crate::core::CoreError::InvalidModelPath)?;
            if (metadata.len(), metadata.modified().ok()) != identity {
                return Err(crate::core::CoreError::BackendFailure(
                    "embedding-artifact-changed".into(),
                ));
            }
            AdmittedEmbeddingModel::load(admission.clone(), wait, || {
                LiteRtLmEmbeddingModel::from_bundled(&path)
            })
        };
        let model = reload()?;
        let embedder = OwnedCoreEmbedder::new(ReloadableEmbeddingModel::new(model, reload));
        let profile = embedder
            .profile()
            .map_err(|e| SessionError::Retrieval(e.to_string()))?;
        if create {
            std::fs::create_dir_all(store_path)
                .map_err(|_| SessionError::Retrieval("knowledge-directory-unavailable".into()))?;
        }
        let store = QdrantKnowledgeStore::open(store_path, profile.clone())
            .map_err(|e| SessionError::Retrieval(e.to_string()))?;
        let index = KnowledgeIndex::open(store, profile)
            .map_err(|e| SessionError::Retrieval(e.to_string()))?;
        Ok(Self(Mutex::new(LocalKnowledge {
            index,
            embedder,
            options,
        })))
    }
}
impl ContextProvider for NativeLocalKnowledge {
    fn release_idle(&self) -> Result<IdleRelease, SessionError> {
        let local = match self.0.try_lock() {
            Ok(local) => local,
            Err(std::sync::TryLockError::WouldBlock) => return Ok(IdleRelease::Busy),
            Err(std::sync::TryLockError::Poisoned(_)) => {
                return Err(SessionError::Retrieval("knowledge unavailable".into()))
            }
        };
        match local.embedder.release_idle().map_err(retrieval_error)? {
            Some(true) => Ok(IdleRelease::Released),
            Some(false) => Ok(IdleRelease::AlreadyReleased),
            None => Ok(IdleRelease::Busy),
        }
    }
    fn index(&self, document: KnowledgeDocument) -> Result<(), SessionError> {
        let mut local = self
            .0
            .lock()
            .map_err(|_| SessionError::Retrieval("knowledge unavailable".into()))?;
        let LocalKnowledge {
            index, embedder, ..
        } = &mut *local;
        index
            .add_text_document(
                Record {
                    id: document.id,
                    document_id: document.document_id,
                    content: document.content,
                    source: Source {
                        title: document.title,
                        location: None,
                    },
                    public: document.public,
                },
                embedder,
                crate::knowledge::text::TextChunkOptions::default(),
            )
            .map_err(retrieval_error)?;
        Ok(())
    }
    fn retrieve(&self, query: &str) -> Result<Vec<ContextSource>, SessionError> {
        let local = self
            .0
            .lock()
            .map_err(|_| SessionError::Retrieval("knowledge unavailable".into()))?;
        local
            .index
            .search_text(query, &local.embedder, local.options)
            .map(|hits| {
                hits.into_iter()
                    .map(|hit| ContextSource {
                        title: hit.record.source.title,
                        content: hit.record.content,
                    })
                    .collect()
            })
            .map_err(retrieval_error)
    }
}

// Preserve explicit admission diagnostics without exposing arbitrary store paths
// or encoder errors through a retrieval response.
fn retrieval_error(error: KnowledgeError) -> SessionError {
    if let KnowledgeError::Backend(message) = error {
        for code in [
            "execution-busy",
            "execution-queue-full",
            "execution-admission-timeout",
            "execution-admission-unavailable",
            "generation-cancelled",
        ] {
            if message == format!("BackendFailure(\"{code}\")") {
                return SessionError::Core(crate::core::CoreError::BackendFailure(code.into()));
            }
        }
    }
    SessionError::Retrieval("knowledge-query-failed".into())
}

#[cfg(test)]
mod admission_tests {
    use super::*;
    #[test]
    fn admission_diagnostic_survives_retrieval_but_unrelated_errors_are_redacted() {
        assert!(
            matches!(retrieval_error(KnowledgeError::Backend("BackendFailure(\"execution-busy\")".into())), SessionError::Core(crate::core::CoreError::BackendFailure(code)) if code == "execution-busy")
        );
        assert!(
            matches!(retrieval_error(KnowledgeError::Backend("private store path".into())), SessionError::Retrieval(code) if code == "knowledge-query-failed")
        );
    }
}
