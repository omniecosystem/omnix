// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

/// Selects the requested LiteRT-LM execution backend without automatic fallback.
enum OmnixLiteRtLmBackend { cpu, gpu, npu }

/// Configures the native LiteRT-LM provider independently of the host UI.
///
/// Accelerator availability depends on the native distribution, device and
/// model. Selecting NPU does not make a CPU/GPU model NPU-compatible.
final class OmnixLiteRtLmOptions {
  const OmnixLiteRtLmOptions({
    this.backend = OmnixLiteRtLmBackend.cpu,
    this.cacheDirectory,
    this.dispatchDirectory,
  });
  final OmnixLiteRtLmBackend backend;

  /// Existing absolute directory for runtime-generated optimization caches.
  final String? cacheDirectory;

  /// Existing absolute directory containing NPU dispatch libraries.
  ///
  /// Only valid for NPU. When omitted, the native facade uses the engine
  /// library's directory; the required vendor libraries must be present there.
  final String? dispatchDirectory;

  String encode() {
    if (dispatchDirectory != null && backend != OmnixLiteRtLmBackend.npu) {
      throw ArgumentError('A dispatch directory requires the NPU backend.');
    }
    for (final directory in [cacheDirectory, dispatchDirectory]) {
      if (directory != null &&
          (directory.trim().isEmpty || directory.contains('\u0000'))) {
        throw ArgumentError('Invalid runtime directory.');
      }
    }
    // Rust verifies target-specific paths and directory existence.
    return jsonEncode({
      'backend': backend.name,
      if (cacheDirectory != null) 'cacheDirectory': cacheDirectory,
      if (dispatchDirectory != null) 'dispatchDirectory': dispatchDirectory,
    });
  }
}
