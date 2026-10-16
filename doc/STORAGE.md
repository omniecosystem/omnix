# Native storage

Omnix Storage provides independently selectable SQLite and Qdrant Edge
components. A separate database service is not required for these embedded
backends.

## Ownership

Rust owns database connections, validation, durable operations and lifecycle.
Hosts select dedicated private paths and decide which application records
to store. Existing product databases are not migrated automatically.

SQLite snapshots and vector indexes are different capabilities.
Storage does not perform inference or decide which retrieved information
belongs in a response; Core and Knowledge have those responsibilities.

## Conversation snapshots

`OmnixConversationSnapshotStore` exposes a serialized snapshot store through
the standalone Dart API.

```dart
final store = OmnixConversationSnapshotStore(path: privateDatabasePath);
try {
  await store.initialize();
  final serializedRecords = await store.readSerializedRecords();
} finally {
  await store.close();
}
```

The store validates its supported snapshot format.
It is not an arbitrary SQL API or a substitute for every application schema.

Operations are serialized; closure drains accepted work.
Database ownership and schema mismatches must fail explicitly rather than
silently reset an unrelated database.

## Privacy and durability

Private app storage is not encryption. Checkpoints can contain prompts,
tool results and media. Directory permissions, backups and retention are host
responsibilities.

WAL/shared-memory files belong with the database.
Atomic snapshot replacement does not provide exactly-once external tool effects.

## Vectors

Qdrant indexes bind to an embedding profile. Dimensional equality alone is
insufficient compatibility. Validate metadata filters and visibility before
returning results to a remote peer.

Knowledge adds source identity and retrieval orchestration over Storage.
Use a separate index or explicit rebuild when changing incompatible profiles.

## Validation

Test write, close/reopen, rejected-write preservation, deletion and ownership
conflicts with disposable databases. Vector tests need profile-mismatch,
filtering and durable update/removal checks.

A test with fixed vectors does not establish embedding quality.
Native bridge tests do not qualify every platform or clean-machine packaging.

See the [Storage module](../modules/omnix_storage/README.md) and
[Knowledge integration](KNOWLEDGE_PLAN.md).
