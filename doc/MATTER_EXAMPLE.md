# Matter in the Flutter example

Open Nexus → Devices. The example selects a backend explicitly and displays
connection and readback results. This is a qualification interface, not a
general production provisioning application.

Commands pass through the public Nexus API into Rust and the selected host.
A command acknowledgment is not an independently verified attribute value.

## Windows

The example's Windows qualification path needs a separately staged, verified
Matter.js runtime bundle. It does not resolve arbitrary executables from PATH.

From the repository root, after following
[the bundle guide](../tool/matterjs_app/README.md):

```powershell
$bundle = (Resolve-Path .local-native/matterjs-app).Path
cd example
flutter run -d windows "--dart-define=OMNIX_MATTER_BUNDLE=$bundle"
```

The fixture uses disposable software-light state. Keep port 5542 free.
Disconnect closes the owned child; this does not create a persistent
commercial-device pairing.

## Android

Android uses the official SDK through Java/JNI, not Matter.js.
Build the [pinned SDK artifact](../tool/matter_android_sdk/README.md) and follow
the [module resolver contract](../modules/omnix_nexus/android/README.md).

A clean checkout needs a compatible local artifact, verified cache or an
explicitly configured artifact URL. No default public release URL is supplied.

Build without deploying:

```powershell
cd example
flutter build apk --debug --target-platform android-arm64
```

Device testing requires a separate deployment/signing decision.
Do not uninstall a consumer app or clear its data to resolve an install error.

## Fixture testing

Use a trusted multicast-capable LAN and a disposable software light.
Supply the test host's actual address. Commissioning changes test fabric state;
restarting a fresh fixture can require commissioning again.

Frontend closure detaches from Android's process-owned controller rather than
claiming deterministic SDK deletion. Native failures can require process restart.
Outstanding callbacks must retain their owners and not deliver results into
detached Flutter engines.

See the [isolated harness](../tool/matter_android_app/README.md) for test modes.

## Limits

A UI test with a fake session, an APK build, a startup test and an authenticated
device command establish different things. Test independent readback and
restart reconnect explicitly. Software fixtures do not qualify production
attestation, physical devices, BLE provisioning or every platform.
