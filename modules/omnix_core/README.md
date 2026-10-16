# Omnix Core

Run local models through an independent Rust implementation with a Dart API.
Core owns model execution, runtime resources, streaming, cancellation, embedding
execution and optional model installation. It does not require root Omnix,
Knowledge, Storage or Nexus.

The backend crate is in `rust/backend`; `rust` contains the separate native
bridge. The current Dart package requires the Flutter SDK and builds its bridge
through Native Assets.

## Select runtimes

Neither runtime is included by default. Select at least one in the consuming
application's build configuration:

```yaml
hooks:
  user_defines:
    omnix_core:
      runtimes: [litertlm, llamacpp]
```

Choose `[litertlm]`, `[llamacpp]` or both. Runtime selection controls what is
built and bundled; a runtime switch cannot add an excluded engine to the binary.
Invalid, missing and duplicate selections fail explicitly.

Rust applications consume `rust/backend` with `default-features = false` and
the `litertlm` and/or `llamacpp` features. Core calls the upstream native APIs
directly. The llama.cpp integration builds pinned C/C++ sources; consumers need
CMake and a C++ compiler, but do not need to generate bindings.

## Start a conversation

`loadModel` inspects the model container to choose a bundled runtime. Supply an
absolute path to a trusted, compatible model.

```dart
import 'package:omnix_core/omnix_core.dart';

Future<void> greet(String absoluteModelPath, void Function(String) onText) async {
  final model = await OmnixCore().loadModel(modelPath: absoluteModelPath);
  try {
    final conversation = await model.startConversation(maxOutputTokens: 128);
    try {
      await for (final delta in conversation.sendStream('Say hello.')) {
        onText(delta);
      }
    } finally {
      await conversation.close();
    }
  } finally {
    await model.close();
  }
}
```

Use `cancelGeneration` to request cancellation of streamed generation. Closing
a conversation requests stop and drains native completion. Native cleanup may
take longer than stopping visible text; a runtime callback must finish before
its resources can safely be released.

## Model and conversation ownership

Model and conversation handles retain native resources independently. Closing a
model handle does not invalidate a conversation that retains its engine.
`shareRuntime: true` opts into compatible-load sharing through the Rust model
pool; it does not merge conversation histories.

The LiteRT-LM adapter retains up to 16 logical conversations per loaded model,
with one live native conversation at a time. Switching conversations rebuilds
native context from owned history while retaining model weights. Root Omnix
adds session lifecycle and persistence above Core. GGUF conversations share
weights while keeping separate text histories.

Text `exportHistory` and `restoreHistory` snapshots support application-owned
persistence. They are versioned history records, not portable KV caches.
Restore requires a fresh conversation and compatible settings. Unsupported
history formats and context overflow return errors rather than silently
discarding content.

## Media, embeddings and runtime settings

Compatible LiteRT-LM models can accept image and WAV audio input. Enable the
required encoders when loading the model. Media support depends on both the
model contents and adapter; the current llama.cpp adapter does not provide
image/audio input or tool parity with LiteRT-LM.

The optional embedding APIs support explicit embedding profiles and separate
document/query conventions. Select `embedding_engine: true` for the LiteRT-LM
embedding engine in the Dart build configuration. The Rust backend also offers
separate `litertlm-embedding-engine` and `litertlm-embeddings` features.

`cacheDirectory` selects an existing, absolute, host-owned LiteRT-LM optimized
cache directory. Omitting it keeps the runtime's native default. Core does not
treat this as a portable cache or migrate it between runtimes.

Sampling, output, context and accelerator controls are runtime-specific.
Unsupported combinations return explicit errors. CPU/GPU execution depends on
the chosen adapter and device; NPU support remains experimental.

## Installation and background transfers

Inference does not download a model implicitly. Enable Rust
`model-installation` or Dart `model_installation: true` to use
`OmnixModelInstaller` for verified imports, downloads and artifact registration.

The installer also supports host-managed transfers: reserve a durable destination,
write a completed download to that destination, then verify and publish it without
a second model copy. Your host supplies background scheduling and platform
download services. Check available space and retain an existing working model
until its replacement is verified.

## Native packaging

Windows x64 LiteRT-LM libraries are acquired and checksum-verified by the build
hook. Offline builds can supply the exact pinned archive. llama.cpp is compiled
into the selected bridge.

Android LiteRT-LM packaging targets ARM64 and API 31 or later. It requires a
verified archive and extracted native libraries. Configure extraction for both
direct APKs and bundle-generated APKs. GPU profiles require their matching
accelerator libraries and host manifest declarations; a CPU-only archive cannot
satisfy a GPU build.

A trusted `libraryPath` override is available for LiteRT-LM, not GGUF. Loading
native code from an arbitrary path can execute code or crash the process. Prefer
the pinned bundle and retain the [third-party notices](THIRD_PARTY_NOTICES.md)
when redistributing it.

Android LiteRT-LM and Windows native integrations have been exercised.
Availability is model- and adapter-specific; other native targets and browser
execution are not complete supported integrations. Inspect the selected
adapter's capabilities before offering a feature in your application.

## Development

From this package directory:

```sh
flutter pub get
cargo test --manifest-path rust/Cargo.toml --workspace --features litertlm,llamacpp
```

The standalone Flutter application is in `example/`. Real-model tests require
compatible local model and runtime inputs; tests without those inputs may skip.
Model files are not included.

The backend and bridge pin their build dependencies and toolchains in their
Cargo manifests and toolchain files. Applications need Rust and the target
platform's compiler tools. Only maintainers changing bridge declarations need
`flutter_rust_bridge_codegen` version `2.13.0`.

Core is a source-only developer preview. Rust, Dart and native-artifact
publication are separate distribution steps.
