# Integration validation

Validate the operations your application relies on against the selected Omnix
revision, native artifacts, model and target. This checklist is not a claim
that every combination has passed.

## Validation matrix

| Area | Checks |
| --- | --- |
| Conversations | Close/reopen, isolation, balanced tool exchanges and no historical action replay |
| Resilience | Cancellation, immediate follow-up, failed loads, memory pressure and background/resume |
| Runtime controls | Sampling, context/output limits, accelerator selection and unsupported-operation errors |
| Knowledge | Source identity, visibility, profile compatibility, removal and rebuild |
| Installation | Interrupted transfer, restart, corruption, low storage and retention of valid installed models |
| Media | Supported modalities, capture formats, attachment lifetime and restored-history behavior |
| Extensions | Skill loading, executor compatibility, structured failures and accurate completion reporting |
| Durable work | Wakeups, cancellation, restart and reconciliation of uncertain side effects |
| Distribution | Pinned native assets, release builds and upgrades with representative saved data |

A foreground notification alone does not establish durable background execution.
A passing mock test does not establish native backend or packaged-device behavior.
Build success alone is not runtime qualification.

## Agent checkpoints

Core owns runtime context serialization. Root Omnix controls the live agent and
exposes checkpoint export/restore through Dart. Hosts supply fresh executors
and access policy when restoring a session.

`OmnixAgentSession.exportCheckpoint()` returns sensitive context.
`restoreCheckpoint()` restores context on a fresh session. Treat checkpoints as
private trusted application data, not marketplace artifacts or authorization.

Historical context must never execute tools during restoration. A saved
checkpoint is not proof that an uncertain action completed. Compatibility
validation and supported content depend on the current adapter and checkpoint
format; applications must handle rejection rather than silently discard context.

Checkpoint persistence and a product's visible transcript serve different
purposes. Define how user messages, partial replies, errors and tool results
are retained, including failures after an external action already ran.

## Opt-in checkpoint test

The Windows-only native test at `test/native_agent_checkpoint_test.dart` requires:

- `OMNIX_SESSION_TEST_BRIDGE`: a matching rebuilt root bridge.
- `OMNIX_SESSION_TEST_RUNTIME`: the compatible native runtime.
- `OMNIX_SESSION_TEST_MODEL`: an existing compatible model.

Run from the repository root:

```powershell
dart test test/native_agent_checkpoint_test.dart
```

On other platforms or without the required inputs, the test is skipped, not passed.
The test exercises a host callback, exports context, recreates the engine and
agent with fresh callbacks, and checks that restoration does not execute the
historical tool before continuing inference.

This test is not evidence of mobile process-death, low-memory recovery, all
media combinations or every host executor.

## Data-safe validation

Use isolated application IDs and disposable test stores for device tests.
Validate representative upgrade records separately from live user data.
Do not uninstall an installed consumer app or clear its model/database stores
as a testing shortcut.

For Android distribution, inspect native packaging in both a direct APK and
APKs generated from the release App Bundle. Signing and update compatibility
are application release responsibilities.
