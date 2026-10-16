# Windows Matter.js packaged-app harness

Qualification application for a bundled Matter.js controller runtime.
It is not a production controller distribution or a Windows C++ SDK adapter.

## Build and test

From the repository root, prepare the pinned Node runtime and fixture dependencies
using `tool/stage_matterjs_app.ps1`. Follow that script's required arguments and
provenance checks, then:

```powershell
cd tool/matterjs_app
flutter pub get
flutter test
flutter analyze
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/packaged_controller_test.dart -d windows
```

The staged runtime lives in ignored build state, not source control.
The application expects its runtime beside the executable rather than a
globally available Node installation.

## Test scope

The fixture commissions a disposable software light, sends On/Off commands,
reads attributes and exercises controller reopen with retained test state.
Both peers use Matter.js; this is not physical-device or cross-SDK qualification.

The test uses network sockets and temporary credentials.
Run only on a trusted test network. Controller reopen is not whole-application
crash recovery.

## Distribution boundary

Runtime provenance, Node/dependency notices, updates and platform packaging
need review before shipping a binary. Passing this harness does not qualify
BLE provisioning, production attestation or hostile-process isolation.

See [the controller fixture](../matterjs_spike/README.md) and
[Nexus backend boundaries](../../modules/omnix_nexus/README.md).
