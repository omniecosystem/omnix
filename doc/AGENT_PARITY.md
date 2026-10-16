# Agent integration and compatibility

Root Omnix owns the model/tool/result interaction loop. Core supplies
runtime-specific inference and structured output. Hosts provide tool
implementations, skill instructions, access policy and user interaction.

[Flutter Edge AI](https://github.com/DenisovAV/flutter_edge_ai) is a behavioral
reference, not an execution dependency or an API-compatibility guarantee.

## Integration contract

A model requests a declared tool; Omnix validates and dispatches it through
the registered executor. The result returns to the model before continuation.
An instruction-loading result is not an executed action, and a successful
handoff is not necessarily completion of the external effect.

Recoverable argument or executor errors should remain observable as structured
results. A native stream failure is a distinct terminal condition; do not
convert it into a claim of tool success.

## Tools and skills

Developers supply extension definitions through the public API.
Skills explain how to use available tools; tools implement callable operations.
The example supplies device actions and workflow skills as host code and assets,
not as mandatory capabilities baked into the engine.

Loading a skill does not install an OS executor. An application's JavaScript,
native intent or external-service integration needs an appropriate callback
and any required platform permission.

See [registered tools and skills](AGENT_EXTENSIONS.md).

## Interruption and history

Cancellation, completed context and visible partial replies are separate
concerns. Hosts should retain the visible transcript according to their
persistence policy and report native restoration failures explicitly.
Restoring context must not execute historical actions or restore stale consent.

## Runtime coverage

Agent execution depends on structured-call support in the selected adapter.
The current root native agent integration uses LiteRT-LM on supported Windows
and Android targets. This is not a claim of llama.cpp agent parity or universal
tool reliability across models.

Modality support also depends on the model and native configuration. Test
text, media and tool continuation together rather than inferring agent support
from an ordinary multimodal conversation.

## Acceptance checks

- Validate declared arguments and return recoverable errors accurately.
- Distinguish loaded instructions, attempted actions, handoffs and completion.
- Preserve streaming order and balanced tool exchanges.
- Cancel and continue without mixing histories or duplicating effects.
- Restore checkpoints with fresh executors and policy.
- Apply runtime limits and report unsupported operations explicitly.

Test with the actual model, native artifacts and host executors used by the
application. Scripted tests and fixture tools alone do not qualify every
platform action.
