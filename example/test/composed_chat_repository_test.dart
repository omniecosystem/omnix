import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:omnix_core/omnix_core.dart';
import 'package:omnix_example/features/home/domain/agent_activity.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/home/data/repositories/composed_chat_repository.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';
import 'package:omnix_storage/omnix_storage.dart';
import 'package:test/test.dart';
import 'package:flutter_test/flutter_test.dart' show TestWidgetsFlutterBinding;
import 'chat_instructions_test.dart' show InstructionStore;

class SessionTransport implements OmnixSessionTransport {
  int creates = 0;
  int opens = 0;
  int? outputTokens;
  String? instructions;
  String? restored;
  int closed = 0;
  int engineClosed = 0;
  int cancellations = 0;
  bool fail = false;
  bool pause = false;
  final started = Completer<void>();
  final released = Completer<void>();
  final engineClosing = Completer<void>();
  @override
  Future<BigInt> create(
    List<String> runtimes,
    String? library,
    int context,
  ) async {
    expect(runtimes, ['litertlm']);
    creates++;
    return BigInt.one;
  }

  @override
  Future<BigInt> open(
    BigInt engine,
    String path,
    String? prompt,
    int output,
  ) async {
    instructions = prompt;
    opens++;
    outputTokens = output;
    return BigInt.two;
  }

  @override
  Stream<String> stream(BigInt session, String text) async* {
    if (!started.isCompleted) started.complete();
    if (fail) throw StateError('Inference failed');
    if (pause) await released.future;
    yield 'Bonjour';
  }

  @override
  Future<String> history(BigInt session) async =>
      '{"version":1,"messages":[["user","Hello"],["assistant","Bonjour"]]}';
  @override
  Future<void> restore(BigInt session, String history) async {
    restored = history;
  }

  @override
  void cancel(BigInt session) {
    cancellations++;
    if (pause && !released.isCompleted) released.complete();
  }

  @override
  Future<void> closeSession(BigInt session) async {
    closed++;
  }

  @override
  Future<void> closeEngine(BigInt engine) async {
    engineClosed++;
    if (!engineClosing.isCompleted) engineClosing.complete();
  }
}

class ResourceSessionTransport extends SessionTransport
    implements OmnixResourceTransport {
  int resourceRequests = 0;
  @override
  Future<String> releaseIdleResources(BigInt engine) async {
    resourceRequests++;
    return '{"knowledge":"NotRegistered","retainedChatModels":1}';
  }
}

class KnowledgeSessionTransport extends SessionTransport
    implements OmnixKnowledgeSessionTransport {
  OmnixLocalKnowledge? registration;
  String? query;
  bool noHits = false;
  @override
  Future<BigInt> createWithKnowledge(
    List<String> runtimes,
    String? library,
    int context,
    OmnixLocalKnowledge knowledge,
  ) async {
    registration = knowledge;
    return BigInt.one;
  }

  @override
  Stream<String> groundedStream(
    BigInt session,
    String text,
    OmnixKnowledgeUse policy,
  ) async* {
    query = text;
    yield* stream(session, text);
  }

  @override
  Future<List<OmnixInteractionSource>> sources(BigInt session) async => noHits
      ? []
      : [
          const OmnixInteractionSource(
            title: 'Manual',
            content: 'Press reset.',
          ),
        ];
  @override
  Future<String> history(BigInt session) async => jsonEncode({
    'version': 1,
    'messages': [
      [
        'user',
        noHits
            ? query
            : 'Native reference prompt\nReference 1: Manual\nPress reset.\n\nUser request:\n$query',
      ],
      ['assistant', 'Bonjour'],
    ],
  });
}

class AgentTransport extends KnowledgeSessionTransport
    implements OmnixAgentTransport, OmnixAgentStreamingTransport {
  int agentClosed = 0;
  @override
  Future<BigInt> openAgent(
    BigInt engine,
    String model,
    String? prompt,
    int tokens,
  ) async {
    instructions = prompt;
    outputTokens = tokens;
    return BigInt.from(3);
  }

  @override
  Future<OmnixAgentReply> runAgent(BigInt id, String text) async {
    if (!started.isCompleted) started.complete();
    if (pause) await released.future;
    if (super.fail) throw StateError('Agent failed');
    return OmnixAgentReply(
      text: 'Reset code: 73921',
      toolCalls: 1,
      sources: [
        const OmnixInteractionSource(title: 'Manual', content: '73921'),
      ],
    );
  }

  @override
  void cancelAgent(BigInt id) => cancel(id);
  @override
  Future<void> closeAgent(BigInt id) async {
    agentClosed++;
  }

  @override
  Stream<OmnixAgentEvent> streamAgent(BigInt id, String text) async* {
    yield const OmnixAgentEvent(kind: OmnixAgentEventKind.turnStarted);
    yield const OmnixAgentEvent(
      kind: OmnixAgentEventKind.text,
      text: 'Looking up the manual.',
    );
    yield const OmnixAgentEvent(
      kind: OmnixAgentEventKind.toolStarted,
      toolName: 'search_knowledge',
    );
    final reply = await runAgent(id, text);
    yield const OmnixAgentEvent(
      kind: OmnixAgentEventKind.toolFinished,
      toolName: 'search_knowledge',
    );
    yield const OmnixAgentEvent(kind: OmnixAgentEventKind.turnStarted);
    yield OmnixAgentEvent(kind: OmnixAgentEventKind.text, text: reply.text);
    yield OmnixAgentEvent(kind: OmnixAgentEventKind.completed, reply: reply);
  }
}

