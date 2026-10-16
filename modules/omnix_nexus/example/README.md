# Standalone Nexus example

A minimal Flutter host for `omnix_nexus`, with no aggregate Omnix dependency,
model downloads, embeddings, database, account or Tailscale.

From this directory:

```powershell
flutter pub get
flutter run -d windows
```

Select **Run local demo**. The example creates two temporary identities, approves
the caller, opens a loopback listener, receives a signed A2A public answer, and
checks that an empty private answer is refused. It closes the listener and deletes
only its own temporary directory afterwards. Identities are intentionally not
persisted in this small example; the module supports durable identity directories.

Android is scaffolded under its own application ID:
`xyz.omniecosystem.omnix_nexus_example`. It is not OmniAsk and must never adopt
OmniAsk's application ID. No Android installation or device run was performed for
this addition; run it only after checking the target device and app ID:

```powershell
flutter devices
flutter run -d <device-id>
```

First builds require Rust and compile the native Nexus library. No AI model is
downloaded. The widget preview uses a fake callback rather than native networking.
Widget tests exercise loading, results, retry and disposal; they do not prove
native networking. Existing module native-loopback tests cover the bridge.

The native integration harness is also hosted here, not inside a consumer app:

```powershell
flutter drive -d windows --driver=test_driver/nexus_integration_test.dart --target=integration_test/nexus_native_test.dart
```

Device installation/tests require explicit approval. Use only this example's
separate app ID, never the ID of an installed consumer app.

Verified on Windows on 3 October 2026: clean analysis, three widget tests, and
both native integration cases (the minimal demo and the peer/grant lifecycle).
Android scaffolding is present but was not installed or run for this addition.

This is an in-process, two-node loopback demo, not remote discovery, background
hosting, Matter commissioning, or a two-device UI.

- `lib/local_demo.dart`: public Nexus API calls and cleanup.
- `lib/demo_controller.dart`: presentation state.
- `lib/demo_app.dart`: minimal Omni-colored UI.
