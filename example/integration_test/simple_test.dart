import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix/omnix.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('initializes the native Omnix engine', () async {
    final engine = Omnix.createEngine();
    final statesFuture = engine.events
        .map((event) => event.state)
        .take(2)
        .toList();

    final info = await engine.initialize();
    final states = await statesFuture;

    expect(info.engineName, 'Omnix');
    expect(info.apiVersion, 1);
    expect(engine.state, OmnixEngineState.ready);
    expect(states, [OmnixEngineState.initializing, OmnixEngineState.ready]);

    await engine.close();
  });

  test('owns a conversation from open through runtime close', () async {
    final backend = _IntegrationInferenceBackend();
    final runtime = Omnix.createRuntime(inferenceBackend: backend);

    final info = await runtime.initialize();
    final conversation = await runtime.openConversation(
      const OmnixConversationConfiguration(
        modelTemplate: OmnixModelTemplate.general,
      ),
    );
    final events = await conversation.send('integration').toList();

    expect(info.engineName, 'Omnix');
    expect(events, hasLength(1));
    expect(events.single, isA<OmnixTextDelta>());
    expect((events.single as OmnixTextDelta).text, 'integration');

    await conversation.stop();
    await runtime.close();

    expect(backend.conversation.stopCalls, 1);
    expect(backend.conversation.closeCalls, 1);
  });
}

final class _IntegrationInferenceBackend implements OmnixInferenceBackend {
  final _IntegrationConversation conversation = _IntegrationConversation();

  @override
  Future<OmnixConversation> openConversation(
    OmnixConversationConfiguration configuration,
  ) async => conversation;
}

final class _IntegrationConversation implements OmnixConversation {
  int stopCalls = 0;
  int closeCalls = 0;

  @override
  Stream<OmnixConversationEvent> send(String prompt) async* {
    yield OmnixTextDelta(prompt);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> close() async {
    closeCalls++;
  }
}
