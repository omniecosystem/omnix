# Verified Workflow data flow

`omnix-workflow` resolves input arguments from earlier successful, durable
receipts. Root Omnix admits plans and supplies fresh authorization. Dart exposes
typed definitions; the example supplies executors and skill instructions.

```json
{
  "id": "format",
  "executor": "host_format_utc",
  "input": {},
  "outputBindings": {"utc": {"step": "read", "pointer": "/utc"}}
}
```

The pointer is relative to the source step's actual output, not its serialized
checkpoint envelope. Empty pointer selects the whole output; a successful JSON
null is valid. Only earlier steps may be referenced. At most 16 arguments may
be bound per step. Static/event arguments cannot overlap output bindings.
Resolved input is bounded to 64 KiB. No expression evaluation, model-based
coercion or access to grants/executors/retry metadata is provided.

Resolution occurs before the destination's Running checkpoint and host dispatch.
Missing/oversized data produces a durable Failed receipt with
`WORKFLOW_BINDING_UNAVAILABLE` and `executionStarted: false`. No destination
effect occurred, and no automatic retry is scheduled. A changed binding is a
changed definition and cannot reuse an existing workflow identity.

Saved definitions remain immutable. After restart, a pending dependent step
uses the already committed successful receipt; the source is not rerun. A
successfully reconciled receipt can also supply data. Failed or uncertain
sources cannot drive subsequent execution. Existing definitions without output
bindings deserialize unchanged as snapshot version 1. Bound jobs use snapshot
version 2, rejected by older Workflow binaries. The existing catalogue is promoted
from version 2 to 3 when a bound plan is first saved; records and paths are retained,
but older task services reject that catalogue rather than ignore the new bindings.
This is a one-way format upgrade; do not downgrade the binary against that data.

## Try the example

Rebuild/update the example and start a new Home agent conversation:

> Propose a task that reads UTC time and formats that same saved reading on a simulated tick.

Review/accept the plan in Workflow, emit a simulated tick, and run the read step.
Record its `utc` receipt. Restart the app, refresh Workflow, then run the format
step. Its UTC value must exactly equal the saved reading. Ask Home whether the
task finished; a completed job does not end the recurring subscription.

Both callbacks are consumer-supplied and read-only. No background listener,
messaging provider or physical action is baked into the Cognitive Engine.

## Reliability evidence

Inspection reports per-step `failureCategory` and aggregate `failureCategories`
over all saved jobs, including omitted receipt details: binding_unavailable,
invalid_arguments, denied, unavailable, failed, uncertain_execution. Categories
are derived from actual checkpoint states/receipts before output truncation.
They count current persisted failures/uncertainty, not every historic attempt,
model proposal repair, or first-attempt success rate. They are diagnostic signals,
not an automatic retry policy. A recovered/reconciled state changes the counts.

Tool schema rejection is distinct from denial. Unknown results and lost replies
remain uncertain; unsafe Running steps require host reconciliation after restart.
Failed steps stay blocked. Harmless model argument repair must not be confused
with replaying an external action. Real-model reliability still needs repeated
device qualification with matched configuration and varied requests.
