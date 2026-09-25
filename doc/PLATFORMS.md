# Platform support

Omnix is designed for Android, iOS, Windows, macOS, Linux, and web. Support is
reported conservatively: a platform becomes **verified** only after native
bridge build and integration tests run for it in continuous integration.

| Platform | Current status | Priority |
| --- | --- | --- |
| Android | Scaffolded | Primary |
| Windows | Scaffolded | Primary |
| iOS | Scaffolded | Secondary |
| macOS | Scaffolded | Secondary |
| Linux | Scaffolded | Secondary |
| Web/WASM | Scaffolded, separate FRB web build required | Experimental |

Primary priority reflects initial verification capacity, not a permanent API
or architecture limitation. Platform-specific functionality must sit behind
an Omnix contract and expose capability detection rather than silently
changing behavior.

The experimental Omnixus A2A dependency is compiled only for native Rust
targets. Its Windows loopback runtime round trip passes through the Rust A2A
listener and Dart Knowledge. Android ARM64 Rust checks pass, and the example
debug APK builds with `libomnix.so`; device runtime behavior remains untested.
iOS, macOS, and Linux builds also need verification. The web bridge
exposes an explicit unsupported result for these node operations rather than
pretending that a browser can run the current native listener. This does not
change the broader Omnix platform goals above.
