# Official Matter SDK shim (experimental)

This Omnix-authored shim wraps the `connectedhomeip` controller C++ API with
a versioned C function table consumed by Rust. It is not an upstream C API,
a standalone SDK distribution or a complete Matter controller.

The host owns SDK startup, commissioning, fabric storage and the event loop.
It supplies a live `DeviceController` and owner-retention callbacks to the shim.
Rust submits On/Off commands and polls their completion through
`omnix_nexus::matter::cpp`.

## Integrate into an SDK host

`BUILD.gn` is a source-set fragment for an application already building the
official SDK. Its controller dependency supplies SDK headers and generated cluster
types. Include it in the host's GN build and export `omnix_matter_get_api_v1`
from the resulting shared library.

Build the shim and host against the same SDK revision and configuration.
Do not pass a controller from an unrelated SDK binary. Enable exceptions for
the shim; its boundary catches exceptions rather than passing them through C.

Enable the Rust `matter-cpp` feature explicitly, then load the trusted absolute
shared-library path with `CppMatterApi::load` and attach the controller. Loading
and attachment are unsafe: the caller must verify artifact provenance,
architecture, ABI compatibility and native ownership. A matching version number
does not establish those properties.

The legacy `omnix_nexus::matter_cpp` path is a compatibility re-export.
Selecting the Cargo feature builds the Rust loader; it does not initialize an
SDK host or package a native shim for a Flutter application.

## Operations and lifetime

Only On/Off command submission and completion polling are exposed. A completed
operation reports an SDK error code, not attribute readback. There is no
`chip-tool` or simulator fallback. Commissioning, discovery, credential storage,
readback and platform initialization must be supplied separately.

- Retain/release hooks must be nonthrowing and keep the controller, SDK storage
  and event loop alive until outstanding callbacks finish. Release must defer
  SDK teardown until the current callback/stack-lock scope has unwound.
- Call bridge operations outside the SDK stack lock. One frontend owns a handle;
  do not close it concurrently with another operation.
- Poll returns pending or a terminal SDK error. A terminal poll consumes the
  operation ID. At most 32 unconsumed operations are accepted per handle.
- Close invalidates the frontend handle; it does not cancel device operations.
  Pending callbacks retain the host owner. A stopped event loop can therefore
  retain resources.
- Rust keeps successfully loaded shim libraries mapped for the process lifetime
  so SDK callbacks cannot enter unloaded code. Runtime replacement requires a
  process restart.

## Contract tests

From the repository root:

```sh
cargo test --locked --manifest-path modules/omnix_nexus/rust/backend/Cargo.toml --no-default-features --features matter-cpp --lib
```

These tests cover the Rust ABI checks and a deterministic function-table double.
They do not build the official SDK or communicate with Matter devices.

A separate Windows harness compiles `controller.cpp` against SDK doubles and
exercises delayed callbacks, owner retention, exception containment and capacity:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\test_matter_cpp_contract.ps1
```

Neither suite establishes compatibility with a particular official SDK build or
device. Validate that integration separately, including close during an active
command, commissioning, attribute readback, durable fabric storage and restart.
Applications must also configure their platform's network permissions and native
packaging.
