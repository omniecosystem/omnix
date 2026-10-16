import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_example/app/showcase_shell.dart';
import 'package:omnix_example/features/core/presentation/pages/core_screen.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';

class _Backend implements CoreDemoBackend {
  @override
  Stream<String> generate(String model, String prompt) => const Stream.empty();
  @override
  Future<void> stop() async {}
  @override
  Future<void> close() async {}
}

void setSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget shell({List<WidgetBuilder>? pages}) => MaterialApp(
  home: ShowcaseShell(
    home: const TextField(decoration: InputDecoration(labelText: 'Home draft')),
    history: const Center(child: Text('Saved chats')),
    pages:
        pages ??
        List.generate(
          4,
          (i) =>
              (_) => Text('Feature $i'),
        ),
  ),
);

void main() {
  testWidgets('Workflow opens as a feature without replacing Home', (
    tester,
  ) async {
    setSize(tester, const Size(1366, 768));
    await tester.pumpWidget(
      shell(
        pages: List.generate(
          5,
          (i) =>
              (_) => Text('Feature $i'),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Keep the conversation');
    await tester.tap(find.text('Workflow'));
    await tester.pumpAndSettle();
    expect(find.text('Feature 4'), findsOneWidget);
    await tester.tap(find.byTooltip('Close feature'));
    await tester.pumpAndSettle();
    expect(find.text('Keep the conversation'), findsOneWidget);
  });
  testWidgets(
    'wide landscape opens panels automatically without bottom navigation',
    (tester) async {
      setSize(tester, const Size(1366, 768));
      final opened = <int>[];
      await tester.pumpWidget(
        shell(
          pages: List.generate(
            4,
            (i) => (_) {
              opened.add(i);
              return Text('Feature $i');
            },
          ),
        ),
      );
      expect(find.text('Saved chats'), findsOneWidget);
      expect(find.text('Features'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(opened, isEmpty);
      await tester.enterText(find.byType(TextField), 'Keep my draft');
      await tester.tap(find.text('Knowledge'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Feature 1'), findsOneWidget);
      expect(opened.every((i) => i == 1), isTrue);
      await tester.tap(find.byTooltip('Close feature'));
      await tester.pumpAndSettle();
      expect(find.text('Feature 1'), findsNothing);
      expect(find.text('Keep my draft'), findsOneWidget);
      await tester.tap(find.byTooltip('Chat history'));
      await tester.pumpAndSettle();
      expect(find.text('Saved chats'), findsNothing);
      expect(find.text('Keep my draft'), findsOneWidget);
    },
  );

  testWidgets('compact home opens drawers and feature sheets', (tester) async {
    setSize(tester, const Size(390, 844));
    await tester.pumpWidget(shell());
    expect(find.text('Saved chats'), findsNothing);
    expect(find.text('Features'), findsNothing);
    await tester.tap(find.byTooltip('Chat history'));
    await tester.pumpAndSettle();
    expect(find.text('Saved chats'), findsOneWidget);
    Navigator.of(tester.element(find.text('Saved chats'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Feature menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Storage'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Feature 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Close feature'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'resize preserves draft and docks panels when space becomes available',
    (tester) async {
      setSize(tester, const Size(800, 1200));
      await tester.pumpWidget(shell());
      expect(find.text('Saved chats'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Draft after resize');
      tester.view.physicalSize = const Size(1366, 768);
      await tester.pumpAndSettle();
      expect(find.text('Saved chats'), findsOneWidget);
      expect(find.text('Features'), findsOneWidget);
      expect(find.text('Draft after resize'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Core is a configuration sheet, not the home conversation', (
    tester,
  ) async {
    setSize(tester, const Size(1366, 768));
    final controller = CoreController(_Backend());
    await tester.pumpWidget(
      shell(
        pages: [
          (_) => CoreScreen(controller: controller),
          for (var i = 0; i < 3; i++) (_) => const SizedBox(),
        ],
      ),
    );
    expect(find.text('Trusted local model path'), findsNothing);
    await tester.tap(find.text('Core'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Trusted local model path'),
      'local.gguf',
    );
    await tester.tap(find.text('Use this model'));
    await tester.pumpAndSettle();
    expect(controller.modelPath, 'local.gguf');
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Trusted local model path'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await controller.close();
    controller.dispose();
  });
}
