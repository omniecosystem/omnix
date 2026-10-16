import 'dart:io';

import 'package:omnix_core/omnix_core.dart';

Future<String> runNativeDemo() async {
  final library = Platform.environment['OMNIX_CORE_TEST_LIBRARY'];
  final modelPath = Platform.environment['OMNIX_CORE_TEST_MODEL'];
  if (modelPath == null) {
    throw StateError('Set OMNIX_CORE_TEST_MODEL to a trusted local artifact.');
  }
  final model = await OmnixCore().loadModel(
    libraryPath: library,
    modelPath: modelPath,
  );
  OmnixCoreConversation? chat;
  try {
    chat = await model.startConversation(
      systemPrompt: 'Answer briefly.',
      maxOutputTokens: 64,
    );
    await model.close();
    final first = await chat
        .sendStream('My favorite color is violet. Reply with just OK.')
        .join();
    var stopped = false;
    await for (final _ in chat.sendStream(
      'Count from one to one hundred, each number on its own line.',
    )) {
      if (!stopped) {
        stopped = true;
        await chat.cancelGeneration();
      }
    }
    if (!stopped) {
      throw StateError('No streamed chunk was received before stop.');
    }
    final second = await chat
        .sendStream('What is my favorite color? Answer with one word.')
        .join();
    if (!second.toLowerCase().contains('violet')) {
      throw StateError('History recovery after stopping failed.');
    }
    return 'Streamed first turn:\n$first\n\nStopped a turn and recovered history:\n$second';
  } finally {
    await chat?.close();
    await model.close();
  }
}
