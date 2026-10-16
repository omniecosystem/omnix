# Android conversation switching

Switching a saved conversation can require native context reconstruction
before its next generated token. This differs from merely displaying a stored
transcript.

## Runtime lifetime

The Android LiteRT-LM adapter retains validated runtime library handles for
the process lifetime. Engine/conversation ownership and worker shutdown remain
separate; retaining a library does not retain every model's weights.

This reduces repeated unload/reinitialization risk.
It is not a guarantee against every native TLS, memory or driver failure.
Replacing a loaded runtime requires process restart.

## First-token latency

Measure model loading, context restoration, retrieval and generation separately.
A restored checkpoint can require prompt processing on the next turn.
Long or multimodal histories can therefore add latency after the visible
transcript is already available.

Thinking is an explicit model/runtime setting, not something inferred from
a loading animation. See [generation controls](CORE_GENERATION_SETTINGS.md).

## Validation

Alternate ordinary and agent conversations with supported text/media histories.
Test follow-up recall, cancellation, background/resume and repeated switching.
Restoration must not execute historical tools.

For a native crash, preserve the first error and exact library BuildId for
symbolication. A final stack-overflow symptom alone does not identify the
initial cause; increasing stack size is not a demonstrated repair.

Use isolated test stores and a deliberate device deployment plan.
Do not uninstall a consumer app or clear its data to run these checks.

See [mixed-input chats](MIXED_INPUT_CHATS.md) and
[tool availability](TOOL_CAPABILITY_SWITCHING.md).
