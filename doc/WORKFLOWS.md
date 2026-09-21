# Workflow runtime

Omnix Workflow turns host-defined executors into durable, observable tasks. The
runtime owns lifecycle transitions, event ordering, retries, cancellation,
restart recovery, and access to the shared non-preemptive inference scheduler.
It does not own presentation or prescribe a database.

## Storage contract

Hosts implement `OmnixWorkflowStore` using their preferred persistence layer.
`persistTransition` must atomically save the latest task and append its event.
That invariant prevents a crash from leaving task state and event history in
disagreement.

Tasks found in `running` state during initialization are treated as interrupted,
returned to `queued`, recorded with a `recovered` event, and resumed. Terminal
tasks are never replayed.

## Executor contract

Each `OmnixWorkflowExecutor` handles one stable task `kind`. It emits progress
updates and an optional final result without exposing provider-specific agent or
model objects:

```dart
final class SummarizeExecutor implements OmnixWorkflowExecutor {
  @override
  String get kind => 'summarize';

  @override
  Stream<OmnixWorkflowExecutionUpdate> execute(
    OmnixWorkflowTask task,
    OmnixWorkflowCancellationToken cancellationToken,
  ) async* {
    cancellationToken.throwIfCancelled();
    yield OmnixWorkflowProgress(message: 'Reading source.');
    yield const OmnixWorkflowResult(output: 'Summary');
  }
}
```

Compose the runtime with the same scheduler used by interactive inference:

```dart
final runtime = FlutterGemmaOmnix.createRuntime();
final workflows = await runtime.openWorkflow(
  store: appWorkflowStore,
  executors: [SummarizeExecutor()],
);

await workflows.initialize();
await workflows.createTask(
  id: 'task-1',
  kind: 'summarize',
  title: 'Summarize the document',
  maxAttempts: 2,
);
```

Workflow attempts release scheduler ownership before a retry is queued. A
waiting interactive job using the reserved `chat` task identifier therefore
runs before the next workflow attempt, while an active task is never interrupted
mid-turn.

The package intentionally does not select Drift, SQLite, or another database.
Persistence adapters can evolve independently while the task and event
contracts remain stable.

`OmnixWorkflowCodec` provides the versioned JSON-compatible representation for
those adapters. Persist the encoded maps as records or JSON, and reject schema
versions newer than the adapter understands instead of guessing at fields.
