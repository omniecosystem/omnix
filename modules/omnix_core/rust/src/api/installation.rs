// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

#[cfg(all(feature = "model-installation", not(target_arch = "wasm32")))]
mod native {
    use omnix_core::installation::{self, ModelSpec, Progress};
    use std::{
        collections::HashMap,
        path::Path,
        sync::{
            atomic::{AtomicBool, AtomicU64, Ordering},
            Arc, Mutex, OnceLock,
        },
    };
    struct Job {
        cancel: AtomicBool,
        progress: Mutex<Progress>,
    }
    static JOBS: OnceLock<Mutex<HashMap<String, Arc<Job>>>> = OnceLock::new();
    static NEXT: AtomicU64 = AtomicU64::new(1);
    fn jobs() -> &'static Mutex<HashMap<String, Arc<Job>>> {
        JOBS.get_or_init(Default::default)
    }
    pub(super) fn start(
        root: String,
        spec: String,
        source: String,
        network: bool,
        token: Option<String>,
    ) -> Result<String, String> {
        let spec: ModelSpec =
            serde_json::from_str(&spec).map_err(|_| "Invalid model specification")?;
        spec.validate()?;
        if !Path::new(&root).is_absolute() {
            return Err("Model store must be absolute".into());
        }
        let id = NEXT.fetch_add(1, Ordering::Relaxed).to_string();
        let job = Arc::new(Job {
            cancel: AtomicBool::new(false),
            progress: Mutex::new(Progress {
                phase: "starting".into(),
                received: 0,
                total: spec.bytes,
                path: None,
                error: None,
            }),
        });
        {
            let mut registry = jobs()
                .lock()
                .map_err(|_| "Installer registry unavailable")?;
            if registry.len() >= 32 {
                return Err("Too many retained installations; release completed jobs".into());
            }
            registry.insert(id.clone(), job.clone());
        }
        let worker = job.clone();
        if std::thread::Builder::new()
            .name("omnix-model-install".into())
            .spawn(move || {
                let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                    installation::install(
                        Path::new(&root),
                        spec,
                        &source,
                        network,
                        token.as_deref(),
                        &worker.cancel,
                        |update| {
                            if let Ok(mut state) = worker.progress.lock() {
                                *state = update;
                            }
                        },
                    )
                }))
                .unwrap_or_else(|_| Err("Installation worker failed".into()));
                if let Ok(mut state) = worker.progress.lock() {
                    match result {
                        Ok(record) => {
                            state.phase = "installed".into();
                            state.received = record.spec.bytes;
                            state.path = Some(record.path);
                        }
                        Err(error) => {
                            state.phase = if worker.cancel.load(Ordering::Acquire) {
                                "cancelled"
                            } else {
                                "failed"
                            }
                            .into();
                            state.error = Some(error);
                        }
                    }
                }
            })
            .is_err()
        {
            jobs()
                .lock()
                .map_err(|_| "Installer registry unavailable")?
                .remove(&id);
            return Err("Cannot start installation worker".into());
        }
        Ok(id)
    }
    pub(super) fn status(id: String) -> Result<String, String> {
        let job = jobs()
            .lock()
            .map_err(|_| "Installer registry unavailable")?
            .get(&id)
            .cloned()
            .ok_or("Unknown installation")?;
        let state = job
            .progress
            .lock()
            .map_err(|_| "Installation state unavailable")?;
        serde_json::to_string(&*state).map_err(|_| "Cannot encode installation progress".into())
    }
    pub(super) fn cancel(id: String) -> Result<(), String> {
        let registry = jobs()
            .lock()
            .map_err(|_| "Installer registry unavailable")?;
        let job = registry.get(&id).ok_or("Unknown installation")?;
        job.cancel.store(true, Ordering::Release);
        Ok(())
    }
    pub(super) fn release(id: String) -> Result<(), String> {
        let mut registry = jobs()
            .lock()
            .map_err(|_| "Installer registry unavailable")?;
        if let Some(job) = registry.get(&id) {
            let state = job
                .progress
                .lock()
                .map_err(|_| "Installation state unavailable")?;
            if !matches!(state.phase.as_str(), "installed" | "failed" | "cancelled") {
                return Err("Cancel and await completion before releasing an installation".into());
            }
        }
        registry.remove(&id);
        Ok(())
    }
    pub(super) fn list(root: String) -> Result<String, String> {
        serde_json::to_string(&installation::list(Path::new(&root))?)
            .map_err(|_| "Cannot encode installed models".into())
    }
    pub(super) fn remove(root: String, spec: String) -> Result<Option<String>, String> {
        let spec: ModelSpec =
            serde_json::from_str(&spec).map_err(|_| "Invalid model specification")?;
        installation::remove(Path::new(&root), spec)
    }
    pub(super) fn adopt(root: String, spec: String, path: String) -> Result<String, String> {
        let spec: ModelSpec =
            serde_json::from_str(&spec).map_err(|_| "Invalid model specification")?;
        serde_json::to_string(&installation::adopt_file(
            Path::new(&root),
            spec,
            Path::new(&path),
            &AtomicBool::new(false),
        )?)
        .map_err(|_| "Cannot encode adopted model".into())
    }
    pub(super) fn reserve(root: String, spec: String) -> Result<String, String> {
        let spec: ModelSpec =
            serde_json::from_str(&spec).map_err(|_| "Invalid model specification")?;
        serde_json::to_string(&installation::reserve_transfer(Path::new(&root), spec)?)
            .map_err(|_| "Cannot encode transfer reservation".into())
    }
    pub(super) fn pending(root: String) -> Result<String, String> {
        serde_json::to_string(&installation::pending_transfers(Path::new(&root))?)
            .map_err(|_| "Cannot encode pending transfers".into())
    }
    pub(super) fn complete(root: String, id: String) -> Result<String, String> {
        serde_json::to_string(&installation::complete_transfer(
            Path::new(&root),
            &id,
            &AtomicBool::new(false),
        )?)
        .map_err(|_| "Cannot encode installed model".into())
    }
}

