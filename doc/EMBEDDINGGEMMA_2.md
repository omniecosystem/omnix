# EmbeddingGemma 2 integration

Core executes EmbeddingGemma 2 through the LiteRT-LM embedding C API.
Knowledge coordinates indexing/retrieval and Storage persists vectors.
A generation model is not required for vector search alone.

## Pinned model profiles

| Profile | Bundle | Size |
| --- | --- | --- |
| Text | `embeddinggemma-2-text-270m.litertlm` | 164,626,432 bytes |
| Multimodal | `embeddinggemma-2-740m.litertlm` | 484,622,336 bytes |

Text distribution revision:
`9be6e8b90982095dc05c2bd162e4b954ee4dbac7`.
SHA-256:
`2d079ee2f6f066b1f368e8d7c819f55214eaef1d0513b312321901f30ab286fb`.

Multimodal distribution revision:
`24d962e906c7d332c6428e71c9676855024569e2`.
SHA-256:
`e7a8a2204b91e0f96e92960e84a09a89212e1633dcb7575a9bf3378b4df77f4c`.

These pins identify integration inputs, not bundled model weights.
Consult the official model card and distribution for licensing and capabilities.

- [Model card](https://ai.google.dev/gemma/docs/embeddinggemma/model_card_2)
- [Text distribution](https://huggingface.co/litert-community/embeddinggemma-2-text-270m-litert-lm)
- [Full distribution](https://huggingface.co/litert-community/embeddinggemma-2-740m-litert-lm)

## Selection

The Core Rust feature is `litertlm-embedding-engine`.
The Dart build hook selects `embedding_engine: true` alongside an explicit
compatible runtime selection.

The embedding engine owns bundle tokenization, pooling and output processing.
Its profile is distinct from the older tensor/SentencePiece adapter.
Do not reinterpret Gecko or text-only vectors as full-model vectors.

## Dart input

```dart
final model = await OmnixEmbeddingModel.open(
  modelPath: trustedFullBundle,
  convention: OmnixEmbeddingConvention.embeddingGemma2Multimodal,
);
try {
  final vector = await model.generateMultimodalEmbedding([
    const OmnixEmbeddingInput.text('Search this scene'),
    OmnixEmbeddingInput.image(imageBytes),
    OmnixEmbeddingInput.audio(wavBytes),
  ], document: false);
} finally {
  await model.close();
}
```

Use `embeddingGemma2` and ordinary text embedding calls for the text-only bundle.
Matching vector dimensions do not establish compatible embedding spaces.

## Media boundaries

The input contract supports ordered text, PNG/JPEG and PCM16 mono 16 kHz WAV.
Admission bounds and model context limits are independent.
The current C API does not accept a video container as a native input type.

Hosts can decode containers and supply supported sampled frames with metadata,
but that does not establish a temporal-understanding pipeline.
Retrieving a media source also does not automatically deliver its bytes to
an answering model through every tool-result adapter.

## Validation

Native tests require explicitly supplied compatible models and runtime artifacts.
They do not download weights. Test finite normalized vectors, profile isolation,
overflow, relevance and durable attributed retrieval separately.

Synthetic tones and image fixtures establish narrow behavior, not broad
speech or cross-modal quality. Validate resource coexistence and lifecycle
on actual deployment devices.

See [Core embeddings](CORE_EMBEDDINGS.md),
[Knowledge examples](KNOWLEDGE_EXAMPLE.md), and
[multimodal input](CORE_MULTIMODALITY.md).
