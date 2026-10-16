# Idle resource release

An operating-system pressure signal is a host input, not a model-generated tool.
Rust consumers call `Omnix::release_idle_resources`; Dart consumers call
`OmnixCognitiveEngine.releaseIdleResources()`. The example's Home lifecycle observer
forwards Flutter's memory-pressure callback to its root engines.
It also notifies the Knowledge panel's root owner; a borrowed Home engine may
receive the same signal twice, which is harmless because release is idempotent.

## What is released

The native local Knowledge encoder is dropped only when its owner can be acquired
without waiting. Retrieval or indexing in progress (including waiting for an
inference slot) produces `Busy`. There is no cancellation or automatic retry.
The index remains open, documents remain persisted, and visibility rules do not
change. A later embedding operation reloads through the same admission gate.

Core provides a runtime-neutral `ReloadableEmbeddingModel` with a supplied loader.
Knowledge's owned adapter uses that primitive; root composition supplies the
native loader. Reload rejects a changed embedding profile. The native local
adapter also rejects changed file size/modification metadata. Hosts must still
treat installed model files as immutable; metadata is not an integrity proof.

Chat model pools already use weak references. Models retained by conversations,
agents, or prepared sessions are not evicted: the report counts live model owners,
not sessions, bytes, or available RAM. A host may separately close its idle
prepared session, but this API never discards a live conversation or its history.

## Boundaries and limitations

- No guessed memory budgets or guarantee of immediate OS RAM reclamation.
- Custom context providers explicitly report `Unsupported` unless they implement
  idle release. No provider reports `NotRegistered`.
- Dart forwards the native result. It tracks release completion for safe engine
  closure but does not queue pressure handling behind indexing.
- This slice does not evict Qdrant caches, manage GPU-driver caches, release the
  standalone module example's encoder, or provide automatic OOM recovery.
- Root local Knowledge is qualified on Windows. Android's standalone Knowledge
  path is still separate; do not claim that it gains encoder trimming here.

## Verification

Unit tests cover actual model-owner destruction, idempotent release, unchanged
profile, single reload, failed reload, explicit unsupported transports, and
pressure/close ordering. The root Windows native indexing test exercises `Busy`
during contention, release/reload with a persisted index and public filtering,
and continued generation from a retained chat. An actual OS pressure notification
is distinct from this explicit API qualification and must be validated separately.

The bridge API changed: rebuild native libraries and apps together. No app data
reset or model download is required.

Verified on Windows in this slice: 71 root Rust tests, seven focused Core
embedding tests, four Knowledge adapter tests, 32 selected public Dart tests,
48 example lifecycle/controller tests, and the real-model release/reload test
passed. Targeted Dart and Flutter analysis was clean. Core library strict Clippy
also passed. The three real-model admission/context/agent-checkpoint regressions
passed against the rebuilt root bridge. The first native test assertion incorrectly expected a model lease
to survive cancellation; the test now opens a live conversation before checking
preservation, matching the engine's existing cancellation semantics.
