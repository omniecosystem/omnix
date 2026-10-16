//! Bridge ownership only; execution and recovery remain in Rust.
use flutter_rust_bridge::DartFnFuture;

#[cfg(all(feature = "workflow-local", not(target_arch = "wasm32")))]
mod native {
    use crate::{workflow::*, workflow_runtime::*};
    use std::{
        collections::HashMap,
        sync::{
            atomic::{AtomicBool, AtomicU64, Ordering},
            Arc, Mutex, OnceLock,
        },
    };
    pub(super) struct Entry {
        pub owner: Mutex<(Workflow<StorageJournal>, AuthorizedExecutor)>,
        pub cancel: AtomicBool,
        pub closed: AtomicBool,
    }
    impl Entry {
        pub(super) fn lock(
            &self,
        ) -> Result<std::sync::MutexGuard<'_, (Workflow<StorageJournal>, AuthorizedExecutor)>, String>
        {
            let guard = self.owner.try_lock().map_err(|_| "Workflow busy")?;
            if self.closed.load(Ordering::Acquire) {
                return Err("Workflow closed".into());
            }
            Ok(guard)
        }
    }
    static ENTRIES: OnceLock<Mutex<HashMap<u64, Arc<Entry>>>> = OnceLock::new();
    static NEXT: AtomicU64 = AtomicU64::new(1);
    pub(super) fn entries() -> &'static Mutex<HashMap<u64, Arc<Entry>>> {
        ENTRIES.get_or_init(Default::default)
    }
    pub(super) fn entry(id: u64) -> Result<Arc<Entry>, String> {
        entries()
            .lock()
            .map_err(|_| "Workflow registry unavailable")?
            .get(&id)
            .cloned()
            .ok_or("Workflow closed".into())
    }
    pub(super) fn open(
        path: String,
        definition: String,
        registry: crate::agent::registry::ToolRegistry,
        grants: Vec<String>,
    ) -> Result<u64, String> {
        if definition.len() > 1_048_576 {
            return Err("Workflow definition too large".into());
        }
        let definition: Progress =
            serde_json::from_str(&definition).map_err(|_| "Invalid workflow definition")?;
        let executor = AuthorizedExecutor::new(registry, grants)?;
        let workflow = Workflow::open(
            StorageJournal::open(std::path::Path::new(&path))?,
            definition,
        )?;
        let id = NEXT
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |n| n.checked_add(1))
            .map_err(|_| "Workflow handle space exhausted")?;
        let mut entries = entries()
            .lock()
            .map_err(|_| "Workflow registry unavailable")?;
        if entries.len() >= 64 {
            return Err("Too many open workflows".into());
        }
        entries.insert(
            id,
            Arc::new(Entry {
                owner: Mutex::new((workflow, executor)),
                cancel: AtomicBool::new(false),
                closed: AtomicBool::new(false),
            }),
        );
        Ok(id)
    }
}

pub fn workflow_open(
    database_path: String,
    definition_json: String,
    registration_json: String,
    engine_id: Option<u64>,
    execute: impl Fn(String) -> DartFnFuture<String> + Send + Sync + 'static,
) -> Result<u64, String> {
    #[cfg(all(feature = "workflow-local", not(target_arch = "wasm32")))]
    {
        let (registry, grants, _, _, _) =
            super::agent_extensions::registered_tools(engine_id, registration_json, execute)?;
        native::open(database_path, definition_json, registry, grants)
    }
    #[cfg(not(all(feature = "workflow-local", not(target_arch = "wasm32"))))]
    {
        let _ = (
            database_path,
            definition_json,
            registration_json,
            engine_id,
            execute,
        );
        Err("Native local Workflow is not selected".into())
    }
}

/// Runs at most one authorized step; reports durable progress, not model prose.
pub fn workflow_run_next(workflow_id: u64) -> Result<String, String> {
    #[cfg(all(feature = "workflow-local", not(target_arch = "wasm32")))]
    {
        let entry = native::entry(workflow_id)?;
        let mut owner = entry.lock()?;
        let (workflow, executor) = &mut *owner;
        workflow.run_next(executor, &entry.cancel)?;
        serde_json::to_string(workflow.progress()).map_err(|_| "Workflow encoding failed".into())
    }
    #[cfg(not(all(feature = "workflow-local", not(target_arch = "wasm32"))))]
    {
        let _ = workflow_id;
        Err("Native local Workflow is not selected".into())
    }
}

