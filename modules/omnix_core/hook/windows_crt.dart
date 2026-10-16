// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

// Cargo gives encoded flags precedence over RUSTFLAGS. Preserve caller flags
// while making the Windows native asset independent of the VC redistributable.
Map<String, String> staticWindowsCrt(Map<String, String> environment) {
  final encoded = environment['CARGO_ENCODED_RUSTFLAGS'];
  if (encoded != null) {
    return {
      'CARGO_ENCODED_RUSTFLAGS':
          '$encoded\u001f-C\u001ftarget-feature=+crt-static',
    };
  }
  final flags = environment['RUSTFLAGS'] ?? '';
  return {'RUSTFLAGS': '$flags -C target-feature=+crt-static'.trim()};
}
