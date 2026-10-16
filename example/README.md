# Omnix Flutter example

This application demonstrates root Omnix sessions, agents and selected native
modules. It is a host integration, not a second implementation of the engine.

## Build and run

From the repository root:

```powershell
cd example
flutter pub get
flutter run -d windows
```

Native builds require Rust and the target compiler tools. llama.cpp source
builds also need CMake and a C++ compiler. Model weights are not bundled.
Use trusted compatible models with appropriate licenses.

Android ARM64 requires API 31 or later for this application's LiteRT-LM
configuration. Its native archive and optional Matter SDK are separate build
inputs; see the [Android build guide](../tool/LITERTLM_ANDROID_BUILD.md) and
[Matter setup](../doc/MATTER_EXAMPLE.md).

Do not use an installed consumer application's package ID for testing.
Device deployment requires a deliberate data/signing safety plan; build
success does not guarantee a data-preserving update.

## Home

Home provides a shared conversation interface with streamed replies and tool
activity. Model and interaction settings live in Core. History and feature
panels adapt to the window size; module screens open without becoming
independent agents.

With a compatible model, Home accepts supported image/audio inputs and
foreground microphone capture. Capture and playback are host functions;
native validation, model execution and agent orchestration remain in Omnix.

Configure tools and autonomy in Core. The example supplies its own tools,
skills and policy; registering them does not make them engine defaults.

## Features

- Core: import or download a trusted model, choose runtime settings and use it
  for Home. Native installation verifies artifact metadata; OS-backed transfer
  remains a host adapter.
- Knowledge: configure an embedding model and index supported content. Home
  can access the registered index; retrieved sources are evidence, not a
  guarantee of every generated claim.
- Storage: inspect persistence behavior independently of model inference.
- Workflow: inspect durable jobs, saved results and recovery. Host callbacks
  implement device effects; an uncertain effect may require reconciliation.
- Nexus: exercise authenticated peer exchanges and experimental Matter adapters.
  Fixtures and test credentials are not production device provisioning.

The default embedding selection is EmbeddingGemma 2. Different encoder profiles
require compatible stores; do not reopen old vectors under unrelated weights.

## Persistence and lifecycle

Visible transcripts and native checkpoints have different roles.
Restoration must not execute historical tools. Saved context is sensitive;
keep application stores private and handle compatibility errors explicitly.

Runtime preparation, cancellation and conversation switching need native
ownership to settle before another operation. The UI may retain a draft while
waiting. An external action already accepted cannot be rolled back merely by
stopping generation.

## Validation

Unit/widget tests use doubles where appropriate. Native integration tests
require matching bridge artifacts and compatible existing models.
A skipped native test is not a passing qualification.

Use disposable stores and isolated app IDs. Do not uninstall a consumer app or
clear downloaded models to make an integration test pass.

See [architecture](../doc/EXAMPLE_ARCHITECTURE.md),
[model installation](../doc/MODEL_INSTALLATION.md),
[integration validation](../doc/MIGRATION_QUALIFICATION.md), and
[feature scope](../doc/EXAMPLE_FEATURE_PARITY.md).
