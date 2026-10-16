//! Binding-owned embedding handles; model execution remains in Core.

pub struct EmbeddingInfo {
    pub handle: u64,
    pub profile: String,
    pub dimension: u32,
    pub sequence_length: u32,
}

pub struct EmbeddingPart {
    pub kind: String,
    pub text: String,
    pub bytes: Vec<u8>,
}

#[cfg(all(
    any(feature = "litertlm-embeddings", feature = "litertlm-embedding-engine"),
    any(
        target_os = "windows",
        all(target_os = "android", feature = "litertlm-embedding-engine")
    )
))]
mod native {
    use super::{EmbeddingInfo, EmbeddingPart};
    use omnix_core::embedding::{EmbeddingModel, EmbeddingTask};
    use std::{
        collections::HashMap,
        path::Path,
        sync::{
            atomic::{AtomicU64, Ordering},
            Arc, Mutex, OnceLock,
        },
    };
    type Model = Arc<Mutex<Option<Box<dyn EmbeddingModel + Send>>>>;
    static MODELS: OnceLock<Mutex<HashMap<u64, Model>>> = OnceLock::new();
    static NEXT: AtomicU64 = AtomicU64::new(1);
    fn models() -> &'static Mutex<HashMap<u64, Model>> {
        MODELS.get_or_init(|| Mutex::new(HashMap::new()))
    }
    #[flutter_rust_bridge::frb(ignore)]
    pub async fn open(
        model: String,
        tokenizer: String,
        convention: String,
    ) -> Result<EmbeddingInfo, String> {
        tokio::task::spawn_blocking(move || {
            let (model, sequence_length): (Box<dyn EmbeddingModel + Send>, u32) =
                if convention == "gemma2" || convention == "gemma2-multimodal" {
                    #[cfg(feature = "litertlm-embedding-engine")]
                    {
                        (
                        Box::new(
                            if convention == "gemma2-multimodal" {
                                omnix_core::litertlm_embedding::LiteRtLmEmbeddingModel::from_bundled_multimodal(Path::new(&model))
                            } else {
                                omnix_core::litertlm_embedding::LiteRtLmEmbeddingModel::from_bundled(Path::new(&model))
                            }
                            .map_err(|e| e.to_string())?,
                        ),
                        8192,
                    )
                    }
                    #[cfg(not(feature = "litertlm-embedding-engine"))]
                    {
                        return Err(
                        "EmbeddingGemma 2 requires embedding_engine: true in Core Native Assets"
                            .into(),
                    );
                    }
                } else {
                    #[cfg(feature = "litertlm-embeddings")]
                    {
                        use omnix_core::litert_embedding::{
                            LiteRtEmbeddingConvention, LiteRtEmbeddingModel,
                        };
                        let convention = match convention.as_str() {
                            "gemma" => LiteRtEmbeddingConvention::GemmaRetrieval,
                            "gecko-legacy" => LiteRtEmbeddingConvention::LegacyGeckoRetrieval,
                            _ => return Err("Unknown explicit embedding convention".into()),
                        };
                        let model = LiteRtEmbeddingModel::from_bundled(
                            Path::new(&model),
                            Path::new(&tokenizer),
                            convention,
                        )
                        .map_err(|e| e.to_string())?;
                        let sequence_length = model.input_sequence_length() as u32;
                        (Box::new(model), sequence_length)
                    }
                    #[cfg(not(feature = "litertlm-embeddings"))]
                    {
                        let _ = tokenizer;
                        return Err(
                            "Legacy tensor encoders require embeddings: true in Core Native Assets"
                                .into(),
                        );
                    }
                };
            let id = NEXT
                .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |n| n.checked_add(1))
                .map_err(|_| "Embedding handles exhausted")?;
            let info = EmbeddingInfo {
                handle: id,
                profile: model.profile().id.clone(),
                dimension: model.profile().dimension as u32,
                sequence_length,
            };
            models()
                .lock()
                .map_err(|_| "Embedding registry unavailable")?
                .insert(id, Arc::new(Mutex::new(Some(model))));
            Ok(info)
        })
        .await
        .map_err(|_| "Embedding worker failed")?
    }
    #[flutter_rust_bridge::frb(ignore)]
    pub async fn embed(id: u64, text: String, document: bool) -> Result<Vec<f32>, String> {
        let model = models()
            .lock()
            .map_err(|_| "Embedding registry unavailable")?
            .get(&id)
            .cloned()
            .ok_or("Embedding model closed")?;
        tokio::task::spawn_blocking(move || {
            model
                .lock()
                .map_err(|_| "Embedding model unavailable")?
                .as_mut()
                .ok_or("Embedding model closed")?
                .generate_embedding(
                    &text,
                    if document {
                        EmbeddingTask::RetrievalDocument
                    } else {
                        EmbeddingTask::RetrievalQuery
                    },
                )
                .map_err(|e| e.to_string())
        })
        .await
        .map_err(|_| "Embedding worker failed")?
    }
    #[flutter_rust_bridge::frb(ignore)]
    pub async fn close(id: u64) -> Result<(), String> {
        let model = models()
            .lock()
            .map_err(|_| "Embedding registry unavailable")?
            .remove(&id);
        tokio::task::spawn_blocking(move || {
            if let Some(model) = model {
                model
                    .lock()
                    .map_err(|_| "Embedding model unavailable")?
                    .take();
            }
            Ok(())
        })
        .await
        .map_err(|_| "Embedding worker failed")?
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub async fn embed_parts(
        id: u64,
        parts: Vec<EmbeddingPart>,
        document: bool,
    ) -> Result<Vec<f32>, String> {
        let model = models()
            .lock()
            .map_err(|_| "Embedding registry unavailable")?
            .get(&id)
            .cloned()
            .ok_or("Embedding model closed")?;
        tokio::task::spawn_blocking(move || {
            use omnix_core::embedding::EmbeddingInput;
            let inputs: Result<Vec<_>, String> = parts
                .into_iter()
                .map(|part| match part.kind.as_str() {
                    "text" if part.bytes.is_empty() => Ok(EmbeddingInput::Text(part.text)),
                    "image" if part.text.is_empty() => Ok(EmbeddingInput::Image(part.bytes)),
                    "audio" if part.text.is_empty() => Ok(EmbeddingInput::Audio(part.bytes)),
                    _ => Err("Invalid embedding input part".into()),
                })
                .collect();
            model
                .lock()
                .map_err(|_| "Embedding model unavailable")?
                .as_mut()
                .ok_or("Embedding model closed")?
                .generate_multimodal_embedding(
                    &inputs?,
                    if document {
                        EmbeddingTask::RetrievalDocument
                    } else {
                        EmbeddingTask::RetrievalQuery
                    },
                )
                .map_err(|e| e.to_string())
        })
        .await
        .map_err(|_| "Embedding worker failed")?
    }
}

