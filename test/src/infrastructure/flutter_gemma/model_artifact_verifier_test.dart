// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:omnix/src/infrastructure/flutter_gemma/model_artifact_verifier.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;
  late File artifact;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'omnix-verifier-',
    );
    artifact = File('${temporaryDirectory.path}${Platform.pathSeparator}model');
    await artifact.writeAsString('hello');
  });

  tearDown(() => temporaryDirectory.delete(recursive: true));

  test('accepts an artifact matching size and SHA-256', () async {
    await verifyModelArtifact(
      path: artifact.path,
      expectedSize: 5,
      expectedSha256:
          '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
    );
  });

  test('rejects an artifact with the wrong size', () async {
    await expectLater(
      verifyModelArtifact(
        path: artifact.path,
        expectedSize: 6,
        expectedSha256:
            '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
      ),
      throwsStateError,
    );
  });

  test('rejects an artifact with the wrong digest', () async {
    await expectLater(
      verifyModelArtifact(
        path: artifact.path,
        expectedSize: 5,
        expectedSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      throwsStateError,
    );
  });
}
