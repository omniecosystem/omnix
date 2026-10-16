//! Explicit sequential execution, independent of models, Flutter and databases.
//! Hosts own executors, authorization and durable journal implementation.
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::atomic::{AtomicBool, Ordering};
mod bindings;
pub use bindings::OutputBinding;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum RetrySafety {
    SafeToRepeat,
    RequiresReconciliation,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum StepState {
    Pending,
    Running,
    Succeeded,
    Failed,
    NeedsReconciliation,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Step {
    pub id: String,
    pub executor: String,
    pub input: Value,
    #[serde(
        rename = "outputBindings",
        default,
        skip_serializing_if = "std::collections::BTreeMap::is_empty"
    )]
    pub output_bindings: std::collections::BTreeMap<String, OutputBinding>,
    pub retry: RetrySafety,
    pub state: StepState,
    #[serde(with = "checkpoint_output")]
    pub output: Option<Value>,
}
// Preserve a successful JSON null result rather than decoding it as no result.
mod checkpoint_output {
    use super::*;
    #[derive(Serialize, Deserialize)]
    struct Present {
        value: Value,
    }
    pub fn serialize<S: serde::Serializer>(
        value: &Option<Value>,
        serializer: S,
    ) -> Result<S::Ok, S::Error> {
        value
            .as_ref()
            .map(|v| Present { value: v.clone() })
            .serialize(serializer)
    }
    pub fn deserialize<'de, D: serde::Deserializer<'de>>(
        deserializer: D,
    ) -> Result<Option<Value>, D::Error> {
        Ok(Option::<Present>::deserialize(deserializer)?.map(|p| p.value))
    }
}
impl Step {
    pub fn new(
        id: impl Into<String>,
        executor: impl Into<String>,
        input: Value,
        retry: RetrySafety,
    ) -> Self {
        Self {
            id: id.into(),
            executor: executor.into(),
            input,
            output_bindings: Default::default(),
            retry,
            state: StepState::Pending,
            output: None,
        }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Progress {
    pub version: u32,
    pub id: String,
    pub cancelled: bool,
    pub steps: Vec<Step>,
}
impl Progress {
    pub fn new(id: impl Into<String>, steps: Vec<Step>) -> Self {
        Self {
            version: if steps.iter().any(|step| !step.output_bindings.is_empty()) {
                2
            } else {
                1
            },
            id: id.into(),
            cancelled: false,
            steps,
        }
    }
    /// Checks checkpoint structure without granting execution authority.
    pub fn validate(&self) -> Result<(), String> {
        if !matches!(self.version, 1 | 2)
            || (self.version == 1
                && self
                    .steps
                    .iter()
                    .any(|step| !step.output_bindings.is_empty()))
            || self.id.is_empty()
            || self.id.len() > 128
            || self.steps.is_empty()
            || self.steps.len() > 32
        {
            return Err("Invalid workflow definition".into());
        }
        let mut ids = std::collections::BTreeSet::new();
        let mut unfinished = false;
        let mut active = false;
        for (index, step) in self.steps.iter().enumerate() {
            bindings::validate(step, &self.steps[..index])?;
            if step.id.is_empty()
                || step.id.len() > 128
                || step.executor.is_empty()
                || step.executor.len() > 128
                || !ids.insert(&step.id)
            {
                return Err("Invalid or duplicate workflow step".into());
            }
            if unfinished && step.state != StepState::Pending {
                return Err("Invalid sequential workflow progress".into());
            }
            let completed = matches!(step.state, StepState::Succeeded | StepState::Failed);
            if completed != step.output.is_some() {
                return Err("Step output does not match its state".into());
            }
            if step.state != StepState::Succeeded {
                unfinished = true;
            }
            if step.state == StepState::Running {
                if active {
                    return Err("Multiple active workflow steps".into());
                }
                active = true;
            }
        }
        if serde_json::to_vec(self)
            .map_err(|_| "Workflow encoding failed")?
            .len()
            > 1_048_576
        {
            return Err("Workflow exceeds checkpoint limit".into());
        }
        Ok(())
    }
}

/// Durable, single-owner checkpoints. Save must atomically replace the whole
/// checkpoint and return only after commit. Hosts must prevent concurrent owners.
pub trait Journal {
    fn load(&mut self, id: &str) -> Result<Option<Progress>, String>;
    fn save(&mut self, progress: &Progress) -> Result<(), String>;
}
pub enum Outcome {
    Succeeded(Value),
    Failed(Value),
    Interrupted,
}
/// Receives a stable workflow/step identity for host idempotency or reconciliation.
/// This adapter must enforce grants, supplied policy and OS constraints itself;
/// a workflow definition confers no authority to bypass host authorization.
pub trait Executor {
    fn execute(&mut self, workflow: &str, step: &Step, cancel: &AtomicBool) -> Outcome;
}
pub struct Workflow<J: Journal> {
    progress: Progress,
    journal: J,
}
impl<J: Journal> Workflow<J> {
    pub fn open(mut journal: J, definition: Progress) -> Result<Self, String> {
        definition.validate()?;
        let progress = match journal.load(&definition.id)? {
            Some(saved) => {
                saved.validate()?;
                if saved.id != definition.id
                    || saved.version != definition.version
                    || saved.steps.len() != definition.steps.len()
                    || saved.steps.iter().zip(&definition.steps).any(|(a, b)| {
                        a.id != b.id
                            || a.executor != b.executor
                            || a.input != b.input
                            || a.output_bindings != b.output_bindings
                            || a.retry != b.retry
                    })
                {
                    return Err("Saved workflow does not match definition".into());
                }
                saved
            }
            None => {
                if definition.cancelled
                    || definition
                        .steps
                        .iter()
                        .any(|s| s.state != StepState::Pending || s.output.is_some())
                {
                    return Err("New workflows must start pending".into());
                }
                journal.save(&definition)?;
                definition
            }
        };
        Ok(Self { progress, journal })
    }
    pub fn progress(&self) -> &Progress {
        &self.progress
    }
    fn checkpoint(&mut self, next: Progress) -> Result<(), String> {
        next.validate()?;
        self.journal.save(&next)?;
        self.progress = next;
        Ok(())
    }
    /// Explicit recovery after owner restart; never repeats an unsafe action.
    pub fn recover(&mut self) -> Result<(), String> {
        let mut next = self.progress.clone();
        for step in &mut next.steps {
            if step.state == StepState::Running {
                step.state = match step.retry {
                    RetrySafety::SafeToRepeat => StepState::Pending,
                    RetrySafety::RequiresReconciliation => StepState::NeedsReconciliation,
                };
            }
        }
        self.checkpoint(next)
    }
    pub fn cancel(&mut self) -> Result<(), String> {
        let mut next = self.progress.clone();
        next.cancelled = true;
        self.checkpoint(next)
    }
    /// Records the host-confirmed outcome of an interrupted action.
    /// Unsafe or failed actions are not retried automatically.
    pub fn reconcile(&mut self, id: &str, outcome: Outcome) -> Result<(), String> {
        let mut next = self.progress.clone();
        let step = next
            .steps
            .iter_mut()
            .find(|s| s.id == id)
            .ok_or("Unknown step")?;
        if step.state != StepState::NeedsReconciliation {
            return Err("Step does not need reconciliation".into());
        }
        match outcome {
            Outcome::Succeeded(value) => {
                step.state = StepState::Succeeded;
                step.output = Some(value);
            }
            Outcome::Failed(value) => {
                step.state = StepState::Failed;
                step.output = Some(value);
            }
            Outcome::Interrupted => {
                return Err("An uncertain outcome cannot resolve reconciliation".into())
            }
        }
        self.checkpoint(next)
    }
    /// Runs ready steps until completion, cancellation or a blocked outcome.
    /// Never recovers, retries or reconciles an interrupted/failed step implicitly.
    pub fn run_until_blocked(
        &mut self,
        executor: &mut impl Executor,
        cancel: &AtomicBool,
    ) -> Result<(), String> {
        // The immutable plan bounds the number of dispatches in this invocation.
        for _ in 0..self.progress.steps.len() {
            if cancel.load(Ordering::Acquire) {
                self.cancel()?;
                break;
            }
            if self.progress.cancelled
                || !matches!(
                    self.progress.steps.iter().find(|s| s.state != StepState::Succeeded),
                    Some(step) if step.state == StepState::Pending
                )
            {
                break;
            }
            self.run_next(executor, cancel)?;
        }
        Ok(())
    }
    /// Executes at most one step, checkpointing Running before any host effect.
    /// Returns false for completed/cancelled work. Failure/uncertainty blocks progress.
    pub fn run_next(
        &mut self,
        executor: &mut impl Executor,
        cancel: &AtomicBool,
    ) -> Result<bool, String> {
        if cancel.load(Ordering::Acquire) {
            self.cancel()?;
            return Ok(false);
        }
        if self.progress.cancelled {
            return Ok(false);
        }
        let Some(index) = self
            .progress
            .steps
            .iter()
            .position(|s| s.state != StepState::Succeeded)
        else {
            return Ok(false);
        };
        if self.progress.steps[index].state != StepState::Pending {
            return Err("Workflow is blocked; recover or reconcile before continuing".into());
        }
        let invocation = match bindings::resolve(&self.progress, index) {
            Ok(invocation) => invocation,
            Err(_) => {
                let mut failed = self.progress.clone();
                failed.steps[index].state = StepState::Failed;
                failed.steps[index].output = Some(serde_json::json!({
                    "status":"invalid_arguments", "code":"WORKFLOW_BINDING_UNAVAILABLE",
                    "reason":"Required saved output could not be bound within the input limits.",
                    "executionStarted":false
                }));
                self.checkpoint(failed)?;
                return Ok(true);
            }
        };
        let mut running = self.progress.clone();
        running.steps[index].state = StepState::Running;
        self.checkpoint(running)?;
        if cancel.load(Ordering::Acquire) {
            self.cancel()?;
            return Ok(false);
        }
        let outcome = executor.execute(&self.progress.id, &invocation, cancel);
        let mut next = self.progress.clone();
        let step = &mut next.steps[index];
        match outcome {
            Outcome::Succeeded(value) => {
                step.state = StepState::Succeeded;
                step.output = Some(value);
            }
            Outcome::Failed(value) => {
                step.state = StepState::Failed;
                step.output = Some(value);
            }
            Outcome::Interrupted => {} // Running is the durable uncertain-outcome marker.
        }
        next.cancelled |= cancel.load(Ordering::Acquire);
        self.checkpoint(next)?;
        Ok(true)
    }
}

#[cfg(test)]
mod tests;
