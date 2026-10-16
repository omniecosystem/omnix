# Native agents

The optional agent capability belongs to root Omnix.
Core supplies model execution and typed calls; registered executors perform
tools. Knowledge, Nexus and Workflow remain separate capabilities.

```text
Model turn -> validated calls -> supplied policy -> executor results
        -> model continuation -> final answer and execution evidence
```

## Registration and policy

Supply tools, skills, grants and policy through public APIs.
Neither model output nor skill instructions authorize an action.
A declared tool needs a real executor with semantic validation and platform
permissions where applicable.

Knowledge tools operate within the configured retrieval scope.
Nexus authenticates and authorizes remote participation; it does not bypass
local execution policy. Workflow adds durable progress and recovery without
becoming the owner of the interactive loop.

## Runtime support

The current root agent bridge supports LiteRT-LM on selected Windows and
Android targets. Core exposes a runtime-neutral tool contract, but this does
not establish llama.cpp agent parity.

Tool-capable models need compatible declarations and runtime handling.
Prompting for JSON is not equivalent to native typed tool support.

Supported media can pass through agent input contracts. Required encoders
must be enabled by the native configuration; support in an ordinary chat does
not independently prove media/tool continuation.

## Streaming

Dart consumers use `OmnixAgentSession.sendEvents`; Rust consumers use the
native streaming agent API. Events distinguish model turns, live text, tool
activity and terminal outcomes.

Text preceding a tool call can be provisional preamble. Render tool activity
separately and use the completed reply as the authoritative final answer.
A tool finish is not necessarily success: inspect its outcome.

The non-streaming Dart convenience operation collects native events rather
than fabricating streaming from a completed reply.

## Cancellation and restoration

Cancellation is cooperative. It must prevent new dispatch while allowing native
callback ownership to settle. Host work already accepted can still complete
and may need reconciliation.

Persist transcript and checkpoint state deliberately, including partial replies
and failures. Restore context with fresh executors and policy; historical
calls are context, not executable instructions.

See [registered extensions](AGENT_EXTENSIONS.md),
[agent compatibility](AGENT_PARITY.md), and
[checkpoint validation](MIGRATION_QUALIFICATION.md).