pub async fn embedding_generate_multimodal(
    handle: u64,
    parts: Vec<EmbeddingPart>,
    document: bool,
) -> Result<Vec<f32>, String> {
    #[cfg(all(
        any(feature = "litertlm-embeddings", feature = "litertlm-embedding-engine"),
        any(
            target_os = "windows",
            all(target_os = "android", feature = "litertlm-embedding-engine")
        )
    ))]
    {
        native::embed_parts(handle, parts, document).await
    }
    #[cfg(not(all(
        any(feature = "litertlm-embeddings", feature = "litertlm-embedding-engine"),
        any(
            target_os = "windows",
            all(target_os = "android", feature = "litertlm-embedding-engine")
        )
    )))]
    {
        let _ = (handle, parts, document);
        Err("Native embeddings unavailable".into())
    }
}

pub async fn embedding_open(
    model: String,
    tokenizer: String,
    convention: String,
) -> Result<EmbeddingInfo, String> {
    #[cfg(all(
        any(feature = "litertlm-embeddings", feature = "litertlm-embedding-engine"),
        any(
            target_os = "windows",
            all(target_os = "android", feature = "litertlm-embedding-engine")
        )
    ))]
    {
        native::open(model, tokenizer, convention).await
    }
    #[cfg(not(all(
        any(feature = "litertlm-embeddings", feature = "litertlm-embedding-engine"),
        any(
            target_os = "windows",
            all(target_os = "android", feature = "litertlm-embedding-engine")
        )
    )))]
    {
        let _ = (model, tokenizer, convention);
        Err("Embeddings require an explicit feature and supported native CPU target".into())
    }
}
pub async fn embedding_generate(
    handle: u64,
    text: String,
    document: bool,
) -> Result<Vec<f32>, String> {
    #[cfg(all(
        any(feature = "litertlm-embeddings", feature = "litertlm-embedding-engine"),
        any(
            target_os = "windows",
            all(target_os = "android", feature = "litertlm-embedding-engine")
        )
    ))]
    {
        native::embed(handle, text, document).await
    }
    #[cfg(not(all(
        any(feature = "litertlm-embeddings", feature = "litertlm-embedding-engine"),
        any(
            target_os = "windows",
            all(target_os = "android", feature = "litertlm-embedding-engine")
        )
    )))]
    {
        let _ = (handle, text, document);
        Err("Native embeddings unavailable".into())
    }
}
pub async fn embedding_close(handle: u64) -> Result<(), String> {
    #[cfg(all(
        any(feature = "litertlm-embeddings", feature = "litertlm-embedding-engine"),
        any(
            target_os = "windows",
            all(target_os = "android", feature = "litertlm-embedding-engine")
        )
    ))]
    {
        native::close(handle).await
    }
    #[cfg(not(all(
        any(feature = "litertlm-embeddings", feature = "litertlm-embedding-engine"),
        any(
            target_os = "windows",
            all(target_os = "android", feature = "litertlm-embedding-engine")
        )
    )))]
    {
        let _ = handle;
        Ok(())
    }
}
