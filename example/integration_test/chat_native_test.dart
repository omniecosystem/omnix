import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix_example/features/home/data/repositories/chat_repository.dart';
import 'package:omnix_example/features/core/domain/structured_draft.dart';
import 'package:omnix_storage/omnix_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native chat survives SQLite close and runtime replay',
    (tester) async {
      const model = String.fromEnvironment('OMNIX_GENERATION_MODEL');
      expect(model, isNotEmpty);
      final directory = await Directory.systemTemp.createTemp(
        'omnix-chat-replay-',
      );
      final file = p.join(directory.path, 'chat.sqlite');
      NativeChatRepository? active;
      try {
        await tester.runAsync(() async {
          final first = active = NativeChatRepository(
            OmnixConversationSnapshotStore(path: file),
          );
          first.configureInstructions(
            'Be concise. Follow the requested answer format.',
          );
          await first
              .generate(
                model,
                'My favorite color is turquoise. Remember it. Reply with just OK.',
              )
              .drain<void>();
          expect(first.messages.length, 2);
          final records = await first.records();
          expect(records.length, 1);
          await first.close();
          active = null;
          final reopened = active = NativeChatRepository(
            OmnixConversationSnapshotStore(path: file),
          );
          await reopened.select(records.single.id);
          expect(
            reopened.instructions,
            'Be concise. Follow the requested answer format.',
          );
          expect(reopened.messages.first.text, contains('turquoise'));
          final answer = await reopened
              .generate(
                model,
                'What is my favorite color? Answer with one word.',
              )
              .join();
          expect(answer.toLowerCase(), contains('turquoise'));
          expect(reopened.messages.length, 4);
          expect((await reopened.records()).length, 1);
          await reopened.close();
          active = null;
          final drafts = NativeStructuredDraftBackend();
          try {
            final note = await drafts.draft(
              model,
              'Write a French note about paying transport costs in 2 days. Contact: 90 12 34 56.',
            );
            expect(note.title, isNotEmpty);
            expect(note.details, contains('2'));
            expect(note.details, contains('90'));
          } finally {
            await drafts.close();
          }
        });
      } finally {
        await active?.close();
        await directory.delete(
          recursive: true,
        ); // Only this test's owned directory.
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
