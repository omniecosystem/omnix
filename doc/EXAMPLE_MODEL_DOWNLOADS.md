# Example background model transfers

Status: host-tested adapter with recovery hardening, 9 October 2026. Background
reliability is not yet qualified on a phone.

## Boundary

Core owns trusted artifact metadata, durable transfer reservations, SHA-256 and
size checks, container validation and publication into the installed catalog.
Its Rust implementation is exposed through the same Dart API.

Only the Flutter example depends on `background_downloader`. This adapter owns
permissions, task scheduling, notification setup, progress observation and task
reconciliation. Consumer apps can implement another transport using Core's
reservation API; no Flutter transport dependency was added to that API.
Complete pure-Dart packaging of the existing module remains separate work.

```text
User consents -> Core reserves destination -> OS task transfers bytes
  -> app observes completion -> Core verifies and publishes -> user selects model
```

Network tasks use a dedicated group and deterministic reservation-based task IDs.
Backgrounding or disposing the UI does not request cancellation of the OS task.
Reopening the app reattaches to recorded active/completed tasks. It does not
automatically re-enqueue failed tasks or recover every OS-killed task. Empty
reservation files are never treated as completed downloads.
If no active/completed task is available, reopening surfaces the first retained
failed, cancelled or untracked reservation rather than silently hiding it.
Missing tracking asks for an explicit retry; it never schedules a new download
on its own. Active/completed transfers take priority over interrupted ones.

Rust publication renames the reservation directory on the same filesystem;
it does not copy the whole model again. OS transfer services may use temporary
files of their own. File imports still copy, and pickers may make a cached copy.

## Important limits

- The example pins downloader **9.5.9**: this workspace uses Dart 3.12.2, while
  downloader 9.6.x requires Dart 3.13. No SDK upgrade is implicit in this change.
- Tasks use priority zero with notifications and `RUN_USER_INITIATED_JOBS` so
  Android 14+ can select the package's user-initiated transfer (UIDT) service.
  Older Android uses configured foreground work. These paths avoid the package's
  ordinary background-worker timeout when successfully selected, but OS limits
  and denied permissions can still interrupt transfers. They need device tests.
- Hugging Face tasks disable pause/resume, following the reference's validator
  policy. Explicit retries may start again rather than preserve network progress.
  Very long transfers on slow connections are **not yet reliably qualified**.
- Tasks request three retries. Observed HTTP 401/403/404 stops retries and asks
  the user to correct access or URL. Automatic retry behavior while the app is
  absent remains controlled by the downloader.
- Notifications and OS background permissions can be denied. Force-stop, process
  termination, battery restrictions and platform-specific behavior need testing.
- Verification runs in the app process. If a transfer completes while the app
  is absent, reopening reconciles completion and starts verification.
- Failed verification retains Rust's bytes/reservation but clears the completed
  OS task record when cleanup succeeds so an explicit retry can request a fresh transfer. Pending file
  reclamation is not automatic; retained files can consume significant storage.
- Transfers are currently observed one at a time by the example UI.

## Credentials

Rust reservations contain no URL or token. The downloader persists URL and
Authorization headers in its app-private task database to recover tasks. Those
records are not a secure-keystore integration. Completed records are deleted
after finalization (also after failed verification); failed/cancelled task records
can remain for retry. A crash between publication and task-record cleanup may
leave a stale record. Use narrowly scoped tokens and avoid shared device storage.
Cleanup failure after successful verification does not invalidate the installed
model: the UI shows the verified model and a warning about retained URL/headers.
Cleanup failure after rejected verification preserves the original integrity
error instead of replacing it with a database error. Automatic stale-record
reclamation and retry after a persistent cleanup failure remain separate work.

## Qualification checklist

Rebuild the example normally; do not uninstall it or clear its data. On Android,
if installing a built APK manually, use `adb install -r` for the example only.
Never uninstall on update failure; resolve signing/version mismatches explicitly.

1. Start with a small trusted preset, not a multi-gigabyte chat model.
2. Check progress and notifications, then background and reopen the app.
3. Test lost connectivity, denial of notifications, cancellation and retry.
4. Test app process termination separately from OS force-stop; compare outcomes.
5. Confirm only Rust-verified files appear as installed and can run inference.
6. Confirm installed models survive a normal restart without redownloading.
7. Qualify long Hugging Face transfers after addressing SDK/resume limitations.

Host tests cover reservation reuse, completed-task recovery, failed verification,
credential-error handling, scoped task construction and lifecycle detachment.
Regression tests also cover failed/cancelled/missing-task restart recovery,
cleanup failures after publication and preservation of integrity errors.
They do not establish Android/iOS background transfer reliability.
