# Persistence boundaries

Omnix separates active model-session history from durable application
persistence.

## Session history

`OmnixConversation` and `OmnixAgentSession` expose provider-neutral
`OmnixMessage` snapshots and can replace their active history. This supports
suspending a native session, recreating it, and replaying context without
exposing provider message types.

Session history is not a database. Closing an application process may discard
it unless a host stores the snapshots. `OmnixConversationStore` is the durable
repository boundary for complete conversation snapshots. A store must write
conversation metadata and ordered messages atomically.

`OmnixConversationCodec` provides a versioned JSON-compatible representation,
including multimodal message bytes. Database adapters may store binary payloads
more efficiently as separate blobs while preserving the same decoded contract.

## Durable storage

The core package does not require Drift, `sqlite3`, Qdrant, or another storage
engine. Durable conversation and workflow storage will be expressed through
repository contracts. Hosts can then supply adapters appropriate to their
schema, encryption, synchronization, and platform requirements.

An application that already owns a relational schema should adapt that schema
to Omnix contracts instead of migrating data into an engine-owned database.
Optional reusable storage adapters may be published separately when their
platform dependency and schema lifecycle justify an independent package.

Active model context is selected independently through `OmnixContextPolicy`.
Context trimming affects only replay into a native session and must never be
written back as deletion of older durable messages.

`OmnixConversationCoordinator` enforces this boundary for ordinary
conversations. It restores an existing snapshot, selects bounded context before
each turn, performs context restoration and generation under one scheduler
lease, and writes the complete finished turn atomically. Hosts remain
responsible only for implementing `OmnixConversationStore`.

```dart
final conversation = await OmnixConversationCoordinator.open(
  runtime: runtime,
  store: conversationStore,
  record: conversationRecord,
  configuration: configuration,
  contextPolicy: OmnixRecentContextPolicy(
    budget: OmnixContextBudget(
      contextWindowTokens: 8192,
      reservedOutputTokens: 1024,
    ),
  ),
);

await for (final event in conversation.send(
  augmentedPrompt,
  durablePrompt: 'Continue our discussion',
)) {
  // Render text, thinking, or tool-call events.
}
```

Overlapping turns on the same coordinator are rejected. If generation fails,
events already emitted remain observable to the caller, but the incomplete turn
is not committed to durable history. `durablePrompt` lets retrieval-augmented
applications send hidden context to the model without storing it as text the
user supposedly wrote.

## Vector stores

Embedding indexes are retrieval infrastructure, not the source of truth for
conversation records. A knowledge module may index selected content in a
vector store while retaining exact documents, messages, ownership, and
deletion state in durable application storage.
