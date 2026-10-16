# Root Knowledge integration

Root Omnix can own an embedding provider and a compatible persistent index.
Dart configures the provider and exposes native indexing/retrieval; it does
not implement a second embedding or prompt-construction pipeline.

## Configuration

```dart
final engine = await OmnixCognitiveEngine.open(
  runtimes: ['litertlm'],
  knowledge: OmnixLocalKnowledge(
    embeddingModel: absoluteEmbeddingGemma2Path,
    storePath: absoluteExistingIndexPath,
    publicOnly: true,
  ),
);
final session = await engine.startSession(modelPath: absoluteChatModelPath);
try {
  final reply = await session.send(
    'How do I reset the device?',
    knowledge: OmnixKnowledgeUse.required,
  );
} finally {
  await session.close();
  await engine.close();
}
```

The native build must include the selected Knowledge and runtime integrations.
An import alone does not add missing artifacts.

## Retrieval policy

A configured provider can retrieve without a model-selected tool.
`disabled` skips retrieval; `required` requires a provider, not a positive match.
This deterministic policy is distinct from an agent choosing a search tool.

Source attribution is evidence, not a guarantee of every generated statement.
Retrieved content remains untrusted data.
Access scope is supplied by the host, not expanded by model output.

## Indexing and ownership

Explicit creation allows a new compatible store; reopening validates the profile.
An incompatible encoder must not silently rebind existing vectors.
Indexing acknowledges only after its native persistence operations complete.

Release independently opened index/encoder owners before reopening their paths
through root Omnix. Never pass companion native handles into the root library.
Sessions can retain owners after their engine facade closes.

Inference and admitted embedding operations can share a gate within a configured
engine. Independently loaded libraries or instances do not automatically share it.

## Persistence and lifecycle

Hosts may persist resource configuration, not live handles or historical grants.
Missing resources and invalid settings need explicit failure handling.

Displayed questions/sources and native context are different records.
Restore supported context faithfully without interpreting saved tool calls as
new actions.

See [Knowledge examples](KNOWLEDGE_EXAMPLE.md),
[execution admission](EXECUTION_ADMISSION.md), and
[integration validation](MIGRATION_QUALIFICATION.md).
