import 'dart:convert';
import 'dart:io';

import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  final bridge = Platform.environment['OMNIX_SESSION_TEST_BRIDGE'];
  final runtime = Platform.environment['OMNIX_SESSION_TEST_RUNTIME'];
  final model = Platform.environment['OMNIX_SESSION_TEST_MODEL'];
  test(
    'unsupported context accounting leaves native inference usable',
    () async {
      await initializeOmnixSessionLibrary(bridge!);
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        libraryPath: runtime!,
        contextTokens: 1024,
      );
      OmnixInteractionSession? session;
      try {
        session = await engine.startSession(
          modelPath: model!,
          instructions: 'Answer briefly.',
          maxOutputTokens: 64,
        );
        final unsupported = throwsA(
          predicate<Object>(
            (error) => error.toString().contains(
              'context-accounting-unsupported:litertlm',
            ),
          ),
        );
        final before = await session.exportHistory();
        await expectLater(session.configureContext(), unsupported);
        await expectLater(session.contextUsage(), unsupported);
        await session.configureContext(enabled: false);
        expect(await session.exportHistory(), before);
        const prompt = 'Reply with the word OK.';
        final output = (await session.sendStream(prompt).toList()).join();
        expect(output.trim(), isNotEmpty);
        final history =
            jsonDecode(await session.exportHistory()) as Map<String, dynamic>;
        final messages = history['messages'] as List<dynamic>;
        expect(messages, hasLength(2));
        expect(messages.first, ['user', prompt]);
      } finally {
        await session?.close();
        await engine.close();
      }
    },
    skip: bridge == null || runtime == null || model == null
        ? 'Set existing trusted bridge, runtime and model paths.'
        : false,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
