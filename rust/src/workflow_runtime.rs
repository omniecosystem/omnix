//! Composition only: Storage commits snapshots; Workflow owns transitions;
//! the same tool registry and approval guard used by agents authorize effects.
use crate::{
    agent::{registry::ToolRegistry, AgentError, ToolExecutor},
    core::tools::ToolCall,
    storage::WorkflowStore,
    workflow::*,
};
use serde_json::json;
use std::{collections::BTreeSet, path::Path, sync::atomic::AtomicBool};

pub struct StorageJournal(WorkflowStore);
impl StorageJournal {
    pub fn open(path: &Path) -> Result<Self, String> {
        Ok(Self(WorkflowStore::open(path)?))
    }
}
impl Journal for StorageJournal {
    fn load(&mut self, id: &str) -> Result<Option<Progress>, String> {
        self.0
            .read(id)?
            .map(|raw| serde_json::from_str(&raw).map_err(|_| "Invalid workflow checkpoint".into()))
            .transpose()
    }
    fn save(&mut self, progress: &Progress) -> Result<(), String> {
        self.0.write(
            &progress.id,
            &serde_json::to_string(progress).map_err(|_| "Workflow encoding failed")?,
        )
    }
}
/// Fresh host registrations/grants for one exclusive workflow owner.
/// Unknown or lost execution evidence stays uncertain, never successful.
/// Skill guidance is not an execution receipt. The host must resolve uncertainty
/// from actual evidence rather than asking the runner to replay an unsafe action.
pub struct AuthorizedExecutor {
    registry: ToolRegistry,
    grants: BTreeSet<String>,
}
impl AuthorizedExecutor {
    pub fn new(registry: ToolRegistry, grants: Vec<String>) -> Result<Self, String> {
        let names: BTreeSet<_> = registry.definitions().into_iter().map(|d| d.name).collect();
        if grants.iter().any(|g| !names.contains(g)) {
            return Err("Grant names an unregistered workflow tool".into());
        }
        Ok(Self {
            registry,
            grants: grants.into_iter().collect(),
        })
    }
    pub fn revoke(&mut self, tool: &str) {
        self.grants.remove(tool);
    }
}
impl Executor for AuthorizedExecutor {
    fn execute(&mut self, workflow: &str, step: &Step, cancel: &AtomicBool) -> Outcome {
        if !self.grants.contains(&step.executor) {
            return Outcome::Failed(
                json!({"status":"denied","reason":"Tool is not granted to this workflow owner."}),
            );
        }
        let call = ToolCall {
            id: json!([workflow, step.id]).to_string(),
            name: step.executor.clone(),
            arguments: step.input.clone(),
        };
        match self.registry.execute_cancellable(&call, cancel) {
            Ok(result) => match result["status"].as_str() {
                Some("succeeded" | "ok" | "prepared" | "editor_opened") => {
                    Outcome::Succeeded(result)
                }
                Some("failed" | "denied" | "invalid_arguments" | "unavailable") => {
                    Outcome::Failed(result)
                }
                _ => Outcome::Interrupted,
            },
            Err(AgentError::Denied) => {
                Outcome::Failed(json!({"status":"denied","reason":"Tool dispatch rejected."}))
            }
            Err(AgentError::InvalidArguments) => Outcome::Failed(
                json!({"status":"invalid_arguments","reason":"Tool reported invalid arguments. No automatic retry was performed."}),
            ),
            Err(_) => Outcome::Interrupted,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        agent::{approval::*, ToolExecutor},
        core::tools::ToolDefinition,
    };
    use std::sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    };
    struct Tool(Arc<AtomicUsize>);
    impl ToolExecutor for Tool {
        fn execute(&mut self, _: &ToolCall) -> Result<serde_json::Value, AgentError> {
            self.0.fetch_add(1, Ordering::Relaxed);
            Ok(json!({"status":"succeeded"}))
        }
    }
    fn registry(calls: Arc<AtomicUsize>) -> ToolRegistry {
        let mut registry = ToolRegistry::default();
        registry.register(ToolDefinition { name:"host_test".into(), description:"Test".into(), parameters:json!({"type":"object","properties":{},"required":[],"additionalProperties":false}) }, Tool(calls)).unwrap();
        registry
    }
    struct Refuse;
    impl ToolApprover for Refuse {
        fn approve(&mut self, _: &ToolCall, _: &AtomicBool) -> Result<bool, AgentError> {
            Ok(false)
        }
    }
    #[test]
    fn revocation_and_review_prevent_effects() {
        let calls = Arc::new(AtomicUsize::new(0));
        let mut r = registry(calls.clone());
        r.set_approval(ApprovalGuard::new(
            ApprovalPolicy {
                mode: AutonomyMode::ReviewEveryCall,
                automatic_tools: Default::default(),
                always_review: Default::default(),
            },
            Box::new(Refuse),
        ));
        let mut host = AuthorizedExecutor::new(r, vec!["host_test".into()]).unwrap();
        let step = Step::new("one", "host_test", json!({}), RetrySafety::SafeToRepeat);
        assert!(matches!(
            host.execute("job", &step, &AtomicBool::new(false)),
            Outcome::Failed(_)
        ));
        host.revoke("host_test");
        assert!(matches!(
            host.execute("job", &step, &AtomicBool::new(false)),
            Outcome::Failed(_)
        ));
        assert_eq!(calls.load(Ordering::Relaxed), 0);
    }
    #[test]
    fn storage_restart_uses_fresh_grants_and_skips_completed_steps() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("workflow.sqlite");
        let definition = Progress::new(
            "job",
            vec![
                Step::new("one", "host_test", json!({}), RetrySafety::SafeToRepeat),
                Step::new("two", "host_test", json!({}), RetrySafety::SafeToRepeat),
            ],
        );
        let calls = Arc::new(AtomicUsize::new(0));
        let mut first =
            Workflow::open(StorageJournal::open(&path).unwrap(), definition.clone()).unwrap();
        let mut host =
            AuthorizedExecutor::new(registry(calls.clone()), vec!["host_test".into()]).unwrap();
        first.run_next(&mut host, &AtomicBool::new(false)).unwrap();
        drop(first);
        let mut resumed = Workflow::open(StorageJournal::open(&path).unwrap(), definition).unwrap();
        let mut revoked = AuthorizedExecutor::new(registry(calls.clone()), vec![]).unwrap();
        resumed
            .run_next(&mut revoked, &AtomicBool::new(false))
            .unwrap();
        assert_eq!(calls.load(Ordering::Relaxed), 1);
        assert_eq!(resumed.progress().steps[0].state, StepState::Succeeded);
        assert_eq!(resumed.progress().steps[1].state, StepState::Failed);
    }
}
