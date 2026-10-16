import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix_example/features/knowledge/presentation/controllers/knowledge_demo_controller.dart';
import 'package:omnix_example/features/knowledge/data/services/knowledge_native_backend.dart';
import 'package:omnix_storage/omnix_storage.dart';
import 'package:omnix_nexus/omnix_nexus.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('composed package opens SQLite and durable Nexus identity', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'omnix-composition-test-',
    );
    try {
      await tester.runAsync(() async {
        final file = p.join(directory.path, 'snapshots.sqlite');
        final snapshot = jsonEncode({
          'schemaVersion': 1,
          'record': {
            'id': 'test',
            'updatedAt': DateTime.now().toUtc().toIso8601String(),
          },
          'messages': [
            {'text': 'persistent'},
          ],
        });
        final store = OmnixConversationSnapshotStore(path: file);
        try {
          await store.writeSerializedSnapshot(snapshot);
        } finally {
          await store.close();
        }
        final reopened = OmnixConversationSnapshotStore(path: file);
        try {
          expect(await reopened.readSerializedSnapshot('test'), snapshot);
        } finally {
          await reopened.close();
        }
        final node = OmnixNexusNode(
          nodeDirectory: p.join(directory.path, 'node'),
        );
        final key = await node.createIdentity();
        expect(key, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(await node.publicKey(), key);
      });
    } finally {
      await directory.delete(recursive: true); // Only this test's owned data.
    }
  });
  testWidgets(
    'packaged native embeddings retrieve reopened source and generate',
    (tester) async {
      const encoder = String.fromEnvironment('OMNIX_EMBEDDING_MODEL');
      const tokenizer = String.fromEnvironment('OMNIX_EMBEDDING_TOKENIZER');
      const generation = String.fromEnvironment('OMNIX_GENERATION_MODEL');
      const embeddingGemma2 = bool.fromEnvironment('OMNIX_EMBEDDING2');
      expect(
        encoder,
        isNotEmpty,
        reason: 'Supply trusted local artifacts with --dart-define.',
      );
      if (!embeddingGemma2) expect(tokenizer, isNotEmpty);
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
            legacyGecko: !embeddingGemma2,
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
