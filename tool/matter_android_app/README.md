# Android Matter qualification harness

Isolated Flutter controller host for the official Matter SDK's Java/JNI
integration. Its application ID is
`xyz.omniecosystem.qualification.omnix_matter_android_app`.
It is not OmniAsk or the root Omnix example.

Android uses the C++ SDK, not Matter.js. The `android_light.mjs` fixture runs
on a separate desktop host; its name identifies the test client.

## SDK and build

Build the source artifact using [the SDK pipeline](../matter_android_sdk/README.md).
Set `OMNIX_MATTER_ANDROID_AAR` to a matching trusted AAR.
Candidate builds additionally require the matching candidate checksum when
the harness's pinned artifact differs.

From the repository root:

```powershell
cd tool/matter_android_app
flutter pub get
flutter analyze
flutter build apk --debug --target-platform android-arm64
```

These commands build without deploying to a phone.

## Test network and fixture

Use a trusted LAN allowing the required UDP and multicast traffic.
USB alone is not the Matter transport. Do not disable firewall protection to
force a pass.

The separate [Matter.js fixture](../matterjs_spike/README.md) supplies a
disposable software light. Use its current LAN address, not a documented
workstation's address. Public fixture credentials are not production secrets
or appropriate commercial device credentials.

## Explicit device execution

`run_control.ps1` requires a device ID and fixture address.
It builds an isolated test target, stops that test package, attempts an in-place
install and attaches to its VM service. Review signing compatibility first:
an in-place install is not a universal guarantee of data preservation.
The runner must not fall back to uninstalling an incompatible package.

Modes include commissioning, lifecycle/discovery probes, a JNI Rust host and
the registered FRB host. Some modes require a previously commissioned fixture;
consult the script's argument validation before running it.

Do not run this harness against a consumer application ID or production fabric.
No device operation is required to review or publish its source.

## Ownership and evidence

The process host retains the SDK controller independently of Activity lifetime.
Frontend detachment and cancellation do not imply native controller deletion.
The SDK's public close behavior must not be mistaken for deterministic teardown.

Check commissioning, independent attribute readback, process-restart reconnect,
callback lifetime and late-result handling separately. Passing startup is not
proof of device control.

Fixture trust is explicitly test-only. Unknown roots must not be accepted by
an unconditional attestation bypass. Production trust-store configuration,
commercial devices and general BLE provisioning need separate validation.

See [the shared host contract](../../doc/MATTER_HOST_CONTRACT.md).
