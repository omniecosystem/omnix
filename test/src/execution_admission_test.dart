import 'dart:convert';
import 'package:omnix/omnix.dart';
import 'package:test/test.dart';
import '../interaction_session_test.dart' as fixtures;

class ExecutionTransport extends fixtures.KnowledgeTransport
    implements OmnixExecutionTransport {
  OmnixExecutionOptions? execution;
  OmnixLocalKnowledge? knowledge;
  int admittedCreates = 0;
  @override
  Future<BigInt> createWithExecution(
    List<String> runtimes,
    String? libraryPath,
    int contextTokens,
    OmnixExecutionOptions execution,
    OmnixLocalKnowledge? knowledge,
  ) async {
    admittedCreates++;
    this.execution = execution;
    this.knowledge = knowledge;
    return BigInt.one;
  }

  @override
  Future<String> executionSnapshot(BigInt engine) async =>
      '{"active":1,"waiting":2}';
}

class RejectedTransport extends fixtures.Transport {
  @override
  Stream<String> stream(BigInt session, String text) async* {
    throw StateError('Core(BackendFailure("execution-queue-full"))');
  }
}

void main() {
  group('Native execution admission', () {
    test(
      'configuration is explicit and rejects ambiguous or excessive limits',
      () {
        expect(jsonDecode(const OmnixExecutionOptions().encode()), {
          'maxActive': 1,
          'maxWaiting': 0,
          'waitMilliseconds': 0,
        });
        for (final options in [
          const OmnixExecutionOptions(maxActive: 0),
          const OmnixExecutionOptions(maxActive: 17),
          const OmnixExecutionOptions(maxWaiting: -1),
          const OmnixExecutionOptions(
            maxWaiting: 257,
            wait: Duration(seconds: 1),
          ),
          const OmnixExecutionOptions(maxWaiting: 1),
          const OmnixExecutionOptions(wait: Duration(seconds: 1)),
          const OmnixExecutionOptions(
            maxWaiting: 1,
            wait: Duration(minutes: 6),
          ),
          const OmnixExecutionOptions(
            maxWaiting: 1,
            wait: Duration(microseconds: 1),
          ),
        ]) {
          expect(options.encode, throwsArgumentError);
        }
      },
    );
    test(
      'Dart passes configuration and Knowledge together without scheduling',
      () async {
        final transport = ExecutionTransport();
        const options = OmnixExecutionOptions(
          maxWaiting: 2,
          wait: Duration(seconds: 2),
        );
        const knowledge = OmnixLocalKnowledge(
          embeddingModel: 'encoder',
          storePath: 'index',
        );
        final engine = await OmnixCognitiveEngine.open(
          runtimes: ['litertlm'],
          transport: transport,
          execution: options,
          knowledge: knowledge,
        );
        expect(transport.admittedCreates, 1);
        expect(transport.execution, same(options));
        expect(transport.knowledge, same(knowledge));
        final snapshot = await engine.executionSnapshot();
        expect(snapshot.active, 1);
        expect(snapshot.waiting, 2);
        await engine.close();
        await expectLater(engine.executionSnapshot(), throwsStateError);
      },
    );
    test(
      'old transports work by default and reject explicit admission support',
      () async {
        final transport = fixtures.Transport();
        final engine = await OmnixCognitiveEngine.open(
          runtimes: ['litertlm'],
          transport: transport,
        );
        await expectLater(engine.executionSnapshot(), throwsUnsupportedError);
        await engine.close();
        await expectLater(
          OmnixCognitiveEngine.open(
            runtimes: ['litertlm'],
            transport: transport,
            execution: const OmnixExecutionOptions(),
          ),
          throwsUnsupportedError,
        );
      },
    );
    test('diagnostics reject invented or malformed counters', () {
      for (final raw in [
        'null',
        '{}',
        '{"active":-1,"waiting":0}',
        '{"active":0,"waiting":1.5}',
      ]) {
        expect(() => OmnixExecutionSnapshot.decode(raw), throwsFormatException);
      }
    });
    test('only explicit native codes become typed failures', () {
      expect(
        OmnixExecutionException.fromNative('execution-busy')!.failure,
        OmnixExecutionFailure.busy,
      );
      expect(
        OmnixExecutionException.fromNative(
          'Core(BackendFailure("execution-admission-timeout"))',
        )!.failure,
        OmnixExecutionFailure.timedOut,
      );
      expect(OmnixExecutionException.fromNative('Session busy'), isNull);
      expect(
        OmnixExecutionException.fromNative('execution-busy-unknown'),
        isNull,
      );
    });
    test(
      'admission rejection is surfaced without retrying or saving a response',
      () async {
        final transport = RejectedTransport();
        final engine = await OmnixCognitiveEngine.open(
          runtimes: ['litertlm'],
          transport: transport,
        );
        final session = await engine.startSession(modelPath: 'model');
        await expectLater(
          session.send('hello'),
          throwsA(
            isA<OmnixExecutionException>().having(
              (e) => e.failure,
              'failure',
              OmnixExecutionFailure.queueFull,
            ),
          ),
        );
        expect(transport.sessionCloses, 1);
        await engine.close();
      },
    );
  });
}
