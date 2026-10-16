// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'package:omnix/omnix.dart';
import 'package:test/test.dart';
import 'dart:async';

class Transport implements OmnixSessionTransport {
  int engineCloses = 0;
  int sessionCloses = 0;
  int cancels = 0;
  String? instructions;
  String? restored;
  bool fail = false;
  @override
  Future<BigInt> create(
    List<String> runtimes,
    String? libraryPath,
    int contextTokens,
  ) async => BigInt.one;
  @override
  Future<BigInt> open(
    BigInt engine,
    String modelPath,
    String? instructions,
    int outputTokens,
  ) async {
    this.instructions = instructions;
    return BigInt.two;
  }

  @override
  Stream<String> stream(BigInt session, String text) async* {
    if (fail) throw StateError('native failure');
    yield 'hello ';
    yield 'world';
  }

  @override
  Future<String> history(BigInt session) async => '{"version":1,"messages":[]}';
  @override
  Future<void> restore(BigInt session, String history) async {
    restored = history;
  }

  @override
  void cancel(BigInt session) {
    cancels++;
  }

  @override
  Future<void> closeSession(BigInt session) async {
    sessionCloses++;
  }

  @override
  Future<void> closeEngine(BigInt engine) async {
    engineCloses++;
  }
}

class KnowledgeTransport extends Transport
    implements OmnixKnowledgeSessionTransport {
  OmnixLocalKnowledge? configuration;
  OmnixKnowledgeUse? policy;
  @override
  Future<BigInt> createWithKnowledge(
    List<String> runtimes,
    String? libraryPath,
    int contextTokens,
    OmnixLocalKnowledge knowledge,
  ) async {
    configuration = knowledge;
    return BigInt.one;
  }

  @override
  Stream<String> groundedStream(
    BigInt session,
    String text,
    OmnixKnowledgeUse knowledge,
  ) async* {
    policy = knowledge;
    yield* stream(session, text);
  }

  @override
  Future<List<OmnixInteractionSource>> sources(BigInt session) async =>
      policy == OmnixKnowledgeUse.disabled
      ? []
      : [
          const OmnixInteractionSource(
            title: 'Manual',
            content: 'Reset for ten seconds.',
          ),
        ];
}

class AgentTransport extends Transport implements OmnixAgentTransport {
  final response = Completer<OmnixAgentReply>();
  int closes = 0;
  @override
  Future<BigInt> openAgent(
    BigInt engine,
    String model,
    String? prompt,
    int tokens,
  ) async => BigInt.two;
  @override
  Future<OmnixAgentReply> runAgent(BigInt id, String text) => response.future;
  @override
  void cancelAgent(BigInt id) {
    cancels++;
  }

  @override
  Future<void> closeAgent(BigInt id) async {
    closes++;
  }
}

class CheckpointTransport extends AgentTransport
    implements OmnixAgentCheckpointTransport {
  String? restoredCheckpoint;
  Completer<String>? pendingCheckpoint;
  @override
  Future<String> agentCheckpoint(BigInt id, String? checkpoint) async {
    restoredCheckpoint = checkpoint;
    return pendingCheckpoint == null
        ? 'opaque native context'
        : pendingCheckpoint!.future;
  }
}

class StreamingAgentTransport extends AgentTransport
    implements OmnixAgentStreamingTransport {
  List<OmnixAgentEvent> events = [];
  @override
  Stream<OmnixAgentEvent> streamAgent(BigInt id, String text) =>
      Stream.fromIterable(events);
}

class EmailAgentTransport extends AgentTransport
    implements OmnixEmailIntentTransport {
  int emailOpens = 0;
  @override
  Future<BigInt> openAgentWithEmailDrafts(
    BigInt engine,
    String model,
    String? prompt,
    int tokens,
  ) async {
    emailOpens++;
    return BigInt.from(3);
  }
}

class RegisteredTransport extends AgentTransport
    implements OmnixRegisteredAgentTransport {
  OmnixAgentExtensions? registration;
  @override
  Future<BigInt> openRegisteredAgent(
    BigInt engine,
    String model,
    String? prompt,
    int tokens,
    OmnixAgentExtensions extensions,
  ) async {
    registration = extensions;
    return BigInt.from(4);
  }
}

class WorkflowTransport implements OmnixWorkflowTransport {
  BigInt? engine;
  int opens = 0;
  int closes = 0;
  @override
  Future<BigInt> open(
    String path,
    String definition,
    String registration,
    BigInt? engine,
    Future<String> Function(String) execute,
  ) async {
    this.engine = engine;
    opens++;
    return BigInt.two;
  }

