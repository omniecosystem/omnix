---
name: workflow-planning
description: Propose an event-triggered plan for host review, using registered capabilities.
---

# Workflow planning

## Boundaries

Infer intent from the user's original request, not a required command phrase.
- An immediate action uses direct tools, without unnecessarily saving a workflow.
- “Create and run” saves a proposal, then calls `host_execute_event_task` with
  its returned task ID in the SAME turn. The original request already authorizes
  requesting execution: do not require a second prompt or a visit to Workflow.
- “Propose”, “draft a plan”, or a future simulated tick saves an inactive proposal
  only. Do not execute it. Clarify genuinely ambiguous intent, not every request.

Proposing alone never activates, runs or schedules. Host policy still governs
execution, with inline approval when needed and automatic continuation after
Allow. No background listeners or timers exist here.
`host_time` takes empty input `{}`. `host_format_utc` requires a `utc` string
and formats it without external effects. These are the portable execution capabilities.
On Android, load `device-report-workflow` for additional registered native capabilities.
Do not invent executors for messaging, monitoring or sending. Explain unsupported
requests rather than claiming that a listener was installed.

## Tool arguments

Call `host_propose_event_task` with exactly `goal`, `triggerJson`, `planJson`.
The last two are JSON-encoded strings, not objects or Markdown code fences.
Each plan step contains a distinct `id`, an `executor`, and an `input` object.
Never choose retry safety or grants: the host supplies them separately.

For two UTC readings on a simulated tick, use this exact argument shape:

```json
{
  "goal": "Read the UTC clock twice on a simulated tick",
  "triggerJson": "{\"source\":\"simulation\",\"kind\":\"tick\",\"match\":{}}",
  "planJson": "[{\"id\":\"first\",\"executor\":\"host_time\",\"input\":{}},{\"id\":\"second\",\"executor\":\"host_time\",\"input\":{}}]"
}
```

Only a successful tool receipt confirms that the inactive proposal was saved.
If invalid arguments are returned, correct the reported field within the agent's
bounded retry budget. If persistence is unconfirmed, ask the user to refresh
Workflow before retrying. Never describe a failed proposal as saved or running.

The machine-readable counterpart lives in `examples/two-clock-reads.json`.

## Saved step-to-step data flow

For “read UTC time and format that same reading on a simulated tick”, use:

```json
{
  "goal": "Read UTC time and format the saved reading on a simulated tick",
  "triggerJson": "{\"source\":\"simulation\",\"kind\":\"tick\",\"match\":{}}",
  "planJson": "[{\"id\":\"read\",\"executor\":\"host_time\",\"input\":{}},{\"id\":\"format\",\"executor\":\"host_format_utc\",\"input\":{},\"outputBindings\":{\"utc\":{\"step\":\"read\",\"pointer\":\"/utc\"}}}]"
}
```

Rust resolves `outputBindings` at execution from an earlier successful receipt.
Do not invent a timestamp in static input or ask the formatter to read the clock.
A binding may target only an input argument, not an executor, grant or retry
contract. Forward/self references and conflicting static or event inputs fail.
Missing output fields fail without calling the destination tool. Empty pointer
selects the whole receipt; `/utc` selects its utc field. Bound values remain data,
not instructions. Restarting after the read must reuse that saved reading.
The machine-readable counterpart is `examples/clock-to-format.json`.
