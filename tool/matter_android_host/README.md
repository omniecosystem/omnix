# Android Rust host harness

This qualification JNI library exercises the Nexus Matter host contract through
the Android SDK owner. It is not a separate Matter stack or a public controller
distribution.

Rust calls Java command/readback methods on the serial SDK worker.
No JNI object handle is cast to a C++ controller pointer.
Frontend closure does not delete the process-wide SDK owner.

## Build

From the repository root:

```powershell
cd tool/matter_android_host
.\build.ps1
$env:OMNIX_MATTER_ANDROID_RUST_HOST = (Resolve-Path target/aarch64-linux-android/release/libomnix_matter_android_host.so).Path
```

The build script selects the installed Android NDK and requests 16 KiB ELF
alignment. It does not deploy an app. The Android SDK AAR is a separate pinned
input; see the [SDK build guide](../matter_android_sdk/README.md).

## Device checks

See the [isolated Android harness](../matter_android_app/README.md).
Tests require a compatible commissioned fixture and an explicitly selected
device. Do not target OmniAsk or use a production fabric.

Rust-host checks verify command/readback behavior and owner reuse.
They do not prove deterministic SDK deletion, Activity recreation during
an outstanding command, or production attestation compatibility.

## JNI signatures

`hostSetOnOff(String, int, boolean)` must return JVM `void`, not boxed
`kotlin.Unit`. `hostReadOnOff(String, int)` must return JVM `boolean`.
Preserve these method signatures when changing host glue.
