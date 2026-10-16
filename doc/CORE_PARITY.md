# Core runtime compatibility

Core implements safe Rust contracts over native runtime C interfaces.
The Dart API exposes those contracts without requiring a Dart inference
implementation. Backend availability is explicit; neither runtime is an
implicit default.

## Capability areas

| Area | Integration consideration |
| --- | --- |
| Model selection | Included runtime, artifact format, target and requested capabilities must agree |
| Resource ownership | Models, conversations and callbacks must retain their required native owners |
| Streaming | Ordered owned deltas and explicit terminal success, cancellation or failure |
| Context | Separate logical histories, runtime context limits and compatible replay |
| Cancellation | Native cancellation and callback draining before resource release |
| Sampling | Only settings supported by the selected adapter |
| Tools and thinking | Structured channels require adapter support; do not flatten them silently |
| Media | Model, load configuration, input format and runtime must support the modality |
| Embeddings | Explicit preprocessing profile, model identity and compatible vector dimensions |
| Packaging | Matching native artifacts, checksums, ABI and target toolchains |

A shared API does not imply equivalent capability coverage across runtimes.
Consult the selected module and adapter documentation before deployment.

## LiteRT-LM

Core uses the pinned official C interface. Logical conversations can share
model ownership while the adapter manages the active native conversation.
Reconstruction of context is different from retaining multiple concurrent
native contexts or restoring a serialized KV cache.

Image/audio input, tools and accelerator availability depend on the selected
model and load configuration. Cancellation and recovery must preserve callback
lifetimes; closing a Dart stream alone is not sufficient native cleanup.

## llama.cpp

Core integrates the native llama.cpp C API and checked-in generated bindings.
GGUF validation, tokenization, decoding and sampling are adapter responsibilities.
Do not assume that a model's chat template, media features or tool output work
merely because its weights load.

See [runtime routing](CORE_RUNTIME_ROUTING.md) for integration details.

## Accounting and unsupported capabilities

Context capacity, output limits and token accounting are distinct.
Character counts are not exact token counts. Where reliable accounting is
unavailable, automatic token-budget features must report that limitation rather
than estimate silently. See [context working sets](CONTEXT_WORKING_SET.md).

## Validation

Compare behavior with a fixed model, configuration and target. Cover normal
completion, early stop, abandoned subscriptions, follow-up context, logical
session switching, load errors and close/reopen.

Tests using scripted providers establish contracts, not real-model behavior.
Native host tests do not establish Flutter packaging, and a packaged Windows
test does not qualify Android, GPU or another runtime.

Flutter Edge AI and llamadart are useful behavioral references. Their package
coverage does not constitute evidence of equivalent Omnix support.
