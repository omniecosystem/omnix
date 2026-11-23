# Omnix Core C API

This source-based preview exposes the independent Rust Core crate to C and C++
hosts. Build it with Cargo. The build has no Flutter, Dart or FRB dependency.

```sh
cargo build --locked --release --manifest-path modules/omnix_core/c-api/Cargo.toml
```

On Windows x64, link the generated `omnix_core_c.dll.lib` import library and
include [omnix_core.h](include/omnix_core.h). Deploy `omnix_core_c.dll` and the
[pinned CPU runtime DLLs](../rust/backend/build_support/litertlm_windows_cpu.txt)
from the same Cargo profile directory beside the host executable. Cargo verifies
the runtime archive during the build. Supply an absolute path to a trusted,
compatible `.litertlm` model at runtime. No model file is bundled.

Open a model once, then open a conversation for each session. Pass the text,
JPEG/PNG and PCM WAV parts in prompt order after enabling the corresponding
encoders on the model. Follow up on the same conversation handle to retain
context. Use a new cancellation handle for each send. Run model opening,
conversation opening and sending off the UI thread. The send drains native work
before returning. Close the conversation and free the cancellation handle only
after the send returns, then close the model when it is no longer needed.

Windows x64 CPU is the first exercised C host configuration. The ABI is a
preview and currently covers streamed conversation turns. Apple packaging and
tool conversations through this C surface remain to be qualified.
