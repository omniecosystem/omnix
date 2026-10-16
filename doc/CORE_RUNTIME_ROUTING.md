# Core runtime routing

Core selects explicitly registered runtime providers using artifact format,
target, required capabilities and host preference.
An unavailable preference fails; loading must not silently choose a provider
that drops requested functionality.

## Explicit inclusion

Select `litertlm`, `llamacpp` or both for standalone Core.
Root Omnix exposes corresponding `core-litertlm` and `core-llamacpp` features.

Dart consumers select runtimes through native build-hook configuration.
At least one runtime is required for a Core execution build; neither is a
default. Selection during inference cannot add a compiled-out backend.

## Artifact validation

`probe_model_format` inspects container headers rather than trusting file
extensions. Unknown, truncated or unsupported containers fail explicitly.
A recognized header does not establish trustworthy provenance, valid tensors
or support for every advertised modality.

Model acquisition is separate from loading.
Inference does not download executable dependencies or model files implicitly.

## LiteRT-LM

Rust calls the pinned native C interface.
Windows build-time delivery verifies archive checksums and stages required
libraries. Offline input must satisfy the same digest.
Android uses its separate pinned C-API distribution.

Runtime loading uses owned trusted paths and compatible sibling libraries,
not an arbitrary working-directory executable.
Native dependency closure and distribution notices remain required.

## llama.cpp

The opt-in adapter directly uses generated upstream C bindings.
Its pinned source is under `modules/omnix_core/rust/backend/vendor/llama.cpp`;
see [source provenance](../modules/omnix_core/rust/backend/vendor/LLAMA_UPSTREAM.md).

The CPU source build requires CMake and a C++ compiler.
libclang/bindgen are maintainer binding-generation tools, not consumer-time
runtime dependencies.

The adapter owns native model, context, batch and sampler resources.
Container routing does not establish chat-template, tool or media support.
The current text path replays recorded history into a per-turn context;
it does not claim incremental KV reuse across turns.

## Shared behavior and target differences

Both providers expose the Core lifecycle and conversation contracts.
Capabilities and accelerator coverage still differ by runtime, model and target.
Unsupported requests must remain visible rather than silently changing operation.

Logical session isolation, stop/recovery, output delivery, overflow and closure
need tests for each adapter. A passing host executable is not proof of packaged
Flutter delivery or clean-machine runtime dependencies.

## Native packaging

Configure one compatible asset owner for each runtime library when root and
standalone bridges coexist. Asset sharing does not merge handle registries
or loaded model instances across libraries.

Keep source revisions, archive checksums and redistribution notices with the
build configuration. A compiler installation or prefilled local path is not a
consumer runtime dependency contract.

See [Core compatibility](CORE_PARITY.md),
[optional components](OPTIONAL_COMPONENTS.md), and
[platform coverage](PLATFORMS.md).
