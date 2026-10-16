import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

import '../interaction_media_test.dart' show MediaTransport;
import '../interaction_session_test.dart' show Transport;

class ThinkingTransport extends MediaTransport
    implements
        OmnixThinkingSessionTransport,
        OmnixOutputSessionTransport,
        OmnixThinkingConfigurationTransport,
        OmnixThinkingRestorationTransport {
  final changes = <bool>[];
  bool? restoreSetting;
  @override
  Future<void> setSessionThinking(BigInt id, bool enabled) async {
    changes.add(enabled);
  }

  @override
  Future<void> setAgentThinking(BigInt id, bool enabled) async {
    changes.add(enabled);
  }

  @override
  Future<void> restoreSessionThinking(
    BigInt id,
    String history,
    bool enabled,
  ) async {
    restored = history;
    restoreSetting = enabled;
  }

  @override
  Future<String> restoreAgentThinking(
    BigInt id,
    String checkpoint,
    bool enabled,
  ) async {
    restored = checkpoint;
    restoreSetting = enabled;
    return '';
  }

  String? sampler;
  bool thinkingOpened = false;
  @override
  Future<BigInt> openThinkingSession(
    BigInt engine,
    String path,
    String? instructions,
    int tokens,
    bool images,
    bool audio,
    String? samplingJson,
  ) async {
    thinkingOpened = true;
    sampler = samplingJson;
    this.images = images;
    this.audio = audio;
    return BigInt.two;
  }

  @override
  Future<BigInt> openThinkingAgent(
    BigInt engine,
    String path,
    String? instructions,
    int tokens,
    OmnixAgentExtensions extensions,
    String? samplingJson,
  ) async => throw UnimplementedError();
  @override
  Stream<OmnixOutputDelta> messageEvents(
    BigInt session,
    List<OmnixInteractionInput> parts,
    OmnixKnowledgeUse knowledge,
  ) async* {
    yield const OmnixOutputDelta(OmnixOutputKind.reasoning, 'native reasoning');
    yield const OmnixOutputDelta(OmnixOutputKind.text, 'answer');
  }
}

void main() {
  group('native reasoning boundary', () {
    test(
      'live settings and explicit restore stay native without reopening or rewriting history',
      () async {
        final transport = ThinkingTransport();
        final engine = await OmnixCognitiveEngine.open(
          runtimes: ['litertlm'],
          transport: transport,
        );
        addTearDown(engine.close);
        final session = await engine.startSession(modelPath: 'model');
        addTearDown(session.close);
        await session.setThinking(true);
        await session.restoreHistory(
          'opaque native checkpoint',
          thinking: false,
        );
        expect(transport.changes, [true]);
        expect(transport.restored, 'opaque native checkpoint');
        expect(transport.restoreSetting, isFalse);
        expect(transport.sessionCloses, 0);
      },
    );
    test(
      'thinking reaches transport without implicitly changing the sampler',
      () async {
        final transport = ThinkingTransport();
        final engine = await OmnixCognitiveEngine.open(
          runtimes: ['litertlm'],
          transport: transport,
        );
        addTearDown(engine.close);
        final session = await engine.startSession(
          modelPath: 'model',
          thinking: true,
          enableAudio: true,
        );
        addTearDown(session.close);
        expect(transport.thinkingOpened, isTrue);
        expect(transport.sampler, isNull);
        expect(transport.audio, isTrue);
        final events = await session.sendMessageEvents([
          OmnixInteractionInput.text('question'),
        ]).toList();
        expect(events.map((e) => e.kind), [
          OmnixOutputKind.reasoning,
          OmnixOutputKind.text,
        ]);
        expect(
          await session.sendMessageStream([
            OmnixInteractionInput.text('next'),
          ]).join(),
          'answer',
        );
      },
    );
    test('unsupported configuration is never silently ignored', () async {
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: Transport(),
      );
      addTearDown(engine.close);
      await expectLater(
        engine.startSession(modelPath: 'model', thinking: true),
        throwsUnsupportedError,
      );
    });
    test('legacy media transport still supplies typed visible text', () async {
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: MediaTransport(),
      );
      addTearDown(engine.close);
      final session = await engine.startSession(modelPath: 'model');
      addTearDown(session.close);
      final events = await session.sendMessageEvents([
        OmnixInteractionInput.text('question'),
      ]).toList();
      expect(events.single.kind, OmnixOutputKind.text);
      expect(events.single.text, 'image answer');
    });
    test(
      'event parsers preserve canonical channels and reject malformed metadata',
      () {
        expect(
          OmnixOutputDelta.fromJson({
            'kind': 'reasoning',
            'text': 'thought',
          }).kind,
          OmnixOutputKind.reasoning,
        );
        expect(
          OmnixAgentEvent.fromJson({
            'kind': 'reasoning',
            'text': 'thought',
          }).kind,
          OmnixAgentEventKind.reasoning,
        );
        for (final value in [
          <String, dynamic>{'kind': 'reasoning'},
          <String, dynamic>{'kind': 'reasoning', 'text': 17},
          <String, dynamic>{'kind': 'channels', 'text': 'thought'},
        ]) {
          expect(() => OmnixOutputDelta.fromJson(value), throwsFormatException);
        }
        expect(
          () => OmnixAgentEvent.fromJson({'kind': 'reasoning'}),
          throwsFormatException,
        );
        expect(
          OmnixOutputDelta.fromJson({
            'kind': 'text',
            'text': '<think>literal</think>',
          }).kind,
          OmnixOutputKind.text,
        );
      },
    );
  });
}
