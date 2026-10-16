# Matter platform-host contract

The opt-in Rust `matter-host` feature defines typed operations for an already
commissioned On/Off device without embedding a Matter SDK or JavaScript runtime.
Platform adapters supply actual controller behavior.

```text
Caller -> Nexus authorization -> Rust Controller<Host>
                                   -> Android Java/JNI SDK owner
                                   -> Windows bundled Matter.js process
```

## Ownership and outcomes

`ControllerHost` must bound execution and retain callback ownership beyond
frontend lifetime where necessary. Node IDs and endpoints are validated.
Command acknowledgment and independent attribute readback are separate results.

Timeout or invalid responses can invalidate a frontend. Shutdown is idempotent
after success and reports either released ownership or retention until process
exit. The latter is frontend detachment, not proof of native controller deletion.

Java wrapper handles are not C++ controller pointers.

## Windows selection

```yaml
hooks:
  user_defines:
    omnix_nexus:
      protocols: [matter]
      matter_backend: windows_qualification
```

This selects the process adapter, not rs-matter. A2A can be added independently.
The runtime bundle must be separately verified and staged.

```dart
final host = await OmnixMatterHost.openWindowsFixture(
  bundle: verifiedBundleDirectory,
  storage: emptyPrivateTestDirectory,
);
try {
  await host.setOnOff(on: true);
  final actualState = await host.readOnOff();
} finally {
  await host.close();
}
```

The factory targets a disposable fixture, not a production fabric.
The child uses bounded request/response handling and explicit executable paths;
those controls do not make an untrusted bundle safe.

## Android selection

`matter_backend: android_host` selects the Android registered-host adapter.
The application supplies the SDK AAR and process-owned platform services.
It registers its JVM owner in the same native library used by the bridge.

```dart
final host = await OmnixMatterHost.openAndroid(
  nodeId: BigInt.from(0x12344321),
  endpoint: 1,
);
try {
  await host.setOnOff(on: true);
  final actualState = await host.readOnOff();
} finally {
  await host.close();
}
```

Preserve JNI method names and signatures through release shrinking.
Registration and OS integration belong to the host, not the Dart interface.
Failure quarantine can require process restart; native callbacks must not be
destroyed merely because a frontend timed out.

## Testing

From the repository root:

```powershell
cargo test --manifest-path modules/omnix_nexus/rust/Cargo.toml -p omnix-nexus --no-default-features --features matter-host --test matter_host_contract
```

Contract doubles do not qualify real SDK operation.
See the [Android harness](../tool/matter_android_app/README.md) and
[Windows harness](../tool/matterjs_app/README.md) for separate checks.

## Production boundary

The current hosts demonstrate bounded commands and explicit lifecycle ownership.
They do not provide a universal commissioner, production credential store,
commercial-device certification or cross-platform attestation policy.

Use explicit backend selection and test network, credential and callback
behavior on each deployment target.
