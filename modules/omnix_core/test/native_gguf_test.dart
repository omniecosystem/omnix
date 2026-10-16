import 'dart:io';
import 'package:omnix_core/omnix_core.dart';
import 'package:test/test.dart';
import 'native_test_support.dart';

void main() {
  final artifact = Platform.environment['OMNIX_GGUF_MODEL'];
  setUpAll(() async {
    if (artifact != null && Platform.isWindows) await initializeTestBridge();
  });
  test(
    'GGUF routes and retains history after stream cancellation through Dart',
    () async {
      final model = await OmnixCore().loadModel(modelPath: artifact!);
      OmnixCoreConversation? chat;
      try {
        chat = await model.startConversation(
          systemPrompt: 'Answer briefly.',
          maxOutputTokens: 64,
        );
        await model.close();
        expect(
          await chat.send('My favorite color is violet. Reply with just OK.'),
          isNotEmpty,
        );
        expect(
          await chat
              .sendStream(
                'Count from one to one hundred, each number on its own line.',
              )
              .take(1)
              .join(),
          isNotEmpty,
        );
        expect(
          (await chat
                  .sendStream(
                    'What is my favorite color? Answer with one word.',
                  )
                  .join())
              .toLowerCase(),
          contains('violet'),
        );
      } finally {
        await chat?.close();
        await model.close();
      }
    },
    skip: artifact == null || !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
