# Native Core embeddings

Core executes embedding models. Knowledge supplies document semantics and
retrieval orchestration; Storage persists vectors. No generation model is
required to index or search text.

## Implemented slice

EmbeddingGemma 2 text execution now uses the separate opt-in
`litertlm-embedding-engine` feature and LiteRT-LM v0.18 embedding C API.
Flutter selects it with `embedding_engine: true`. The older tensor adapter below
is retained, not automatically repurposed. See [qualification and usage](EMBEDDINGGEMMA_2.md).

The Rust `litertlm-embeddings` feature explicitly enables the selected LiteRT
runtime plus the embedding adapter and statically built canonical SentencePiece
tokenizer. It is not enabled by a plain chat-only `litertlm` selection.
Neither runtime becomes a default. The reusable `EmbeddingModel` contract has
query/document tasks, an embedding profile and final vectors.

`.tflite` encoders use the official **LiteRT tensor C API**, not the LiteRT-LM
conversation API. Bindings are generated from LiteRT revision
`9fe5be45564c868408e6514c8aabb83e211a0911` (the dependency pinned by the current
LiteRT-LM bundle). Omnix owns lifecycle, tokenization orchestration and validation;
the native runtime executes the graph. No Dart reference package is imported.

The current adapter supports CPU, one Int32 input `[1, sequence_length]` and one
Float32 pooled output `[1, dimension]`. It refuses multi-input, dynamic-width,
per-token-output and mismatched tensor types. Native handles and the tokenizer
remain on one owning worker; drop closes and joins it. Host tensor buffers are
64-byte aligned and outlive their native views. Output is read through the native
lock/unlock API, copied and checked for dimension, finiteness and nonzero norm.
There is no second pooling or normalization step.

Profiles fingerprint model weights, tokenizer bytes, preprocessing convention
and tensor dimensions. Dimensions alone never identify compatible vectors.
Files must be trusted and remain immutable while open. Oversized text is rejected
instead of silently truncated; token-budgeted chunking remains Knowledge work.

## Explicit preprocessing, not model-name guessing

- `GemmaRetrieval`: BOS 2, EOS 1, pad 0, query prefix
  `task: search result | query: ` and document prefix `title: none | text: `.
  The tokenizer must declare the expected special IDs. EmbeddingGemma real-model
  qualification is still pending; correct-looking vectors are not sufficient.
- `LegacyGeckoRetrieval`: explicitly preserves the legacy task-prefixed ID-2
  preprocessing used by the Dart reference for Gecko. Its tokenizer disables BOS
  and assigns ID 2 to UNK. This is a **compatibility profile**, not a claim that
  it implements canonical Gecko preprocessing. It has a separate profile identity
  and is never selected automatically from a filename or dimension.

Reference inspection uncovered this distinction; blindly applying a single
Gemma tokenizer convention to every encoder would hide it. HF tokenizer JSON,
WordPiece, SigLIP and GGUF embedding execution are not implemented by this slice.

## Verify on Windows

From the Omnix root, with Rust and CMake/MSVC tools:

```powershell
cargo +1.98.1 test --manifest-path modules/omnix_core/rust/Cargo.toml -p omnix-core --features litertlm-embeddings
cargo +1.98.1 clippy --manifest-path modules/omnix_core/rust/Cargo.toml -p omnix-core --all-targets --features litertlm-embeddings -- -D warnings

$env:OMNIX_EMBEDDING_LIBRARY = 'C:\trusted-runtime\libLiteRt.dll'
$env:OMNIX_EMBEDDING_MODEL = 'C:\models\Gecko_512_quant.tflite'
$env:OMNIX_EMBEDDING_TOKENIZER = 'C:\models\sentencepiece.model'
cargo +1.98.1 test --manifest-path modules/omnix_core/rust/Cargo.toml -p omnix-core --features litertlm-embeddings --test litert_embedding_native -- --ignored --nocapture
```

The explicitly opted-in real test requires those trusted matching Gecko files;
ordinary CI tests download no model. It checks query/document differences,
semantic ranking, deterministic repeat/reopen, empty input and input overflow.
Local evidence reused an existing 120 MB model: 768-dimensional output, width
512, router query similarity 0.8552 for the relevant guide vs 0.5674 for a recipe.
This is fixture-level evidence, not a retrieval-quality benchmark.

For an explicitly chosen model/convention, the Rust example accepts:

```powershell
cargo +1.98.1 run --manifest-path modules/omnix_core/rust/Cargo.toml -p omnix-core --features litertlm-embeddings --example litert_embedding -- "$env:OMNIX_EMBEDDING_LIBRARY" "$env:OMNIX_EMBEDDING_MODEL" "$env:OMNIX_EMBEDDING_TOKENIZER" gecko-legacy 'How do I reset my router?'
```

## Knowledge composition

Knowledge's optional `core-litertlm-embeddings` feature supplies `CoreEmbedder`,
borrowing a mutable Core model without taking lifecycle ownership. The ordinary
Qdrant/vector-only Knowledge feature remains independent of Core.

```powershell
cargo +1.98.1 test --manifest-path modules/omnix_knowledge/rust/backend/Cargo.toml --features qdrant,core-litertlm-embeddings --test native_core -- --ignored --nocapture
```

That test indexes text with real Core vectors into its own disposable Qdrant
shard, flushes/reopens and retrieves the attributed public passage. It touches
no consumer database or installed app.

## Remaining gates

The handwritten Dart embedding API and its generated bridge now exist, behind
`omnix_core.embeddings: true` plus an explicit `litertlm` runtime selection.
The root Flutter example composes this with the separate Knowledge bridge.
See [Knowledge example and its packaged test](KNOWLEDGE_EXAMPLE.md).
The older packaged Storage test qualifies vector storage, not this new execution
path. EmbeddingGemma 2 text execution and packaged retrieval/generation are now
qualified on Windows CPU via the separate v0.18 embedding engine; the original
tensor adapter's Gemma convention still needs model/tokenizer qualification.
The tensor adapter still needs broader model/tokenizer and quality evaluation.
Qualification of a separate embedding-engine path does not qualify every tensor
layout or platform. Consult the current module configuration for target support.

Reference sources inspected, not copied: embedding tokenizer/worker and
LiteRT forward-pass implementations in Flutter Edge AI;
[official LiteRT headers](https://github.com/google-ai-edge/LiteRT/tree/9fe5be45564c868408e6514c8aabb83e211a0911/litert/c);
[canonical SentencePiece](https://github.com/google/sentencepiece);
[Gecko distribution](https://huggingface.co/litert-community/Gecko-110m-en).
