# Third-party runtime notices

Omnix Core integrates native runtimes with their own licenses, build inputs and
redistribution requirements. Model weights are separate external artifacts and
are not included in this package.

## llama.cpp

The optional `llamacpp` build uses upstream llama.cpp/ggml C/C++ sources pinned
to revision `26394b4e6749a41c3633db040e0987500a5f7013`:

- Source: <https://github.com/ggml-org/llama.cpp>.
- License: [MIT](third_party/llamacpp/LICENSE).
- Vendored source: `rust/backend/vendor/llama.cpp/`.
- Pin and binding-generation information:
  [LLAMA_UPSTREAM.md](rust/backend/vendor/LLAMA_UPSTREAM.md).

Preserve the upstream license and nested third-party notices when redistributing
the sources or compiled runtime. Rust bindings are generated from the upstream
C headers; the implementation is not supplied by a Rust runtime-wrapper crate.

## Windows LiteRT-LM chat runtime

The pinned Windows x64 distribution is
[native-v0.17.1-a](https://github.com/DenisovAV/flutter_gemma/releases/tag/native-v0.17.1-a),
built from Google's LiteRT-LM v0.17.1 (`5e58e9a0`).

Archive SHA-256:

```text
e505e247b07313c05bbc957b7c33c82f6adb6c6c78eecae03a590319c7d049e2
```

The LiteRT-LM Apache-2.0 license is retained in
[rust/backend/vendor/litertlm/LICENSE](rust/backend/vendor/litertlm/LICENSE).

The native archive includes accelerator companions such as Dawn, the DirectX
shader compiler, OpenVINO and TBB. The selected packaging profile determines
which libraries are bundled. Preserve the applicable license and notice material
for each redistributed component, including any transitive native dependencies.

An accelerator library's presence does not by itself establish model/device
compatibility or provide its required system runtimes. External-library overrides
remain the application's responsibility.

## Windows LiteRT-LM embedding runtime

The optional `embedding_engine: true` selection extracts
`litert_lm/litert-lm.dll` from Google's
[litert-lm-api 0.18.0 wheel](https://pypi.org/project/litert-lm-api/0.18.0/).
It does not package Python, an interpreter or model weights.

Wheel SHA-256:

```text
eb02dc5d0fc6a894a664cfcc63e3aaf3100973ba2c9a6a7eebf4df8749a01038
```

The matching headers and upstream license are in
`rust/backend/vendor/litertlm_embedding/`. This embedding artifact is separate
from the Windows v0.17 chat runtime.

## Other distributions and models

Android builds use separate pinned archives. Retain the license material and
build provenance associated with the archive selected by your application.
These Windows artifact hashes do not identify an Android distribution.

Each model has its own license and usage terms. Check the selected model's
published terms before redistribution. Runtime licenses do not grant rights to
model weights.