/// Runs ready steps in Rust until completion, cancellation or a blocked receipt.
pub fn workflow_run_until_blocked(workflow_id: u64) -> Result<String, String> {
    #[cfg(all(feature = "workflow-local", not(target_arch = "wasm32")))]
    {
        let entry = native::entry(workflow_id)?;
        let mut owner = entry.lock()?;
        let (workflow, executor) = &mut *owner;
        workflow.run_until_blocked(executor, &entry.cancel)?;
        serde_json::to_string(workflow.progress()).map_err(|_| "Workflow encoding failed".into())
    }
    #[cfg(not(all(feature = "workflow-local", not(target_arch = "wasm32"))))]
    {
        let _ = workflow_id;
        Err("Native local Workflow is not selected".into())
    }
}

pub fn workflow_progress(workflow_id: u64) -> Result<String, String> {
    #[cfg(all(feature = "workflow-local", not(target_arch = "wasm32")))]
    {
        let entry = native::entry(workflow_id)?;
        let owner = entry.lock()?;
        serde_json::to_string(owner.0.progress()).map_err(|_| "Workflow encoding failed".into())
    }
    #[cfg(not(all(feature = "workflow-local", not(target_arch = "wasm32"))))]
    {
        let _ = workflow_id;
        Err("Native local Workflow is not selected".into())
    }
}

pub fn workflow_recover(workflow_id: u64) -> Result<String, String> {
    #[cfg(all(feature = "workflow-local", not(target_arch = "wasm32")))]
    {
        let entry = native::entry(workflow_id)?;
        let mut owner = entry.lock()?;
        owner.0.recover()?;
        serde_json::to_string(owner.0.progress()).map_err(|_| "Workflow encoding failed".into())
    }
    #[cfg(not(all(feature = "workflow-local", not(target_arch = "wasm32"))))]
    {
        let _ = workflow_id;
        Err("Native local Workflow is not selected".into())
    }
}

/// Accepts host-attested evidence; it is not an approval to replay an action.
pub fn workflow_reconcile(
    workflow_id: u64,
    step_id: String,
    succeeded: bool,
    evidence_json: String,
) -> Result<String, String> {
    #[cfg(all(feature = "workflow-local", not(target_arch = "wasm32")))]
    {
        if evidence_json.len() > 65536 {
            return Err("Evidence too large".into());
        }
        let evidence = serde_json::from_str(&evidence_json).map_err(|_| "Invalid evidence JSON")?;
        let entry = native::entry(workflow_id)?;
        let mut owner = entry.lock()?;
        owner.0.reconcile(
            &step_id,
            if succeeded {
                crate::workflow::Outcome::Succeeded(evidence)
            } else {
                crate::workflow::Outcome::Failed(evidence)
            },
        )?;
        serde_json::to_string(owner.0.progress()).map_err(|_| "Workflow encoding failed".into())
    }
    #[cfg(not(all(feature = "workflow-local", not(target_arch = "wasm32"))))]
    {
        let _ = (workflow_id, step_id, succeeded, evidence_json);
        Err("Native local Workflow is not selected".into())
    }
}

#[flutter_rust_bridge::frb(sync)]
pub fn workflow_cancel(workflow_id: u64) -> Result<(), String> {
    #[cfg(all(feature = "workflow-local", not(target_arch = "wasm32")))]
    {
        use std::sync::{atomic::Ordering, TryLockError};
        let entry = native::entry(workflow_id)?;
        entry.cancel.store(true, Ordering::Release);
        let result = match entry.owner.try_lock() {
            Ok(mut owner) => {
                if entry.closed.load(Ordering::Acquire) {
                    return Err("Workflow closed".into());
                }
                owner.0.cancel()
            }
            Err(TryLockError::WouldBlock) => Ok(()), // Active runner checkpoints cancellation on return.
            Err(TryLockError::Poisoned(_)) => Err("Workflow owner unavailable".into()),
        };
        result
    }
    #[cfg(not(all(feature = "workflow-local", not(target_arch = "wasm32"))))]
    {
        let _ = workflow_id;
        Err("Native local Workflow is not selected".into())
    }
}

pub fn workflow_close(workflow_id: u64) -> Result<(), String> {
    #[cfg(all(feature = "workflow-local", not(target_arch = "wasm32")))]
    {
        let entry = native::entry(workflow_id)?;
        let mut owner = entry
            .lock()
            .map_err(|_| "Workflow busy or closed; await execution before closing")?;
        if entry.cancel.load(std::sync::atomic::Ordering::Acquire) {
            owner.0.cancel()?;
        }
        entry
            .closed
            .store(true, std::sync::atomic::Ordering::Release);
        native::entries()
            .lock()
            .map_err(|_| "Workflow registry unavailable")?
            .remove(&workflow_id);
        Ok(())
    }
    #[cfg(not(all(feature = "workflow-local", not(target_arch = "wasm32"))))]
    {
        let _ = workflow_id;
        Err("Native local Workflow is not selected".into())
    }
}
