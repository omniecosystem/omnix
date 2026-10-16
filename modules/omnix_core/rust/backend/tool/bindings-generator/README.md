# Maintainer binding generation

Generate C API bindings from the checked-in upstream headers. The tool verifies
the pinned entry-header SHA-256 values before generation, has a separate lockfile
and is excluded from ordinary Core builds. It neither downloads native artifacts
nor compiles a runtime.

Install libclang and Rust's rustfmt component. Set `LIBCLANG_PATH` if libclang
is not discoverable. Supply SDK include paths through
`BINDGEN_EXTRA_CLANG_ARGS` when required by the target toolchain.

From `modules/omnix_core/rust`:

```sh
cargo run --locked --manifest-path backend/tool/bindings-generator/Cargo.toml
cargo run --locked --manifest-path backend/tool/bindings-generator/Cargo.toml -- --llama
cargo run --locked --manifest-path backend/tool/bindings-generator/Cargo.toml -- --embedding
cargo run --locked --manifest-path backend/tool/bindings-generator/Cargo.toml -- --embedding-engine
```

The default generates LiteRT-LM conversation bindings. The other modes generate,
respectively, llama.cpp bindings, LiteRT tensor bindings and LiteRT-LM embedding
engine bindings. Select one mode per invocation.

Append `--check` after the argument separator to compare generated output without
writing it. For example:

```sh
cargo run --locked --manifest-path backend/tool/bindings-generator/Cargo.toml -- --llama --check
```

Commit regenerated output together with the corresponding header pins and tool
lockfile. The allowlist selects the APIs used by each adapter. Exposing another
symbol requires implementing and testing its ownership and error contracts too.

LiteRT-LM uses opaque handles and scalar/pointer arguments. llama.cpp also exposes
concrete model/context parameters and batch structures; these bindings were
generated for Windows x64. Check layout, compilation and runtime behavior before
using them with another target ABI.

The tensor embedding mode uses a maintainer-only include configuration for
optional accelerator declarations. Neither successful generation nor matching
declarations establish a model's tokenizer, preprocessing or pooling convention.
