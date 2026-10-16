# Omnix

Omnix is a modular, Rust-first Cognitive System for applications, services and
devices. Compose local inference, agent capabilities, knowledge retrieval,
persistent storage, workflows and connectivity through one API, or use the
modules independently.

Rust implements execution and orchestration. Dart APIs expose that implementation
through Flutter Rust Bridge. Your host supplies the interface, media capture,
operating-system permissions and platform services.

## Choose your integration

| Integration | Use it when |
| --- | --- |
| Root Omnix | You want sessions, agents and selected modules coordinated through one system API. |
| Independent Rust crates | You want to compose capabilities directly without Dart or Flutter. |
| Module Dart packages | You want a focused capability in a Flutter application. |

The root Dart package is headless. The current Core, Storage, Knowledge and Nexus
Dart packages require the Flutter SDK for their bindings and build integration.
Workflow is available as an independent Rust crate and through root Omnix's Dart
API; a separate Workflow Dart package is not yet available.

## Modules

| Module | Responsibilities | Selectable components |
| --- | --- | --- |
| [Core](modules/omnix_core/README.md) | Model execution, streaming, cancellation, embeddings and model installation | LiteRT-LM, llama.cpp |
| [Storage](modules/omnix_storage/README.md) | Conversation snapshots, workflow checkpoints and vector persistence | SQLite, Qdrant Edge |
| [Knowledge](modules/omnix_knowledge/README.md) | Profile-bound indexing, retrieval and source attribution | Optional Qdrant and Core adapters |
| [Workflow](modules/omnix_workflow/README.md) | Sequential execution, saved results, recovery and cancellation | Host-supplied journals and executors |
| [Nexus](modules/omnix_nexus/README.md) | Authenticated A2A exchanges and experimental Matter integrations | A2A, Matter adapters |

The optional agent capability belongs to root Omnix. Supply tool definitions,
skill instructions, execution callbacks and access policies appropriate to your
application. Core runs the model; Workflow persists jobs; Knowledge supplies
retrieval; Nexus connects permitted remote capabilities.

## Source layout

```text
lib/                            Root Dart API and generated bridge bindings
rust/                           Root Rust composition and bridge
modules/
  omnix_core/
  omnix_storage/
  omnix_knowledge/
  omnix_workflow/
  omnix_nexus/
example/                        Flutter application composing the modules
hook/                           Root native build integration
website/                        Developer website, deployed separately
```

Core, Storage, Knowledge and Nexus use this layout:

```text
modules/omnix_core/
  lib/                          Dart API
  hook/                         Native build configuration
  example/                      Standalone Flutter example
  rust/
    src/                        Flutter Rust Bridge adapter
    backend/
      src/                      Independent Rust implementation
      Cargo.toml                Backend crate manifest
```

Workflow currently contains its independent Rust crate under `rust/backend`,
with integration exposed by root Omnix.

## Start a Dart conversation

Use a compatible local model and include its runtime in the application's native
build configuration. Neither inference runtime is included implicitly.

```yaml
hooks:
  user_defines:
    omnix:
      windows:
        runtimes: [litertlm]
```

The following example takes an absolute model path as its first argument:

```dart
import 'package:omnix/omnix.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    throw ArgumentError('Supply an absolute path to a compatible model.');
  }

  final engine = await OmnixCognitiveEngine.open(runtimes: ['litertlm']);
  try {
    final session = await engine.startSession(
      modelPath: arguments.single,
      instructions: 'Reply briefly.',
    );
    try {
      await for (final delta in session.sendStream('Hello')) {
        print(delta);
      }
    } finally {
      await session.close();
    }
  } finally {
    await engine.close();
  }
}
```

Build-time inclusion and runtime selection are separate: selecting a runtime in
Dart cannot add a backend omitted from the native build. Model and native-library
paths must refer to trusted artifacts. Model licensing and device compatibility
depend on the selected model and runtime.

## Platforms and packaging

Android ARM64 LiteRT-LM integration powers OmniAsk, including compatible Gemma
image/audio input and tools. Android packaging requires API 31 or later and
extracted native libraries. Both direct APK packaging and bundle-generated APKs
must preserve that extraction setting.

Windows native integrations include LiteRT-LM and llama.cpp. CPU/GPU availability
depends on the adapter, model and device; NPU support is experimental. Other
targets are not currently supported as complete end-to-end integrations.

Rust and platform compiler tools are build prerequisites. CMake and a C++ compiler
are needed for llama.cpp source builds. Native assets are selected by build hooks;
their manifests document artifact pins, checksums and licensing requirements.
Some Android profiles currently require a separately built pinned archive.

## Development status

The APIs and storage formats are a developer preview. Cargo and pub publication
are disabled for the extracted packages; integrate from a source checkout.
OmniAsk uses Omnix, but applications should verify their own models, target
platforms and lifecycle requirements before deployment.

To work on the root Dart package:

```sh
dart pub get
dart analyze lib test hook
dart test
```

Native integration tests may require explicit runtime and model paths. Tests
without those inputs can be skipped; a skipped native test is not execution
coverage.

After changing bridge declarations, regenerate bindings with
`flutter_rust_bridge_codegen generate` using version `2.13.0`. Applications
consuming the existing bindings do not need to run the generator.

Omnix is licensed under Apache-2.0. Bundled runtimes and other third-party
components retain their own licenses and redistribution requirements.