class RegisteredTransport extends AgentTransport
    implements OmnixRegisteredAgentTransport {
  OmnixAgentExtensions? supplied;
  @override
  Future<BigInt> openRegisteredAgent(
    BigInt engine,
    String model,
    String? instructions,
    int tokens,
    OmnixAgentExtensions extensions,
  ) async {
    supplied = extensions;
    outputTokens = tokens;
    return BigInt.from(3);
  }
}

class CheckpointAgentTransport extends RegisteredTransport
    implements OmnixAgentCheckpointTransport {
  int restores = 0;
  int generations = 0;
  String? restoredCheckpoint;
  bool rejectRestore = false;
  @override
  Future<String> agentCheckpoint(BigInt id, String? checkpoint) async {
    if (checkpoint != null) {
      if (rejectRestore) throw StateError('Checkpoint configuration mismatch');
      restores++;
      restoredCheckpoint = checkpoint;
    }
    return 'opaque native tool context';
  }

  @override
  Future<OmnixAgentReply> runAgent(BigInt id, String text) {
    generations++;
    return super.runAgent(id, text);
  }
}

class FailingAgentStore extends InstructionStore {
  bool failWrites = false;
  @override
  Future<String> request(BigInt id, String operation, String payload) {
    if (operation == 'write' && failWrites) {
      throw StateError('Storage write failed');
    }
    return super.request(id, operation, payload);
  }
}

class SwitchingTransport extends CheckpointAgentTransport
    implements OmnixAgentCapabilityTransport {
  final changes = <bool>[];
  bool toolsEnabled = true;
  bool failSwitch = false;
  bool failImport = false;
  Completer<void>? switchGate;
  String? imported;
  @override
  Future<void> setAgentToolsEnabled(BigInt id, bool enabled) async {
    await switchGate?.future;
    if (failSwitch) throw StateError('Switch failed');
    changes.add(enabled);
    toolsEnabled = enabled;
  }

  @override
  Future<void> importAgentChatHistory(BigInt id, String history) async {
    if (failImport) throw StateError('Import failed');
    imported = history;
  }
}

class CheckpointMediaTransport extends CheckpointAgentTransport
    implements OmnixAgentMediaTransport {
  List<OmnixInteractionInput>? parts;
  @override
  Stream<OmnixAgentEvent> streamAgentMessage(
    BigInt id,
    List<OmnixInteractionInput> input,
  ) {
    parts = input;
    return streamAgent(id, 'Voice');
  }
}

class CalendarTransport extends RegisteredTransport {
  CalendarTransport(this.status);
  final String? status;
  @override
  Stream<OmnixAgentEvent> streamAgent(BigInt id, String text) async* {
    const name = 'host_prepare_calendar_event';
    final outcome = status == null
        ? null
        : OmnixToolOutcome(
            callId: 'calendar-1',
            toolName: name,
            status: status!,
            reason: 'Host detail',
          );
    yield const OmnixAgentEvent(
      kind: OmnixAgentEventKind.toolStarted,
      toolName: name,
    );
    yield OmnixAgentEvent(
      kind: OmnixAgentEventKind.toolFinished,
      toolName: name,
      toolFailed: status != 'editor_opened',
      outcome: outcome,
    );
    yield const OmnixAgentEvent(
      kind: OmnixAgentEventKind.text,
      text: 'Event saved successfully!',
    );
    yield OmnixAgentEvent(
      kind: OmnixAgentEventKind.completed,
      reply: OmnixAgentReply(
        text: 'Event saved successfully!',
        toolCalls: 1,
        sources: [],
        toolOutcomes: [?outcome],
      ),
    );
  }
}

class EmailTransport extends AgentTransport
    implements OmnixEmailIntentTransport {
  bool optedIn = false;
  @override
  Future<BigInt> openAgentWithEmailDrafts(
    BigInt engine,
    String model,
    String? instructions,
    int tokens,
  ) async {
    optedIn = true;
    return BigInt.from(3);
  }

  @override
  Stream<OmnixAgentEvent> streamAgent(BigInt id, String text) async* {
    yield const OmnixAgentEvent(
      kind: OmnixAgentEventKind.toolStarted,
      toolName: 'prepare_email_intent',
    );
    yield const OmnixAgentEvent(
      kind: OmnixAgentEventKind.toolFinished,
      toolName: 'prepare_email_intent',
      toolFailed: true,
    );
    yield const OmnixAgentEvent(
      kind: OmnixAgentEventKind.toolStarted,
      toolName: 'prepare_email_intent',
    );
    yield const OmnixAgentEvent(
      kind: OmnixAgentEventKind.toolFinished,
      toolName: 'prepare_email_intent',
    );
    yield OmnixAgentEvent(
      kind: OmnixAgentEventKind.completed,
      reply: OmnixAgentReply(
        text: 'Draft ready for review.',
        toolCalls: 2,
        sources: [],
        intents: [
          OmnixEmailIntent.fromJson({
            'kind': 'email',
            'recipient': 'alex@example.com',
            'subject': 'Hello',
            'body': 'Meet tomorrow?',
          }),
        ],
      ),
    );
  }
}

