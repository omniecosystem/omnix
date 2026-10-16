import 'package:flutter/material.dart';
import 'package:omnix_example/features/core/presentation/widgets/conversation_controls.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';
import 'package:omnix_example/features/home/presentation/widgets/home_chat_panel.dart';
import 'package:omnix_example/features/knowledge/presentation/controllers/knowledge_demo_controller.dart';
import 'home_knowledge_test.dart' show RetrievalBackend;

class PanelBackend implements CoreDemoBackend, GroundedCoreBackend {
  @override
  bool get hasGrounding => false;
  @override
  Stream<String> generate(String model, String prompt) => Stream.value('Blue');
  @override
  Stream<String> generateGrounded(
    String model,
    String question,
    List<KnowledgePassage> sources,
  ) => Stream.value('Wait for blue.');
  @override
  Future<void> stop() async {}
  @override
  Future<void> close() async {}
}

void main() {
  testWidgets('Home opts in to Knowledge and expands saved evidence', (
    tester,
  ) async {
    final knowledge = KnowledgeDemoController(RetrievalBackend())
      ..indexed = true;
    final core = CoreController(PanelBackend(), knowledge: knowledge)
      ..configureModel('model');
    addTearDown(() async {
      await tester.runAsync(core.close);
      core.dispose();
      knowledge.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HomeChatPanel(controller: core)),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationControls(controller: core)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Answer from Knowledge'));
    await tester.pump();
    expect(core.useKnowledge, isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: HomeChatPanel(controller: core)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Message'),
      'How do I reset?',
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Send'));
      while (core.busy) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(find.text('How do I reset?'), findsOneWidget);
    final source = find.text('Router manual');
    await tester.scrollUntilVisible(
      source,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(source);
    await tester.pumpAndSettle();
    expect(
      find.text('Hold reset for ten seconds and wait for blue.'),
      findsOneWidget,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationControls(controller: core)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged,
      isNull,
    );
  });
  testWidgets('grounded evidence preview renders without loading native APIs', (
    tester,
  ) async {
    await tester.pumpWidget(homeKnowledgeEvidencePreview());
    expect(find.text('Router guide'), findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);
  });
}
