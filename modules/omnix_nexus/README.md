# Omnix Nexus

Connect local capabilities to other systems through authenticated A2A exchanges
and experimental Matter controller adapters. Nexus is independently usable:
it does not require Omnix Core, Storage, an inference model or OmniAsk.

The reusable Rust crate is in `rust/backend`. The Dart package wraps a separate
native bridge and currently requires the Flutter SDK.

## Select protocols

Choose at least one protocol in the consuming application's build configuration:

```yaml
hooks:
  user_defines:
    omnix_nexus:
      protocols: [a2a]
```

Use `[matter]` or `[a2a, matter]` for the experimental Matter surface.
Selecting A2A does not include Matter, and selecting Matter does not include A2A.
Rust consumers select backend Cargo features explicitly with empty defaults.

The Dart build hook compiles the simulator backend in debug mode to limit build
cost. A2A and platform-host-only selections use a release native build. The
simulator profile is for development tests, not production device onboarding.

## A2A

The current A2A interface supports paired public-knowledge requests. Your host
supplies an asynchronous answer callback and controls retrieval, document
visibility and presentation. Nexus validates peer proofs and public grants
before invoking the callback; an empty answer denies the request.

Identity directories retain persistent keys and peer grants. Keep them in
private storage and manage pairing and revocation through the public node API.
Restoring an identity does not grant access to additional local capabilities.

The built-in listener binds to loopback. Your host supplies a reachable HTTPS
origin and the network route for remote peers. No account or particular relay
provider is required. Loopback authentication tests do not establish public
internet reachability, NAT traversal or background-service availability.

Independent systems can use Nexus without the rest of Omnix or implement A2A
directly.

## Matter

Matter integrations are experimental and have distinct execution paths:

| Integration | Configuration and requirements |
| --- | --- |
| Rust Matter adapter | The `matter` feature selects the experimental rs-matter path for simulator use. |
| Android SDK host | Select `matter_backend: android_host`, register the retained Java SDK owner in the app, then attach through `OmnixMatterHost.openAndroid`. |
| Windows software-device host | Select `matter_backend: windows_qualification` and supply the separately staged Node/Matter.js bundle. This path is for disposable software-device tests. |
| Native C++ backend | The Rust `matter-cpp` feature loads the Omnix C wrapper around the official Matter SDK; native SDK/wrapper builds are separate prerequisites. |

The Android host uses the Java/native Matter SDK, not Matter.js. A protocol
selection does not automatically bundle the Android SDK, Node.js or a native
C++ runtime. These adapters are not interchangeable packaging profiles.

Software-light commissioning, command/readback and reconnect tests provide
integration examples, not certification for arbitrary consumer devices.
Production smart-home distribution and cross-platform controller parity are
not currently available.

## Host responsibilities

Your application owns networking, OS permissions, user consent, private identity
storage and lifecycle integration. Device credentials and access grants are
sensitive. Do not expose a listener or allow remote actions solely because a
peer supplied an address or natural-language request.

Browser-native identity and listeners are not supported by these native
adapters.

## Development

Run from this package directory:

```sh
flutter pub get
cargo test --manifest-path rust/Cargo.toml --workspace --features a2a
```

The standalone Flutter host is in `example/`; its README describes its
configuration. Native loopback tests have been exercised on Windows and Android.
Use isolated identities and software devices when testing integrations.

Applications import `omnix_nexus.dart`; generated bridge types remain internal.
Only maintainers changing bridge declarations need to regenerate bindings.
The package is a source-only developer preview.
