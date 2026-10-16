# Native Qdrant Edge qualification

This isolated executable evaluates the official Rust `qdrant-edge` 0.8.0 API.
It does not use a Dart plugin, UniFFI bridge, vector database server, model, or
embedding download. Its temporary three-dimensional vectors are test fixtures,
not model-generated embeddings. No existing database is opened.

From the Omnix repository root:

```powershell
cargo +stable run --manifest-path tool/qdrant_edge_spike/Cargo.toml --locked
```

The lockfile's `sysinfo` 0.39 dependency requires Rust >=1.95. Omnix's existing
1.93.1 toolchain cannot build this dependency graph. The isolated experiment
uses the already-installed stable compiler (1.98.1 on the qualification host);
it does not upgrade Omnix or change production module dependencies. Do not bypass
the dependency's Rust-version check or patch downloaded registry source.

The executable asserts nearest-vector ordering, ID filtering, rejection of a
wrong vector dimension, durable flush/reopen and deletion. A fresh OS temporary
directory is owned by the test and cleaned up on normal completion.

This is engine qualification, **not the Storage adapter**. A subsequent
experimental adapter now exists in `modules/omnix_storage/rust/backend`, behind
the `qdrant` feature. Its own tests cover profile ownership, finite-vector
validation, metadata filtering, exclusive-open behavior and fail-closed state.
See [the module README](../../modules/omnix_storage/rust/backend/README.md).
Consumers of that optional feature need a newer compiler; SQLite-only builds
retain the existing toolchain. Changing the shared toolchain still needs
build-hook/CI qualification. Native Windows success
does not establish Android, iOS, macOS, Linux or web availability.
