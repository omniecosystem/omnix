# Omnix roadmap

Omnix combines independently usable Rust modules into a Cognitive System.
Its Dart API exposes native execution and orchestration; applications supply
their interface, accounts, media capture and operating-system integrations.

This roadmap describes development areas, not release dates or a platform
support guarantee. See the [project overview](../README.md) for current
integration requirements.

## Developer preview

Core, Storage, Knowledge, Nexus and Workflow have native Rust implementations.
Root Omnix composes selected capabilities and provides sessions and an optional
agent loop. The Flutter example demonstrates their integration.

APIs and persistence formats remain in development. Package-registry
publication is disabled; source integrations should pin a revision and verify
their selected features, models and targets.

## Release priorities

### Sessions and native delivery

The baseline covers model loading, streaming, cancellation, follow-up context,
resource ownership and recovery. Validation includes standalone and combined
consumers, packaged native libraries, and application upgrades with existing
models and databases.

Android and Windows integrations are the current focus. Runtime and capability
coverage differs by target.

### Runtime coverage

Core integrates LiteRT-LM and llama.cpp through their native C interfaces.
Neither runtime is an implicit default. Image, audio, embedding, structured
output and accelerator capabilities depend on the adapter, model and target.

Further work expands tested coverage and exposes capability differences through
public contracts. Unavailable operations must not silently become different
operations.

### Persistent knowledge and workflows

Knowledge provides profile-bound indexing, retrieval and source attribution.
Storage provides SQLite persistence and Qdrant Edge vector storage.
Workflow provides sequential execution, checkpoints and recovery.

Priorities include upgrade compatibility, interrupted-operation recovery and
sharing inference resources between interactive sessions and background work.
Hosts provide platform scheduling, permissions and execution callbacks.

### Extensible and live interaction

Developers supply tools, skills and policies through root Omnix.
The agent coordinates model requests and tool results without requiring
application actions to be built into the engine.

Longer-term work includes bounded live input from cameras, microphones and
sensors, with cancellation, backpressure and explicit resource ownership.
This direction does not imply continuous audio or video support in every model.

### Connectivity

Nexus contains authenticated A2A exchanges and experimental Matter adapters.
Production Matter integration requires appropriate attestation credentials,
platform packaging and interoperability testing beyond fixture demonstrations.

Broader peer discovery and remote reachability remain development areas.
Applications should not assume automatic NAT traversal or universal device
compatibility.

## Contribution boundaries

- Core owns model execution and inference resources.
- Storage owns persistence primitives.
- Knowledge owns indexing and retrieval orchestration.
- Workflow owns durable execution and recovery.
- Nexus owns protocol and device connectivity.
- Root Omnix owns composition and agent orchestration.
- Hosts own product UI, accounts, capture and operating-system services.

See [module responsibilities](MODULES.md) and the module READMEs for integration
details.
