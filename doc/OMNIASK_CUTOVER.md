# Integrating Omnix into an assistant application

OmniAsk uses Omnix for native execution. Its integration illustrates a broader
boundary: an application supplies its product experience, while Omnix
coordinates selected inference, agent, knowledge and workflow capabilities.

This document describes integration responsibilities, not an instruction to
replace an application's database or adopt every Omnix module.

## Responsibility mapping

| Application concern | Integration boundary |
| --- | --- |
| Model configuration and inference | Root sessions and Core runtime controls |
| Tool and skill availability | Host-supplied definitions, instructions and execution callbacks |
| User permissions and entitlement | Application policy and OS adapters |
| Retrieval | Knowledge APIs over a selected embedding profile and storage adapter |
| Durable tasks | Workflow checkpoints and executors, with host-provided wakeups |
| File picking and PDF/DOCX decoding | Host services supplying extracted content |
| Model transfer | Host OS-backed transport with Core artifact validation and installation |
| Account, marketplace and purchases | Application services |
| Conversation presentation | Host UI over streamed events and persisted records |

## Session behavior

Preserve system instructions, supported sampling controls, separate context
and output limits, streaming events and cancellation semantics.
Model and runtime selection must reflect the native components actually
included in the build.

Conversation restoration requires an explicit conversion of stored records.
A provider's message list is not automatically compatible with a native
checkpoint, and historical tool calls must not be replayed as new actions.

## Tools and skills

Reuse host action implementations through callbacks rather than hardcoding
application tools into Rust. Translate declarations and execution results at
the boundary. A skill's instructions do not supply its executor.

Distinguish instruction loading, attempted execution, successful handoff and
confirmed completion. For example, opening a calendar editor does not prove
that an event was saved.

## Storage and knowledge

Replacing inference does not require replacing unrelated application storage.
An application may keep its existing database while using native conversation
checkpoints or Knowledge indexes.

Preserve source identity, visibility and embedding-profile compatibility.
A switch of encoder may require a new index. Equal dimensions do not establish
that old and new vectors can be searched together.

## Workflows and background execution

Workflow owns durable execution state and recovery; the host supplies platform
wakeups and action implementations. Avoid running competing native and Dart
executors for the same task.

Existing task records require a migration decision. Check action retry
semantics and reconciliation before resuming unfinished work.

## Multimodal interaction

Capture, file selection and playback belong to the host. Core processes
supported model input. Direct audio understanding is distinct from a separate
speech-to-text or text-to-speech service.

Availability depends on the model, adapter and target. UI controls should
reflect those capabilities without reducing the engine's public contract to
one application's current interface restrictions.

## Release validation

Test representative saved conversations, tool failures, cancellation, model
loading, interrupted downloads and packaged upgrades. Preserve installed
models and user data during validation. Validate native-library packaging in
both direct APKs and APKs generated from an Android App Bundle.

See the [project overview](../README.md) for current platform and packaging
constraints, and the [roadmap](ROADMAP.md) for development areas.
