// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  test('runtime information has value semantics', () {
    const first = OmnixRuntimeInfo(
      apiVersion: 1,
      engineName: 'Omnix',
      engineVersion: '0.1.0-dev.1',
    );
    const second = OmnixRuntimeInfo(
      apiVersion: 1,
      engineName: 'Omnix',
      engineVersion: '0.1.0-dev.1',
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });
}
