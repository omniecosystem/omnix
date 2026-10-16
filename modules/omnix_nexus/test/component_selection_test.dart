// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:test/test.dart';
import '../hook/component_selection.dart';

void main() {
  test('each component is independently selected, with no default', () {
    expect(() => selectNexusFeatures({}), throwsArgumentError);
    expect(
      selectNexusFeatures({
        'protocols': ['a2a'],
      }),
      ['a2a'],
    );
    expect(
      selectNexusFeatures({
        'protocols': ['matter'],
      }),
      ['matter'],
    );
    expect(
      selectNexusFeatures({
        'protocols': ['matter', 'a2a'],
      }),
      ['a2a', 'matter'],
    );
  });
  test('rejects empty, unknown, duplicate and malformed selections', () {
    for (final value in [
      [],
      ['unknown'],
      ['a2a', 'a2a'],
      [1],
      'a2a',
      true,
    ]) {
      expect(
        () => selectNexusFeatures({'protocols': value}),
        throwsArgumentError,
      );
    }
  });
  test('rejects the retired experimental_matter setting', () {
    for (final defines in <Map<String, Object?>>[
      {'experimental_matter': true},
      {
        'protocols': ['matter'],
        'experimental_matter': false,
      },
      {
        'protocols': ['matter'],
        'android': <String, Object?>{'experimental_matter': true},
      },
    ]) {
      expect(
        () => selectNexusFeatures(defines, android: true),
        throwsArgumentError,
      );
    }
  });
  test('rejects malformed platform overrides before feature selection', () {
    for (final value in [false, 'android_host', <String>[]]) {
      expect(
        () => selectNexusFeatures({
          'protocols': ['a2a'],
          'android': value,
        }, android: true),
        throwsArgumentError,
      );
    }
  });
}
