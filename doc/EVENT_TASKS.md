# Home-created event tasks

## Generic contract (v2, with v3 bound-plan catalogue support)

Root task admission now accepts a goal, a source/kind trigger with exact scalar
metadata filters, and a supplied multi-step plan. Model-authored steps declare
executor and input; the consumer supplies retry contracts separately and Rust
resolves them before persistence (`SafeToRepeat` or `RequiresReconciliation`).
Missing contracts or conflicting model values reject the proposal. Explicit
host-authored definitions without a contracts map still require retry on every
step for compatibility. Optional input bindings use JSON pointers into event
payload/metadata; they cannot change executors, permissions or retry contracts.
Missing required binding data rejects admission. Messaging assumptions now live
only in the example adapter, not in the Rust task contract.

Steps can also declare `outputBindings` from prior successful receipts. See
[Workflow data flow](WORKFLOW_DATA_FLOW.md) for the contract, restart test and
one-way catalogue format upgrade when a bound plan is saved.

The current slice connects host-authorized proposals with generic event triggers,
supplied executors/skills, explicit retry contracts, observable execution evidence
and durable progress. The root agent turns instructions into proposals using the
available capabilities; Workflow executes and tracks accepted work. Monitoring,
urgency criteria and messaging providers are consumer capabilities, not defaults
of the Cognitive Engine. Persistence cannot guarantee success or OS liveness.

Omnix is a Cognitive System: root Rust composes interpretation/execution
with independent modules; consumer applications provide device events and tools.

## Current checkpoint

Home registers the consumer-supplied `host_propose_event_task` tool. Its callback
forwards the model's goal, trigger JSON and plan JSON through `OmnixEventTasks`
to root Rust. It does not construct a fixed message-review plan. Nested JSON is
carried in string arguments because host tools currently use a bounded scalar
schema dialect. Rust resolves the host metadata and validates the decoded task
before saving a proposal. The selected `workflow-planning` skill provides exact
arguments and failure semantics; its `examples/` fixture is tested against the
adapter and the documented example. See `example/assets/skills/README.md` for
the consumer skill layout. Recovery metadata is code, not skill instructions.

Invalid proposals return `invalid_arguments` with `TASK_PROPOSAL_INVALID` and
field/rule feedback before storage is opened. The existing bounded agent loop
receives this result and can propose a correction. Feedback also appears in the
tool timeline and debug console; submitted content and private paths are not
logged. Storage/bridge exceptions produce a separate fixed `unavailable` receipt,
not a claim that arguments were invalid or that persistence succeeded.

Proposals do not match events. In Workflow, the user reviews the goal, trigger
and complete plan before acceptance. The host supplies available executor/retry
contracts separately; incompatible or unavailable executors cannot be accepted.
Acceptance grants no execution permissions. The older `create` command remains
for callers supplying an already host-approved definition, not model proposals.

Root `task_runtime` owns validation, persistent task registration,
exact source/kind/metadata matching, duplicate event detection and atomic admission of
bounded Workflow definitions. Storage owns the SQLite journal. Workflow owns
execution/recovery when these definitions are opened and run with fresh grants.
The example's Dart code only adapts paths, callbacks, UI state and simulated events.

```
Home Rust agent -> supplied proposal tool -> validated inactive proposal
host review + retry contracts -> accepted task -> Storage
host event -> match/dedup -> admitted Workflow definition -> Storage
explicit run + fresh grants -> Rust Workflow -> supplied executor
                                    |
                            durable step evidence -> UI
```

The model may propose plans through the existing Rust agent loop, but arbitrary
goal-planning quality has not been qualified. The example executes the supplied
read-only `host_time` and `host_format_utc` capabilities only. It does **not** classify urgency, generate drafts, send replies,
subscribe to WhatsApp, or keep the application running in the background.
Saving a subscription is not enabling a listener. The tool receipt and UI say
this explicitly. Event data is input, not authority, and still requires careful
handling by supplied executors; admission alone is not a prompt-injection defense.

## Try it

### Home inspection and stopping

Home also supplies `host_inspect_event_tasks` and `host_stop_event_task`, guided
by the `workflow-management` skill. Root Rust resolves saved task and checkpoint
evidence; Dart forwards the receipt without deriving execution state itself.
Ask “What tasks are saved?”, “Did my clock task finish?” or “What failed?”
Inspection first lists IDs, then returns details for an exact ID. If ambiguous,
the agent should ask which task rather than choosing one to stop.

