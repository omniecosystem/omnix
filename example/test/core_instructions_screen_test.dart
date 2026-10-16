import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';
import 'package:omnix_example/features/core/presentation/pages/core_screen.dart';

class InstructionBackend
    implements InstructionCoreBackend, ResponseBudgetBackend {
  @override
  int maxOutputTokens = 1024;
  @override
  void configureResponseBudget(int tokens) => maxOutputTokens = tokens;
  @override
  String instructions = '';
  @override
  void configureInstructions(String value) => instructions = value.trim();
  @override
  Stream<String> generate(String model, String prompt) => const Stream.empty();
  @override
  Future<void> stop() async {}
  @override
  Future<void> close() async {}
}

void main() {
  testWidgets('Core changes response length in-app and locks existing chats', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final backend = InstructionBackend();
    final core = CoreController(backend);
    addTearDown(core.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CoreScreen(controller: core)),
      ),
    );
    await tester.ensureVisible(find.text('2048'));
    await tester.tap(find.text('2048'));
    await tester.pump();
    expect(backend.maxOutputTokens, 2048);
    expect(find.text('2048 output tokens'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await core.send('model', 'Hello');
    await tester.pump();
    expect(
      tester
          .widget<Slider>(find.byKey(const Key('core-response-budget')))
          .onChanged,
      isNull,
    );
    core.configureResponseBudget(4096);
    expect(backend.maxOutputTokens, 2048);
  });
  testWidgets('Core commits instructions before a chat and locks live edits', (
    tester,
  ) async {
    final backend = InstructionBackend();
    final core = CoreController(backend)..configureModel('model');
    addTearDown(core.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CoreScreen(controller: core)),
      ),
    );
    final field = find.widgetWithText(TextField, 'Instructions for this chat');
    final scrollable = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.enterText(field, 'Reply in French.');
    await tester.scrollUntilVisible(
      find.text('Use this model'),
      200,
      scrollable: scrollable,
    );
    await tester.tap(find.text('Use this model'));
    await tester.pumpAndSettle();
    expect(core.instructions, 'Reply in French.');
    expect(backend.instructions, 'Reply in French.');
    await core.send('model', 'Hello');
    await tester.pump();
    await tester.scrollUntilVisible(field, -200, scrollable: scrollable);
    expect(tester.widget<TextField>(field).enabled, isFalse);
    await tester.scrollUntilVisible(
      find.text('Use this model'),
      200,
      scrollable: scrollable,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Use this model'),
          )
          .onPressed,
      isNull,
    );
  });
}
