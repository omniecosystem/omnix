---
name: device-report-workflow
description: Propose a native Android battery report and a user-controlled share handoff.
---

# Device report workflow

Available only in this Android consumer. The Rust engine has no battery or
sharing builtins. `host_battery_status` takes `{}` and returns a saved `report`
string, percentage and charging state. `host_share_text` takes `text` and opens
the Android share chooser. It does NOT send a message or confirm delivery.
`host_open_app` takes `{"application":"settings"}` and opens Settings without
changing anything. Never invent other applications or background listeners.

For a request to propose a battery-report sharing workflow, call
`host_propose_event_task` with these arguments. Do not execute the steps directly
while proposing. For propose-only or simulated-tick requests, stop after saving;
the user can inspect and manage it in Workflow. If the original request is to
create AND RUN now, immediately call `host_execute_event_task` with the returned
task ID in the same turn. No second message or simulated tick is needed. Any
required approval appears inline in Home; Allow resumes execution. A manual
start queues only that task. The data and handoff are native.

```json
{
  "goal": "Read the phone battery and open a share sheet with that saved report",
  "triggerJson": "{\"source\":\"simulation\",\"kind\":\"tick\",\"match\":{}}",
  "planJson": "[{\"id\":\"battery\",\"executor\":\"host_battery_status\",\"input\":{}},{\"id\":\"share\",\"executor\":\"host_share_text\",\"input\":{},\"outputBindings\":{\"text\":{\"step\":\"battery\",\"pointer\":\"/report\"}}}]"
}
```

The host supplies recovery safety, not the model. Reading battery is repeatable;
opening Settings or a chooser requires reconciliation if interrupted before the
handoff receipt was saved. Do not blindly retry uncertain external effects.
`editor_opened` means only that Android accepted opening the chooser; cancelling
it is not a failed delivery, and completing the workflow never means text was sent.
After restart, the share step must use the saved report, not reread battery or
invent text. Only a successful proposal receipt proves an inactive plan was saved.
