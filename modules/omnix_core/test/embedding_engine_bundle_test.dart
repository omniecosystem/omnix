// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'dart:io';
import 'package:test/test.dart';
import '../hook/embedding_engine_bundle.dart';

void main() {
  test(
    'rejects unverified local runtime before copying or extracting',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'omnix-embedding-bundle-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final archive = File.fromUri(directory.uri.resolve('untrusted.whl'));
      await archive.writeAsString('not a trusted archive');
      final output = directory.uri.resolve('output/');
      await expectLater(
        prepareEmbeddingEngineBundle(output, sourceArchive: archive),
        throwsStateError,
      );
      expect(await Directory.fromUri(output).exists(), isTrue);
      expect(
        await File.fromUri(
          output.resolve('embedding-engine/litert-lm.dll'),
        ).exists(),
        isFalse,
      );
    },
  );
}
