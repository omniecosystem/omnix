# omnix-core Rust backend

Run local inference through directly integrated native runtime APIs. This crate
owns provider selection, model and conversation lifetimes, streaming,
cancellation and embedding execution. It does not execute host tools, store
documents or depend on Flutter.

## Choose runtime features

No runtime is selected by default. Enable `litertlm`, `llamacpp` or both.
Building without either feature fails explicitly.

| Feature | Purpose |
| --- | --- |
| `litertlm` | LiteRT-LM conversations, media input, tools and history |
| `llamacpp` | llama.cpp GGUF text inference and history |
| `model-installation` | Verified imports, HTTPS downloads and host-managed transfer registration |
| `litertlm-embedding-engine` | LiteRT-LM embedding engine, including compatible multimodal models |
| `litertlm-embeddings` | Separate single-input LiteRT tensor encoder with explicit tokenizer and pooling conventions |

Features include their required dependencies; actual input modalities and
accelerators also depend on the model and runtime distribution. The current
llama.cpp adapter does not implement media or tool conversations. Inspect
provider capabilities before selecting a model.

## Build and run

From this directory, with a compatible model at an absolute path:

```sh
cargo test --locked --features litertlm --lib
cargo run --locked --features litertlm --example litertlm_chat -- /absolute/path/model.litertlm "Say hello."
cargo run --locked --features llamacpp --example gguf_chat -- /absolute/path/model.gguf
```

Replace the model paths with local files. Models are not included. llama.cpp
builds the pinned C/C++ source and requires CMake and a C++ compiler. Generated
C bindings are checked in; ordinary consumers do not need libclang.

On Windows x64 MSVC, standalone Cargo builds with `litertlm` acquire a
checksum-pinned CPU distribution and stage its DLLs beside executables,
examples and tests. Deploy those libraries with the executable. For an offline
build, set `OMNIX_CORE_LITERTLM_ARCHIVE` to the exact pinned archive.

A host that supplies its own verified native packaging can set
`OMNIX_CORE_LITERTLM_HOST_PACKAGING` to bypass Cargo's acquisition step.
This does not supply libraries or change runtime capabilities. The Dart Native
Assets hook handles packaging separately, including Android archives.

Use `LiteRtLmProvider::from_bundled` for the bundled distribution. An unsafe
`from_library` override requires trusted, ABI-compatible native libraries;
loading an arbitrary library executes native code in the host process.

## Ownership and execution

Providers are registered explicitly. Selection checks requested format, platform
and capabilities; it does not silently fall back after a selected provider fails.

Conversations retain their model resources. A `ModelPool` can share compatible
loads without sharing conversation histories; the host's key must identify both
the artifact and every engine-affecting setting. Optional execution admission
bounds concurrent inference and queued work.

Use streaming APIs for stoppable generation. Cancellation requests stop, but
native callbacks must drain before their resources can be released. Closing a
handle may therefore take longer than stopping visible output. The LiteRT-LM
adapter retains up to 16 logical conversations per loaded model and switches
one live native conversation between them by replaying owned history. Root Omnix
adds session lifecycle and persistence above this boundary.

History and checkpoints are versioned transcript records, not portable native
KV caches. Restore operations require compatible settings and validate input
bounds. Tool declarations and results pass through Core; the host or root
orchestrator executes tools and supplies results.

## Media and embeddings

Messages carry text and encoded image/audio bytes, not host file paths.
Admission validates size and format bounds. WAV audio uses mono 16 kHz PCM16;
hosts handle capture and conversion. Enable the required model encoders before
sending media. Unsupported inputs return errors.

Embedding profiles identify weights, preprocessing and output conventions.
Keep document and query conventions consistent with the selected model.
Embedding execution does not own a vector database or retrieval policy.

## Tests and bindings

The library suite includes contract tests with synthetic models and media.
Passing those tests does not establish native inference support on another
target or for another model. Real-model integration tests require explicit local
artifacts; inspect each test's environment variables and ignored-test annotation
before running it.

The [binding generator](tool/bindings-generator/README.md) verifies pinned headers
before regeneration. Generated declarations do not replace adapter tests.

See the [module guide](../../README.md) for the Dart API, platform packaging
requirements and current runtime limitations. Retain the
[third-party notices](../../THIRD_PARTY_NOTICES.md) when redistributing native
artifacts. This crate is a source-only developer preview and is not published
to crates.io.
