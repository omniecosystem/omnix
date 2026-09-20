# Model management

The recommended LiteRT-LM setup is intentionally small:

```dart
final runtime = FlutterGemmaOmnix.createRuntime();
await runtime.initialize();
```

This registers the LiteRT-LM inference engine and exposes model operations at
`runtime.models`. Applications do not need to import Flutter Gemma or its
engine package directly.

## Sources

`OmnixModelInstallRequest` accepts network, Flutter asset, existing file, and
native bundled-resource sources. A successful installation becomes the active
inference model.

Network credentials belong to `OmnixNetworkModelSource.authToken`. They are
used for that operation only; applications must not persist them in plain text.

## Integrity

An install request can carry an expected byte length and SHA-256 digest. Both
must be supplied together. `OmnixModelInstallRequest.fromManifest` carries the
validated manifest values automatically.

On native platforms Omnix verifies the installed bytes using streamed hashing
off the UI isolate. A mismatch removes the invalid artifact and fails the
installation. Manifest-backed installation currently fails before downloading
on platforms where artifact verification is unavailable, rather than silently
weakening the integrity policy.

## Progress and cancellation

Pass `onProgress` to receive integer progress from 0 through 100. Pass an
`OmnixCancellationToken` when the host needs a cancel action:

```dart
final cancellation = OmnixCancellationToken();
final installation = runtime.models.install(
  request,
  cancellationToken: cancellation,
);

cancellation.cancel('Cancelled by the user');
await installation;
```

Cancellation is translated into `OmnixOperationCancelled`, independent of the
underlying inference plugin.

## Android foreground downloads

Setting `OmnixNetworkModelSource.foreground` to `true` requests the underlying
Android foreground download path. Omnix deliberately does not own permission
UI. The host must provide the required manifest declarations and decide how to
explain or pre-request notification permission.

For API 34 and newer, declare `FOREGROUND_SERVICE_DATA_SYNC` and merge
WorkManager's `SystemForegroundService` with `foregroundServiceType="dataSync"`.
The example application contains a working manifest.

## Lifecycle

`OmnixRuntime.initialize` initializes model infrastructure once. Opening a
conversation initializes the runtime automatically if needed. Closing the
runtime closes every conversation it owns before closing the native engine.
