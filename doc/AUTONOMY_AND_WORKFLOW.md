# Autonomy and durable execution

## Autonomy is policy, not unrestricted access

Autonomy settings govern how already granted capabilities are used. They must
not grant tools, override OS permissions or weaken validation. A model, character,
skill or remote node cannot raise its own autonomy level.

Implemented session-scoped modes (`agent::approval` in Rust,
`OmnixApprovalPolicy` in headless Dart):

| Preset | Behavior |
| --- | --- |
| Review every call | Ask before every tool, including reads; enforce grants |
| Scoped assistance | Automatically allow an explicit tool list; review all others |
| Delegated scope | Automatically allow an explicit tool list within a call budget and lifetime; then require review |

Presets are shortcuts for per-capability policy, not a universal risk slider.
High-risk capabilities can require review regardless of preset. Policy needs
resource scope, expiry, revocation and allowed effects where relevant. The consumer
supplies those choices with its tools and skills. Root Rust owns only the reusable
enforcement mechanism, so Dart and Rust consumers use the same agent-loop semantics.
The host presents consent and enforces OS/resource constraints. Registration alone
confers no authority.

The registry checks execution grants before calls, then the Rust approval guard
checks per-call review. `always_review` overrides automatic allowance; review-every-call
overrides both. Delegation requires 1–32 automatic calls and a 1–3600 second
session lifetime. Resource constraints remain executor-owned; this is not yet a
resource-specific grant, revocation registry, or durable permission service.
The guard never raises grants. Ungranted batch calls execute nothing. Review is
per call, not atomic approval/rollback of an entire batch.

The bridge invokes the same host binding with `phase: approval`, a correlated
request ID, tool name and exact arguments. Its response contains `approved: true`
only for that call. Missing reviewers and host exceptions deny; the bridge wait
is bounded and cancellation is checked again before dispatch. Denied review
produces a structured `denied` outcome without invoking the executor.
Registered host schema validation precedes review; semantic validation and OS
permissions are still enforced by the executor. Existing registrations without
an approval policy retain their explicit-grant behavior for compatibility.

No approval policy means no additional engine confirmation, not unrestricted
access: only registered, explicitly granted tools can execute. The consumer may
choose an OS-only review policy. Platform permissions still belong to the app,
not to individual agent requests, and an already granted permission may not prompt
again. The host must explicitly check/request permissions where required. Rust
does not invent consumer business policies; it also runs the agent loop and
enforces schemas, grants, cancellation and execution bounds. Platform access and
consumer consent to an intended effect are separate decisions.

The example defaults to scoped assistance: clock, skill loading, device facts
and selected Knowledge reads are automatic, as are allowlisted Settings opening,
calendar-editor preparation and explicitly enabled email-draft preparation.
These tools do not send messages, save events, change settings or control physical
devices. Tools outside the supplied automatic list require a Flutter one-call
review. After Rust authorizes that exact call, the trusted example host
adapter marks the handoff as engine-authorized, avoiding a duplicate native
dialog. This marker is not a model argument, grant or OS permission bypass.
Standalone adapter calls still require native review. Argument checks and OS
permission handling remain native. Dialog dismissal, 20-second expiry,
app backgrounding and cancellation refuse the pending call. Policy is currently
selected in Core before the first message: Scoped assistance or Review every
call. It cannot change mid-session and is not yet persisted across app restarts.
Do not advertise
"unrestricted" mode or treat callbacks as a sandbox.

## Calendar qualification slice

`host_prepare_calendar_event` is a consumer-supplied Android tool. Rust owns the
agent loop; Dart validates bounded text and explicit-zone timestamps; Kotlin
independently validates arguments and uses `ACTION_INSERT`
with `CalendarContract.Events.CONTENT_URI`.

The shared native approval path supports Cancel, dismissal, expiry, host closure
and programmatic cancellation. Outcomes are `denied`, `invalid_arguments`,
`unavailable`, `failed`, or `editor_opened`. The last means handoff only: Omnix
cannot claim the event was saved or observe a later editor Cancel. No direct
calendar write or calendar permission is added. See the official
[Calendar Provider intent guidance](https://developer.android.com/identity/providers/calendar-provider).

Approval uses the correlated JSON bridge contract with typed Dart policy and
handler APIs; the Rust-only API accepts a `ToolApprover` implementation without Dart.
Foreground approval expires after 20 seconds, below the bridge's 30-second wait.

## When Workflow enters

`omnix-workflow` now has an independent Rust execution/checkpoint foundation;
root headless Dart now exposes its Storage-backed authorized execution. Use it
when work must survive a session or process, not to rename
the interactive agent loop. Storage provides persistence; Workflow owns job
state, scheduling, retries and recovery; root Omnix composes these with agent
decisions and granted executors. Core owns inference resource arbitration.

The first implementation gate is persisted task identity/transitions,
cancellation, execution leases and restart recovery, tested with deterministic
executors before an LLM. Record external side-effect outcomes and idempotency
keys; uncertain outcomes must not be blindly replayed. Retry only operations
with safe retry contracts. Recheck grants when resuming.

Next qualify the example UI and device/process-restart behavior through that API.
OS background scheduling remains a host adapter concern: a durable queue does
not keep a mobile process alive.

Sequence: foreground approval/outcome contract -> persistent agent/tool records
-> first native Workflow recovery slice. Useful Knowledge already exists;
Workflow is no longer waiting for Knowledge to begin. The first slice implements
sequential transitions, durable cancellation and conservative restart recovery
through host-supplied adapters. Local SQLite ownership is protected by an OS
lock. Platform scheduling and UI integration require host adapters; this does
not imply distributed leases or all-platform background execution. See
[the composed API testing guide](WORKFLOW_INTEGRATION.md).
See [Workflow scope and restart demonstration](../modules/omnix_workflow/README.md).
