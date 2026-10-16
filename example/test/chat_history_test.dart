import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';
import 'package:omnix_example/features/home/presentation/widgets/home_chat_panel.dart';
import 'package:omnix_example/features/home/presentation/widgets/chat_history_panel.dart';
import 'package:omnix_example/app/showcase_shell.dart';

class MemoryBackend implements PersistentCoreBackend {
  @override
  String? currentId;
  @override
  List<ChatEntry> messages = [];
  @override
  Future<List<ChatRecord>> records() async => [
    const ChatRecord('saved', 'Saved conversation', 'model'),
  ];
  @override
  Future<void> select(String? id) async {
    currentId = id;
    messages = id == null
        ? []
        : [const ChatEntry('assistant', 'Restored answer')];
  }

  @override
  Stream<String> generate(String model, String prompt) async* {
    currentId ??= 'saved';
    messages = [
      ...messages,
      ChatEntry('user', prompt),
      const ChatEntry('assistant', 'Reply'),
    ];
    yield 'Reply';
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> close() async {}
}

void main() {
  testWidgets('history selects saved chat and new chat clears view', (
    tester,
  ) async {
    final controller = CoreController(MemoryBackend());
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: ShowcaseShell(
          home: HomeChatPanel(controller: controller),
          history: ChatHistoryPanel(controller: controller),
          pages: List.generate(
            4,
            (_) =>
                (_) => const SizedBox(),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Chat history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saved conversation'));
    await tester.pumpAndSettle();
    expect(find.text('Restored answer'), findsOneWidget);
    expect(controller.modelPath, 'model');
    await tester.tap(find.text('New chat'));
    await tester.pumpAndSettle();
    expect(find.text('Restored answer'), findsNothing);
    expect(controller.selectedId, isNull);
    await tester.pumpWidget(const SizedBox());
    await controller.close();
    controller.dispose();
  });

  test('persistent completion adopts authoritative history', () async {
    final controller = CoreController(MemoryBackend());
    await controller.send('model', 'Hello');
    expect(controller.messages.map((e) => e.text), ['Hello', 'Reply']);
    expect(controller.selectedId, 'saved');
    expect(controller.history.single.title, 'Saved conversation');
    await controller.close();
    controller.dispose();
  });
}
