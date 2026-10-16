// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! Thin async bridge to the independent storage module.

#[cfg(all(feature = "sqlite", not(target_arch = "wasm32")))]
mod native {
    use omnix_storage::ConversationStore;
    use std::{
        collections::HashMap,
        path::Path,
        sync::{
            atomic::{AtomicU64, Ordering},
            Arc, Mutex, OnceLock,
        },
    };
    type Store = Arc<Mutex<Option<ConversationStore>>>;
    static STORES: OnceLock<Mutex<HashMap<u64, Store>>> = OnceLock::new();
    static NEXT: AtomicU64 = AtomicU64::new(1);
    fn stores() -> &'static Mutex<HashMap<u64, Store>> {
        STORES.get_or_init(|| Mutex::new(HashMap::new()))
    }
    #[flutter_rust_bridge::frb(ignore)]
    pub async fn open(path: String) -> Result<u64, String> {
        tokio::task::spawn_blocking(move || {
            let store = ConversationStore::open(Path::new(&path))?;
            let id = NEXT.fetch_add(1, Ordering::Relaxed);
            stores()
                .lock()
                .map_err(|_| "Storage registry unavailable")?
                .insert(id, Arc::new(Mutex::new(Some(store))));
            Ok(id)
        })
        .await
        .map_err(|_| "Storage worker failed")?
    }
    #[flutter_rust_bridge::frb(ignore)]
    pub async fn request(id: u64, operation: String, payload: String) -> Result<String, String> {
        let store = stores()
            .lock()
            .map_err(|_| "Storage registry unavailable")?
            .get(&id)
            .cloned()
            .ok_or("Conversation store is closed")?;
        tokio::task::spawn_blocking(move || {
            let mut guard = store.lock().map_err(|_| "Storage connection unavailable")?;
            let store = guard.as_mut().ok_or("Conversation store is closed")?;
            match operation.as_str() {
                "records" => Ok(format!("[{}]", store.records()?.join(","))),
                "read" => Ok(store.read(&payload)?.unwrap_or_else(|| "null".into())),
                "write" => {
                    store.write(&payload)?;
                    Ok("null".into())
                }
                "delete" => {
                    store.delete(&payload)?;
                    Ok("null".into())
                }
                _ => Err("Unknown storage operation".into()),
            }
        })
        .await
        .map_err(|_| "Storage worker failed")?
    }
    #[flutter_rust_bridge::frb(ignore)]
    pub async fn close(id: u64) -> Result<(), String> {
        let store = stores()
            .lock()
            .map_err(|_| "Storage registry unavailable")?
            .remove(&id);
        tokio::task::spawn_blocking(move || {
            if let Some(store) = store {
                if let Some(connection) = store
                    .lock()
                    .map_err(|_| "Storage connection unavailable")?
                    .take()
                {
                    connection.close()?;
                }
            }
            Ok(())
        })
        .await
        .map_err(|_| "Storage worker failed")?
    }
}

pub async fn storage_open(path: String) -> Result<u64, String> {
    #[cfg(all(feature = "sqlite", not(target_arch = "wasm32")))]
    {
        native::open(path).await
    }
    #[cfg(not(all(feature = "sqlite", not(target_arch = "wasm32"))))]
    {
        let _ = path;
        Err("SQLite was not selected or is unsupported on this platform".into())
    }
}
pub async fn storage_request(
    id: u64,
    operation: String,
    payload: String,
) -> Result<String, String> {
    #[cfg(all(feature = "sqlite", not(target_arch = "wasm32")))]
    {
        native::request(id, operation, payload).await
    }
    #[cfg(not(all(feature = "sqlite", not(target_arch = "wasm32"))))]
    {
        let _ = (id, operation, payload);
        Err("SQLite was not selected or is unsupported on this platform".into())
    }
}
pub async fn storage_close(id: u64) -> Result<(), String> {
    #[cfg(all(feature = "sqlite", not(target_arch = "wasm32")))]
    {
        native::close(id).await
    }
    #[cfg(not(all(feature = "sqlite", not(target_arch = "wasm32"))))]
    {
        let _ = id;
        Ok(())
    }
}
