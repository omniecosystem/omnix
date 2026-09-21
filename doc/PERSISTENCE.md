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

## Vector stores

Embedding indexes are retrieval infrastructure, not the source of truth for
conversation records. A knowledge module may index selected content in a
vector store while retaining exact documents, messages, ownership, and
deletion state in durable application storage.
