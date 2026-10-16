# Android native integration

The current composed LiteRT-LM path targets Android ARM64 and API 31 or later.
It uses the official runtime C interface from Rust, not the Kotlin/JNI AAR as
a substitute for C exports.

## Native artifact requirements

Provide the pinned archive selected by the consuming build configuration.
CPU and GPU profiles require different compatible contents and checksums.
The GPU profile includes dynamically loaded companions in addition to the
libraries visible in ELF dependencies.

Build hooks validate native delivery inputs. A fresh checkout can require
a locally built or separately obtained pinned archive.
See [the build guide](../tool/LITERTLM_ANDROID_BUILD.md).

## Loading and packaging

Rust locates sibling native libraries beside the loaded bridge.
The application must enable native-library extraction.
For App Bundles, validate generated APK behavior as well as the source manifest.

Check ARM64 architecture, required C symbols, dependency closure, ELF LOAD
alignment and APK alignment separately. A successful cross-build does not
establish runtime ABI compatibility.

## Embeddings

Android can use the selected LiteRT-LM embedding engine through its C API.
The separate older tensor/SentencePiece path and other runtime combinations
have different integration requirements; do not infer their support from the
chat library.

A Kotlin library with JNI entrypoints does not automatically expose the C API
required by a dynamically loaded Rust adapter.

## Host services and lifecycle

Flutter or other hosts supply capture, permissions, transfer scheduling and
background-service integration. Native sessions require explicit closure,
safe callback drain and compatible restoration.

Validate startup, streaming, cancellation, switching, resource pressure,
Knowledge coexistence and process restart using isolated test stores.
An APK build or visible Home screen does not qualify every scenario.

## Distribution

Native artifacts need source provenance, checksums and complete redistribution
notices. Production Matter distribution is separate from Core packaging.

Do not test by uninstalling a consumer app or clearing its model/database data.
Locally signed artifacts must not replace a Play-signed installation without
a deliberate signing and data-safety plan.
