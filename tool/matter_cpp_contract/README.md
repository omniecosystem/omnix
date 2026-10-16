# Native Matter wrapper contract checks

Private host-side test tooling. This compiles the **actual Omnix C++ wrapper**
against minimal, authored SDK doubles, loads the resulting DLL through the Rust
adapter, and executes C++ ownership/error checks. It is not an SDK implementation,
not an interoperability test, and never contacts a device.

On Windows, from the Omnix repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\test_matter_cpp_contract.ps1
```

Requires Dart 3.12+, MSVC C++ tools and Rust 1.93.1. Dependency resolution may
download ordinary Dart packages; no model, Matter SDK image or SDK submodule
is downloaded. Native compilation uses `native_toolchain_c` rather than an
environment-specific compiler invocation. The runner restores its environment
variable and working directory, and fails on either build or test errors.

The checks cover synchronous completion, delayed connection/command callbacks,
close during either phase, connection and command failures, exception containment,
consumed operation IDs, invalid commands and the 32-operation bound. The doubles
do not reproduce SDK locks, network sessions, generated command serialization,
commissioning or platform services. Only the official-SDK build/device tests
can qualify those properties.

The test library and doubles must never be packaged with an application. They
are absent from the production GN target. There is no fallback to these doubles
if a production library fails to load.
