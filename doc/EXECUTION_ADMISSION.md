# Shared native execution admission

First implementation slice, 11 October 2026. Core owns admission mechanics;
Omnix composition selects a shared gate. This is not a complete inference or
workflow scheduler, memory budget, priority system or live-input API.

## Implemented

`omnix_core::execution::ExecutionAdmission` supplies explicit active-slot and
waiting-request limits. Acquisition can reject immediately or wait FIFO within
a supplied duration. Waiting observes cancellation; timeout and cancellation
remove the queued ticket. A permit releases its slot on return, error or unwind.
Snapshot reports actual active and waiting counts, not estimated resource use.

Core consumers opt in through `ownership::ModelPool::with_admission`. Root
`session::Omnix::new` uses a host-scoped one-slot gate with zero waiting capacity:
contention returns `execution-busy` rather than accumulating inference requests.
Rust hosts may select another shared gate with `with_execution_admission` before
loading models. Separate Omnix instances are independent unless explicitly given
the same gate. There is no global process-wide scheduler.

All ordinary/tool generation entry points on pooled model conversations acquire
one slot, including media requests and tool-result continuations. Shared weights
do not share conversation histories. A returned tool turn releases admission
before the agent invokes host tools or approval. A workflow executor using a
model from the same pool participates in the same gate; arbitrary host callbacks
and independently loaded models do not automatically do so.

Cold initialization in this pool now acquires the same gate. Only the
single-flight leader acquires a slot; cached leases and followers of the same
load do not acquire additional slots. Admission rejection or timeout is published
to attached followers like a loader failure, allowing later calls to retry.
The permit covers native loading, not the lifetime of resident model weights,
and releases on success, loader error or panic. Loading runs outside pool locks.
This prevents unbounded overlapping cold loads and inference, not out-of-memory
failures from already resident models.

Core's runtime-neutral `embedding::AdmittedEmbeddingModel` wraps any
`EmbeddingModel`. Its `load` method admits encoder initialization; query and
document embeddings acquire the supplied gate per call and release on return,
error or unwind. Profiles, vectors and retrieval conventions are unchanged.
Standalone Core/Knowledge hosts opt in by supplying this model to an existing
Knowledge adapter. There is no second Knowledge scheduler or runtime-specific
admission policy.

Root Rust hosts can use `Omnix::load_embedding`; the local Knowledge provider's
`open_with_engine` uses that API. The root bridge now configures the engine before
opening its Knowledge encoder, so both encoder loading and query embeddings share
the selected gate. The existing Dart `OmnixExecutionOptions` therefore applies
without another Dart implementation or a changed bridge signature. Retrieval
finishes before conversational inference acquires its slot; do not retain a
permit across a host callback that reenters the same gate.

Root now exposes `index_document` and `retrieve_sources` through its configured
context provider. The local adapter performs Knowledge's document embedding,
upsert and flush before acknowledging success. The public Dart methods are
`indexDocument` and `retrieveSources`; they forward to Rust, not a Dart encoder
or retrieval implementation. Read-only custom context providers reject indexing
by default. Visibility is explicitly supplied by the trusted host and defaults
to private in the Dart document API. This does not register a model-callable tool.

`OmnixLocalKnowledge.createStore` explicitly permits a new host-selected index.
Without it the existing profile marker is required. Existing indexes still must
match their persisted profile; no automatic clearing or space rebinding occurs.

The Windows example's non-legacy panel uses root indexing/retrieval and generation. Before
assigning the index to Home it owns a temporary root engine and verifies close/
reopen. After assignment, it borrows Home's engine when the model, store and
retrieval policy match, without closing the borrowed engine. The host selects a
two-place, thirty-second queue. Borrowed indexing therefore shares Home's gate.
Legacy Gecko remains explicitly separate; independently opened module/native
engines do not automatically share capacity across libraries or instances.
Android root integration is documented separately in
[Android root Knowledge](ANDROID_ROOT_KNOWLEDGE.md). Windows evidence here does
not independently qualify Android behavior.

The public Dart API uses this root gate without a Dart scheduler. Pass optional
`OmnixExecutionOptions` when opening `OmnixCognitiveEngine`; configuration is
immutable for that engine. `executionSnapshot()` reads actual native counters
without waiting for the current inference to finish. Explicit native diagnostic
codes surface as `OmnixExecutionException`; unrelated errors retain their cause.
Older custom transports retain their default behavior and reject explicit
configuration/diagnostics unless they implement `OmnixExecutionTransport`.

```dart
final engine = await OmnixCognitiveEngine.open(
  runtimes: ['litertlm'],
  execution: const OmnixExecutionOptions(
    maxActive: 1,
    maxWaiting: 2,
    wait: Duration(seconds: 30),
  ),
);
final snapshot = await engine.executionSnapshot();
```

The binding permits 1–16 active calls, 0–256 waiting calls, and up to five minutes
of waiting in whole milliseconds. Queue capacity and waiting duration must both
be zero or both positive; defaults still reject contention immediately. These
are API envelope limits, not measured device capacity. Session recovery follows
the selected adapter's lifecycle contract; admission failures do not trigger
automatic retries.

Counters are point-in-time snapshots, not a pushed admission event stream. Native
text now uses the same structured terminal-event stream as media so a native
failure cannot silently end text delivery and become a later source-lookup error.

## Boundaries and limits

- Unwrapped embedding providers, checkpoint operations
  and model memory usage are not covered by this admission gate.
- Embedding providers participate only when wrapped in the admitted Core model.
  Rust callers can cancel queued admission through its explicit cancellation
  method; the underlying synchronous embedding/Knowledge contracts do not offer
  cancellation of native computation or cancellation propagation from a chat.
