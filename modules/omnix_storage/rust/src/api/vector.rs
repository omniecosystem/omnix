// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

#[cfg(all(feature = "qdrant", not(target_arch = "wasm32")))]
mod native {
    use omnix_storage::{QdrantStore, VectorProfile};
    use serde_json::Value;
    use std::{
        collections::HashMap,
        path::Path,
        sync::{
            atomic::{AtomicU64, Ordering},
            Arc, Mutex, OnceLock,
        },
    };

    type Store = Arc<Mutex<Option<QdrantStore>>>;
    static STORES: OnceLock<Mutex<HashMap<u64, Store>>> = OnceLock::new();
    static NEXT: AtomicU64 = AtomicU64::new(1);
    fn stores() -> &'static Mutex<HashMap<u64, Store>> {
        STORES.get_or_init(|| Mutex::new(HashMap::new()))
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub async fn open(path: String, profile: String) -> Result<u64, String> {
        tokio::task::spawn_blocking(move || {
            let profile: VectorProfile =
                serde_json::from_str(&profile).map_err(|e| e.to_string())?;
            let store = QdrantStore::open(Path::new(&path), profile)?;
            let id = NEXT.fetch_add(1, Ordering::Relaxed);
            stores()
                .lock()
                .map_err(|_| "Vector registry unavailable")?
                .insert(id, Arc::new(Mutex::new(Some(store))));
            Ok(id)
        })
        .await
        .map_err(|_| "Vector worker failed")?
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub async fn request(id: u64, operation: String, payload: String) -> Result<String, String> {
        let store = stores()
            .lock()
            .map_err(|_| "Vector registry unavailable")?
            .get(&id)
            .cloned()
            .ok_or("Vector store is closed")?;
        tokio::task::spawn_blocking(move || {
            let mut guard = store.lock().map_err(|_| "Vector connection unavailable")?;
            let store = guard.as_mut().ok_or("Vector store is closed")?;
            let data: Value = serde_json::from_str(&payload).map_err(|e| e.to_string())?;
            let vector = || -> Result<Vec<f32>, String> {
                serde_json::from_value(data.get("vector").cloned().ok_or("Missing vector")?)
                    .map_err(|e| e.to_string())
            };
            let point_id = || {
                data.get("id")
                    .and_then(Value::as_u64)
                    .ok_or_else(|| "Invalid point ID".to_owned())
            };
            match operation.as_str() {
                "upsert" => {
                    let metadata = data
                        .get("metadata")
                        .and_then(Value::as_object)
                        .ok_or("Metadata must be an object")?
                        .clone();
                    store.upsert(point_id()?, vector()?, metadata)?;
                }
                "search" => {
                    let limit = data
                        .get("limit")
                        .and_then(Value::as_u64)
                        .and_then(|v| usize::try_from(v).ok())
                        .ok_or("Invalid search limit")?;
                    let hits = if let Some(filter) = data.get("filter") {
                        let field = filter
                            .get("field")
                            .and_then(Value::as_str)
                            .ok_or("Invalid filter field")?;
                        let value = filter
                            .get("value")
                            .and_then(Value::as_str)
                            .ok_or("Invalid filter value")?;
                        store.search_filtered(vector()?, limit, field, value)?
                    } else {
                        store.search(vector()?, limit)?
                    };
                    return serde_json::to_string(&hits).map_err(|e| e.to_string());
                }
                "delete" => store.delete(point_id()?)?,
                "metadata" => {
                    return serde_json::to_string(&store.read_metadata(point_id()?)?)
                        .map_err(|e| e.to_string());
                }
                "clear" => store.clear()?,
                "flush" => store.flush()?,
                _ => return Err("Unknown vector operation".into()),
            }
            Ok("null".into())
        })
        .await
        .map_err(|_| "Vector worker failed")?
    }

    #[flutter_rust_bridge::frb(ignore)]
    pub async fn close(id: u64) -> Result<(), String> {
        let store = stores()
            .lock()
            .map_err(|_| "Vector registry unavailable")?
            .remove(&id);
        tokio::task::spawn_blocking(move || {
            if let Some(store) = store {
                if let Some(connection) = store
                    .lock()
                    .map_err(|_| "Vector connection unavailable")?
                    .take()
                {
                    connection.flush()?;
                }
            }
            Ok(())
        })
        .await
        .map_err(|_| "Vector worker failed")?
    }
}

pub async fn vector_open(path: String, profile: String) -> Result<u64, String> {
    #[cfg(all(feature = "qdrant", not(target_arch = "wasm32")))]
    {
        native::open(path, profile).await
    }
    #[cfg(not(all(feature = "qdrant", not(target_arch = "wasm32"))))]
    {
        let _ = (path, profile);
        Err("Qdrant was not selected or is unsupported on this platform".into())
    }
}

pub async fn vector_request(id: u64, operation: String, payload: String) -> Result<String, String> {
    #[cfg(all(feature = "qdrant", not(target_arch = "wasm32")))]
    {
        native::request(id, operation, payload).await
    }
    #[cfg(not(all(feature = "qdrant", not(target_arch = "wasm32"))))]
    {
        let _ = (id, operation, payload);
        Err("Qdrant was not selected or is unsupported on this platform".into())
    }
}

pub async fn vector_close(id: u64) -> Result<(), String> {
    #[cfg(all(feature = "qdrant", not(target_arch = "wasm32")))]
    {
        native::close(id).await
    }
    #[cfg(not(all(feature = "qdrant", not(target_arch = "wasm32"))))]
    {
        let _ = id;
        Ok(())
    }
}

#[cfg(all(test, feature = "qdrant", not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    #[test]
    fn bridge_round_trip_reopen_filter_delete_and_closed_handle() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().to_string_lossy().into_owned();
        let runtime = tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap();
        runtime.block_on(async {
            let profile = r#"{"id":"bridge-test-v1","dimension":2}"#.to_owned();
            let handle = vector_open(path.clone(), profile.clone()).await.unwrap();
            vector_request(
                handle,
                "upsert".into(),
                r#"{"id":1,"vector":[1,0],"metadata":{"source":"note"}}"#.into(),
            )
            .await
            .unwrap();
            vector_close(handle).await.unwrap();
            assert!(vector_request(handle, "flush".into(), "{}".into())
                .await
                .is_err());
            let reopened = vector_open(path, profile).await.unwrap();
            let result = vector_request(
                reopened,
                "search".into(),
                r#"{"vector":[1,0],"limit":5,"filter":{"field":"source","value":"note"}}"#.into(),
            )
            .await
            .unwrap();
            let hits: serde_json::Value = serde_json::from_str(&result).unwrap();
            assert_eq!(hits[0]["id"], 1);
            assert_eq!(hits[0]["metadata"]["source"], "note");
            assert!(vector_request(
                reopened,
                "search".into(),
                r#"{"vector":[1],"limit":5}"#.into()
            )
            .await
            .is_err());
            vector_request(reopened, "delete".into(), r#"{"id":1}"#.into())
                .await
                .unwrap();
            let result = vector_request(
                reopened,
                "search".into(),
                r#"{"vector":[1,0],"limit":5}"#.into(),
            )
            .await
            .unwrap();
            assert_eq!(result, "[]");
            vector_request(
                reopened,
                "upsert".into(),
                r#"{"id":2,"vector":[1,0],"metadata":{"source":"private"}}"#.into(),
            )
            .await
            .unwrap();
            let metadata = vector_request(reopened, "metadata".into(), r#"{"id":2}"#.into())
                .await
                .unwrap();
            assert_eq!(
                serde_json::from_str::<serde_json::Value>(&metadata).unwrap()["source"],
                "private"
            );
            vector_request(reopened, "clear".into(), "{}".into())
                .await
                .unwrap();
            assert_eq!(
                vector_request(
                    reopened,
                    "search".into(),
                    r#"{"vector":[1,0],"limit":5}"#.into()
                )
                .await
                .unwrap(),
                "[]"
            );
            vector_close(reopened).await.unwrap();
            vector_close(reopened).await.unwrap();
        });
    }
}
