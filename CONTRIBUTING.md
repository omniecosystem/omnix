# Contributing to Omnix

Thank you for helping build Omnix.

Before opening a change:

1. Keep public contracts independent of Flutter UI and generated bridge types.
2. Add or update tests for observable behavior.
3. Regenerate bridge files after changing Rust APIs.
4. Format and analyze both Dart and Rust code.
5. Keep extraction commits separate from refactoring commits.
6. Explain compatibility, privacy, and resource implications in the change.

Generated files under `lib/src/rust` and `rust/src/frb_generated.rs` must be
produced by `flutter_rust_bridge_codegen`; do not edit them manually.
