# Optional components

Selection controls native dependencies and binaries, not just Dart visibility.

| Module | Independently selectable components |
| --- | --- |
| Core | LiteRT-LM, llama.cpp |
| Storage | SQLite, Qdrant Edge |
| Nexus | A2A, Matter backends |

Neither Core runtime is a default. A consuming execution build selects at
least one compatible runtime explicitly.

## Dart build configuration

```yaml
hooks:
  user_defines:
    omnix_core:
      runtimes: [litertlm, llamacpp]
    omnix_storage:
      engines: [sqlite, qdrant]
    omnix_nexus:
      protocols: [a2a]
```

Configure only imported modules and supported target combinations.
Matter additionally needs an explicit appropriate backend configuration;
see [Matter selection](MATTER_BACKENDS.md).

A Dart import cannot enable a compiled-out component.
Cargo feature unification is additive across a Rust dependency graph.

## Artifact delivery

LiteRT-LM uses pinned native distributions with target/backend-specific
dependency closure. llama.cpp is built from pinned native source.
Different build mechanisms do not imply that one runtime should become an
implicit default.

Offline archives must satisfy the same integrity requirements.
One compatible owner should package a shared native library when multiple
bridges need it; this does not merge their runtime handle registries.

## Storage

SQLite snapshots and vector search are different capabilities.
Qdrant Edge runs in process and does not require a Qdrant server.
Knowledge orchestrates embeddings and retrieval over a selected store.

Selected dependencies can impose newer toolchain requirements.
Use the checked-in manifests and pins rather than assuming every optional
combination shares the lean foundation's requirements.

## Distribution checks

Measure a clean deployment bundle rather than generated directories containing
stale libraries from earlier selections. Include required notices and native
runtime dependencies.

The Windows Sandbox harness under `tool/` is a development check, not a shipped
runtime dependency. Linux containers, WSL and route providers are likewise
development or deployment choices, not universal consumer requirements.

See [platform coverage](PLATFORMS.md) and the module READMEs.
