# LiteRT-LM Android C-API build

Build the official LiteRT-LM C target for Android ARM64.
This is distinct from the Kotlin/JNI AAR: Core calls the C interface from Rust,
and Dart exposes that implementation through its bridge.

## Prerequisites

Use Linux, including Ubuntu on WSL, with:

- LiteRT-LM revision `b2f686e2ed4718fb84ec398a61dd59ca0f0aff27`.
- Pinned Android prebuilt companions materialized with Git LFS.
- Bazel 7.6.1 and Linux Android NDK 28.2.13676358.
- Native compiler tools, Python, curl, unzip and CA certificates.
- An Android SDK location when required by the upstream configuration.

Keep the checkout and build cache on a Linux filesystem. Build dependencies
can occupy several gigabytes. These tools are not consumer runtime requirements.

## Build

From the Omnix checkout in Linux:

```bash
bash tool/build_litertlm_android.sh /path/to/LiteRT-LM /path/to/android-ndk-r28c /path/to/bazel /path/to/output
```

The arguments identify the checkout, NDK, Bazel executable and output directory.
Materialize the pinned `prebuilt/android_arm64/*.so` LFS objects first.
The script checks source pins, exported C functions and native dependencies.

## Packaging

`package_litertlm_android.sh` supports CPU and GPU profiles.
GPU packaging requires the pinned accelerator/sampler/Dawn companions,
including dynamically loaded libraries absent from `DT_NEEDED`.

Packaging checks ARM64 architecture, dependency closure, required C symbols
and 16 KiB ELF load alignment. Redistribution also requires complete licenses
and notices. Provenance checks are not device-inference qualification.

The Android build targets API 31. A lower minimum SDK needs a separately
qualified build. NPU delivery requires qualified vendor assets; it is not
implied by GPU packaging.

## Flutter delivery

Stage the archive at the path declared by the consuming application's hook
configuration. CPU and GPU profiles have different pinned checksums;
a CPU archive cannot satisfy a GPU selection.

From the application directory:

```powershell
flutter build apk --debug --target-platform android-arm64
```

Inspect the APK using `tool/verify_android_example.ps1` with the installed
NDK's readelf and Android build tools. ELF page alignment, APK alignment and
App Bundle generated-APK behavior are separate checks.

Android requires appropriate native-library extraction and, for API 31+
GPU loading, applicable optional vendor-library declarations. See
[Android native-library declarations](https://developer.android.com/guide/topics/manifest/uses-native-library-element).

## Validation boundary

Build and package inspection do not establish model execution, GPU performance,
low-memory resilience or platform lifecycle behavior.
Use isolated test apps and explicitly authorized device deployment.
Do not replace a Play-signed consumer installation with a locally signed APK.

Windows distributions and llama.cpp builds use separate artifacts and
qualification paths.