#[cfg(any(not(feature = "model-installation"), target_arch = "wasm32"))]
mod native {
    pub(super) fn remove(_root: String, _spec: String) -> Result<Option<String>, String> {
        Err("Native model installation is not enabled".into())
    }
    pub(super) fn adopt(_root: String, _spec: String, _path: String) -> Result<String, String> {
        Err("Native model installation is not enabled".into())
    }
    pub(super) fn reserve(_root: String, _spec: String) -> Result<String, String> {
        Err("Native model installation is not enabled".into())
    }
    pub(super) fn pending(_root: String) -> Result<String, String> {
        Err("Native model installation is not enabled".into())
    }
    pub(super) fn complete(_root: String, _id: String) -> Result<String, String> {
        Err("Native model installation is not enabled".into())
    }
    pub(super) fn start(
        _root: String,
        _spec: String,
        _source: String,
        _network: bool,
        _token: Option<String>,
    ) -> Result<String, String> {
        Err("Native model installation is not enabled".into())
    }
    pub(super) fn status(_id: String) -> Result<String, String> {
        Err("Native model installation is not enabled".into())
    }
    pub(super) fn list(_root: String) -> Result<String, String> {
        Err("Native model installation is not enabled".into())
    }
    pub(super) fn cancel(_id: String) -> Result<(), String> {
        Err("Native model installation is not enabled".into())
    }
    pub(super) fn release(_id: String) -> Result<(), String> {
        Err("Native model installation is not enabled".into())
    }
}
pub fn model_install_start(
    root: String,
    spec: String,
    source: String,
    network: bool,
    token: Option<String>,
) -> Result<String, String> {
    native::start(root, spec, source, network, token)
}
pub fn model_install_status(id: String) -> Result<String, String> {
    native::status(id)
}
pub fn model_install_cancel(id: String) -> Result<(), String> {
    native::cancel(id)
}
pub fn model_install_release(id: String) -> Result<(), String> {
    native::release(id)
}
pub fn model_install_list(root: String) -> Result<String, String> {
    native::list(root)
}
pub fn model_install_remove(root: String, spec: String) -> Result<Option<String>, String> {
    native::remove(root, spec)
}
pub fn model_install_adopt(root: String, spec: String, path: String) -> Result<String, String> {
    native::adopt(root, spec, path)
}
pub fn model_transfer_reserve(root: String, spec: String) -> Result<String, String> {
    native::reserve(root, spec)
}
pub fn model_transfer_pending(root: String) -> Result<String, String> {
    native::pending(root)
}
pub fn model_transfer_complete(root: String, id: String) -> Result<String, String> {
    native::complete(root, id)
}
