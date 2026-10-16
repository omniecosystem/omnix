import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/knowledge/data/services/text_document_import.dart';
import 'package:path/path.dart' as p;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'imported long text survives native reopen and grounds an answer',
    (tester) async {
      const encoder = String.fromEnvironment('OMNIX_EMBEDDING_MODEL');
      const model = String.fromEnvironment('OMNIX_GENERATION_MODEL');
      expect(encoder, isNotEmpty);
      expect(model, isNotEmpty);
      await tester.runAsync(() async {
        expect(await File(encoder).exists(), isTrue);
        expect(await File(model).exists(), isTrue);
        final temporary = await Directory.systemTemp.createTemp(
          'omnix-text-import-',
        );
        OmnixCognitiveEngine? engine;
        OmnixInteractionSession? session;
        Future<OmnixCognitiveEngine> open(bool create) =>
            OmnixCognitiveEngine.open(
              runtimes: ['litertlm'],
              contextTokens: 4096,
              knowledge: OmnixLocalKnowledge(
                embeddingModel: encoder,
                storePath: p.join(temporary.path, 'index'),
                createStore: create,
                topK: 3,
                threshold: 0,
              ),
            );
        try {
          // More than one Rust chunk, with the queried fact beyond the first chunk.
          final text =
              '${'The archive includes ordinary office inventory records. ' * 16}\n'
              'Réparation guide: The emergency router recovery code is COBALT-7391. '
              'Use COBALT-7391 for emergency router recovery.\n'
              '${'The archive also includes routine cleaning schedules. ' * 10}';
          final file = File(p.join(temporary.path, 'manual.txt'));
          await file.writeAsString(text, flush: true);
          final imported = decodeKnowledgeText(
            p.basename(file.path),
            await file.readAsBytes(),
          );
          expect(imported.text, text);
          expect(imported.text.length, greaterThan(512));
          engine = await open(true);
          await engine.indexDocument(
            OmnixKnowledgeDocument(
              id: 'manual-import',
              documentId: 'manual-import',
              title: imported.name,
              content: imported.text,
              public: true,
            ),
          );
          // A second import must not replace the first one.
          await engine.indexDocument(
            const OmnixKnowledgeDocument(
              id: 'other-import',
              documentId: 'other-import',
              title: 'other.txt',
              content: 'The office opens at nine in the morning.',
              public: true,
            ),
          );
          await engine.close();
          engine = null;
          engine = await open(false);
          const question = 'What is the emergency router recovery code?';
          final sources = await engine.retrieveSources(question);
          expect(
            sources.any(
              (source) =>
                  source.title == 'manual.txt' &&
                  source.content.contains('COBALT-7391'),
            ),
            isTrue,
          );
          expect(
            sources.every((source) => source.content.runes.length <= 512),
            isTrue,
          );
          session = await engine.startSession(
            modelPath: model,
            maxOutputTokens: 128,
          );
          final answer = await session.send(
            question,
            knowledge: OmnixKnowledgeUse.required,
          );
          expect(answer.toUpperCase(), contains('COBALT-7391'));
          expect(
            session.sources.any((source) => source.title == 'manual.txt'),
            isTrue,
          );
          binding.reportData = {
            'textImport': 'passed',
            'retrievedPassages': sources.length,
            'bytes': utf8.encode(text).length,
          };
        } finally {
          await session?.close();
          await engine?.close();
          // Only this invocation's newly created test files/index, never model data.
          await temporary.delete(recursive: true);
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
