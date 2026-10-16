import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_knowledge_example/knowledge_demo_controller.dart';
import 'package:omnix_knowledge_example/knowledge_panel_view.dart';
import 'knowledge_demo_controller_test.dart' show Backend;

void main() {
  testWidgets('prefills editable model paths and the paired profile', (
    tester,
  ) async {
    final controller = KnowledgeDemoController(Backend());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KnowledgePanelView(
            controller: controller,
            initialEncoderPath: 'encoder.tflite',
            initialTokenizerPath: 'tokenizer.model',
            initialGenerationPath: 'generation.litertlm',
            initialLegacyGecko: true,
          ),
        ),
      ),
    );
    expect(find.text('encoder.tflite'), findsOneWidget);
    expect(find.text('tokenizer.model'), findsOneWidget);
    final generation = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText ==
              'Generation model (.gguf or .litertlm)',
    );
    final scrollable = find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(generation, 300, scrollable: scrollable);
    expect(
      tester.widget<TextField>(generation).controller!.text,
      'generation.litertlm',
    );
    await tester.enterText(generation, 'another.gguf');
    expect(
      tester.widget<TextField>(generation).controller!.text,
      'another.gguf',
    );
    await tester.scrollUntilVisible(
      find.byType(SwitchListTile),
      -300,
      scrollable: scrollable,
    );
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets('reopen and answer show independent source and answer cards', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = KnowledgeDemoController(Backend());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: KnowledgePanelView(controller: controller)),
      ),
    );
    await tester.tap(find.text('Index and reopen'));
    await tester.pumpAndSettle();
    expect(find.text('Index reopened — ready to query'), findsOneWidget);
    await tester.tap(find.text('Retrieve and answer'));
    await tester.pumpAndSettle();
    expect(find.text('Generated answer'), findsOneWidget);
    expect(find.textContaining('Guide · similarity'), findsOneWidget);
    expect(find.text('Press reset.'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
