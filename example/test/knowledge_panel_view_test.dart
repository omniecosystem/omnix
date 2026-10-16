import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_example/features/knowledge/presentation/controllers/knowledge_demo_controller.dart';
import 'package:omnix_example/features/knowledge/presentation/widgets/knowledge_panel_view.dart';
import 'knowledge_demo_controller_test.dart' show Backend;
import 'package:omnix_example/features/knowledge/data/services/text_document_import.dart';

void main() {
  testWidgets('successful indexing hands Knowledge to Home once', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = KnowledgeDemoController(Backend());
    var handoffs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KnowledgePanelView(
            controller: controller,
            onIndexed: () async {
              handoffs++;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Index and make available to Home'));
    await tester.pumpAndSettle();
    expect(handoffs, 1);
    expect(find.text('Retrieve and answer'), findsNothing);
    expect(controller.indexed, isFalse);
    expect(controller.error, isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  testWidgets(
    'import fills an editable review without indexing automatically',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final backend = Backend();
      final controller = KnowledgeDemoController(backend);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KnowledgePanelView(
              controller: controller,
              pickText: () async => const ImportedKnowledgeText(
                'guide.txt',
                'Imported router guide.',
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Import text document'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'guide.txt'), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Imported router guide.'),
        findsOneWidget,
      );
      expect(backend.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  testWidgets(
    'EmbeddingGemma 2 is the default and needs no separate tokenizer',
    (tester) async {
      final controller = KnowledgeDemoController(Backend());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KnowledgePanelView(
              controller: controller,
              initialEncoderPath: 'embeddinggemma-2-text-270m.litertlm',
            ),
          ),
        ),
      );
      expect(
        find.text('EmbeddingGemma 2 text model (.litertlm)'),
        findsOneWidget,
      );
      expect(find.text('SentencePiece tokenizer (.model)'), findsNothing);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(find.text('SentencePiece tokenizer (.model)'), findsOneWidget);
      expect(find.text('embeddinggemma-2-text-270m.litertlm'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
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