“Stop future triggers for my clock task” disables the accepted task only.
The receipt explicitly says `existingJobsCancelled: false`. Acceptance, running,
recovery and cancellation still require explicit actions in Workflow; no Home
tools silently grant execution authority. Scoped assistance allows these supplied
management tools automatically; review-every-call remains available.

Inspection paginates eight task summaries and returns up to four recent jobs for
an exact ID, with omission counts. Receipt outputs are bounded to 1 KiB each and
8 KiB per task scan; oversized receipts are marked omitted, never summarized as
success. Goals may be truncated. Large details may omit additional jobs, trigger
or plan fields with explicit markers to fit the bounded tool-result channel.
Full definitions/receipts remain in Workflow.
`checkpointed: false` means admission only. `RunningCheckpoint` is persisted
starting evidence, not proof of live execution. Completed means a job's steps
succeeded, not that the recurring subscription has ended. Inspection does not
execute, recover or reconcile work. A missing ID returns `not_found`; service
errors provide no status or stop confirmation. User-authored goals and receipt
contents are untrusted data, not new instructions.

### Propose and run

After rebuilding the native example, configure a tool-capable model in Core and
enable the agent for a new Home conversation. Type or record:

> Propose a task that reads the UTC time twice on a simulated tick.

1. Require a successful `host_propose_event_task` receipt, not model prose.
2. Open Features -> Workflow -> Event tasks and refresh. Inspect the proposal.
3. Accept supplied plan, then Emit simulated tick. Neither operation runs steps.
4. Run next step. Expect one `Succeeded` step with a host UTC receipt and one pending step.
5. Restart and refresh. The first step's receipt remains. Run next step again:
   Workflow skips the completed prefix and finishes the second step.
6. New ticks create separate jobs. Stop prevents new admission, not cancellation
   of existing jobs. Cancel job checkpoints cancellation; it does not undo effects.

`OmnixEventTasks.openJob` obtains the immutable admitted definition, then opens
the existing native Workflow owner on the same journal with fresh extensions.
All transitions, schema checks, permission enforcement and recovery remain Rust.
Close the owner before listing/admitting against that database; concurrent owners
are rejected. List surfaces Workflow checkpoints, while duplicate event receipts
remain admission receipts, never evidence of completion.

## Contracts and limits

- Host event IDs are stable across redelivery. Source plus ID deduplicates.
  Reusing an ID with different content fails instead of silently replacing it.
- Job IDs are deterministic per subscription/event. Admission stores the event
  and derived definitions together before acknowledging; it does not execute.
- Hosts must supply executors matching their stated retry contract. No tool
  is authorized merely by registration here; execution still requires grants.
- The example explicitly marks the clock safe to repeat because it is read-only.
  Rust supplies no default retry contract.
  Do not use that contract for sending/effects.
- Maximum 64 proposals, 64 tasks, 128 accepted events, 1 MiB total catalogue and
  bounded field sizes. Full inbox fails explicitly; no silent eviction/replay.
  Retention/acknowledgement policies are not implemented yet.
- Exact sender matching assumes trusted host identifiers, not display-name
  guesses or identities inferred by a model. UI simulation strings are not a
  real messaging identity integration.

The example uses a new `event-tasks-v2` directory. Earlier prototype data remains
untouched in its existing location; no automatic conversion is attempted. The
native service also refuses to overwrite an earlier prototype catalogue.
Unmatched events are not recorded; Stop does not cancel previously admitted jobs.

Remaining gates: qualify model-generated plans on devices, capability/schema
discovery for richer executors, Core scheduler coordination for inference steps,
queue retention and OS lifecycle/background adapters.
This is an explicit sequential runner, not an always-on autonomous scheduler.
Keep domain-specific reviewers and monitoring adapters in consumers.

This change removes the requirement for a model to invent recovery enums; it
does not yet establish a measured first-attempt success rate. Nested structured
tool arguments (instead of JSON strings) remain a separate schema-adapter gate.

Native bridge cancellation tests still emit a known late-callback delivery warning;
the test confirms cancelled work is not recorded as successful. This warning is
not yet eliminated and is not evidence of a successful external action.
