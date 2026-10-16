# Omnix architecture

Omnix is a modular, Rust-first Cognitive System.
Hosts provide interfaces and platform capabilities; native modules provide
reusable execution behavior.

## Dependency direction

```text
Host application
  -> public Rust or Dart API
  -> root Rust orchestration, when selected
  -> independently usable Rust modules
  -> native runtimes, storage engines and protocol adapters
```

Dart exposes native behavior through generated bindings and handwritten facades.
It does not maintain a competing agent loop or workflow engine.
Flutter widgets, account SDKs and generated bridge types are not engine contracts.

## Modules

- Core executes models and owns inference resources.
- Storage provides structured and vector persistence.
- Knowledge coordinates indexing and retrieval.
- Workflow persists execution progress and recovery.
- Nexus provides protocol and device connectivity.
- Root Omnix coordinates selected modules, sessions and agents.

See [module responsibilities](MODULES.md) and
[composition](MODULE_COMPOSITION.md).

## Host boundary

Hosts supply media capture/playback, file-format decoding, permissions,
OS background services, tool executors and product policy.
A callback is trusted application code, not a sandbox for arbitrary downloads.

Model requests, retrieved text and skill instructions do not grant authority.
Execution policy is supplied by the host and enforced at the native boundary.

## Lifecycle and compatibility

Native owners must outlive callbacks and outstanding work.
Cancellation is cooperative and cannot undo accepted external effects.
A logical history checkpoint is not necessarily a serialized KV cache.

Persisted formats and native bindings require compatibility validation.
API changes, generated bindings and relevant tests belong in one reviewed change.
Source integrations should pin a revision during the developer preview.

See [integration validation](MIGRATION_QUALIFICATION.md).
