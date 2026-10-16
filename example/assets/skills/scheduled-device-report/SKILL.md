---
name: scheduled-device-report
description: Schedule a phone battery report notification without keeping Home open.
---

For an explicit delayed request such as "In one minute, read my battery and
notify me", save this plan using host_propose_event_task:

- goal: the user's request
- triggerJson: `{"source":"android-workmanager","kind":"once","match":{}}`
- planJson:
  `[{"id":"battery","executor":"host_battery_status","input":{}},{"id":"notify","executor":"host_notify_text","input":{},"outputBindings":{"text":{"step":"battery","pointer":"/report"}}}]`

Then call host_schedule_event_task with the exact returned task ID and
delaySeconds=60. Do not call host_execute_event_task: that would run immediately.
For other explicit delays use seconds, between 10 and 86400. No recurring
schedules are implemented. Do not claim exact timing: Android may defer work.

Scheduling is not execution. Report only a confirmed scheduled receipt.
Notifications need Android permission; a denied permission means no confirmed
schedule. Never queue a replacement to repair an uncertain receipt. Background
execution uses the saved Rust workflow and does not load the language model.
Only battery reads and notifications are currently allowed in background.
