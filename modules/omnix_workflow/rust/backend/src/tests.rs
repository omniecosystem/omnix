use super::*;
use serde_json::json;
use std::sync::{Arc, Mutex};

#[test]
fn run_until_blocked_completes_bound_steps_and_never_replays_success() {
    let mut workflow = Workflow::open(Memory::default(), bound_definition("/value")).unwrap();
    let mut host = BoundHost {
        calls: 0,
        inputs: vec![],
        receipt: json!({"value":42}),
    };
    workflow
        .run_until_blocked(&mut host, &AtomicBool::new(false))
        .unwrap();
    assert_eq!(host.calls, 2);
    assert_eq!(host.inputs[1], json!({"sample":42}));
    assert!(workflow
        .progress()
        .steps
        .iter()
        .all(|s| s.state == StepState::Succeeded));
    workflow
        .run_until_blocked(&mut host, &AtomicBool::new(false))
        .unwrap();
    assert_eq!(host.calls, 2);
}

#[test]
fn run_until_blocked_returns_uncertainty_without_implicit_recovery() {
    let mut workflow = Workflow::open(
        Memory::default(),
        definition(RetrySafety::RequiresReconciliation),
    )
    .unwrap();
    let mut host = Host {
        calls: 0,
        interrupt: true,
    };
    workflow
        .run_until_blocked(&mut host, &AtomicBool::new(false))
        .unwrap();
    assert_eq!(workflow.progress().steps[0].state, StepState::Running);
    workflow
        .run_until_blocked(&mut host, &AtomicBool::new(false))
        .unwrap();
    workflow.recover().unwrap();
    workflow
        .run_until_blocked(&mut host, &AtomicBool::new(false))
        .unwrap();
    assert_eq!(host.calls, 1);
    assert_eq!(workflow.progress().steps[1].state, StepState::Pending);
}

#[test]
fn run_until_blocked_stops_on_failure_and_cancellation() {
    struct StopHost {
        calls: usize,
        cancel: bool,
    }
    impl Executor for StopHost {
        fn execute(&mut self, _: &str, _: &Step, flag: &AtomicBool) -> Outcome {
            self.calls += 1;
            if self.cancel {
                flag.store(true, Ordering::Release);
                Outcome::Succeeded(json!({"status":"ok"}))
            } else {
                Outcome::Failed(json!({"status":"denied"}))
            }
        }
    }
    for cancelled in [false, true] {
        let mut workflow =
            Workflow::open(Memory::default(), definition(RetrySafety::SafeToRepeat)).unwrap();
        let mut host = StopHost {
            calls: 0,
            cancel: cancelled,
        };
        let flag = AtomicBool::new(false);
        workflow.run_until_blocked(&mut host, &flag).unwrap();
        workflow.run_until_blocked(&mut host, &flag).unwrap();
        assert_eq!(host.calls, 1);
        assert_eq!(workflow.progress().cancelled, cancelled);
        assert_eq!(workflow.progress().steps[1].state, StepState::Pending);
    }
}

