import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_core/omnix_core.dart';
import 'package:omnix_storage/omnix_storage.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';
import 'package:omnix_example/features/core/presentation/widgets/live_generation_panel.dart';
import 'package:omnix_example/features/home/data/repositories/chat_repository.dart';
import 'chat_instructions_test.dart'
    show InstructionTransport, InstructionStore;
import 'generation_settings_test.dart' show Backend;

class LiveBackend extends Backend implements LiveGenerationBackend {
  int calls = 0;
  @override
  bool get canReconfigureLive => true;
  @override
  Future<void> applyGeneration(
    int tokens,
    OmnixCoreSamplingOptions? options,
  ) async {
    calls++;
    maxOutputTokens = tokens;
    sampling = options;
  }
}

class LiveTransport extends InstructionTransport
    implements OmnixCoreReconfigurationTransport {
  int? updated;
  final updates = <int>[];
  @override
  Future<void> reconfigureConversation(
    BigInt id,
    int tokens,
    String? json,
  ) async {
    updated = tokens;
    updates.add(tokens);
  }
}

class FailingStore extends InstructionStore {
  bool failWrites = false;
  @override
  Future<String> request(BigInt id, String operation, String payload) async {
    if (operation == 'write' && failWrites) {
      throw StateError('Disk write failed');
    }
    return super.request(id, operation, payload);
  }
}

void main() {
  test(
    'failed save rolls native configuration back and retains old metadata',
    () async {
      final transport = LiveTransport();
      final storage = FailingStore();
      final store = OmnixConversationSnapshotStore(
        path: 'unused',
        transport: storage,
      );
      final repository = NativeChatRepository(
        store,
        core: OmnixCore(transport: transport),
      );
      await repository.generate('model', 'Hello').toList();
      final previous = storage.snapshot;
      storage.failWrites = true;
      await expectLater(
        repository.applyGeneration(512, null),
        throwsStateError,
      );
      expect(transport.updates, [512, 1024]);
      expect(repository.maxOutputTokens, 1024);
      expect(storage.snapshot, previous);
      await repository.close();
      await store.close();
    },
  );
  testWidgets(
    'sliders stage edits and Apply forwards once without clearing chat',
    (tester) async {
      final backend = LiveBackend();
      final controller = CoreController(backend)
        ..messages.add(const ChatEntry('assistant', 'Previous answer'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (_, _) => LiveGenerationPanel(controller: controller),
            ),
          ),
        ),
      );
      tester
          .widget<Slider>(find.byKey(const Key('live-output-tokens')))
          .onChanged!(512);
      await tester.pump();
      expect(backend.calls, 0);
      await tester.tap(find.byKey(const Key('apply-live-settings')));
      await tester.pumpAndSettle();
      expect(backend.calls, 1);
      expect(backend.maxOutputTokens, 512);
      expect(controller.messages.single.text, 'Previous answer');
      controller.busy = true;
      controller.notifyListeners();
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('apply-live-settings')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
  test(
    'live ordinary settings persist without replacing saved history',
    () async {
      final transport = LiveTransport();
      final storage = InstructionStore();
      final store = OmnixConversationSnapshotStore(
        path: 'unused',
        transport: storage,
      );
      final repository = NativeChatRepository(
        store,
        core: OmnixCore(transport: transport),
      );
      await repository.generate('model', 'Hello').toList();
      final previous = jsonDecode(storage.snapshot!)['messages'];
      await repository.applyGeneration(
        512,
        const OmnixCoreSamplingOptions(seed: 42),
      );
      expect(transport.updated, 512);
      final saved = jsonDecode(storage.snapshot!);
      expect(saved['record']['maxOutputTokens'], 512);
      expect(saved['record']['sampling']['seed'], 42);
      expect(saved['messages'], previous);
      await repository.close();
      await store.close();
    },
  );
}
