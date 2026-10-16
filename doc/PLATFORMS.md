# Platform coverage

The current composed application integration focuses on Windows x64 and
Android ARM64. Independent module and backend support differs; a Rust target
or Flutter runner directory does not establish complete application support.

| Area | Current integration boundary |
| --- | --- |
| Windows x64 | Native LiteRT-LM and llama.cpp integration; accelerator and feature coverage depend on the adapter |
| Android ARM64 | LiteRT-LM C-API integration, API 31+; selected CPU/GPU packaging |
| Linux, macOS and iOS | Additional native integration and packaging qualification required |
| Web/WASM | No complete browser inference/orchestration integration currently provided |
| Embedded | Target-specific native runtimes and host adapters required |

These are composed-integration boundaries, not a claim that every independent
crate is limited to the same platforms.

## Android

Core's current native loading requires extracted sibling libraries.
Validate extraction in both direct APKs and APKs generated from an App Bundle.
API, ABI and ELF/APK page alignment must match the selected distribution.

See [Android readiness](ANDROID_NATIVE_READINESS.md).

## Accelerators

CPU/GPU availability depends on runtime artifacts, model and hardware.
NPU support is experimental and requires separately qualified vendor assets.
An available UI selector is not evidence that execution succeeds.

## OS services

Capture, permissions, notifications, BLE, background work and device actions
are host integrations. Portable Rust contracts do not make those services
uniform across operating systems.

Matter backend selection is explicit; see [backend boundaries](MATTER_BACKENDS.md).
Browser hosting cannot assume native sockets or process launching.

## Validation

Build, packaging inspection, real-model inference and full application lifecycle
tests establish different claims. Record the model, backend and target for
each supported configuration. Unsupported operations must not silently fall
back to behavior that drops the requested capability.