fn bound_definition(pointer: &str) -> Progress {
    let mut value = definition(RetrySafety::SafeToRepeat);
    value.version = 2;
    value.steps[1].output_bindings.insert(
        "sample".into(),
        OutputBinding {
            step: "one".into(),
            pointer: pointer.into(),
        },
    );
    value
}
struct BoundHost {
    calls: usize,
    inputs: Vec<Value>,
    receipt: Value,
}
impl Executor for BoundHost {
    fn execute(&mut self, _: &str, step: &Step, _: &AtomicBool) -> Outcome {
        self.calls += 1;
        self.inputs.push(step.input.clone());
        Outcome::Succeeded(self.receipt.clone())
    }
}
#[test]
fn output_binding_survives_restart_without_mutating_definition_or_replaying_source() {
    let journal = Memory::default();
    let definition = bound_definition("/nested/value");
    let mut host = BoundHost {
        calls: 0,
        inputs: vec![],
        receipt: json!({"nested":{"value":42}}),
    };
    let mut first = Workflow::open(journal.clone(), definition.clone()).unwrap();
    first.run_next(&mut host, &AtomicBool::new(false)).unwrap();
    drop(first);
    host.receipt = json!({"nested":{"value":999}});
    let mut resumed = Workflow::open(journal, definition).unwrap();
    resumed
        .run_next(&mut host, &AtomicBool::new(false))
        .unwrap();
    assert_eq!(host.calls, 2);
    assert_eq!(host.inputs[1], json!({"sample":42}));
    assert_eq!(resumed.progress().steps[1].input, json!({}));
    assert!(!resumed
        .run_next(&mut host, &AtomicBool::new(false))
        .unwrap());
}
#[test]
fn unavailable_binding_checkpoints_failure_without_destination_dispatch() {
    let journal = Memory::default();
    let definition = bound_definition("/missing");
    let mut host = BoundHost {
        calls: 0,
        inputs: vec![],
        receipt: json!({"other":42}),
    };
    let mut workflow = Workflow::open(journal.clone(), definition.clone()).unwrap();
    workflow
        .run_next(&mut host, &AtomicBool::new(false))
        .unwrap();
    workflow
        .run_next(&mut host, &AtomicBool::new(false))
        .unwrap();
    assert_eq!(host.calls, 1);
    assert_eq!(workflow.progress().steps[1].state, StepState::Failed);
    assert_eq!(
        workflow.progress().steps[1].output.as_ref().unwrap()["executionStarted"],
        false
    );
    drop(workflow);
    let mut resumed = Workflow::open(journal, definition).unwrap();
    assert!(resumed
        .run_next(&mut host, &AtomicBool::new(false))
        .is_err());
    assert_eq!(host.calls, 1);
}
#[test]
fn oversized_bound_input_is_rejected_before_dispatch() {
    let mut host = BoundHost {
        calls: 0,
        inputs: vec![],
        receipt: json!({"data":"x".repeat(65536)}),
    };
    let mut workflow = Workflow::open(Memory::default(), bound_definition("/data")).unwrap();
    workflow
        .run_next(&mut host, &AtomicBool::new(false))
        .unwrap();
    workflow
        .run_next(&mut host, &AtomicBool::new(false))
        .unwrap();
    assert_eq!(host.calls, 1);
    assert_eq!(workflow.progress().steps[1].state, StepState::Failed);
}
#[test]
fn binding_validation_rejects_forward_conflicting_and_malformed_pointers() {
    let mut value = bound_definition("/value");
    value.steps[1]
        .output_bindings
        .get_mut("sample")
        .unwrap()
        .step = "two".into();
    assert!(value.validate().is_err());
    value = bound_definition("/bad~2escape");
    assert!(value.validate().is_err());
    value = bound_definition("/value");
    value.steps[1].input = json!({"sample":"override"});
    assert!(value.validate().is_err());
    let journal = Memory::default();
    let original = bound_definition("/value");
    Workflow::open(journal.clone(), original).unwrap();
    assert!(Workflow::open(journal, bound_definition("/other")).is_err());
}
#[test]
fn whole_null_output_and_escaped_pointer_are_valid_bound_values() {
    for (pointer, receipt, expected) in [
        ("", Value::Null, Value::Null),
        ("/a~1b/~0", json!({"a/b":{"~":7}}), json!(7)),
    ] {
        let mut host = BoundHost {
            calls: 0,
            inputs: vec![],
            receipt,
        };
        let mut workflow = Workflow::open(Memory::default(), bound_definition(pointer)).unwrap();
        workflow
            .run_next(&mut host, &AtomicBool::new(false))
            .unwrap();
        workflow
            .run_next(&mut host, &AtomicBool::new(false))
            .unwrap();
        assert_eq!(host.inputs[1]["sample"], expected);
    }
}

