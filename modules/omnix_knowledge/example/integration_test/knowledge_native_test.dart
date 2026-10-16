import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix_knowledge_example/knowledge_demo_controller.dart';
import 'package:omnix_knowledge_example/knowledge_native_backend.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'packaged native embeddings retrieve reopened source and generate',
    (tester) async {
      const encoder = String.fromEnvironment('OMNIX_EMBEDDING_MODEL');
      const tokenizer = String.fromEnvironment('OMNIX_EMBEDDING_TOKENIZER');
      const generation = String.fromEnvironment('OMNIX_GENERATION_MODEL');
      expect(
        encoder,
        isNotEmpty,
        reason: 'Supply trusted local artifacts with --dart-define.',
      );
      expect(tokenizer, isNotEmpty);
      expect(generation, isNotEmpty);
      final directory = await Directory.systemTemp.createTemp(
        'omnix-rag-test-',
      );
      final controller = KnowledgeDemoController(
        NativeKnowledgeDemoBackend(directory.path),
      );
      try {
        await tester.runAsync(() async {
          await controller.index(
            encoder: encoder,
            tokenizer: tokenizer,
            legacyGecko: true,
            title: 'Router guide',
            content:
                'To reset the router, hold its reset button for ten seconds. Wait for the indicator to turn blue before reconnecting.',
          );
          expect(controller.error, isNull);
          expect(controller.indexed, isTrue);
          await controller.ask(
            model: generation,
            question: 'How do I reset the router?',
          );
        });
        expect(controller.error, isNull);
        expect(controller.passages, isNotEmpty);
        expect(controller.passages.first.title, 'Router guide');
        expect(controller.answer, isNotEmpty);
        expect(controller.answer!.toLowerCase(), contains('reset'));
        // Answers are model output, not proof of factual grounding or injection safety.
      } finally {
        await controller.close();
        controller.dispose();
        await directory.delete(
          recursive: true,
        ); // Only this test's owned temporary shard.
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
