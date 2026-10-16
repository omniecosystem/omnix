# Native Android workflow qualification

The example supplies battery reading, text sharing and Settings navigation as
native host capabilities. Inspired by PokeClaw's direct system-query tools,
these implementations live entirely in the consumer's Dart/Kotlin code. Nothing
Android-specific was added to Rust. No accessibility service or automatic
permission-dialog clicking is involved.

## Try it

1. Update/run the example on Android using the usual `flutter run` command.
   Do not uninstall or clear app data. If installing an APK manually, use
   `adb install -r build/app/outputs/flutter-apk/app-debug.apk`.
2. Load your tool-capable model in Home and ask:
   **“Propose a workflow that reads my phone battery and opens the Android share
   sheet with that same saved battery report on a simulated tick.”**
3. In Workflow, refresh and review the proposal. It should have a battery step
   followed by a share step with `outputBindings.text = {step: battery,
   pointer: /report}`. Accept it.
4. Emit a simulated tick, then select **Run workflow** on the queued job. Rust
   reads the battery, saves its receipt, binds that report and opens the chooser.
   It stops on completion, cancellation, failure or an uncertain outcome.
5. Alternatively use **Run next step** twice for debugging; you may restart
   between those steps to verify persistence. Android opens its share chooser
   with the exact saved report. Cancel it or
   choose an app yourself; the engine does not send anything.
6. Inspect the completed job. Completion proves the two host receipts, NOT
   delivery to anyone. Stop the task when finished so future ticks do not queue
   more reports. Other accepted tick tasks also match this shared test trigger.

The trigger remains manual, and execution is foreground work started by the
user. This is not a background battery monitor or scheduler. **Stop execution**
requests cooperative cancellation of the active job; it cannot undo effects or
force an active native callback to stop. Failed/uncertain actions are never
implicitly retried. Expand **View saved receipt** for actual host evidence.
The workflow runner currently uses its own explicit scoped-assistance policy,
not Home's autonomy selection. Navigation/chooser handoffs are automatic after
running the job; final sharing remains under the receiving app's user interface.

## Recovery and boundaries

### Run from Home

With Agent tools enabled, after proposing/reviewing the plan, say:
**“Accept that battery-report workflow and run it once now.”** Home can inspect
the saved plan, accept its exact task ID, queue a targeted manual run and execute
the returned job ID. If multiple plans match, it should ask which one. You may
also ask **“Did that workflow finish? Show me what happened.”**

This uses consumer-supplied `host_accept_event_task`, `host_start_event_task`
and `host_run_workflow_job`, backed by the same root Rust task/workflow APIs.
Starting does not fan out to other tick tasks, install a listener or execute a
step. Execution waits for each callback and persists its result before advancing.
Home's selected autonomy policy applies to the job's individual tools. Its Stop
button requests cancellation of active host workflow execution too.

The same admission identity is deduplicated durably. Re-delivery of the same
consumer callback reuses its identity during the conversation; a new model call
or a new conversation is not an exactly-once execution guarantee. Inspect saved
jobs after an uncertain response instead of creating a replacement run. No
automatic retries of external effects or OS background services were added.

- `host_battery_status`: `SafeToRepeat`; native battery percentage, charging
  state and a concise report. Missing native data returns `unavailable`.
- `host_share_text`: `RequiresReconciliation`; bounded text, plain-text chooser,
  `editor_opened` receipt. Interrupted handoffs are not blindly repeated.
- `host_open_app`: `RequiresReconciliation`; only `application=settings`.
  Its known `opened` receipt is normalized for workflow execution, without
  claiming a setting changed.

One consumer catalogue supplies proposal/acceptance recovery contracts and the
runner's registered tools and grants. Desktop has only the existing portable
clock/formatter capabilities; Android workflows cannot silently execute there.
Rust still owns admission, bindings, durable checkpoints, grants and execution
state. The model does not choose retry safety or add native capabilities.

The new Dart channel adapters and catalogue have regression tests. A passing
build is not proof of a real-device chooser or model-generated plan; use the
steps above for that qualification.
# One request from Home

For an immediate action, Home should use the direct tools. To save and run a
workflow in one interaction, try (text or voice):

> Create and run a workflow now that reads my phone battery and opens the share sheet with that report.

The model infers execution intent, saves a proposal and calls
`host_execute_event_task` with its returned ID in the same turn. This host
convenience tool uses the existing Rust catalogue operations and Rust step
runner; it does not implement another Dart execution loop. Scoped assistance
allows the example's supplied capabilities automatically. Stricter policies
show Home approval dialogs and continue after Allow; review-every-call still
intentionally reviews each action. Workflow remains available for inspection,
recovery and management, not as a mandatory execution screen.

For a proposal only, say “Propose a workflow…”; it must remain inactive. The
combined run tool inspects existing jobs and does not replace completed, failed
or uncertain runs. Re-delivered callbacks reuse their result within the current
Home configuration. Across restarts, saved job evidence prevents this convenience
path from silently starting a replacement. Explicitly requesting an additional
run uses separate management tools. These protections are not an exactly-once
guarantee for external effects. Share-sheet handoff is not proof of delivery.
