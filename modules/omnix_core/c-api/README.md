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

## macOS

On Apple silicon with Rust and the Xcode command-line tools installed, run:

```sh
bash modules/omnix_core/c-api/build-macos.sh
```

The build verifies the pinned LiteRT-LM 0.18.0 archive and checks its exported
symbols. It builds the Rust library and a plain Swift client, then stages
both dylibs beside the executable in `modules/omnix_core/c-api/target/macos`.
The build also runs a linkage check through the Swift client.

Use a trusted, vision-capable local model to try an image question and a
follow-up on the same session:

```sh
modules/omnix_core/c-api/target/macos/omnix-core-smoke \
  /absolute/path/to/model.litertlm overview.png crop.png \
  "What is in these images?" "What color was it?"
```

A Swift app can import `OmnixCoreC` from `include/module.modulemap` and link
the Omnix dylib. Bundle both dylibs together in the app's Frameworks directory
and sign them with the app's signing identity. Model files stay in app-owned
storage or at a host-approved path.

The C ABI is a preview for streamed conversation turns. This build targets
Apple silicon CPU. Intel macOS, iOS, and tool conversations through this C
surface remain outside this preview.