- Existing adapter/index mutex waits are outside the gate's queue. Snapshot counts
  admitted operations and gate waiters, not every host request blocked elsewhere.
- Cold-load admission has a bounded wait but the existing loading API has no
  cancellation handle. Single-flight followers wait for their leader; that wait
  and native initialization itself have no new deadline or interruption guarantee.
- Cancellation polling while waiting is not instantaneous interruption of native
  execution. Runtime cancellation and safe release remain backend responsibilities.
- A synchronous streaming callback must not reenter the same gate while retaining
  a slot. Zero-wait mode rejects such contention instead of blocking; queued mode
  still requires a bounded timeout and non-reentrant host integration.
- Browser blocking admission is unsupported. The gate rejects contended waiting
  on wasm32; this does not qualify browser inference or embedded synchronization.
- Workflow task state, retry safety and durable checkpoints remain Workflow's
  responsibility. A busy error must not be interpreted as successful execution.
- There are no implicit priority, preemption, automatic retry or sensor-frame
  replacement policies.

## Verification and next gates

Rust tests cover capacity, queue rejection, FIFO ordering, queued cancellation,
timeouts, unwinding and all ten ordinary/tool generation entry points. Root
composition tests verify rejection leaves history unchanged and shared model
initialization remains single-flight. These are deterministic contract tests,
not measured device resource or background execution qualification.

The initial admission pass completed 60 Core tests (one separate environment-gated test ignored),
65 root composition tests and 24 public Dart contract tests. The rebuilt Windows
bridge also passed ordinary Gemma 4 inference and agent/tool checkpoint
close/reopen without reexecuting historical tools. Those two real-model checks
are regressions for the new default admission path, not a concurrent workflow
inference or Android qualification.

Follow-up qualification passed through the rebuilt public Windows bridge with
the existing Gemma 4 E2B model: active inference, queued waiting, queue-full
rejection, queued cancellation, and a real workflow whose supplied executor runs
inference through another session on the same engine. The executor ran once;
the workflow persisted success, histories remained isolated, and counters returned to zero. All three
Windows native checks passed, including context capability reporting and agent
checkpoint reopening without reexecuting historical tools. Thirty public
Dart contract tests and 66 root Rust tests pass. This does not qualify Android,
background execution or continuous input.

Cold-load follow-up: 64 Core tests passed (one environment-gated test ignored),
including rejection without invoking the loader, cache reuse under contention,
single-flight followers using only one slot, timeout recovery, and permit release
after loader errors/panics. Root's 66 tests passed; Core strict Clippy and targeted
Dart analysis passed. The rebuilt Windows bridge passed the real workflow/interactive
contention regression. Cold-load contention itself is verified with deterministic
test providers, not a device memory-pressure experiment.

Repeat with `dart test integration_test/execution_native_test.dart`, supplying
the existing trusted `OMNIX_SESSION_TEST_BRIDGE`, `OMNIX_SESSION_TEST_RUNTIME`
and `OMNIX_SESSION_TEST_MODEL` paths. Only a dedicated temporary Workflow database
is created and removed; consumer app data is untouched.

Embedding follow-up: 67 Core tests passed (one environment-gated test ignored),
three Knowledge adapter tests and 68 root tests passed. Tests cover document/query
admission, cancellation before invoking the encoder, queue release, unchanged
profiles/vectors, root gate sharing and redacted retrieval failures. The real
Windows EmbeddingGemma 2 encoder passed rejection/recovery using existing trusted
model/runtime files. That native test holds a gate permit to represent contention;
it does not claim simultaneous real chat inference or Android qualification.
No model download, app installation or app-data reset was performed.

Repeat the real encoder check with trusted `OMNIX_EMBEDDING2_LIBRARY` and
`OMNIX_EMBEDDING2_MODEL` paths:

```powershell
cargo test --manifest-path modules/omnix_core/rust/backend/Cargo.toml --features litertlm-embedding-engine --test embeddinggemma2_native admitted_native_encoder -- --ignored --nocapture
```

These verification runs used `OMNIX_CORE_LITERTLM_HOST_PACKAGING=1` to avoid
redundant chat-runtime downloads while supplying the encoder library explicitly.
This checks execution, not automatic native packaging.

Root indexing follow-up: 70 root Rust tests, 29 selected public Dart tests and
43 selected example tests passed. Targeted Dart/Flutter analysis was clean.
The rebuilt Windows bridge passed real chat/indexing contention: a document
queued behind Gemma 4 inference, persisted after the slot released, survived
engine reopening, and private documents were excluded from public retrieval.
The three native admission/context/checkpoint regressions also passed. The
example's borrowed/owned engine lifetimes are covered by contract tests, not a
new manual Android or UI qualification.

Run `dart test integration_test/knowledge_indexing_native_test.dart` with the
trusted session bridge/runtime/generation paths above and `OMNIX_EMBEDDING2_MODEL`.
The qualified encoder runtime `litert-lm.dll` must be packaged beside the bridge,
alongside the existing chat bundle. For this native check only, the existing
trusted encoder DLL was staged in the build-output directory; models were not
copied or downloaded. The test removes only its dedicated temporary index.


Idle encoder release is now available through the Rust root and Dart facade;
see [idle resource release](IDLE_RESOURCE_RELEASE.md) for ownership boundaries,
reload behavior and platform limits. Broader platform/OS-pressure verification
remains separate from explicit release API qualification.
Priority, pushed admission events and safe interruption policies need additional
bounded slices, not a parallel Dart implementation.
See [live interaction direction](LIVE_INTERACTION_DIRECTION.md).
