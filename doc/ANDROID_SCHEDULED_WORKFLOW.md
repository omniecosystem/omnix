# One-shot background workflow qualification

In the example Home, using scoped assistance, ask:

> In one minute, read my phone battery and notify me with the result.

The agent loads `scheduled-device-report`, saves a plan, then calls
`host_schedule_event_task` with its saved ID and a 60-second delay. Allow
Android's notification permission when prompted. Confirm the tool returned
`scheduled`, then press Home to background the app. No model is needed when
the worker wakes. Inspect the saved job in Workflow afterward for step receipts.

Android WorkManager enqueues a unique one-shot worker keyed by the admitted
Rust job. It starts a headless Flutter engine with a restricted host catalogue;
the Dart adapter opens the saved job and Rust runs/checkpoints its steps.
The battery step's saved `/report` output feeds the notification step. Notification
posting is not proof of user reading. A stable job-based notification ID avoids
multiple visible notifications from replacement posting; uncertain actions are
still not automatically recovered or retried.

This is Android-only qualification, not cross-platform scheduling parity.
WorkManager's initial delay is a minimum, not an exact alarm. Doze/vendor battery
restrictions may defer it; force-stopping the app prevents delivery until Android
allows work again. No recurring schedule, inference background step, accessibility
automation or calendar access is added. Windows scheduling is not implemented.

The worker checks the task remains enabled and only allows saved battery/notification
steps. Stop the task before it starts to revoke future execution. Interactive-review
and expiring delegated modes cannot be silently converted into unattended grants;
this slice requires scoped authorization. Stop does not undo already running effects.

The worker never returns automatic retry on failure. A timeout or lost acknowledgment
requires inspecting the Rust checkpoint. A notification-permission denial or enqueue
failure can leave an admitted pending job; inspect it rather than creating another
run to guess whether scheduling succeeded.

Tests of repository admission and an APK build are not proof of background device
execution. Qualify on a real phone with Home visible, Home backgrounded, notification
permission denied, task stopped before its deadline, and process restart without
uninstalling/clearing data. Compare the durable Rust receipts with the visible alert.