  @override
  Future<void> close(BigInt id) async {
    closes++;
  }

  @override
  void cancel(BigInt id) {}
  @override
  Future<String> progress(BigInt id) async =>
      '{"version":1,"id":"job","cancelled":false,"steps":[]}';
  @override
  Future<String> recover(BigInt id) => progress(id);
  @override
  Future<String> runNext(BigInt id) => progress(id);
  @override
  Future<String> runUntilBlocked(BigInt id) => progress(id);
  @override
  Future<String> reconcile(
    BigInt id,
    String step,
    bool succeeded,
    String evidence,
  ) => progress(id);
}

void main() {
  test(
    'agent checkpoint forwards opaque context without running a turn',
    () async {
      final transport = CheckpointTransport();
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: transport,
      );
      final agent = await engine.startKnowledgeAgent(modelPath: 'model');
      expect(await agent.exportCheckpoint(), 'opaque native context');
      await agent.restoreCheckpoint('saved context');
      expect(transport.restoredCheckpoint, 'saved context');
      expect(transport.response.isCompleted, isFalse);
      expect(transport.cancels, 0);
      await agent.close();
      await expectLater(agent.exportCheckpoint(), throwsStateError);
      await engine.close();
    },
  );
  test(
    'agent checkpoint owns the session until its native operation finishes',
    () async {
      final transport = CheckpointTransport()
        ..pendingCheckpoint = Completer<String>();
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: transport,
      );
      final agent = await engine.startKnowledgeAgent(modelPath: 'model');
      final pending = agent.exportCheckpoint();
      await expectLater(agent.exportCheckpoint(), throwsStateError);
      await expectLater(
        agent.send('do not run while saving'),
        throwsStateError,
      );
      transport.pendingCheckpoint!.complete('saved');
      expect(await pending, 'saved');
      await agent.close();
      await engine.close();
    },
  );
  test(
    'agent checkpoint capability is optional, never a text replay fallback',
    () async {
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: AgentTransport(),
      );
      final agent = await engine.startKnowledgeAgent(modelPath: 'model');
      await expectLater(agent.exportCheckpoint(), throwsUnsupportedError);
      await agent.close();
      await engine.close();
    },
  );
  test(
    'facade opens Workflow against its own engine and rejects opens after close',
    () async {
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: Transport(),
      );
      final transport = WorkflowTransport();
      final definition = OmnixWorkflowDefinition(
        id: 'job',
        steps: [
          OmnixWorkflowStep(
            id: 'one',
            tool: 'host_test',
            arguments: {},
            retry: OmnixRetrySafety.safeToRepeat,
          ),
        ],
      );
      final extensions = OmnixAgentExtensions(grants: []);
      final job = await engine.startWorkflow(
        databasePath: 'host-private-path',
        definition: definition,
        extensions: extensions,
        workflowTransport: transport,
      );
      expect(transport.engine, BigInt.one);
      expect(transport.opens, 1);
      await job.close();
      await job.close();
      expect(transport.closes, 1);
      await engine.close();
      await expectLater(
        engine.startWorkflow(
          databasePath: 'host-private-path',
          definition: definition,
          extensions: extensions,
          workflowTransport: transport,
        ),
        throwsStateError,
      );
      expect(transport.opens, 1);
    },
  );
  test('typed host outcomes roundtrip independently from model prose', () {
    final reply = OmnixAgentReply.fromJson({
      'text': 'Event prepared',
      'toolCalls': 1,
      'sources': [],
      'toolOutcomes': [
        {
          'callId': '1',
          'toolName': 'calendar',
          'status': 'failed',
          'reason': 'No host handoff',
        },
      ],
    });
    expect(reply.toolOutcomes.single.status, 'failed');
    expect(
      OmnixAgentReply.fromJson(reply.toJson()).toolOutcomes.single.reason,
      'No host handoff',
    );
    final event = OmnixAgentEvent.fromJson({
      'kind': 'toolFinished',
      'toolName': 'calendar',
      'outcome': reply.toolOutcomes.single.toJson(),
    });
    expect(event.outcome!.callId, '1');
    expect(() => reply.toolOutcomes.clear(), throwsUnsupportedError);
  });
  test(
    'registered agents forward host bindings without requiring Knowledge',
    () async {
      final registration = OmnixAgentExtensions(grants: ['clock']);
      final transport = RegisteredTransport();
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: transport,
      );
      addTearDown(engine.close);
      final agent = await engine.startAgent(
        modelPath: 'model',
        extensions: registration,
      );
      expect(identical(transport.registration, registration), isTrue);
      await agent.close();
      final unsupported = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: AgentTransport(),
      );
      addTearDown(unsupported.close);
      await expectLater(
        unsupported.startAgent(modelPath: 'model', extensions: registration),
        throwsUnsupportedError,
      );
    },
  );
  test(
    'email drafting requires explicit opt-in and transport support',
    () async {
      final unsupported = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: AgentTransport(),
      );
      addTearDown(unsupported.close);
      await expectLater(
        unsupported.startKnowledgeAgent(
          modelPath: 'model',
          allowEmailDrafts: true,
        ),
        throwsUnsupportedError,
      );
      final transport = EmailAgentTransport();
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: transport,
      );
      addTearDown(engine.close);
      final ordinary = await engine.startKnowledgeAgent(modelPath: 'model');
      expect(transport.emailOpens, 0);
      await ordinary.close();
      final optedIn = await engine.startKnowledgeAgent(
        modelPath: 'model',
        allowEmailDrafts: true,
      );
      expect(transport.emailOpens, 1);
      await optedIn.close();
    },
  );
  test(
    'agent streams native boundaries and future send returns only completion',
    () async {
      final reply = OmnixAgentReply(text: 'Final', toolCalls: 1, sources: []);
      final transport = StreamingAgentTransport()
        ..events = [
          const OmnixAgentEvent(kind: OmnixAgentEventKind.turnStarted),
          const OmnixAgentEvent(
            kind: OmnixAgentEventKind.text,
            text: 'Preamble',
          ),
          const OmnixAgentEvent(
            kind: OmnixAgentEventKind.toolStarted,
            toolName: 'search_knowledge',
          ),
          const OmnixAgentEvent(kind: OmnixAgentEventKind.turnStarted),
          const OmnixAgentEvent(kind: OmnixAgentEventKind.text, text: 'Final'),
          OmnixAgentEvent(kind: OmnixAgentEventKind.completed, reply: reply),
        ];
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: transport,
      );
      addTearDown(engine.close);
      final agent = await engine.startKnowledgeAgent(modelPath: 'model');
      addTearDown(agent.close);
      expect((await agent.sendEvents('Question').toList()).length, 6);
      expect((await agent.send('Question')).text, 'Final');
      expect(
        OmnixAgentEvent.fromJson(transport.events.last.toJson()).reply!.text,
        'Final',
      );
      expect(
        () => OmnixAgentEvent.fromJson({'kind': 'text'}),
        throwsFormatException,
      );
      expect(
        () => OmnixAgentEvent.fromJson({'kind': 'unknown'}),
        throwsFormatException,
      );
    },
  );
  test('abandoned and incomplete streams close the native agent', () async {
    final transport = StreamingAgentTransport()
      ..events = [const OmnixAgentEvent(kind: OmnixAgentEventKind.turnStarted)];
    final engine = await OmnixCognitiveEngine.open(
      runtimes: ['litertlm'],
      transport: transport,
    );
    addTearDown(engine.close);
    final agent = await engine.startKnowledgeAgent(modelPath: 'model');
    await agent.sendEvents('Question').take(1).drain<void>();
    expect(transport.closes, 1);
    final next = await engine.startKnowledgeAgent(modelPath: 'model');
    await expectLater(
      next.sendEvents('Question').drain<void>(),
      throwsStateError,
    );
    expect(transport.closes, 2);
  });
  test('native failure event preserves cause and invalidates agent', () async {
    final transport = StreamingAgentTransport()
      ..events = [
        OmnixAgentEvent.fromJson({
          'kind': 'failed',
          'text': 'InvalidArguments',
        }),
      ];
    final engine = await OmnixCognitiveEngine.open(
      runtimes: ['litertlm'],
      transport: transport,
    );
    addTearDown(engine.close);
    final agent = await engine.startKnowledgeAgent(modelPath: 'model');
    await expectLater(
      agent.sendEvents('Question').drain<void>(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'cause',
          contains('InvalidArguments'),
        ),
      ),
    );
    expect(transport.closes, 1);
    await expectLater(agent.send('Again'), throwsStateError);
    expect(
      () => OmnixAgentEvent.fromJson({'kind': 'failed'}),
      throwsFormatException,
    );
  });
  test(
    'agent rejects overlapping sends and closes after native failure',
    () async {
      final transport = AgentTransport();
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: transport,
      );
      addTearDown(engine.close);
      final agent = await engine.startKnowledgeAgent(
        modelPath: 'model.litertlm',
      );
      final pending = agent.send('Hello');
      await expectLater(agent.send('Overlap'), throwsStateError);
      transport.response.completeError(StateError('Native failure'));
      await expectLater(pending, throwsStateError);
      expect(transport.closes, 1);
      await agent.close();
      expect(transport.closes, 1);
      await expectLater(agent.send('After failure'), throwsStateError);
    },
  );
  test('ordinary-only transports do not silently simulate agents', () async {
    final engine = await OmnixCognitiveEngine.open(
      runtimes: ['litertlm'],
      transport: Transport(),
    );
    addTearDown(engine.close);
    await expectLater(
      engine.startKnowledgeAgent(modelPath: 'model.litertlm'),
      throwsUnsupportedError,
    );
  });
  test(
    'native Knowledge configuration and policy are forwarded without Dart retrieval',
    () async {
      final transport = KnowledgeTransport();
      const knowledge = OmnixLocalKnowledge(
        embeddingModel: 'encoder',
        storePath: 'index',
      );
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: transport,
        knowledge: knowledge,
      );
      final session = await engine.startSession(modelPath: 'model');
      expect(transport.configuration, same(knowledge));
      expect(
        await session.send('reset', knowledge: OmnixKnowledgeUse.required),
        'hello world',
      );
      expect(transport.policy, OmnixKnowledgeUse.required);
      expect(session.sources.single.title, 'Manual');
      expect(() => session.sources.clear(), throwsUnsupportedError);
      await session.send('hello', knowledge: OmnixKnowledgeUse.disabled);
      expect(session.sources, isEmpty);
      await session.close();
      await engine.close();
    },
  );
  test(
    'unsupported Knowledge transport never silently drops registration or required policy',
    () async {
      final transport = Transport();
      await expectLater(
        OmnixCognitiveEngine.open(
          runtimes: ['litertlm'],
          transport: transport,
          knowledge: const OmnixLocalKnowledge(
            embeddingModel: 'encoder',
            storePath: 'index',
          ),
        ),
        throwsUnsupportedError,
      );
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: transport,
      );
      final session = await engine.startSession(modelPath: 'model');
      await expectLater(
        session.send('reset', knowledge: OmnixKnowledgeUse.required),
        throwsUnsupportedError,
      );
      expect(await session.send('hello'), 'hello world');
      await session.close();
      await engine.close();
    },
  );
  test('invalid Knowledge limits fail before native registration', () async {
    final transport = KnowledgeTransport();
    await expectLater(
      OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: transport,
        knowledge: const OmnixLocalKnowledge(
          embeddingModel: 'encoder',
          storePath: 'index',
          threshold: double.nan,
        ),
      ),
      throwsArgumentError,
    );
    expect(transport.configuration, isNull);
  });
  test(
    'requires explicit distinct runtimes before native initialization',
    () async {
      for (final runtimes in <List<String>>[
        [],
        ['unknown'],
        ['litertlm', 'litertlm'],
      ]) {
        await expectLater(
          OmnixCognitiveEngine.open(runtimes: runtimes, transport: Transport()),
          throwsArgumentError,
        );
      }
    },
  );
  test(
    'session forwards instructions, streams, history and independent closure',
    () async {
      final transport = Transport();
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: transport,
      );
      final session = await engine.startSession(
        modelPath: 'trusted-model',
        instructions: 'be concise',
      );
      expect(transport.instructions, 'be concise');
      expect(await session.send('hello'), 'hello world');
      await session.restoreHistory('snapshot');
      expect(transport.restored, 'snapshot');
      await engine.close();
      expect(await session.send('still alive'), 'hello world');
      await expectLater(
        engine.startSession(modelPath: 'model'),
        throwsStateError,
      );
      await session.close();
      await session.close();
      await engine.close();
      expect(transport.engineCloses, 1);
      expect(transport.sessionCloses, 1);
      await expectLater(session.send('closed'), throwsStateError);
    },
  );
  test('native stream failure invalidates and releases the session', () async {
    final transport = Transport()..fail = true;
    final engine = await OmnixCognitiveEngine.open(
      runtimes: ['litertlm'],
      transport: transport,
    );
    final session = await engine.startSession(modelPath: 'model');
    await expectLater(session.send('hello'), throwsStateError);
    expect(transport.sessionCloses, 1);
    expect(transport.cancels, 1);
    await expectLater(session.exportHistory(), throwsStateError);
    await engine.close();
  });
  test(
    'abandoning a stream closes its session rather than reusing uncertain state',
    () async {
      final transport = Transport();
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: transport,
      );
      final session = await engine.startSession(modelPath: 'model');
      expect(await session.sendStream('hello').take(1).toList(), ['hello ']);
      expect(transport.sessionCloses, 1);
      await expectLater(session.send('again'), throwsStateError);
      await engine.close();
    },
  );
}
