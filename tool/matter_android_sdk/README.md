# Official Android Matter controller build

Maintainer pipeline for building an Android controller AAR from the pinned
official connectedhomeip SDK. It does not build or install a consumer app.

## Prerequisites

Linux, including WSL Ubuntu; JDK 17; Python with venv support; GN/Ninja;
Android NDK `28.2.13676358`; Android platform 34; Kotlin compiler `2.1.10`;
and the official SDK bootstrap prerequisites.

Use an isolated official SDK checkout at
`0fa0eb338e20dad90b269149581c693a970a03cc`.
Bootstrap can download substantial toolchain archives.
Do not run Windows NDK executables inside Linux.

```bash
export OMNIX_MATTER_SOURCE=/path/to/isolated/connectedhomeip
export ANDROID_HOME=/path/to/android-sdk
export ANDROID_NDK_HOME=/path/to/android-ndk-r28c
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH=/path/to/kotlin-2.1.10/kotlinc/bin:$PATH
export OMNIX_MATTER_OUTPUT=/path/to/omnix/.local-native/matter/android-arm64
bash /path/to/omnix/tool/matter_android_sdk/build.sh
```

## Packaging

`package.py` checks the source revision, tracked modifications, submodule
revisions, output files, ARM64 ELF alignment and required Java classes.
It rejects conflicting JAR entries and writes stable ZIP ordering/timestamps.
This is not a guarantee of bit-for-bit reproducibility across machines.

Outputs include the AAR and provenance metadata. Provenance is not a signature
or a complete dependency notice inventory. Review all distributed licenses
and runtime dependencies before publishing a binary.

Run packaging unit tests from this directory:

```bash
python3 -m unittest -v test_package
```

These tests do not build the SDK or qualify controller/device interoperability.

## Consumer resolution

The [module SDK resolver](../../modules/omnix_nexus/android/README.md) supports
checksum-verified local artifacts, cache reuse and explicitly configured HTTPS
downloads. A public default release URL is not currently supplied.

Inspect provenance before using a local artifact. Qualification overrides are
not trusted release pins merely because a checksum can be computed locally.

## Release validation

Validate the official Java API, native dependencies, ELF/APK alignment,
commissioning, independent readback and persistent reconnect.
Use isolated test apps and fabrics. Device tests require a separate data-safe
deployment decision.

The manual CI workflow builds a qualification artifact, not a production SDK
release. Windows controller packaging is separate from this Android pipeline.
