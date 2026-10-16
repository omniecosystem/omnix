import 'dart:async';
import 'dart:convert';

import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

import '../interaction_session_test.dart' as fixtures;

mixin ContextCalls implements OmnixContextTransport {
  final calls = <(bool, bool, int)>[];
  Completer<void>? pending;
  String encoded = 'null';
  @override
  Future<void> configureContext(
    BigInt id,
    bool isAgent,
    bool enabled,
    int safetyMargin,
  ) async {
    calls.add((isAgent, enabled, safetyMargin));
    await pending?.future;
  }

  @override
  Future<String> contextUsage(BigInt id, bool isAgent) async => encoded;
}

class ContextTransport extends fixtures.Transport with ContextCalls {}

class ContextAgentTransport extends fixtures.AgentTransport with ContextCalls {}

Map<String, Object?> diagnostic() => {
  'accounting': 'EstimatedText',
  'capacity': 4096,
  'reserved_output': 1024,
  'estimated_input_tokens': 2300,
  'omitted_turns': 4,
  'retained_messages': 6,
};

void main() {
  group('Context diagnostics', () {
    test('decodes estimates, media uncertainty and absence', () {
      expect(OmnixContextUsage.decode('null'), isNull);
      final decoded = OmnixContextUsage.decode(jsonEncode(diagnostic()))!;
      expect(decoded.accounting, OmnixContextAccounting.estimatedText);
      expect(decoded.omittedTurns, 4);
      expect(decoded.estimatedInputTokens, 2300);
      final media = diagnostic()
        ..['accounting'] = 'UnavailableMedia'
        ..['estimated_input_tokens'] = null;
      expect(
        OmnixContextUsage.decode(jsonEncode(media))!.estimatedInputTokens,
        isNull,
      );
    });
    test('rejects malformed or misleading native diagnostics', () {
      for (final value in [
        [],
        {},
        diagnostic()..['accounting'] = 'Exact',
        diagnostic()..['capacity'] = -1,
        diagnostic()..['estimated_input_tokens'] = null,
        diagnostic()..['accounting'] = 'UnavailableMedia',
      ]) {
        expect(
          () => OmnixContextUsage.decode(jsonEncode(value)),
          throwsFormatException,
        );
      }
    });
  });

  group('Native context policy transport', () {
    test(
      'ordinary sessions forward policy and diagnostics without inference',
      () async {
        final transport = ContextTransport()
          ..encoded = jsonEncode(diagnostic());
        final engine = await OmnixCognitiveEngine.open(
          runtimes: ['litertlm'],
          transport: transport,
        );
        final session = await engine.startSession(modelPath: 'model');
        await session.configureContext(safetyMargin: 64);
        await session.configureContext(enabled: false);
        expect(transport.calls, [(false, true, 64), (false, false, 128)]);
        expect((await session.contextUsage())!.omittedTurns, 4);
        await session.close();
        await engine.close();
        expect(session.configureContext(), throwsStateError);
      },
    );
    test(
      'policy operations serialize against turns and validate before dispatch',
      () async {
        final transport = ContextTransport()..pending = Completer<void>();
        final engine = await OmnixCognitiveEngine.open(
          runtimes: ['litertlm'],
          transport: transport,
        );
        final session = await engine.startSession(modelPath: 'model');
        expect(
          () => session.configureContext(safetyMargin: -1),
          throwsArgumentError,
        );
        expect(transport.calls, isEmpty);
        final operation = session.configureContext();
        await Future<void>.delayed(Duration.zero);
        await expectLater(
          session.sendStream('must wait').toList(),
          throwsStateError,
        );
        transport.pending!.complete();
        await operation;
        await engine.close();
      },
    );
    test(
      'agents use their own native handles and retain optional transport compatibility',
      () async {
        final transport = ContextAgentTransport();
        final engine = await OmnixCognitiveEngine.open(
          runtimes: ['litertlm'],
          transport: transport,
        );
        final agent = await engine.startKnowledgeAgent(modelPath: 'model');
        await agent.configureContext(safetyMargin: 32);
        expect(transport.calls, [(true, true, 32)]);
        expect(await agent.contextUsage(), isNull);
        await engine.close();
        final legacyEngine = await OmnixCognitiveEngine.open(
          runtimes: ['litertlm'],
          transport: fixtures.Transport(),
        );
        final legacy = await legacyEngine.startSession(modelPath: 'model');
        await expectLater(legacy.configureContext(), throwsUnsupportedError);
        await legacyEngine.close();
      },
    );
  });
}
