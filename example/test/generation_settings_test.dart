import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_core/omnix_core.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/home/data/services/agent_chat_snapshot.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';
import 'package:omnix_example/features/core/presentation/pages/core_screen.dart';

class Backend implements ResponseBudgetBackend, GenerationSettingsBackend {
  @override
  int maxOutputTokens = 1024;
  @override
  int contextTokens = 4096;
  @override
  OmnixCoreSamplingOptions? sampling;
  @override
  void configureResponseBudget(int tokens) => maxOutputTokens = tokens;
  @override
  void configureGeneration(OmnixCoreSamplingOptions? options, int context) {
    options?.encode();
    sampling = options;
    contextTokens = context;
  }

  @override
  Stream<String> generate(String model, String prompt) => const Stream.empty();
  @override
  Future<void> stop() async {}
  @override
  Future<void> close() async {}
}

void main() {
  test('saved agent configuration keeps native sampler and context', () {
    final snapshot = AgentChatSnapshot(
      id: 'sampled',
      title: 'Sampled',
      model: 'model.litertlm',
      instructions: '',
      email: false,
      autonomy: OmnixAutonomyMode.scopedAssistance,
      checkpoint: 'opaque',
      maxOutputTokens: 1024,
      contextTokens: 8192,
      sampling: const OmnixCoreSamplingOptions(seed: 42),
      entries: const [ChatEntry('user', 'Hi'), ChatEntry('assistant', 'Hello')],
    );
    final restored = AgentChatSnapshot.decode(snapshot.encode());
    expect(restored.contextTokens, 8192);
    expect(restored.sampling!.seed, 42);
    final legacy = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
    (legacy['record'] as Map).remove('sampling');
    (legacy['record'] as Map).remove('contextTokens');
    final old = AgentChatSnapshot.decode(jsonEncode(legacy));
    expect(old.contextTokens, 4096);
    expect(old.sampling, isNull);
  });
  test('sampling metadata round trips without changing seed or filters', () {
    const original = OmnixCoreSamplingOptions(
      temperature: 0.5,
      topK: 50,
      topP: 0.8,
      seed: 42,
    );
    final restored = OmnixCoreSamplingOptions.fromJson(
      jsonDecode(original.encode()) as Map<String, dynamic>,
    );
    expect(restored.encode(), original.encode());
  });
  testWidgets('Core screen enables native sampling and updates temperature', (
    tester,
  ) async {
    final backend = Backend();
    final controller = CoreController(backend);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CoreScreen(controller: controller)),
      ),
    );
    final toggle = find.text('Custom sampling');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(backend.sampling, isNotNull);
    final finder = find.byKey(const Key('core-temperature'));
    await tester.ensureVisible(finder);
    tester.widget<Slider>(finder).onChanged!(0.3);
    await tester.pump();
    expect(backend.sampling!.temperature, 0.3);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