void main() {
  test(
    'host pressure forwards to prepared engine without closing chat ownership',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final transport = ResourceSessionTransport();
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(
          path: 'test.sqlite',
          transport: InstructionStore(),
        ),
        transport: transport,
      );
      addTearDown(repository.close);
      await repository.releaseIdleResources();
      expect(transport.resourceRequests, 0);
      await repository.prepare('model');
      await repository.releaseIdleResources();
      expect(transport.resourceRequests, 1);
      expect(transport.engineClosed, 0);
      expect(transport.closed, 0);
      await repository.generate('model', 'Hello').drain<void>();
      expect(repository.messages.last.text, 'Bonjour');
    },
  );
  test(
    'shared tools override saved mode and survive conversation selection',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final storage = InstructionStore();
      final transport = SwitchingTransport();
      final saves = <bool>[];
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
        transport: transport,
        sharedToolAvailability: true,
        saveToolAvailability: (value) async => saves.add(value),
      );
      addTearDown(repository.close);
      expect(repository.agentEnabled, isTrue);
      await repository.generate('model', 'First').drain<void>();
      final id = repository.currentId!;
      await repository.switchAgent(false, 'model');
      await repository.select(null);
      expect(repository.agentEnabled, isFalse);
      await repository.switchAgent(true, 'model');
      await repository.select(id);
      expect(repository.agentEnabled, isTrue);
      await repository.prepare('model');
      expect(transport.toolsEnabled, isTrue);
      expect(repository.currentId, id);
      expect(repository.messages.length, 2);
      expect(saves, [false, true]);
      await repository.switchAgent(false, 'model');
      await repository.select(null);
      await repository.select(id);
      await repository.prepare('model');
      expect(transport.toolsEnabled, isFalse);
      expect(repository.agentEnabled, isFalse);
    },
  );

  test(
    'current host availability overrides enabled checkpoint on restart',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final storage = InstructionStore();
      final first = ComposedChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
        transport: SwitchingTransport(),
      )..configureAgent(true);
      await first.generate('model', 'First').drain<void>();
      final id = first.currentId!;
      await first.close();
      final transport = SwitchingTransport();
      final next = ComposedChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
        transport: transport,
        sharedToolAvailability: true,
        initialToolsEnabled: false,
      );
      addTearDown(next.close);
      await next.select(id);
      await next.prepare('model');
      expect(next.agentEnabled, isFalse);
      expect(transport.toolsEnabled, isFalse);
      expect(transport.generations, 0);
    },
  );

  test(
    'shared setting save failure restores tools without losing history',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final transport = SwitchingTransport();
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(
          path: 'test.sqlite',
          transport: InstructionStore(),
        ),
        transport: transport,
        sharedToolAvailability: true,
        saveToolAvailability: (_) async =>
            throw StateError('Settings unavailable'),
      );
      addTearDown(repository.close);
      await repository.generate('model', 'First').drain<void>();
      final id = repository.currentId;
      await expectLater(
        repository.switchAgent(false, 'model'),
        throwsStateError,
      );
      expect(repository.agentEnabled, isTrue);
      expect(transport.toolsEnabled, isTrue);
      expect(repository.currentId, id);
      expect(repository.messages.length, 2);
    },
  );

  test('shared availability upgrades ordinary history on selection', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final storage = InstructionStore();
    final first = ComposedChatRepository(
      OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
      transport: SwitchingTransport(),
    );
    await first.generate('model', 'Hello').drain<void>();
    final id = first.currentId!;
    await first.close();
    final transport = SwitchingTransport();
    final next = ComposedChatRepository(
      OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
      transport: transport,
      sharedToolAvailability: true,
    );
    addTearDown(next.close);
    await next.select(id);
    expect(next.currentId, id);
    expect(next.agentEnabled, isTrue);
    expect(transport.imported, isNotNull);
    expect(transport.generations, 0);
    expect(next.messages.length, 2);
  });

  test(
    'Dart capability change is serialized against sending and checkpoint export',
    () async {
      final transport = SwitchingTransport();
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: transport,
      );
      final agent = await engine.startAgent(
        modelPath: 'model',
        extensions: OmnixAgentExtensions(
          tools: [
            OmnixHostTool(
              name: 'clock',
              description: 'Clock',
              parameters: {'type': 'object'},
              execute: (_) async => {},
            ),
          ],
          grants: ['clock'],
        ),
      );
      transport.switchGate = Completer<void>();
      final change = agent.setToolsEnabled(false);
      await expectLater(agent.exportCheckpoint(), throwsStateError);
      await expectLater(agent.send('No concurrent turn'), throwsStateError);
      await expectLater(
        agent.importChatHistory('{"version":1,"messages":[]}'),
        throwsStateError,
      );
      transport.switchGate!.complete();
      await change;
      expect(transport.toolsEnabled, isFalse);
      expect(transport.generations, 0);
      await agent.close();
      await expectLater(agent.setToolsEnabled(true), throwsStateError);
      await engine.close();
    },
  );
  test(
    'ordinary native media import does not substitute its display transcript',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final storage = InstructionStore();
      final transport = SwitchingTransport();
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
        transport: transport,
        durableMedia: true,
      );
      addTearDown(repository.close);
      await repository.generate('model', 'Hello').drain<void>();
      final id = repository.currentId!;
      final saved = jsonDecode(storage.snapshot!) as Map<String, dynamic>;
      saved['historyVersion'] = 2;
      saved['nativeContext'] = 'owned image and WAV runtime context';
      saved['record']['images'] = true;
      saved['record']['audio'] = true;
      (saved['record'] as Map).remove('groundedTurns');
      saved['messages'] = [
        ['user', '[Image and audio names only]'],
        ['assistant', 'Displayed answer'],
      ];
      storage.snapshot = jsonEncode(saved);
      await repository.select(id);
      await repository.switchAgent(true, 'model');
      final imported = jsonDecode(transport.imported!);
      expect(imported['version'], 2);
      expect(imported['context'], 'owned image and WAV runtime context');
      expect(transport.imported, isNot(contains('Image and audio names only')));
      expect(transport.supplied!.enableImages, isTrue);
      expect(transport.supplied!.enableAudio, isTrue);
      expect(repository.messages.first.text, '[Image and audio names only]');
      expect(repository.currentId, id);
    },
  );
  test(
    'tools toggle keeps ID and context, survives reopen, and avoids reloading',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final storage = InstructionStore();
      final transport = SwitchingTransport();
      final store = OmnixConversationSnapshotStore(
        path: 'test.sqlite',
        transport: storage,
      );
      final repository = ComposedChatRepository(store, transport: transport)
        ..configureAgent(true);
      await repository.generate('model', 'First').drain<void>();
      final id = repository.currentId;
      final creates = transport.creates;
      final generations = transport.generations;
      await repository.switchAgent(false, 'model');
      expect(repository.agentEnabled, isFalse);
      expect(repository.currentId, id);
      expect(repository.messages.length, 2);
      expect(transport.toolsEnabled, isFalse);
      expect(transport.creates, creates);
      expect(transport.generations, generations);
      expect(jsonDecode(storage.snapshot!)['record']['toolsEnabled'], isFalse);
      await repository
          .generate('model', 'Continue without tools')
          .drain<void>();
      expect(repository.messages.length, 4);
      expect(repository.currentId, id);
      await repository.close();
      final nextTransport = SwitchingTransport();
      final next = ComposedChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
        transport: nextTransport,
      );
      addTearDown(next.close);
      await next.select(id);
      await next.prepare('model');
      expect(next.agentEnabled, isFalse);
      expect(nextTransport.toolsEnabled, isFalse);
      expect(nextTransport.generations, 0);
      expect(next.messages.length, 4);
      await next.switchAgent(true, 'model');
      expect(next.agentEnabled, isTrue);
      expect(next.currentId, id);
      expect(nextTransport.toolsEnabled, isTrue);
      expect(nextTransport.generations, 0);
    },
  );
  test(
    'ordinary chat becomes tool capable using native history, not display text',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final storage = InstructionStore();
      final transport = SwitchingTransport();
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
        transport: transport,
      );
      addTearDown(repository.close);
      await repository.generate('model', 'Hello').drain<void>();
      final id = repository.currentId;
      final entries = List.of(repository.messages);
      await repository.switchAgent(true, 'model');
      expect(repository.currentId, id);
      expect(repository.messages, entries);
      expect(transport.imported, contains('"messages"'));
      expect(transport.generations, 0);
      expect(jsonDecode(storage.snapshot!)['record']['kind'], 'agent');
      await repository.switchAgent(false, 'model');
      await repository.generate('model', 'Next').drain<void>();
      expect(repository.messages.length, 4);
      expect(repository.currentId, id);
    },
  );
  test(
    'failed switch or durable write leaves previous mode and saved context intact',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final storage = FailingAgentStore();
      final transport = SwitchingTransport();
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
        transport: transport,
      )..configureAgent(true);
      addTearDown(repository.close);
      await repository.generate('model', 'First').drain<void>();
      final saved = storage.snapshot;
      transport.failSwitch = true;
      await expectLater(
        repository.switchAgent(false, 'model'),
        throwsStateError,
      );
      expect(repository.agentEnabled, isTrue);
      transport.failSwitch = false;
      storage.failWrites = true;
      await expectLater(
        repository.switchAgent(false, 'model'),
        throwsStateError,
      );
      expect(repository.agentEnabled, isTrue);
      expect(transport.toolsEnabled, isTrue);
      expect(storage.snapshot, saved);
      expect(repository.messages.length, 2);
    },
  );
  test(
    'failed ordinary import retains saved ordinary transcript and ID',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final storage = InstructionStore();
      final transport = SwitchingTransport();
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
        transport: transport,
      );
      addTearDown(repository.close);
      await repository.generate('model', 'Hello').drain<void>();
      final id = repository.currentId;
      final saved = storage.snapshot;
      transport.failImport = true;
      await expectLater(
        repository.switchAgent(true, 'model'),
        throwsStateError,
      );
      expect(repository.agentEnabled, isFalse);
      expect(repository.currentId, id);
      expect(repository.messages.length, 2);
      expect(storage.snapshot, saved);
      expect(transport.generations, 0);
    },
  );
  test(
    'text agent upgrades to voice, persists modalities and reopens without tools',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final storage = InstructionStore();
      final transport = CheckpointMediaTransport();
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
        transport: transport,
      )..configureAgent(true);
      await repository.generate('model', 'Remember a fact').drain<void>();
      final id = repository.currentId;
      await repository.generateMessage('model', '', [
        ChatAttachment(
          'Voice.wav',
          OmnixInputPart.audio(Uint8List.fromList([1, 2])),
        ),
      ]).drain<void>();
      expect(transport.generations, 2);
      expect(transport.restores, 1);
      expect(transport.supplied!.enableAudio, isTrue);
      expect(repository.currentId, id);
      expect(repository.messages.length, 4);
      final saved = jsonDecode(storage.snapshot!) as Map<String, dynamic>;
      expect(saved['record']['audio'], isTrue);
      await repository.close();
      final nextTransport = CheckpointMediaTransport();
      final next = ComposedChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
        transport: nextTransport,
      );
      await next.select(id);
      await next.prepare('model');
      expect(nextTransport.supplied!.enableAudio, isTrue);
      expect(nextTransport.generations, 0);
      expect(next.messages.length, 4);
      expect(next.messages[2].text, '[Voice.wav]');
      await next.generate('model', 'Continue with text').drain<void>();
      expect(nextTransport.generations, 1);
      await next.close();
    },
  );
  test(
    'startup preparation retains one lease without generating a turn',
    () async {
      final transport = SessionTransport();
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(
          path: 'test.sqlite',
          transport: InstructionStore(),
        ),
        transport: transport,
      );
      await repository.prepare('model');
      await repository.prepare('model');
      expect(transport.creates, 1);
      expect(transport.opens, 1);
      expect(transport.started.isCompleted, isFalse);
      expect(repository.messages, isEmpty);
      expect(repository.currentId, isNull);
      repository.configureInstructions(
        'Remain editable before the first turn.',
      );
      await repository.generate('model', 'Hello').drain<void>();
      expect(transport.creates, 1);
      expect(transport.opens, 2);
      expect(transport.closed, 1);
      await repository.close();
      expect(transport.engineClosed, 1);
    },
  );

  test(
    'in-app response budget reaches agent and persists across reopen',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final storage = InstructionStore();
      final transport = CheckpointAgentTransport();
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
        transport: transport,
      );
      addTearDown(repository.close);
      repository.configureResponseBudget(2048);
      repository.configureAgent(true);
      await repository.generate('model', 'Hello').drain<void>();
      expect(transport.outputTokens, 2048);
      expect(() => repository.configureResponseBudget(4096), throwsStateError);
      final id = repository.currentId;
      await repository.select(null);
      expect(repository.maxOutputTokens, 2048);
      repository.configureResponseBudget(1024);
      await repository.select(id);
      expect(repository.maxOutputTokens, 2048);
      await repository.generate('model', 'Continue').drain<void>();
      expect(transport.outputTokens, 2048);
    },
  );
  test(
    'ordinary Home uses the larger default and forwards a custom budget',
    () async {
      for (final budget in [null, 2048]) {
        final transport = SessionTransport();
        final repository = ComposedChatRepository(
          OmnixConversationSnapshotStore(
            path: 'test.sqlite',
            transport: InstructionStore(),
          ),
          transport: transport,
          maxOutputTokens: budget ?? 1024,
        );
        try {
          await repository.generate('model', 'Hello').drain<void>();
          expect(transport.outputTokens, budget ?? 1024);
        } finally {
          await repository.close();
        }
      }
    },
  );
  test(
    'agent saves native context and restores transcript before a new turn',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final storage = InstructionStore();
      final firstTransport = CheckpointAgentTransport();
      final first = ComposedChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
        transport: firstTransport,
        maxOutputTokens: 1536,
      );
      first.configureInstructions('Use host evidence.');
      first.configureAgent(true);
      await first.generate('model', 'Reset code?').drain<void>();
      final id = first.currentId!;
      final saved = jsonDecode(storage.snapshot!) as Map<String, dynamic>;
      expect(saved['record']['kind'], 'agent');
      expect(saved['record']['maxOutputTokens'], 1536);
      expect(firstTransport.outputTokens, 1536);
      expect(saved['checkpoint'], 'opaque native tool context');
      expect(firstTransport.generations, 1);
      await first.close();
      final nextTransport = CheckpointAgentTransport();
      final next = ComposedChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
        transport: nextTransport,
      );
      addTearDown(next.close);
      await next.select(id);
      expect(next.agentEnabled, isTrue);
      expect(next.currentId, id);
      expect(next.instructions, 'Use host evidence.');
      expect(next.messages.last.sources.single.title, 'Manual');
      expect(next.messages.last.activities.single.toolName, 'search_knowledge');
      expect(nextTransport.generations, 0);
      await next.prepare('model');
      expect(nextTransport.restores, 1);
      expect(nextTransport.generations, 0);
      expect(next.canReconfigureLive, isTrue);
      expect(next.messages.length, 2);
      await next.prepare('model');
      expect(nextTransport.restores, 1);
      await next.generate('model', 'Again').drain<void>();
      expect(nextTransport.restores, 1);
      expect(nextTransport.outputTokens, 1536);
      expect(nextTransport.restoredCheckpoint, 'opaque native tool context');
      expect(nextTransport.generations, 1);
      expect(next.messages.length, 4);
      expect(next.currentId, id);
    },
  );
  test(
    'failed agent save preserves durable history and blocks blind retries',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final storage = FailingAgentStore();
      final transport = CheckpointAgentTransport();
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
        transport: transport,
      );
      addTearDown(repository.close);
      repository.configureAgent(true);
      await repository.generate('model', 'First').drain<void>();
      final saved = storage.snapshot;
      storage.failWrites = true;
      await expectLater(
        repository.generate('model', 'Next').drain<void>(),
        throwsStateError,
      );
      expect(storage.snapshot, saved);
      expect(repository.messages.length, 2);
      await expectLater(
        repository.generate('model', 'Retry').drain<void>(),
        throwsStateError,
      );
      expect(transport.generations, 2);
      await repository.select(null);
      storage.failWrites = false;
      await repository.generate('model', 'New chat').drain<void>();
      expect(transport.generations, 3);
    },
  );
  test(
    'rejected restored context cannot silently fall back to a fresh agent',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final storage = InstructionStore();
      final transport = CheckpointAgentTransport();
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
        transport: transport,
      );
      addTearDown(repository.close);
      repository.configureAgent(true);
      await repository.generate('model', 'First').drain<void>();
      final id = repository.currentId!;
      await repository.select(id);
      transport.rejectRestore = true;
      await expectLater(repository.prepare('model'), throwsStateError);
      expect(transport.generations, 1);
      expect(repository.messages.length, 2);
      expect(repository.canReconfigureLive, isFalse);
      await expectLater(
        repository.generate('model', 'Next').drain<void>(),
        throwsStateError,
      );
      expect(transport.generations, 1);
      expect(repository.messages.length, 2);
      transport.rejectRestore = false;
      await repository.prepare('model');
      expect(repository.canReconfigureLive, isTrue);
      expect(transport.generations, 1);
    },
  );
  test(
    'consumer autonomy choice reaches registration and cannot change mid-session',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final transport = RegisteredTransport();
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(
          path: 'policy.sqlite',
          transport: InstructionStore(),
        ),
        transport: transport,
      );
      addTearDown(repository.close);
      repository.configureAutonomy(OmnixAutonomyMode.reviewEveryCall);
      repository.configureAgent(true);
      await repository.generate('model', 'Hello').drain<void>();
      expect(
        transport.supplied!.approvalPolicy!.mode,
        OmnixAutonomyMode.reviewEveryCall,
      );
      expect(
        () => repository.configureAutonomy(OmnixAutonomyMode.scopedAssistance),
        throwsStateError,
      );
      await repository.select(null);
      repository.configureAutonomy(OmnixAutonomyMode.scopedAssistance);
      expect(repository.autonomy, OmnixAutonomyMode.scopedAssistance);
      expect(
        () => repository.configureAutonomy(OmnixAutonomyMode.delegatedScope),
        throwsArgumentError,
      );
    },
  );
  for (final status in [
    'invalid_arguments',
    'denied',
    'unavailable',
    'failed',
    'editor_opened',
    null,
  ]) {
    test(
      'calendar $status overrides false success prose, including streaming',
      () async {
        final repository = ComposedChatRepository(
          OmnixConversationSnapshotStore(
            path: 'test.sqlite',
            transport: InstructionStore(),
          ),
          transport: CalendarTransport(status),
        )..configureAgent(true);
        addTearDown(repository.close);
        await for (final _ in repository.generate('model', 'Calendar test')) {
          expect(
            repository.agentText,
            isNot(contains('Event saved successfully')),
          );
        }
        final answer = repository.messages.last.text;
        expect(answer, isNot(contains('Event saved successfully')));
        expect(
          answer,
          contains(
            status == 'editor_opened'
                ? 'calendar editor opened'
                : 'No successful calendar handoff',
          ),
        );
        expect(
          repository.messages.last.activities.single.outcomeStatus,
          status,
        );
      },
    );
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'registered host agent works without Knowledge and grants no search',
    () async {
      final transport = RegisteredTransport();
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(
          path: 'test.sqlite',
          transport: InstructionStore(),
        ),
        transport: transport,
      );
      addTearDown(repository.close);
      expect(repository.agentAvailable, isTrue);
      repository.configureAgent(true);
      await repository.generate('model', 'What time is it?').drain<void>();
      expect(transport.supplied!.grants, contains('host_time'));
      expect(transport.supplied!.grants, isNot(contains('search_knowledge')));
      expect(transport.registration, isNull);
    },
  );
  test(
    'email proposal opt-in reaches Rust transport and survives only a completed turn',
    () async {
      final transport = EmailTransport();
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(
          path: 'test.sqlite',
          transport: InstructionStore(),
        ),
        transport: transport,
        knowledge: const OmnixLocalKnowledge(
          embeddingModel: 'encoder',
          storePath: 'index',
        ),
      )..configureAgent(true);
      addTearDown(repository.close);
      expect(repository.emailDraftsEnabled, isFalse);
      repository.configureEmailDrafts(true);
      await repository.generate('model', 'Draft an email').drain<void>();
      expect(transport.optedIn, isTrue);
      expect(
        repository.messages.last.intents.single.recipient,
        'alex@example.com',
      );
      expect(repository.messages.last.activities.map((a) => a.state), [
        AgentActivityState.failed,
        AgentActivityState.completed,
      ]);
      expect(() => repository.configureEmailDrafts(false), throwsStateError);
      await repository.select(null);
      expect(repository.emailDraftsEnabled, isFalse);
      expect(repository.messages, isEmpty);
    },
  );
  test('Home replaces tool preamble with the final streamed answer', () async {
    final repository = ComposedChatRepository(
      OmnixConversationSnapshotStore(
        path: 'test.sqlite',
        transport: InstructionStore(),
      ),
      transport: AgentTransport(),
      knowledge: const OmnixLocalKnowledge(
        embeddingModel: 'encoder',
        storePath: 'index',
      ),
    )..configureAgent(true);
    final controller = CoreController(repository);
    addTearDown(controller.close);
    final seen = <String>[];
    controller.addListener(() => seen.add(controller.answer));
    await controller.send('model', 'Reset code?');
    expect(seen, contains('Looking up the manual.'));
    expect(seen, contains('Reset code: 73921'));
    expect(controller.messages.last.text, 'Reset code: 73921');
    expect(controller.messages.last.text, isNot(contains('Looking up')));
    expect(
      controller.messages.last.activities.single.state,
      AgentActivityState.completed,
    );
    expect(repository.agentActivities, isEmpty);
    final first = controller.messages.last.activities;
    await controller.send('model', 'Another question');
    expect(controller.messages.where((m) => m.role == 'assistant').length, 2);
    expect(first.single.state, AgentActivityState.completed);
    expect(() => first.clear(), throwsUnsupportedError);
  });
  test(
    'agent uses root transport, keeps evidence and never saves text-only history',
    () async {
      final transport = AgentTransport();
      final storage = InstructionStore();
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
        transport: transport,
        knowledge: const OmnixLocalKnowledge(
          embeddingModel: 'encoder',
          storePath: 'index',
        ),
      );
      addTearDown(repository.close);
      expect(repository.agentEnabled, isFalse);
      repository.configureInstructions('Use local references.');
      repository.configureAgent(true);
      expect(
        await repository.generate('model', 'Reset code?').join(),
        contains('73921'),
      );
      expect(transport.instructions, 'Use local references.');
      expect(transport.query, isNull); // No Dart-side grounded chat call.
      expect(repository.messages.last.sources.single.title, 'Manual');
      expect(repository.currentId, isNull);
      expect(storage.snapshot, isNull);
      expect(() => repository.configureAgent(false), throwsStateError);
      await repository.select(null);
      expect(transport.agentClosed, 1);
      expect(transport.engineClosed, 1);
      expect(repository.messages, isEmpty);
      expect(repository.agentActivities, isEmpty);
      repository.configureAgent(false);
      await repository.generate('model', 'Hello').drain<void>();
      expect(storage.snapshot, isNotNull);
    },
  );
  test(
    'failed tool retains failed activity without an assistant answer',
    () async {
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(
          path: 'test.sqlite',
          transport: InstructionStore(),
        ),
        transport: AgentTransport()..fail = true,
        knowledge: const OmnixLocalKnowledge(
          embeddingModel: 'encoder',
          storePath: 'index',
        ),
      )..configureAgent(true);
      addTearDown(repository.close);
      await expectLater(
        repository.generate('model', 'Reset?').drain<void>(),
        throwsStateError,
      );
      expect(repository.messages, isEmpty);
      expect(
        repository.agentActivities.single.state,
        AgentActivityState.failed,
      );
    },
  );
  test(
    'stopped agent discards provisional text and releases native ownership',
    () async {
      final transport = AgentTransport()..pause = true;
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(
          path: 'test.sqlite',
          transport: InstructionStore(),
        ),
        transport: transport,
        knowledge: const OmnixLocalKnowledge(
          embeddingModel: 'encoder',
          storePath: 'index',
        ),
      )..configureAgent(true);
      addTearDown(repository.close);
      final answer = repository.generate('model', 'Reset?').join();
      await transport.started.future;
      await repository.stop();
      expect(await answer, contains('Looking up the manual.'));
      expect(repository.agentText, isEmpty);
      expect(repository.messages, isEmpty);
      expect(
        repository.agentActivities.single.state,
        AgentActivityState.cancelled,
      );
      expect(transport.agentClosed, 1);
      expect(transport.engineClosed, 1);
      await repository.select(null);
      expect(repository.agentActivities, isEmpty);
    },
  );
  test(
    'legacy Knowledge-only transport requires Knowledge and tool counts are bounded',
    () async {
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(
          path: 'test.sqlite',
          transport: InstructionStore(),
        ),
        transport: AgentTransport(),
      );
      addTearDown(repository.close);
      expect(() => repository.configureAgent(true), throwsStateError);
      expect(
        () => OmnixAgentReply.fromJson({
          'text': '',
          'toolCalls': 33,
          'sources': [],
        }),
        throwsFormatException,
      );
      final reply = OmnixAgentReply(text: 'Answer', toolCalls: 0, sources: []);
      expect(OmnixAgentReply.fromJson(reply.toJson()).text, 'Answer');
    },
  );
  test(
    'native references persist without Dart retrieval or fabricated scores',
    () async {
      final transport = KnowledgeSessionTransport();
      final storage = InstructionStore();
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
        transport: transport,
        knowledge: const OmnixLocalKnowledge(
          embeddingModel: 'encoder',
          storePath: 'index',
        ),
      );
      addTearDown(repository.close);
      await repository.generate('model', 'How?').drain<void>();
      expect(transport.registration!.storePath, 'index');
      expect(transport.query, 'How?');
      expect(repository.messages.first.text, 'How?');
      expect(repository.messages.last.sources.single.score, isNull);
      expect(storage.snapshot, contains('Native reference prompt'));
      expect(() => repository.configureKnowledge(null), throwsStateError);
      await repository.select('saved');
      expect(repository.messages.first.text, 'How?');
      expect(repository.messages.last.sources.single.title, 'Manual');
      final tampered = jsonDecode(storage.snapshot!) as Map<String, dynamic>;
      tampered['record']['groundedTurns'][0]['sources'][0]['content'] =
          'Unrelated evidence';
      storage.snapshot = jsonEncode(tampered);
      await expectLater(repository.select('saved'), throwsFormatException);
      await repository.select(null);
      repository.configureKnowledge(null);
      expect(transport.engineClosed, 1);
    },
  );
  test('zero native hits do not manufacture evidence', () async {
    final repository = ComposedChatRepository(
      OmnixConversationSnapshotStore(
        path: 'test.sqlite',
        transport: InstructionStore(),
      ),
      transport: KnowledgeSessionTransport()..noHits = true,
      knowledge: const OmnixLocalKnowledge(
        embeddingModel: 'encoder',
        storePath: 'index',
      ),
    );
    addTearDown(repository.close);
    await repository.generate('model', 'How?').drain<void>();
    expect(repository.messages.last.sources, isEmpty);
  });
  test(
    'active stop reaches root session without waiting for generation',
    () async {
      final transport = SessionTransport()..pause = true;
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(
          path: 'test.sqlite',
          transport: InstructionStore(),
        ),
        transport: transport,
      );
      addTearDown(repository.close);
      final reply = repository.generate('model', 'Hello').join();
      await transport.started.future.timeout(const Duration(seconds: 2));
      await repository.stop();
      expect(transport.cancellations, 1);
      await reply;
    },
  );
  test(
    'root sessions preserve instructions, native history and closure',
    () async {
      final transport = SessionTransport();
      final store = InstructionStore();
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: store),
        transport: transport,
      );
      addTearDown(repository.close);
      expect(repository, isA<MediaCoreBackend>());
      expect(repository, isNot(isA<GroundedCoreBackend>()));
      repository.configureInstructions('Reply in French.');
      expect(await repository.generate('model', 'Hello').join(), 'Bonjour');
      expect(transport.instructions, 'Reply in French.');
      expect(repository.messages.last.text, 'Bonjour');
      await repository.stop();
      // Stopping an already completed stream is intentionally a no-op.
      expect(transport.cancellations, 0);
      await repository.select(null);
      await repository.select('saved');
      await repository.generate('model', 'Again').drain<void>();
      expect(transport.restored, contains('Bonjour'));
      expect(transport.instructions, 'Reply in French.');
      await repository.close();
      expect(transport.closed, 2);
      expect(transport.engineClosed, 2);
    },
  );
  test(
    'failed generation closes root leases and never writes a snapshot',
    () async {
      final transport = SessionTransport()..fail = true;
      final store = InstructionStore();
      final repository = ComposedChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: store),
        transport: transport,
      );
      addTearDown(repository.close);
      await expectLater(
        repository.generate('model', 'Hello').join(),
        throwsStateError,
      );
      expect(store.snapshot, isNull);
      await transport.engineClosing.future.timeout(const Duration(seconds: 2));
      expect(transport.closed, 1);
      expect(transport.engineClosed, 1);
    },
  );
}
