import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_core/omnix_core.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';
import 'package:omnix_example/features/core/domain/structured_draft.dart';
import 'package:omnix_example/features/core/presentation/widgets/structured_draft_panel.dart';

class PanelBackend extends PreviewDraftBackend {
  int drafts = 0;
  bool closed = false;
  Completer<StructuredNote>? pending;
  @override
  Future<StructuredNote> draft(String model, String instruction) async {
    drafts++;
    return pending == null
        ? StructuredNote('Transport', instruction)
        : pending!.future;
  }

  @override
  Future<String> transcribe(String model, OmnixInputPart audio) async =>
      'une dette en 2 jours';
  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  testWidgets('voice becomes an editable request, not an automatic action', (
    tester,
  ) async {
    final backend = PanelBackend();
    final core = CoreController(PreviewDraftCore())..configureModel('model');
    addTearDown(core.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StructuredDraftPanel(
            core: core,
            backend: backend,
            chooseAudio: () async =>
                ChatAttachment('voice.wav', OmnixInputPart.audio(Uint8List(1))),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Transcribe WAV'));
    await tester.pumpAndSettle();
    expect(find.text('une dette en 2 jours'), findsOneWidget);
    expect(backend.drafts, 0);
    await tester.enterText(
      find.byType(TextField).first,
      'Transport en 2 jours',
    );
    await tester.tap(find.text('Generate note'));
    await tester.pumpAndSettle();
    expect(backend.drafts, 1);
    await tester.scrollUntilVisible(
      find.text('Review your note'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Review your note'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(backend.closed, isTrue);
  });
  testWidgets('dismissal during generation does not update disposed widgets', (
    tester,
  ) async {
    final backend = PanelBackend()..pending = Completer<StructuredNote>();
    final core = CoreController(PreviewDraftCore())..configureModel('model');
    addTearDown(core.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StructuredDraftPanel(core: core, backend: backend),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'a note');
    await tester.tap(find.text('Generate note'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    backend.pending!.complete(const StructuredNote('Late', 'Late reply'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(backend.closed, isTrue);
  });
}
