# Omnix Storage

Persist conversation snapshots, workflow checkpoints and embedding vectors
without an inference runtime. The independent `omnix-storage` Rust crate is in
`rust/backend`; the Dart API and its native bridge are separate layers.

## Select components

Neither backend is enabled by default. Select SQLite, Qdrant Edge or both:

```yaml
hooks:
  user_defines:
    omnix_storage:
      engines: [sqlite, qdrant]
```

Rust applications select `sqlite`, `qdrant` or both Cargo features with
`default-features = false`. The backend also accepts `rusqlite` as a SQLite
feature name. The Dart package currently requires the Flutter SDK and builds
native code through Native Assets.

## Conversation snapshots

`OmnixConversationSnapshotStore` provides serialized snapshot reads, writes,
listing and deletion. It accepts version-1 JSON envelopes containing
`schemaVersion`, `record` and ordered `messages`. Records include a stable
`id` and RFC3339 `updatedAt` timestamp.

```dart
import 'package:omnix_storage/omnix_storage.dart';

Future<String?> saveAndRead(
  String privateAbsoluteDatabasePath,
  String snapshotJson,
  String conversationId,
) async {
  final store = OmnixConversationSnapshotStore(
    path: privateAbsoluteDatabasePath,
  );
  try {
    await store.writeSerializedSnapshot(snapshotJson);
    return await store.readSerializedSnapshot(conversationId);
  } finally {
    await store.close();
  }
}
```

Writes replace metadata and ordered messages in one transaction. Operations are
serialized; closing drains accepted operations and rejects new work. Use a
dedicated private database. Foreign or unsupported databases are rejected rather
than reset. This API does not expose arbitrary SQL or migrate an existing
application database.

## Vectors

`OmnixVectorStore` stores numeric point IDs, vectors and JSON metadata. It
supports upsert, cosine-similarity search, top-level string metadata filters,
metadata lookup, removal, clearing and explicit flush.

An `OmnixVectorProfile` identifies the embedding model and preprocessing as
well as the vector dimension. Reopening with a different profile fails.
The Dart API accepts nonnegative IDs up to the signed 64-bit maximum as
`BigInt`; the Rust backend supports `u64` IDs.

Storage does not generate embeddings, parse documents or construct RAG answers.
Use Core for embedding execution and Knowledge for document-level indexing and
attributed retrieval. Flush accepted vector changes before relying on their
durability; closing the Dart vector store also flushes the shard.

## Workflow checkpoints

The Rust SQLite backend exposes `WorkflowStore` for dedicated workflow snapshots.
It uses full-sync checkpoints and an exclusive OS lock. Keep its `.owner`
sidecar in place: deleting the file while an owner exists can defeat locking.

`WorkflowStore` does not depend on Workflow's execution schema. Root Omnix
composes it with the Workflow runner and current host authorization. This
workflow-specific store is not exposed by the standalone Storage Dart API.

## Build and test

Run these commands from the repository root:

```sh
cargo test --manifest-path modules/omnix_storage/rust/backend/Cargo.toml --no-default-features --features sqlite
cargo test --manifest-path modules/omnix_storage/rust/backend/Cargo.toml --no-default-features --features qdrant
```

From this package directory, resolve the Dart dependencies with
`flutter pub get`. Flutter applications bundle their native library through the
build hook. The separate example is in `example/`.

The bridge pins its Rust toolchain in `rust/rust-toolchain.toml`; Qdrant has
additional toolchain requirements compared with SQLite. Platform compiler tools
are required. Native examples have been exercised on Windows; verify each
selected backend on your target platform. The current native backends do not
provide browser storage.

Databases and checkpoints are not encrypted by this package. Your application
owns private-directory access, backups, retention and migrations. This package
is a source-only developer preview.
