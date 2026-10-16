# Pinned llama.cpp source

Upstream: https://github.com/ggml-org/llama.cpp

Revision: `26394b4e6749a41c3633db040e0987500a5f7013`.

Only the directories needed to compile the CPU library are included: `include`,
`src`, `ggml`, `cmake`, `vendor`, plus `CMakeLists.txt` and `LICENSE`.
These are upstream native files, not a Rust or Dart wrapper implementation.
Preserve nested third-party notices. Native sources are unchanged.

The included native files match the official upstream archive at this revision.
Archive URL:
`https://codeload.github.com/ggml-org/llama.cpp/tar.gz/26394b4e6749a41c3633db040e0987500a5f7013`.
Archive SHA-256:
`1d0fcd22eb0fb31b1f75de2cc9e585a3338b8937043662a0c222a1e9261fed29`.

`include/llama.h` SHA-256:
`0199c9f12a5dd4099191a9b508d62ad715212981d181046a0d29750c57dd8694`.

Regenerate checked-in Rust bindings using the maintainer generator with
`--llama`; use `--llama --check` to verify generated output. Ordinary consumer
builds do not need bindgen/libclang or network access for these sources.
