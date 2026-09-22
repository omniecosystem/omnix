# Knowledge and retrieval

Omnix Knowledge separates reusable retrieval behavior from a host's document
picker, database schema, account system, and user interface.

## Core boundary

- `OmnixKnowledgeDocument` describes a durable source and its access label.
- `OmnixKnowledgeChunk` is the independently indexed unit.
- `OmnixKnowledgeBackend` hides embedding and vector-store implementations.
- `OmnixKnowledgeCoordinator` validates indexing, flushes buffered stores,
  normalizes retrieval results, enforces access labels, and assembles bounded
  RAG context with ordered citations.

Backends remain free to use Flutter Gemma RAG, SQLite, Qdrant, a native Rust
index, or a remote service. Those implementation types must not cross the
public Omnix API.

## Semantic interoperability

An embedding is meaningful only inside the space that produced it.
`OmnixEmbeddingSpace` therefore identifies the model, optional immutable
revision, and vector dimensions. A semantic query is rejected before search
when its space differs from the receiving backend.

`OmnixSemanticQuery` defaults to public knowledge only. This makes it a safe
starting contract for Omnixus, but the label is not authentication. A future
network layer must still authenticate peers, authorize every request, protect
transport confidentiality, limit resource use, and treat all remote metadata
as untrusted input.

`OmnixKnowledgeCodec` provides schema-versioned JSON-compatible semantic query
and attributed-result records. Omnixus may transport these records, but Omnix
does not prescribe peer discovery, routing, relays, identity, or wire protocol.

## RAG context

Context assembly accepts an explicit token budget and never silently mixes
citations from omitted chunks. Complete retrieved chunks are added in score
order until the budget is exhausted. The resulting text and citation list can
be passed to a conversation as augmented inference input while the original
user prompt remains the durable message.
