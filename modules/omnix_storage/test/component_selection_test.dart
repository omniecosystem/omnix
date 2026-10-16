// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:test/test.dart';
import '../hook/component_selection.dart';

void main() {
  test('each component is independently selected, with no default', () {
    expect(() => selectStorageFeatures({}), throwsArgumentError);
    expect(
      selectStorageFeatures({
        'engines': ['sqlite'],
      }),
      ['sqlite'],
    );
    expect(
      selectStorageFeatures({
        'engines': ['qdrant'],
      }),
      ['qdrant'],
    );
    expect(
      selectStorageFeatures({
        'engines': ['qdrant', 'sqlite'],
      }),
      ['sqlite', 'qdrant'],
    );
  });
  test('rejects empty, unknown, duplicate and malformed selections', () {
    for (final value in [
      [],
      ['unknown'],
      ['sqlite', 'sqlite'],
      [1],
      'sqlite',
      true,
    ]) {
      expect(
        () => selectStorageFeatures({'engines': value}),
        throwsArgumentError,
      );
    }
  });
}
