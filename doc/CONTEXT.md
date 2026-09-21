# Context management

Omnix keeps durable conversation history separate from the smaller context
replayed into an active model session. Trimming a model context must never
delete messages from durable storage.

`OmnixContextPolicy` selects replay history against an explicit
`OmnixContextBudget`. The included `OmnixRecentContextPolicy` preserves system
information and then keeps the newest contiguous history that fits. Pending
input can be reserved through `additionalMessages` without being returned as
part of replay history.

```dart
final policy = OmnixRecentContextPolicy(
  budget: OmnixContextBudget(
    contextWindowTokens: 8192,
    reservedOutputTokens: 1024,
  ),
);

final conversation = await runtime.openConversation(
  configuration,
  history: durableSnapshot.messages,
  contextPolicy: policy,
);
```

The default estimator is intentionally approximate. It uses four Unicode code
points per token and configurable costs for image and audio attachments. A
provider adapter should supply an exact `OmnixTokenEstimator` when its tokenizer
is available without loading another model.

Mandatory system information and pending input produce an
`OmnixContextOverflowException` when they cannot fit. Omnix does not silently
truncate those inputs because doing so could alter instructions or user intent.
