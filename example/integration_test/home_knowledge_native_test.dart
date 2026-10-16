import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix_example/features/home/data/repositories/chat_repository.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';
import 'package:omnix_example/features/home/presentation/widgets/home_chat_panel.dart';
import 'package:omnix_example/features/knowledge/presentation/controllers/knowledge_demo_controller.dart';
import 'package:omnix_example/features/knowledge/data/services/knowledge_native_backend.dart';
import 'package:omnix_storage/omnix_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Home native retrieval, generation, saved sources and replay',
    (tester) async {
      const encoder = String.fromEnvironment('OMNIX_EMBEDDING_MODEL');
      const generation = String.fromEnvironment('OMNIX_GENERATION_MODEL');
      expect(encoder, isNotEmpty);
      expect(generation, isNotEmpty);
      final directory = await Directory.systemTemp.createTemp(
        'omnix-home-rag-',
      );
      final knowledge = KnowledgeDemoController(
        NativeKnowledgeDemoBackend(p.join(directory.path, 'knowledge')),
      );
      CoreController? active;
      try {
        await tester.runAsync(() async {
          await knowledge.index(
            encoder: encoder,
            tokenizer: '',
            legacyGecko: false,
            title: 'Router guide',
            content:
                'To reset the router, hold its reset button for ten seconds. Wait for the indicator to turn blue before reconnecting.',
          );
          expect(knowledge.error, isNull);
          final home = active = CoreController(
            NativeChatRepository(
              OmnixConversationSnapshotStore(
                path: p.join(directory.path, 'chat.sqlite'),
              ),
            ),
            knowledge: knowledge,
          )..configureKnowledge(true);
          await home.send(generation, 'How do I reset the router?');
          expect(home.error, isNull);
          expect(home.messages.last.text, isNotEmpty);
          expect(home.messages.first.text, 'How do I reset the router?');
          expect(home.messages.last.sources.single.title, 'Router guide');
          final record = home.history.single;
          await home.close();
          home.dispose();
          active = null;
          final reopened = active = CoreController(
            NativeChatRepository(
              OmnixConversationSnapshotStore(
                path: p.join(directory.path, 'chat.sqlite'),
              ),
            ),
            knowledge: knowledge,
          );
          await reopened.select(record);
          expect(reopened.error, isNull);
          expect(reopened.useKnowledge, isTrue);
          expect(
            reopened.messages.last.sources.single.content,
            contains('ten seconds'),
          );
          await reopened.send(
            generation,
            'What color must the indicator turn?',
          );
          expect(reopened.error, isNull);
          expect(reopened.messages.last.text.toLowerCase(), contains('blue'));
          expect(reopened.messages, hasLength(4));
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: HomeChatPanel(controller: active!)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Conversation options'));
        await tester.pumpAndSettle();
        expect(find.text('Answer from Knowledge'), findsOneWidget);
        await tester.tap(find.byTooltip('Close conversation options'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Router guide').first,
          200,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('Router guide'), findsWidgets);
        await tester.pumpWidget(const SizedBox());
      } finally {
        await active?.close();
        active?.dispose();
        await knowledge.close();
        knowledge.dispose();
        await directory.delete(
          recursive: true,
        ); // Only this test's owned directory.
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
