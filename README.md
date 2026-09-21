# Omnix

Omnix is an open, headless, on-device intelligence engine for Flutter
applications.

The project starts with a stable Dart API and a Rust core connected through
`flutter_rust_bridge`. Proven Dart implementations can be adopted
incrementally, while performance-sensitive and security-sensitive operations
move to Rust without changing the public Dart contract.

## Principles

- Local-first and private by default.
- Headless engine APIs, independent of any product interface.
- Stable handwritten contracts; generated bridge code remains internal.
- Explicit capability boundaries for inference, tools, skills, and workflows.
- Behavioral parity tests before replacing Dart implementations with Rust.
- Incremental adoption without requiring a big-bang application rewrite.

## Structure

- `lib/src/domain`: implementation-independent models and contracts.
- `lib/src/application`: engine composition and use cases.
- `lib/src/infrastructure`: Dart, platform, and Rust adapters.
- `lib/src/rust`: generated bridge code. Do not edit manually.
- `rust`: the native Omnix crate.
- `hook`: Native Assets build integration.
- `example`: a minimal host application.
- `doc`: architecture and extraction decisions.
- `website`: the independently deployed developer portal (excluded from the
  pub.dev package archive).

See [platform support](doc/PLATFORMS.md) for the verification tiers. Omnix is
architected for every Flutter target while Android and Windows receive initial
integration priority.

See [module boundaries](doc/MODULES.md) for how Core, Workflow, Knowledge,
Nexus, skills, and tools map to reusable engine capabilities without mirroring
application screens one-for-one.

## Quick start

```dart
import 'package:omnix/omnix.dart';
import 'package:omnix/omnix_flutter_gemma.dart';

final runtime = FlutterGemmaOmnix.createRuntime();
await runtime.initialize();

await runtime.models.install(
  OmnixModelInstallRequest(
    template: OmnixModelTemplate.gemma4,
    format: OmnixModelFormat.liteRtLm,
    source: OmnixNetworkModelSource(modelUri),
  ),
  onProgress: (progress) => print('$progress%'),
);

final conversation = await runtime.openConversation(
  const OmnixConversationConfiguration(
    modelTemplate: OmnixModelTemplate.gemma4,
  ),
);
try {
  await for (final event in conversation.send('Hello')) {
    if (event case OmnixTextDelta(:final text)) print(text);
  }
} finally {
  await runtime.close();
}
```

See [model management](doc/MODELS.md) for sources, integrity verification,
cancellation, Android foreground downloads, and lifecycle behavior.

See [audio and speech](doc/SPEECH.md) for the distinction between direct model
audio, speech-to-text, text-to-speech, and optional provider adapters.

See [persistence boundaries](doc/PERSISTENCE.md) for the distinction between
active session history, durable relational storage, and vector indexes.

Each runtime also owns one provider-neutral capability registry:

```dart
runtime.capabilities.register(
  OmnixTool(
    metadata: OmnixCapabilityMetadata(
      id: 'current_time',
      kind: OmnixCapabilityKind.tool,
      name: 'Current time',
      description: 'Returns the device-local time.',
    ),
    execute: (_) => OmnixToolSuccess(DateTime.now().toIso8601String()),
  ),
);
```

See [skills and tools](doc/CAPABILITIES.md) for capability definitions,
enablement, permission policy, and structured execution results.

An optional agent backend can open headless agent sessions over the same
runtime-owned capability state. See [agent sessions](doc/AGENTS.md) for the
neutral event contract, Flutter Gemma Agent adapter, and scheduling boundary.

## Development

Install Flutter and Rust with `rustup`, then install the matching bridge
generator. Omnix currently compiles its Rust crate as a Native Asset, so
`rustup` and `cargo` must be visible to the process that launches Flutter.

```shell
rustup --version
cargo --version
cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked
flutter pub get
```

On Windows, `rustup` normally adds `%USERPROFILE%\.cargo\bin` to the user
`PATH`. Restart open terminals and IDEs after installing Rust so Flutter sees
the updated environment. If an older terminal reports `Failed to invoke
rustup`, open a new one and verify `rustup --version` before rebuilding.

After changing an API under `rust/src/api`, regenerate bindings:

```shell
flutter_rust_bridge_codegen generate
```

Validate the package:

```shell
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
cargo fmt --manifest-path rust/Cargo.toml --all -- --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
```

Native bridge execution is covered by the example integration test and requires
a Flutter target device.
