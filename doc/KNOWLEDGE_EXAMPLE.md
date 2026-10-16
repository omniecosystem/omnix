# Knowledge examples

The root Flutter example demonstrates Knowledge alongside Home and the other
Omnix modules. The standalone Knowledge example isolates the embedding,
retrieval and generation integration.

## Root example

From the repository root:

```powershell
cd example
flutter pub get
flutter run -d windows
```

Configure a compatible embedding model and storage location in Knowledge.
Index supported content, then use the shared Home interaction to query it.
The interface's import options depend on the current host implementation;
the Rust API receives content and metadata rather than owning a file picker.

Model weights are separate from native runtime dependencies. Use trusted model
files with the appropriate profile and licensing. Import or download controls
in the host do not make every model compatible with every adapter.

## Standalone example

From the repository root:

```powershell
cd modules/omnix_knowledge/example
flutter pub get
flutter run -d windows
```

Build hooks select native components from the example's package configuration.
Rust and native compiler tools are required. Follow the module READMEs for
runtime artifacts and target requirements.

Supply paths to a compatible encoder and generation model. Some embedding
profiles require a paired tokenizer; others use the tokenizer packaged with
the model. Do not enable the legacy Gecko compatibility profile for unrelated
weights.

Index a short passage with a source title, then retrieve and inspect its source
and score separately from the generated answer. A successful generation is not
proof that every claim is supported by the retrieved material.

## Persistence

An index belongs to an embedding profile. Reopening it with an incompatible
encoder must not silently reinterpret existing vectors.
Use a new location or an explicit rebuild when changing profiles.

On Windows, native vector-store paths may require extended-length path handling
for nested files and atomic writes. Use the Storage adapter's path handling
rather than removing path prefixes manually.

## Validation

Use disposable stores for insert, flush, close/reopen, retrieval and removal
tests. Native integration tests need explicitly configured model paths and
matching runtime artifacts. Skipped model tests are not passing qualifications.

UI/controller tests do not validate the OS picker or native model inference.
A packaged desktop test does not qualify mobile process death, memory pressure
or background execution. Device tests require an isolated application and an
explicit data-safety plan.

See [Core embedding conventions](CORE_EMBEDDINGS.md),
[Knowledge integration](KNOWLEDGE_PLAN.md), and the
[Knowledge module](../modules/omnix_knowledge/README.md).
