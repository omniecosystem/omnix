# Workflow composition and qualification

```text
Host supplies steps, registrations, grants and approval policy
  -> OmnixWorkflow / OmnixCognitiveEngine.startWorkflow (headless Dart)
  -> root Omnix Rust composition
      -> Workflow: transitions, cancellation and conservative recovery
      -> Storage: exclusive ownership and atomic SQLite checkpoints
      -> tool registry: validation and supplied approval policy
          -> host executor: OS permissions and actual effects
```

There is no Dart agent loop and no model needed for these explicit jobs.
Import `package:omnix/omnix.dart` for the facade. Each open supplies fresh
`OmnixAgentExtensions`; saved checkpoints contain no grants or approval policy.
Standalone Rust consumers can use Workflow with their own `Journal`/`Executor`,
or use root `workflow_runtime::{StorageJournal, AuthorizedExecutor}`.

## Opt-in packaging

Root Rust selects `workflow-local` plus a Core runtime, for example
`core-litertlm`. It composes `workflow`, `storage-rusqlite` and `agent`.
The agent's current dependency on Core means this composition includes the tool
types from Core, although explicit jobs do not load a model. No engine is default.

For a consuming Dart/Flutter application's native-assets configuration:

```yaml
hooks:
  user_defines:
    omnix:
      runtimes: [litertlm]
      agent: true
      workflow: true
```

Existing runtime asset ownership/Android archive settings still apply. This pass
qualifies Windows x64. It does not claim Android/iOS/Web Workflow qualification.
No Flutter dependency is added to the root Dart API. A standalone Workflow Dart
package/bridge is not yet available; the example exposes Workflow through root APIs.

## Execution evidence

A host tool returns `status: succeeded`, `ok`, `prepared` or `editor_opened` to
confirm its declared step. An editor handoff does **not** prove an event was saved.
`failed`, `denied`, `invalid_arguments` and `unavailable` block following steps.
Unknown/missing status, bridge cancellation/timeout or a thrown handler leaves an
uncertain `Running` step. Explicit recovery changes unsafe interrupted work to
`NeedsReconciliation`. Only host-attested evidence resolves that state.

`OmnixToolRequest.callId` carries the stable serialized `[jobId, stepId]` identity
for host idempotency or outcome lookup. `requestId` is only live callback
correlation. Hosts must never use the model's prose as execution evidence. The
same job ID is rejected if its step definitions change on reopen.

Cancellation is cooperative, not rollback. An active request returns promptly
from the native wait but does not forcibly terminate a Dart/OS executor; that
executor may finish later. Its step therefore stays uncertain and cancellation
is checkpointed when the runner returns. An idle cancellation is saved immediately.
Wait for execution to settle before `close`; close never cancels saved work.

## Run the real bridge tests

From the repository root, in PowerShell:

```powershell
$env:OMNIX_CORE_LITERTLM_HOST_PACKAGING = '1'
cargo build --manifest-path rust/Cargo.toml --no-default-features --features core-litertlm,workflow-local,flutter-bridge
$env:OMNIX_WORKFLOW_NATIVE_TEST_DLL = (Resolve-Path rust/target/debug/omnix.dll).Path
dart test test/workflow_test.dart test/workflow_native_test.dart test/agent_extensions_test.dart
```

The tests use newly created temporary databases and simulated host tools. They
cover close/reopen, completed-step skipping, second-owner refusal, schema failure
before review, denied approval, fresh grants, uncertainty/reconciliation and idle
and active cancellation. They load the real bridge DLL, not a fake Rust transport.
No device installation, app-data clearing or model download is required.

FRB may log a late callback delivery warning if a cancelled Dart handler completes
after Rust has stopped waiting. That result is not recorded as workflow success.
Production host adapters still need cooperative cancellation/late-result handling;
this is not an OS background execution service or exactly-once guarantee.

## Example Workflow screen

Rebuild the example (native features changed; hot reload is insufficient), open
the feature menu, and select **Workflow**. No model is needed for this simulation.

1. **Run next step** reads the host clock and checkpoints its result.
2. **Run next step** simulates a lost confirmation; no external action occurs.
3. **Reopen saved job**, or restart the app. The clock remains completed and
   the interrupted step remains uncertain.
4. **Recover interrupted work** marks that step as needing reconciliation;
   recovery does not execute it again.
5. **Confirm simulated outcome**, then **Run next step**, completes the demo.
6. **Cancel job** durably stops further execution. **New demo** creates a new
   identity without deleting previous jobs or other app data.

The consumer repository supplies these three simulation tools. The panel only
renders native snapshots; Rust owns execution, grants and checkpoint transitions.
Missing saved journals fail instead of silently recreating and replaying work.

`example/integration_test/workflow_restart_native_test.dart` is a two-launch
qualification entry point. Build with a unique `WORKFLOW_QUALIFICATION_ID`, install
using `adb install -r`, launch until `PREPARED`, force-stop only the Omnix example,
then launch again and require `PASSED`. It uses a separate app-private directory.
Restore the normal `lib/main.dart` APK afterwards using `adb install -r`.
Do not uninstall or clear application data. The generic proposal/acceptance and
event-job execution slice is documented in [EVENT_TASKS.md](EVENT_TASKS.md).
Platform scheduling requires the host's explicitly selected OS adapter.

Qualification on 2026-10-10: the Android arm64 bridge test reported `PREPARED`
in process 18717 and `PASSED` after force-stop/relaunch in process 18894, using
qualification identity `20261010-workflow1`. The completed prefix was preserved;
the uncertain simulated step required reconciliation before completion. This is
a process-restart check after checkpointing, not a power-loss durability test or
a real device-action guarantee. Twelve targeted example widget/unit tests passed
and example static analysis was clean.
