# Example application scope

The root Flutter example demonstrates Omnix's public APIs in an assistant-style
interface. OmniAsk is a product integration reference, not a specification that
every product feature must become an engine module.

## Feature boundaries

| Area | Example role | Engine responsibility |
| --- | --- | --- |
| Home | Shared conversation UI, attachments and streamed activity | Sessions, inference and optional agent orchestration |
| Core | Model import, transfer and runtime controls | Model installation validation, execution and resource lifecycle |
| Knowledge | Content submission and retrieval presentation | Indexing, embedding compatibility and attributed retrieval |
| Storage | Persistence demonstrations | SQLite snapshots/checkpoints and Qdrant vector storage |
| Nexus | Host connectivity and device interactions | Protocol integration and authorized dispatch |
| Workflow | Task presentation and OS wakeup adapters | Durable execution, saved results and recovery |

The example supplies host actions, skill assets and platform adapters. Those
demonstrations are not mandatory tools built into the engine.

## Product features

Accounts, purchases, entitlements, marketplace presentation, navigation and
document-format extraction belong to applications. An assistant can retain
these services while adopting Omnix.

Direct model audio input is not equivalent to a dedicated speech-to-text or
text-to-speech service. A model supporting images or audio does not imply
support for every modality combination or runtime backend.

## Evaluating an integration

Compare concrete operations rather than screen counts:

- Configure and load the intended model and accelerator.
- Stream, cancel and continue conversations without mixing histories.
- Restore saved state without executing historical tool calls.
- Deliver tool results and failures accurately.
- Index and retrieve with compatible profiles and visibility rules.
- Resume durable work without blindly repeating uncertain effects.
- Preserve existing user data and installed models across upgrades.

Examples and tests cover different slices of this behavior. Passing a widget
test or building an APK does not demonstrate real-model or device execution.
Refer to [integration validation](MIGRATION_QUALIFICATION.md) and module READMEs
for test entrypoints and capability constraints.

## Independent development areas

Broader platform coverage, live sensor input, production Matter integration and
additional runtime capabilities remain separate development areas. Their
absence does not imply that an application's already-supported inference path
requires another implementation framework.
