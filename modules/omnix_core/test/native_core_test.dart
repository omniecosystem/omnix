import 'dart:io';

import 'package:omnix_core/omnix_core.dart';
import 'package:test/test.dart';
import 'native_test_support.dart';

void main() {
  setUpAll(initializeTestBridge);
  test('standalone Core initializes and reports qualified platforms', () async {
    final platforms = await OmnixCore().supportedPlatforms();
    expect(platforms, Platform.isWindows ? ['windows'] : isEmpty);
  });
  final library = Platform.environment['OMNIX_CORE_TEST_LIBRARY'];
  final model = Platform.environment['OMNIX_CORE_TEST_MODEL'];
  test(
    'trusted native model supports multi-turn conversation through Dart',
    () async {
      final loaded = await OmnixCore().loadTrustedLiteRtLm(
        libraryPath: library!,
        modelPath: model!,
      );
      OmnixCoreConversation? chat;
      try {
        chat = await loaded.startConversation(
          systemPrompt: 'Answer briefly.',
          maxOutputTokens: 64,
        );
        await loaded.close();
        expect(
          await chat.send('My favorite color is violet. Reply with just OK.'),
          isNotEmpty,
        );
        expect(
          (await chat.send(
            'What is my favorite color? Answer with one word.',
          )).toLowerCase(),
          contains('violet'),
        );
        final streamed = await chat
            .sendStream('Say hello in one sentence.')
            .join();
        expect(streamed, isNotEmpty);
        var stopped = false;
        await for (final delta in chat.sendStream(
          'Count from one to one hundred, each number on its own line.',
        )) {
          expect(delta, isNotEmpty);
          if (!stopped) {
            stopped = true;
            await chat.cancelGeneration();
          }
        }
        expect(stopped, isTrue);
        final abandoned = await chat
            .sendStream(
              'Count from one to one hundred, each number on its own line.',
            )
            .take(1)
            .join();
        expect(abandoned, isNotEmpty);
        expect(
          (await chat.send(
            'What is my favorite color? Answer with one word.',
          )).toLowerCase(),
          contains('violet'),
        );
      } finally {
        await chat?.close();
        await loaded.close();
      }
    },
    skip: !Platform.isWindows || library == null || model == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
