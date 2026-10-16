import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_core/model_installation_types.dart';
import 'package:omnix_example/features/core/presentation/controllers/model_library_controller.dart';
import 'package:omnix_example/features/core/presentation/widgets/model_library_panel.dart';
import 'package:omnix_example/features/knowledge/presentation/controllers/knowledge_demo_controller.dart';
import 'package:omnix_example/features/knowledge/presentation/widgets/knowledge_panel_view.dart';
import 'knowledge_demo_controller_test.dart' show Backend;

class EmbeddingLibrary implements ModelLibraryBackend {
  OmnixModelSpec? spec;
  bool? network;
  String? source;
  @override
  Future<List<OmnixInstalledModel>> installed() async => [];
  @override
  Future<String?> pickFile() async => '/picked/embedding.litertlm';
  @override
  Stream<OmnixInstallationProgress> install(
    OmnixModelSpec spec,
    String source, {
    required bool network,
    String? token,
  }) {
    this.spec = spec;
    this.network = network;
    this.source = source;
    return const Stream.empty();
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  for (final network in [true, false]) {
    testWidgets(
      'embedding preset supports ${network ? 'download' : 'import'}',
      (tester) async {
        final backend = EmbeddingLibrary();
        final controller = ModelLibraryController(backend);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ModelLibraryPanel(
                  controller: controller,
                  roleFilter: 'embedding',
                  onUse: (_) {},
                ),
              ),
            ),
          ),
        );
        expect(find.byType(DropdownButton<String>), findsNothing);
        final action = find.text(network ? 'Download' : 'Import file');
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(backend.spec!.role, 'embedding');
        expect(backend.spec!.bytes, 164626432);
        expect(backend.spec!.filename, 'embeddinggemma-2-text-270m.litertlm');
        expect(backend.network, network);
        expect(
          backend.source,
          network
              ? startsWith('https://huggingface.co/')
              : '/picked/embedding.litertlm',
        );
        await tester.pumpWidget(const SizedBox());
        await controller.close();
        controller.dispose();
      },
    );
  }
  testWidgets(
    'Knowledge selects installed embedding without resetting passage',
    (tester) async {
      final models = ModelLibraryController(EmbeddingLibrary())
        ..models = [
          const OmnixInstalledModel(
            spec: OmnixModelSpec(
              filename: 'encoder.litertlm',
              sha256: '',
              bytes: 10,
              role: 'embedding',
            ),
            path: '/installed/encoder.litertlm',
          ),
          const OmnixInstalledModel(
            spec: OmnixModelSpec(
              filename: 'chat.litertlm',
              sha256: '',
              bytes: 20,
              role: 'chat',
            ),
            path: '/installed/chat.litertlm',
          ),
        ];
      final knowledge = KnowledgeDemoController(Backend());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KnowledgePanelView(controller: knowledge, models: models),
          ),
        ),
      );
      await tester.tap(find.text('Import or download embedding model'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Use'));
      await tester.tap(find.text('Use'));
      await tester.pumpAndSettle();
      final encoder = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText ==
                'EmbeddingGemma 2 text model (.litertlm)',
      );
      await tester.scrollUntilVisible(
        encoder,
        -250,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        tester.widget<TextField>(encoder).controller!.text,
        '/installed/encoder.litertlm',
      );
      expect(find.text('chat.litertlm'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      knowledge.dispose();
      models.dispose();
    },
  );
}
