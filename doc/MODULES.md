# Omnix modules

Use root Omnix for a coordinated Cognitive System, or consume its modules
independently for custom composition.

## Responsibilities

| Component | Responsibility |
| --- | --- |
| Core | Model execution, inference resources, streaming, cancellation, embeddings and model installation |
| Storage | SQLite snapshots and checkpoints, vector persistence through Qdrant Edge |
| Knowledge | Profile-bound indexing, retrieval and source attribution |
| Workflow | Sequential execution, checkpoints, saved results and recovery |
| Nexus | Authenticated protocol exchanges and device connectivity |
| Root Omnix | Sessions, agent orchestration and coordination of selected modules |

Core's standalone model-execution role is the Cognitive Engine within the
larger Omnix Cognitive System.

## Composition

Rust implements execution and cross-module orchestration. Dart APIs expose the
native implementation rather than running a second orchestration system.
Independent Rust crates do not require Dart or Flutter.

The root Rust crate selects modules through Cargo features. Native Dart builds
select components through build-hook configuration. Importing a Dart library
cannot add a component omitted from the native build.

Core, Storage, Knowledge and Nexus each include a Dart package, native bridge
and standalone Flutter example. Their current Dart build integration requires
the Flutter SDK. Root Omnix's Dart API is headless. Workflow is available as an
independent Rust crate and through the root Dart API; a standalone Workflow
Dart package is not yet available.

See [the project layout](../README.md) and
[module composition](MODULE_COMPOSITION.md).

## Agents, tools and skills

The optional agent loop belongs to root Omnix, not Core or Workflow.
Core produces model responses; the agent coordinates tools and results.
Workflow adds durable execution when work must survive beyond one interaction.

Developers supply tool definitions, execution callbacks, skill instructions
and access policies. A skill describes how to use capabilities; naming a tool
does not supply its operating-system implementation. Host callbacks perform
application or device actions and return explicit results.
Nexus can provide permitted remote capabilities.

## Persistence and retrieval

SQLite conversation snapshots and Qdrant vector indexes serve different
purposes. Storage components can be selected independently. Knowledge
coordinates retrieval over a selected storage adapter and embedding provider.
Matching vector dimensions alone do not establish embedding compatibility.

## Host boundary

Applications provide navigation, localization, accounts, entitlements, media
capture, platform permission prompts and background-service integration.
The Flutter example demonstrates adapters without making them mandatory
engine dependencies.

Module and runtime coverage varies by target. Refer to the module READMEs
before selecting a deployment configuration; a portable contract does not
guarantee that every native backend runs on every platform.
