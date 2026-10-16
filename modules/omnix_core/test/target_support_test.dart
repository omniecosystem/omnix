// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:code_assets/code_assets.dart';
import 'package:test/test.dart';

import '../hook/target_support.dart';

void main() {
  test('rejects a lower application API than the pinned runtime', () {
    expect(() => validateAndroidCoreApi(30), throwsUnsupportedError);
    expect(() => validateAndroidCoreApi(31), returnsNormally);
    expect(() => validateAndroidCoreApi(35), returnsNormally);
  });
  test('allows qualified Windows x64 packaging', () {
    expect(
      () => validateCoreTarget(OS.windows, Architecture.x64),
      returnsNormally,
    );
  });

  test(
    'rejects unqualified targets before native compilation or downloads',
    () {
      for (final target in [
        (OS.android, Architecture.arm64),
        (OS.android, Architecture.x64),
        (OS.windows, Architecture.arm64),
        (OS.linux, Architecture.x64),
        (OS.macOS, Architecture.arm64),
        (OS.iOS, Architecture.arm64),
      ]) {
        expect(
          () => validateCoreTarget(target.$1, target.$2),
          throwsA(isA<UnsupportedError>()),
        );
      }
    },
  );

  test('Android rejects unselected or unqualified components', () {
    expect(
      () => validateCoreTarget(OS.android, Architecture.arm64),
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'actionable diagnostic',
          contains('llama.cpp and legacy tensor encoders remain unqualified'),
        ),
      ),
    );
  });
  test('Android candidate allows only explicitly selected LiteRT-LM', () {
    expect(
      () => validateCoreTarget(
        OS.android,
        Architecture.arm64,
        features: ['litertlm'],
      ),
      returnsNormally,
    );
    for (final features in [
      ['llamacpp'],
      ['litertlm', 'llamacpp'],
    ]) {
      expect(
        () => validateCoreTarget(
          OS.android,
          Architecture.arm64,
          features: features,
        ),
        throwsUnsupportedError,
      );
    }
    expect(
      () => validateCoreTarget(
        OS.android,
        Architecture.arm64,
        features: ['litertlm'],
        legacyEmbeddings: true,
      ),
      throwsUnsupportedError,
    );
  });
}
