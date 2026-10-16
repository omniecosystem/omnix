# Native Knowledge example

This Windows CPU example composes the independent Core and Knowledge Dart APIs:
native embedding, attributed Qdrant indexing, flush/reopen, retrieval and native
generation. It deliberately does not depend on the legacy root facade/runtime.

See [setup, model paths, qualification and limits](../../../doc/KNOWLEDGE_EXAMPLE.md).

```powershell
flutter pub get
flutter run -d windows
```

Use trusted local artifacts. This example never downloads a model or touches a
consumer application's store. Android and actual EmbeddingGemma remain unqualified.
