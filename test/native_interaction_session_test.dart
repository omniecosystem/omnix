// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'dart:io';
import 'package:omnix/omnix_session.dart';
import 'package:test/test.dart';

void main() {
  final bridge = Platform.environment['OMNIX_SESSION_TEST_BRIDGE'];
  final runtime = Platform.environment['OMNIX_SESSION_TEST_RUNTIME'];
  final model = Platform.environment['OMNIX_SESSION_TEST_MODEL'];
  test(
    'root Dart sessions retain independent histories on the native engine',
    () async {
      await initializeOmnixSessionLibrary(bridge!);
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        libraryPath: runtime!,
        contextTokens: 2048,
      );
      OmnixInteractionSession? first;
      OmnixInteractionSession? second;
      OmnixInteractionSession? restored;
      try {
        first = await engine.startSession(
          modelPath: model!,
          instructions: 'Reply briefly.',
          maxOutputTokens: 16,
        );
        second = await engine.startSession(
          modelPath: model,
          maxOutputTokens: 16,
        );
        expect(await first.send('Remember violet. Say OK.'), isNotEmpty);
        expect(await second.exportHistory(), isNot(contains('violet')));
        expect(await second.send('Remember amber. Say OK.'), isNotEmpty);
        final history = await first.exportHistory();
        expect(history, contains('violet'));
        expect(history, isNot(contains('amber')));
        restored = await engine.startSession(
          modelPath: model,
          maxOutputTokens: 16,
        );
        await restored.restoreHistory(history);
        expect(await restored.exportHistory(), history);
        await engine.close();
        await first.close();
        expect(await restored.send('Reply hello.'), isNotEmpty);
        expect(await second.send('Reply hi.'), isNotEmpty);
      } finally {
        await first?.close();
        await second?.close();
        await restored?.close();
        await engine.close();
      }
    },
    skip:
        !Platform.isWindows ||
        bridge == null ||
        runtime == null ||
        model == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
