# Android root Knowledge integration

Root Knowledge can use the selected Android ARM64 LiteRT-LM C runtime for
embedding execution and Qdrant-backed indexing. Core owns runtime artifacts;
root Omnix owns its configured encoder, index and execution-admission gate.

## Ownership

Indexing and retrieval should use the configured owner rather than open the
same shard through independent bridges. Release old owners before reopening
their paths. Matching Home/index configurations can share a root engine.

Persist resource configuration, not native handles or approvals.
Missing or incompatible resources must not silently create a replacement index.

## Native validation entrypoints

The root example includes:

- `integration_test/root_knowledge_native_test.dart`.
- `integration_test/agent_knowledge_restart_native_test.dart`.

Tests require compatible readable generation and embedding models.
Use explicit test configuration and disposable stores.
Engine close/reopen, process restart and actual OS memory pressure are separate
qualification scenarios.

## Device safety

Use the qualification application identity where supported and verify the built
APK's ID before deployment. It cannot automatically read another application's
private model directory.

Do not copy multi-gigabyte files, broaden storage permissions or replace a
consumer installation merely to bypass isolation.
Device deployment requires an explicit signing/data-safety plan.

## Coverage

Validate shared admission, cancellation, busy/idle encoder release, reload,
visibility filtering, attributed generation and restart restoration.
Restoring an agent must not execute historical tools.

A completed-turn restart does not qualify unfinished external effects,
extended background liveness, low-memory killing or every media combination.
GPU/NPU and other models require their own evidence.

See [root Knowledge](ROOT_KNOWLEDGE.md) and
[integration validation](MIGRATION_QUALIFICATION.md).