#[derive(Clone, Default)]
struct Memory {
    saved: Arc<Mutex<Option<Progress>>>,
    writes: Arc<Mutex<usize>>,
    fail_at: usize,
}
impl Journal for Memory {
    fn load(&mut self, _: &str) -> Result<Option<Progress>, String> {
        Ok(self.saved.lock().unwrap().clone())
    }
    fn save(&mut self, value: &Progress) -> Result<(), String> {
        let mut writes = self.writes.lock().unwrap();
        *writes += 1;
        if *writes == self.fail_at {
            return Err("checkpoint failed".into());
        }
        *self.saved.lock().unwrap() = Some(value.clone());
        Ok(())
    }
}
struct Host {
    calls: usize,
    interrupt: bool,
}
impl Executor for Host {
    fn execute(&mut self, _: &str, _: &Step, _: &AtomicBool) -> Outcome {
        self.calls += 1;
        if self.interrupt {
            Outcome::Interrupted
        } else {
            Outcome::Succeeded(json!({"status":"ok"}))
        }
    }
}
fn definition(retry: RetrySafety) -> Progress {
    Progress::new(
        "demo",
        vec![
            Step::new("one", "host", json!({}), retry),
            Step::new("two", "host", json!({}), RetrySafety::SafeToRepeat),
        ],
    )
}
#[test]
fn restart_skips_completed_steps_and_preserves_outputs() {
    let journal = Memory::default();
    let definition = definition(RetrySafety::SafeToRepeat);
    let mut host = Host {
        calls: 0,
        interrupt: false,
    };
    let mut first = Workflow::open(journal.clone(), definition.clone()).unwrap();
    first.run_next(&mut host, &AtomicBool::new(false)).unwrap();
    drop(first);
    let mut resumed = Workflow::open(journal, definition).unwrap();
    assert_eq!(
        resumed.progress().steps[0].output,
        Some(json!({"status":"ok"}))
    );
    resumed
        .run_next(&mut host, &AtomicBool::new(false))
        .unwrap();
    assert!(!resumed
        .run_next(&mut host, &AtomicBool::new(false))
        .unwrap());
    assert_eq!(host.calls, 2);
}
#[test]
fn unsafe_interruption_requires_host_reconciliation() {
    let journal = Memory::default();
    let definition = definition(RetrySafety::RequiresReconciliation);
    let mut host = Host {
        calls: 0,
        interrupt: true,
    };
    let mut first = Workflow::open(journal.clone(), definition.clone()).unwrap();
    first.run_next(&mut host, &AtomicBool::new(false)).unwrap();
    drop(first);
    let mut resumed = Workflow::open(journal, definition).unwrap();
    assert!(resumed
        .run_next(&mut host, &AtomicBool::new(false))
        .is_err());
    resumed.recover().unwrap();
    assert_eq!(
        resumed.progress().steps[0].state,
        StepState::NeedsReconciliation
    );
    assert!(resumed
        .run_next(&mut host, &AtomicBool::new(false))
        .is_err());
    assert_eq!(host.calls, 1);
    assert!(resumed.reconcile("one", Outcome::Interrupted).is_err());
    resumed
        .reconcile("one", Outcome::Succeeded(json!({"confirmed":true})))
        .unwrap();
    host.interrupt = false;
    resumed
        .run_next(&mut host, &AtomicBool::new(false))
        .unwrap();
    assert_eq!(host.calls, 2);
}
#[test]
fn explicitly_repeatable_interrupted_step_can_retry_after_recovery() {
    let mut workflow =
        Workflow::open(Memory::default(), definition(RetrySafety::SafeToRepeat)).unwrap();
    let mut host = Host {
        calls: 0,
        interrupt: true,
    };
    workflow
        .run_next(&mut host, &AtomicBool::new(false))
        .unwrap();
    workflow.recover().unwrap();
    host.interrupt = false;
    workflow
        .run_next(&mut host, &AtomicBool::new(false))
        .unwrap();
    assert_eq!(host.calls, 2);
}
#[test]
fn checkpoint_failure_prevents_effect_or_leaves_durable_uncertainty() {
    for fail_at in [2, 3] {
        let journal = Memory {
            fail_at,
            ..Memory::default()
        };
        let mut workflow = Workflow::open(
            journal.clone(),
            definition(RetrySafety::RequiresReconciliation),
        )
        .unwrap();
        let mut host = Host {
            calls: 0,
            interrupt: false,
        };
        assert!(workflow
            .run_next(&mut host, &AtomicBool::new(false))
            .is_err());
        assert_eq!(host.calls, usize::from(fail_at == 3));
        if fail_at == 3 {
            assert_eq!(
                journal.saved.lock().unwrap().as_ref().unwrap().steps[0].state,
                StepState::Running
            );
            assert!(workflow
                .run_next(&mut host, &AtomicBool::new(false))
                .is_err());
        }
    }
}
#[test]
fn cancellation_survives_reload_and_never_dispatches() {
    let journal = Memory::default();
    let definition = definition(RetrySafety::SafeToRepeat);
    let mut first = Workflow::open(journal.clone(), definition.clone()).unwrap();
    let mut host = Host {
        calls: 0,
        interrupt: false,
    };
    assert!(!first.run_next(&mut host, &AtomicBool::new(true)).unwrap());
    let mut resumed = Workflow::open(journal, definition).unwrap();
    assert!(!resumed
        .run_next(&mut host, &AtomicBool::new(false))
        .unwrap());
    assert_eq!(host.calls, 0);
}
#[test]
fn replacement_definitions_and_invalid_checkpoints_are_rejected() {
    let journal = Memory::default();
    let original = definition(RetrySafety::SafeToRepeat);
    Workflow::open(journal.clone(), original.clone()).unwrap();
    let mut changed = original.clone();
    changed.steps[0].input = json!({"changed":true});
    assert!(Workflow::open(journal.clone(), changed).is_err());
    let mut malformed = original;
    malformed.steps[0].state = StepState::Running;
    malformed.steps[1].state = StepState::Succeeded;
    *journal.saved.lock().unwrap() = Some(malformed.clone());
    assert!(Workflow::open(journal, malformed).is_err());
}

#[test]
fn null_output_survives_serialized_checkpoint() {
    let mut progress = definition(RetrySafety::SafeToRepeat);
    progress.steps[0].state = StepState::Succeeded;
    progress.steps[0].output = Some(serde_json::Value::Null);
    let serialized = serde_json::to_string(&progress).unwrap();
    let restored: Progress = serde_json::from_str(&serialized).unwrap();
    restored.validate().unwrap();
    assert_eq!(restored.steps[0].output, Some(serde_json::Value::Null));
}
