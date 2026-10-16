// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:test/test.dart';
import '../hook/windows_crt.dart';

void main() {
  test('requests static CRT without selecting a model engine', () {
    expect(staticWindowsCrt({}), {
      'RUSTFLAGS': '-C target-feature=+crt-static',
    });
  });
  test('preserves caller Rust flags', () {
    expect(staticWindowsCrt({'RUSTFLAGS': '--cfg custom'}), {
      'RUSTFLAGS': '--cfg custom -C target-feature=+crt-static',
    });
  });
  test(
    'respects encoded flag precedence and preserves argument boundaries',
    () {
      expect(
        staticWindowsCrt({
          'RUSTFLAGS': 'ignored',
          'CARGO_ENCODED_RUSTFLAGS': '--cfg\u001fcustom',
        }),
        {
          'CARGO_ENCODED_RUSTFLAGS':
              '--cfg\u001fcustom\u001f-C\u001ftarget-feature=+crt-static',
        },
      );
    },
  );
}
