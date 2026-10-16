# omnix-storage

Independent native persistence for Omnix. The crate has no Flutter or model
runtime dependency. It provides dedicated SQLite stores and an optional
Qdrant Edge vector backend.

## Features

No storage engine is enabled by default.

| Cargo feature | Public API |
| --- | --- |
| `sqlite` or `rusqlite` | `ConversationStore`, `WorkflowStore` |
| `qdrant` | `QdrantStore`, `VectorProfile`, `VectorHit` |

Select either backend or both using `default-features = false`.
Qdrant Edge is a native dependency and is not available on `wasm32`.

## SQLite

`ConversationStore` opens a dedicated database for versioned conversation
snapshots. It validates each JSON envelope and replaces metadata and ordered
messages in one transaction. Read, list and delete operations do not alter model
context. Foreign and unsupported databases are rejected without resetting them.

`WorkflowStore` stores opaque workflow snapshots in a separate database with
full-sync checkpoints and an exclusive OS owner lock. Retain its `.owner`
sidecar while the store may be in use. It does not depend on a workflow schema
or grant permission to execute saved work.

Neither API is a general-purpose SQL connection or an automatic migration layer
for another application's database.

## Vectors

`QdrantStore` accepts vectors and JSON metadata. It supports cosine search,
top-level string metadata filters, score thresholds, metadata reads, deletion,
clearing and explicit flush.

Every store is bound to a `VectorProfile` identifying an embedding space and
its dimensions. Reopening with an incompatible profile fails. The store also
rejects unknown formats and foreign directories rather than adopting them
silently. Call `flush` to make accepted vector mutations durable.

This crate does not embed text, parse documents or generate answers.

## Test

From the repository root:

```sh
cargo test --manifest-path modules/omnix_storage/rust/backend/Cargo.toml --no-default-features --features sqlite
cargo test --manifest-path modules/omnix_storage/rust/backend/Cargo.toml --no-default-features --features qdrant
```

Tests use disposable paths. Applications should test their own storage locations,
access policies and recovery behavior. SQLite and Qdrant have different build
requirements; consult the manifest and the binding's pinned toolchain when
building either backend.

## Data handling

Choose dedicated private paths and provide your own backup and retention policy.
Snapshots and metadata are not encrypted by this crate. Checkpoints can contain
sensitive tool arguments and results. Errors do not authorize deleting or
recreating an existing store.

See the [module README](../../README.md) for the Dart binding and build settings.
