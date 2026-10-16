# Native Core: LiteRT-LM qualification

This page records the initial Windows CPU qualification of the pinned v0.17
integration. Its dated results and remaining-work lists are historical, not
the current feature matrix. See the [project overview](../README.md) and
[Core compatibility](CORE_PARITY.md) for current integration boundaries.

## Integration boundary

```text
omnix_core Dart API -> flutter_rust_bridge -> omnix-core
                                          -> LiteRT-LM C API -> native C++ engine
```

The implementation belongs to **Rust Core**, with a standalone Dart binding. It does not depend
on Dart inference plugins, Storage, or Nexus. It does not rewrite the native
runtime in Rust. On Windows x64 MSVC, the opt-in provider can load the pinned
build-time distribution with `LiteRtLmProvider::from_bundled`; Cargo delivers
the DLLs for Rust consumers, while Native Assets delivers them for Flutter.
Applications still own model acquisition, deployment and license compliance.
The unsafe `from_library` override remains available for explicitly audited
external distributions. Other platforms remain unqualified.

Declarations match the upstream [engine header](https://github.com/google-ai-edge/LiteRT-LM/blob/v0.17.1/c/engine.h)
and [conversation header](https://github.com/google-ai-edge/LiteRT-LM/blob/v0.17.1/c/conversation.h).
Config setters copy session/thinking settings and JSON strings. Response
strings are borrowed only while their response object is alive; Rust copies
the parsed text before deleting it. All allocations have owning guards.
Opaque handles stay on one worker thread; engine/conversation pointers have
no manually asserted `Send`/`Sync` implementations.

The former handwritten function table is replaced by checked-in bindgen output.
The isolated generator pins bindgen 0.72.1, validates the exact upstream header
digests, and supports `--check` for reproducibility. The headers and upstream
license are vendored; no native runtime or reference-plugin code is copied.
The adapter's owning resource guards are now generic over the distinct generated
opaque types instead of treating all native pointers as `void*`.

Symbol presence is not ABI proof. The external-library constructor is unsafe for this reason.
Runtime/header versions must be pinned and qualified together. Automatic
downloads must validate the entire distribution against reviewed digests.
Runtime/model licenses and notices must accompany a future distribution.
Reusing locally installed artifacts for testing is not completed packaging.

On 4 October 2026, the standalone Rust example used the build-time SHA-256-pinned
archive with no runtime-library argument, generated `OK.` and recalled `Violet`.
Copying that executable and its sibling DLLs into a fresh temporary folder also
passed real inference, without Cargo or a runtime path. A deliberately wrong
archive failed verification before extraction. The verified offline-archive path
was used for these tests; network delivery availability and clean-machine CRT
qualification are separate gates. See [runtime routing](CORE_RUNTIME_ROUTING.md).

## Evidence: 3 October 2026

Windows x64, Rust 1.93.1, CPU, 2,048-token context, 128 output-token limit:

- Local LiteRT-LM DLL SHA-256:
  `2d3bf213db2b96d16014538705d222efe6ed2a4235ae9503fa42fe25ee688655`.
  This identifies the tested DLL, not the integrity of the dependency bundle.
- Existing Gemma 4 E2B `.litertlm` model: 2,588,147,712 bytes.
- Prompt: `My favorite color is violet. Reply with just OK.` Reply: `OK`.
- Follow-up: `What is my favorite color? Answer with one word.` Reply: `Violet`.
- The example drops the model handle **before** both turns. The conversation
  safely retains its worker/engine; shutdown completes normally.
- The local Qwen3 0.6B artifact failed in upstream tokenizer initialization
  (`piece must not include null character`). It is **not qualified**. No
  fallback, model conversion, or artifact mutation was attempted.
- Initial Windows loading with slash-form paths failed. Canonicalizing the
  absolute path fixed loading without loosening DLL-search flags. OS error
  codes are retained when available, without disclosing prompt content.

The opt-in integration test checks invalid settings, rejected empty input
without losing valid history, multi-turn recall, fresh conversation creation
on the same engine, and conversation ownership after model drop. Rerun it
with matching trusted artifacts when upgrading the model or runtime.
It passed on the above Windows/Gemma combination: one real-model integration
test, four generated replies across two separate conversations, in 4.58 seconds
including model initialization. This is a smoke-test timing, not a benchmark.
After switching to generated bindings and adding overlapping-conversation
rejection, the same real-model regression passed again (5.82 seconds). Binding
regeneration/check and the Core unit tests also passed. This does not add
streaming, cancellation, Android, or Flutter qualification.

## Standalone streaming and packaged Windows evidence

On 4 October 2026, isolated Windows Core and Storage Flutter integration tests
executed their bundled bridge libraries, not just a standalone Dart test runner.
Core's example streamed a first fact, stopped a longer response after receiving
text, reconstructed the native conversation, and recalled the fact in another
streamed reply. Storage wrote, closed and reopened its own temporary snapshot.
No consumer app was installed or modified and no model was downloaded.

The native Rust real-model regression also verified stop followed by recall and
a fresh complete stream. The Dart native regression verified normal streaming,
explicit stop, abandoned consumption and subsequent recall. Injected transport
tests cover normal completion, errors, shutdown, overlapping streams and paused
subscription cancellation. This is Windows CPU/text evidence, not full parity.

The adapter copies borrowed upstream callback data into owned Rust text and uses
a bounded 64-delta callback queue. Stop is signalled out of band; the native
owner thread cancels and waits for the terminal callback before recovering or
releasing resources. Errors/panics never substitute an early cleanup timeout
for native completion. A hung native runtime remains a pending watchdog/isolation
problem. Blocking sends remain non-cancellable. Text history includes stopped
exchanges' partial output, matching the inspected reference recovery behavior.

The ABI behavior was checked against the pinned upstream
[C callback implementation](https://github.com/google-ai-edge/LiteRT-LM/blob/v0.17.1/c/conversation.cc).

## Remaining gates

Standalone-module check on 4 October 2026: the `omnix_core` Dart API loaded
the same local runtime/model, closed the model handle, generated two replies
and recalled `violet` on the second turn. Its native initialization and four
injected-transport lifecycle tests passed. The isolated Windows Flutter example
built with `omnix_core_bridge.dll` in its output bundle, and its three UI tests
passed. Subsequent packaged execution is recorded above; Android and clean-machine
qualification remain open.

1. Broader adversarial callback, failure and shutdown qualification; logical
   session switching/replay and bounded context/history policies. Blocking
   generation cannot currently be cancelled.
2. Verified distributable binaries/dependencies, notices, clean-machine loading,
   and optional Core-only native packaging.
3. Additional packaged platform and clean-machine qualification without duplicate
   runtime ownership; Windows CPU/text execution is now verified.
4. Android artifacts and real-device generation. Compilation is not verification.
5. Explicit model/backend capabilities for acceleration, multimodal input,
   reasoning and tools; then additional providers.

No consumer migration or all-platform support claim follows from this test.
The [parity matrix](CORE_PARITY.md) records the observable behaviors to reproduce
from the working reference integration before declaring parity.
