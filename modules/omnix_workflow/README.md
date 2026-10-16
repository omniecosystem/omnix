# Omnix Workflow

Execute sequential jobs with checkpoints, saved step results and explicit
recovery. The independent `omnix-workflow` Rust crate is in `rust/backend` and
has no runtime dependency on a model, Flutter or a database library.

Use it directly with your own storage and executors, or select the `workflow`
feature in root Omnix. Root Omnix also exposes its integrated Workflow execution
through the Dart `OmnixWorkflow` API. A standalone Workflow Dart package is not
currently available.

## Execution model

Define a `Progress` value containing ordered `Step` values. Each step identifies
an executor, JSON input and a retry policy. Supply these two host implementations:

- `Journal`: loads and atomically saves the complete checkpoint. A successful
  save must mean the checkpoint is durably committed. Prevent concurrent owners
  of the same workflow.
- `Executor`: performs a step and returns `Succeeded`, `Failed` or `Interrupted`.
  Enforce your current access policy and platform permissions on every execution,
  including after a restart. Saved definitions do not grant execution authority.

Open a workflow with `Workflow::open`, then use `run_next` to execute at most one
step or `run_until_blocked` to process ready steps in sequence. Each executor
returns before the next step starts. The runner saves `Running` before calling
the executor and saves its result afterward. Completed steps are skipped when
the same definition is reopened.

### Passing results between steps

Use `Step::output_bindings` to fill top-level input arguments from earlier
successful step outputs. Each `OutputBinding` selects a source step and an
RFC 6901 JSON pointer; an empty pointer selects its entire output. Missing fields
or oversized resolved inputs fail the destination step without calling its
executor. Bindings cannot reference later steps or overwrite literal input fields.

### Recovery and cancellation

After an interruption, call `recover` explicitly:

| Retry policy | Recovery behavior |
| --- | --- |
| `SafeToRepeat` | The interrupted step returns to `Pending` and can run again. |
| `RequiresReconciliation` | The step becomes `NeedsReconciliation`; confirm its real outcome through `reconcile` before continuing. |

Choose retry policies based on the executor's actual behavior. For actions with
external effects, use stable workflow and step IDs for idempotency or reconcile
the outcome with the external system. Workflow does not guarantee exactly-once
external effects or automatically retry failed steps.

Cancellation is cooperative and persisted. It stops subsequent dispatch but
cannot undo completed effects. Executors receive an `AtomicBool` cancellation
signal so they can stop their own work where possible.

## Run the checkpoint example

The example supplies a SQLite journal and simulated executors. SQLite is an
example dependency, not a requirement for applications using the library.

From the repository root, choose an unused absolute path for the demo database:

```powershell
$journal = Join-Path $env:TEMP "omnix-workflow-demo.sqlite"
cargo run --manifest-path modules/omnix_workflow/rust/backend/Cargo.toml --locked --example checkpoint -- $journal
```

The first run completes `inspect` and simulates lost confirmation for `handoff`.
Run the same command again: `inspect` is skipped, and `handoff` enters
`NeedsReconciliation` without being repeated.

Confirm the simulated handoff to allow the final step to run:

```powershell
cargo run --manifest-path modules/omnix_workflow/rust/backend/Cargo.toml --locked --example checkpoint -- $journal --confirm-demo-handoff
```

The confirmation flag applies only to this simulation; it does not verify any
device or external action. The example rejects databases belonging to other
applications. Keep checkpoints in private storage: they contain arguments and
results and are not encrypted by this crate.

## Test

```shell
cargo test --manifest-path modules/omnix_workflow/rust/backend/Cargo.toml --locked
```

The tests exercise recovery, cancellation, failed checkpoint writes, result
bindings and protection against replaying completed steps. Application-specific
executors and journals require their own integration tests.

## Integration responsibilities

The crate executes explicit plans. Model-based planning and tool orchestration
can be supplied through root Omnix or your own application. Your host is also
responsible for wakeups, scheduling and operating-system background execution;
creating a workflow does not keep an application process alive.

The API and checkpoint format are a developer preview. Applications upgrading
between versions should test checkpoint compatibility before opening existing
jobs with a changed definition.
