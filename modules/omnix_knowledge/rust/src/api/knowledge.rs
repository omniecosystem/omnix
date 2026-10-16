//! Vector boundary: Core executes embeddings; Knowledge enforces document rules.
#[cfg(all(feature = "qdrant", not(target_arch = "wasm32")))]
mod native {
    use omnix_knowledge::{
        qdrant::QdrantKnowledgeStore, AccessScope, EmbeddingProfile, KnowledgeIndex, Record,
        SearchOptions,
    };
    use std::{
        collections::HashMap,
        path::Path,
        sync::{
            atomic::{AtomicU64, Ordering},
            Arc, Mutex, OnceLock,
        },
    };
    type Index = Arc<Mutex<Option<KnowledgeIndex<QdrantKnowledgeStore>>>>;
    static INDEXES: OnceLock<Mutex<HashMap<u64, Index>>> = OnceLock::new();
    static NEXT: AtomicU64 = AtomicU64::new(1);
    fn indexes() -> &'static Mutex<HashMap<u64, Index>> {
        INDEXES.get_or_init(|| Mutex::new(HashMap::new()))
    }
    #[flutter_rust_bridge::frb(ignore)]
    pub async fn open(path: String, profile: String, dimension: u32) -> Result<u64, String> {
        tokio::task::spawn_blocking(move || {
            let profile = EmbeddingProfile {
                id: profile,
                dimension: dimension as usize,
            };
            let store = QdrantKnowledgeStore::open(Path::new(&path), profile.clone())
                .map_err(|e| e.to_string())?;
            let index = KnowledgeIndex::open(store, profile).map_err(|e| e.to_string())?;
            let id = NEXT
                .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |n| n.checked_add(1))
                .map_err(|_| "Knowledge handles exhausted")?;
            indexes()
                .lock()
                .map_err(|_| "Knowledge registry unavailable")?
                .insert(id, Arc::new(Mutex::new(Some(index))));
            Ok(id)
        })
        .await
        .map_err(|_| "Knowledge worker failed")?
    }
    #[flutter_rust_bridge::frb(ignore)]
    pub async fn add(id: u64, record: String, vector: Vec<f32>) -> Result<(), String> {
        let index = get(id)?;
        tokio::task::spawn_blocking(move || {
            let record: Record = serde_json::from_str(&record).map_err(|e| e.to_string())?;
            index
                .lock()
                .map_err(|_| "Knowledge index unavailable")?
                .as_mut()
                .ok_or("Knowledge index closed")?
                .add_vector(record, vector)
                .map_err(|e| e.to_string())
        })
        .await
        .map_err(|_| "Knowledge worker failed")?
    }
    fn get(id: u64) -> Result<Index, String> {
        indexes()
            .lock()
            .map_err(|_| "Knowledge registry unavailable")?
            .get(&id)
            .cloned()
            .ok_or_else(|| "Knowledge index closed".into())
    }
    #[flutter_rust_bridge::frb(ignore)]
    pub async fn search(
        id: u64,
        vector: Vec<f32>,
        top_k: u32,
        threshold: f32,
    ) -> Result<String, String> {
        let index = get(id)?;
        tokio::task::spawn_blocking(move || {
            let guard = index.lock().map_err(|_| "Knowledge index unavailable")?;
            let hits = guard
                .as_ref()
                .ok_or("Knowledge index closed")?
                .search_vector(
                    &vector,
                    SearchOptions {
                        top_k: top_k as usize,
                        threshold,
                        scope: AccessScope::PublicOnly,
                    },
                )
                .map_err(|e| e.to_string())?;
            let results: Vec<_> = hits
                .into_iter()
                .map(|hit| serde_json::json!({"record": hit.record, "similarity": hit.similarity}))
                .collect();
            serde_json::to_string(&results).map_err(|e| e.to_string())
        })
        .await
        .map_err(|_| "Knowledge worker failed")?
    }
    #[flutter_rust_bridge::frb(ignore)]
    pub async fn close(id: u64) -> Result<(), String> {
        let index = indexes()
            .lock()
            .map_err(|_| "Knowledge registry unavailable")?
            .remove(&id);
        tokio::task::spawn_blocking(move || {
            if let Some(index) = index {
                if let Some(mut index) = index
                    .lock()
                    .map_err(|_| "Knowledge index unavailable")?
                    .take()
                {
                    index.flush().map_err(|e| e.to_string())?;
                }
            }
            Ok(())
        })
        .await
        .map_err(|_| "Knowledge worker failed")?
    }
}
pub async fn knowledge_open(path: String, profile: String, dimension: u32) -> Result<u64, String> {
    #[cfg(all(feature = "qdrant", not(target_arch = "wasm32")))]
    {
        native::open(path, profile, dimension).await
    }
    #[cfg(not(all(feature = "qdrant", not(target_arch = "wasm32"))))]
    {
        let _ = (path, profile, dimension);
        Err("Select native Knowledge qdrant support".into())
    }
}
pub async fn knowledge_add(handle: u64, record: String, vector: Vec<f32>) -> Result<(), String> {
    #[cfg(all(feature = "qdrant", not(target_arch = "wasm32")))]
    {
        native::add(handle, record, vector).await
    }
    #[cfg(not(all(feature = "qdrant", not(target_arch = "wasm32"))))]
    {
        let _ = (handle, record, vector);
        Err("Native Knowledge unavailable".into())
    }
}
pub async fn knowledge_search(
    handle: u64,
    vector: Vec<f32>,
    top_k: u32,
    threshold: f32,
) -> Result<String, String> {
    #[cfg(all(feature = "qdrant", not(target_arch = "wasm32")))]
    {
        native::search(handle, vector, top_k, threshold).await
    }
    #[cfg(not(all(feature = "qdrant", not(target_arch = "wasm32"))))]
    {
        let _ = (handle, vector, top_k, threshold);
        Err("Native Knowledge unavailable".into())
    }
}
pub async fn knowledge_close(handle: u64) -> Result<(), String> {
    #[cfg(all(feature = "qdrant", not(target_arch = "wasm32")))]
    {
        native::close(handle).await
    }
    #[cfg(not(all(feature = "qdrant", not(target_arch = "wasm32"))))]
    {
        let _ = handle;
        Ok(())
    }
}
