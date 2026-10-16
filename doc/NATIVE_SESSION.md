# Native sessions

Root Omnix coordinates selected modules through Rust-owned sessions.
Independent modules remain usable without root orchestration.

```text
Host configuration -> Omnix session -> selected context -> Core execution
                              -> streamed response and source evidence
```

## Model ownership

Compatible model requests within one Omnix instance can share model leases.
Different instances or independently loaded bridge libraries do not share
handle registries or model pools automatically.

Use trusted immutable model files. Sessions retain their required model owner.
Logical conversation switching preserves separate histories; it is not proof
that the runtime supports concurrent native contexts. Replay has latency and
retained media has a memory cost.

## Context and retrieval

A host can configure Knowledge through root APIs rather than retrieve and
inject prompts manually on each turn. Retrieval policy and access scope are
explicit; model text does not expand the configured scope.

Retrieved sources provide provenance, not a guarantee that every generated
sentence follows them. Retrieved content is untrusted reference data, and
prompt wording alone is not a complete prompt-injection defense.

## Dart boundary

Import `package:omnix/omnix.dart` or the session entrypoint.
`OmnixCognitiveEngine` and `OmnixInteractionSession` expose native behavior;
the root Dart API does not orchestrate companion Dart libraries.

Build-time native features remain explicit. Selecting a runtime through Dart
cannot include a backend omitted from the build.
Native handles must remain within the library that owns them.

## Streaming, cancellation and persistence

Observe streaming completion, cancellation and errors separately.
Native ownership must settle before releasing callback state or starting
conflicting work. Cancelling an interaction does not undo an external action.

Visible transcripts and native history/checkpoints serve different purposes.
Restore compatible native context with fresh host capabilities; never execute
historical tools as new requests. Handle unsupported content and incompatible
checkpoints explicitly rather than silently substitute display text.

## Native asset ownership

When root Omnix and a standalone module use the same runtime distribution,
configure one compatible build-time asset owner to avoid duplicate library
filenames. Asset sharing is not shared native handles or Dart delegation.

See [the project overview](../README.md),
[model preparation](CHAT_READINESS.md),
[root Knowledge](ROOT_KNOWLEDGE.md), and
[integration validation](MIGRATION_QUALIFICATION.md).
