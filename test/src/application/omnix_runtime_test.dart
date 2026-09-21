// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:typed_data';

import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  group('OmnixRuntime', () {
    late _FakeEngine engine;
    late _FakeInferenceBackend backend;
    late OmnixRuntime runtime;

    setUp(() {
      engine = _FakeEngine();
      backend = _FakeInferenceBackend();
      runtime = OmnixRuntime(engine: engine, inferenceBackend: backend);
    });

    test(
      'initializes once and owns the complete conversation lifecycle',
      () async {
        final conversation = await runtime.openConversation(_configuration);

        expect(engine.initializeCalls, 1);
        expect(backend.openCalls, 1);
        expect(await conversation.send('hello').toList(), [
          isA<OmnixTextDelta>().having((event) => event.text, 'text', 'hello'),
        ]);

        await conversation.stop();
        await runtime.close();

        expect(backend.conversation.stopCalls, 1);
        expect(backend.conversation.closeCalls, 1);
        expect(engine.closeCalls, 1);
      },
    );

    test('closes conversations still owned when the runtime closes', () async {
      await runtime.openConversation(_configuration);

      await runtime.close();

      expect(backend.conversation.closeCalls, 1);
      expect(engine.closeCalls, 1);
    });

    test('stops active generation before closing runtime resources', () async {
      backend.conversation.blockUntilStopped = true;
      final conversation = await runtime.openConversation(_configuration);
      final response = conversation.send('hello').drain<void>();
      await backend.conversation.sendStarted.future;

      await runtime.close();
      await response;

      expect(backend.conversation.stopCalls, 1);
      expect(backend.conversation.closeCalls, 1);
      expect(engine.closeCalls, 1);
    });

    test(
      'forwards image and audio attachments without provider types',
      () async {
        final conversation = await runtime.openConversation(_configuration);
        final image = Uint8List.fromList([1, 2]);
        final audio = Uint8List.fromList([3, 4]);

        await conversation
            .send('describe', imageBytes: image, audioBytes: audio)
            .drain<void>();

        expect(backend.conversation.lastImageBytes, image);
        expect(backend.conversation.lastAudioBytes, audio);
      },
    );

    test(
      'routes conversation turns through its chat-priority scheduler',
      () async {
        final conversation = await runtime.openConversation(_configuration);
        final firstStarted = Completer<void>();
        final releaseFirst = Completer<void>();
        final order = <String>[];
        backend.conversation.onSend = () => order.add('chat');
        final first = runtime.inferenceScheduler.enqueue<void>(
          taskId: 'task-1',
          generation: () async {
            order.add('task-1:start');
            firstStarted.complete();
            await releaseFirst.future;
            order.add('task-1:end');
          },
        );
        await firstStarted.future;
        final second = runtime.inferenceScheduler.enqueue<void>(
          taskId: 'task-2',
          generation: () async => order.add('task-2'),
        );
        final reply = conversation.send('hello').toList();

        releaseFirst.complete();
        await Future.wait<Object?>([first, second, reply]);

        expect(order, ['task-1:start', 'task-1:end', 'chat', 'task-2']);
        await runtime.close();
      },
    );

    test('serializes conversation creation with inference work', () async {
      final taskStarted = Completer<void>();
      final releaseTask = Completer<void>();
      final task = runtime.inferenceScheduler.enqueue<void>(
        taskId: 'task-1',
        generation: () async {
          taskStarted.complete();
          await releaseTask.future;
        },
      );
      await taskStarted.future;

      final opening = runtime.openConversation(_configuration);
      await Future<void>.delayed(Duration.zero);
      expect(backend.openCalls, 0);

      releaseTask.complete();
      await task;
      await opening;
      expect(backend.openCalls, 1);
      await runtime.close();
    });

    test('restores context and sends under one scheduler lease', () async {
      final conversation = await runtime.openConversation(_configuration);
      expect(conversation, isA<OmnixContextualConversation>());
      final contextual = conversation as OmnixContextualConversation;
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final order = <String>[];
      backend.conversation.onReplaceHistory = () => order.add('replace');
      backend.conversation.onSend = () => order.add('send');
      final first = runtime.inferenceScheduler.enqueue<void>(
        taskId: 'task-1',
        generation: () async {
          order.add('task-1:start');
          firstStarted.complete();
          await releaseFirst.future;
          order.add('task-1:end');
        },
      );
      await firstStarted.future;
      final reply = contextual.sendWithHistory([
        OmnixMessage.text(text: 'history', role: OmnixMessageRole.user),
      ], 'hello').toList();
      final second = runtime.inferenceScheduler.enqueue<void>(
        taskId: 'task-2',
        generation: () async => order.add('task-2'),
      );

      releaseFirst.complete();
      await Future.wait<Object?>([first, reply, second]);

      expect(order, [
        'task-1:start',
        'task-1:end',
        'replace',
        'send',
        'task-2',
      ]);
      await runtime.close();
    });

    test('does not close a conversation twice', () async {
      final conversation = await runtime.openConversation(_configuration);

      await conversation.close();
      await runtime.close();

      expect(backend.conversation.closeCalls, 1);
      expect(engine.closeCalls, 1);
    });

    test('replays only history selected for the active context', () async {
      final history = [
        OmnixMessage(
          text: 'system',
          role: OmnixMessageRole.assistant,
          kind: OmnixMessageKind.systemInfo,
        ),
        OmnixMessage.text(text: 'old message', role: OmnixMessageRole.user),
        OmnixMessage.text(text: 'new', role: OmnixMessageRole.user),
      ];

      await runtime.openConversation(
        _configuration,
        history: history,
        contextPolicy: const OmnixRecentContextPolicy(
          budget: OmnixContextBudget(
            contextWindowTokens: 13,
            reservedOutputTokens: 0,
          ),
          estimator: _MessageTextLengthEstimator(),
        ),
      );

      expect(backend.conversation.history.map((message) => message.text), [
        'system',
        'new',
      ]);
      await runtime.close();
    });

    test('closes the engine when conversation cleanup fails', () async {
      backend.conversation.throwOnClose = true;
      await runtime.openConversation(_configuration);

      await expectLater(runtime.close(), throwsStateError);

      expect(backend.conversation.closeCalls, 1);
      expect(engine.closeCalls, 1);
    });

    test('rejects new conversations after close', () async {
      await runtime.close();

      expect(
        () => runtime.openConversation(_configuration),
        throwsA(isA<StateError>()),
      );
    });

    test('initializes an optional model manager with the runtime', () async {
      final modelManager = _FakeModelManager();
      runtime = OmnixRuntime(
        engine: engine,
        inferenceBackend: backend,
        modelManager: modelManager,
      );

      await runtime.openConversation(_configuration);

      expect(runtime.supportsModelManagement, isTrue);
      expect(runtime.models, same(modelManager));
      expect(modelManager.initializeCalls, 1);
    });

    test('reports unavailable model management explicitly', () {
      expect(runtime.supportsModelManagement, isFalse);
      expect(() => runtime.models, throwsUnsupportedError);
    });

    test('owns one shared capability registry', () async {
      runtime.capabilities.register(_tool());

      expect(runtime.capabilities.find('clock'), isA<OmnixTool>());

      await runtime.close();
      expect(() => runtime.capabilities.register(_tool()), throwsStateError);
    });

    test('reports unavailable agent support explicitly', () {
      expect(runtime.supportsAgents, isFalse);
      expect(
        () => runtime.openAgent(_agentConfiguration),
        throwsUnsupportedError,
      );
    });

    test('rejects unsupported modalities before initializing', () async {
      backend.capabilitiesOverride = const OmnixInferenceProviderCapabilities(
        providerId: 'text-only',
        formats: {OmnixModelFormat.liteRtLm},
        inputModalities: {OmnixInputModality.text},
        platform: OmnixTargetPlatform.android,
        supportsThinking: false,
        supportsFunctionCalls: false,
      );

      await expectLater(
        runtime.openConversation(
          const OmnixConversationConfiguration(
            modelTemplate: OmnixModelTemplate.gemma4,
            supportsAudio: true,
          ),
        ),
        throwsUnsupportedError,
      );

      expect(engine.initializeCalls, 0);
      expect(backend.openCalls, 0);
    });

    test('opens agents with the current capability snapshot', () async {
      final agentBackend = _FakeAgentBackend();
      runtime = OmnixRuntime(
        engine: engine,
        inferenceBackend: backend,
        agentBackend: agentBackend,
      );
      runtime.capabilities.register(_tool(), enabled: false);

      final session = await runtime.openAgent(_agentConfiguration);

      expect(runtime.supportsAgents, isTrue);
      expect(agentBackend.openCalls, 1);
      expect(agentBackend.snapshot!.revision, 1);
      expect(agentBackend.snapshot!.enabledTools, isEmpty);
      expect(await session.ask('hello').toList(), [
        isA<OmnixAgentTextDelta>().having(
          (event) => event.text,
          'text',
          'hello',
        ),
      ]);
    });

    test('routes agent turns through the runtime scheduler', () async {
      final agentBackend = _FakeAgentBackend();
      runtime = OmnixRuntime(
        engine: engine,
        inferenceBackend: backend,
        agentBackend: agentBackend,
      );
      final session = await runtime.openAgent(_agentConfiguration);
      final taskStarted = Completer<void>();
      final releaseTask = Completer<void>();
      final task = runtime.inferenceScheduler.enqueue<void>(
        taskId: 'task-1',
        generation: () async {
          taskStarted.complete();
          await releaseTask.future;
        },
      );
      await taskStarted.future;
      final reply = session.ask('hello').toList();

      await Future<void>.delayed(Duration.zero);
      expect(agentBackend.session.askCalls, 0);
      releaseTask.complete();
      await task;
      await reply;
      expect(agentBackend.session.askCalls, 1);
      await runtime.close();
    });

    test('owns agent sessions and does not close them twice', () async {
      final agentBackend = _FakeAgentBackend();
      runtime = OmnixRuntime(
        engine: engine,
        inferenceBackend: backend,
        agentBackend: agentBackend,
      );
      final session = await runtime.openAgent(_agentConfiguration);

      await session.close();
      await runtime.close();

      expect(agentBackend.session.closeCalls, 1);
    });

    test('replays selected history into a new agent session', () async {
      final agentBackend = _FakeAgentBackend();
      runtime = OmnixRuntime(
        engine: engine,
        inferenceBackend: backend,
        agentBackend: agentBackend,
      );

      await runtime.openAgent(
        _agentConfiguration,
        history: [
          OmnixMessage.text(text: 'older', role: OmnixMessageRole.user),
          OmnixMessage.text(text: 'new', role: OmnixMessageRole.user),
        ],
        contextPolicy: const OmnixRecentContextPolicy(
          budget: OmnixContextBudget(
            contextWindowTokens: 3,
            reservedOutputTokens: 0,
          ),
          estimator: _MessageTextLengthEstimator(),
          preserveSystemInformation: false,
        ),
      );

      expect(agentBackend.session.history.single.text, 'new');
      await runtime.close();
    });

    test('closes active agent sessions with the runtime', () async {
      final agentBackend = _FakeAgentBackend();
      runtime = OmnixRuntime(
        engine: engine,
        inferenceBackend: backend,
        agentBackend: agentBackend,
      );
      await runtime.openAgent(_agentConfiguration);

      await runtime.close();

      expect(agentBackend.session.closeCalls, 1);
      expect(engine.closeCalls, 1);
    });

    test('closes its scheduler with the runtime', () async {
      final scheduler = runtime.inferenceScheduler;

      await runtime.close();

      await expectLater(
        scheduler.enqueue<void>(taskId: 'task', generation: () async {}),
        throwsStateError,
      );
    });

    test('does not close an application-owned scheduler', () async {
      final scheduler = InferenceScheduler();
      runtime = OmnixRuntime(
        engine: engine,
        inferenceBackend: backend,
        inferenceScheduler: scheduler,
      );

      await runtime.close();

      await scheduler.enqueue<void>(
        taskId: 'host-task',
        generation: () async {},
      );
      await scheduler.close();
    });

    test('opens and owns Workflow runtimes on the same lifecycle', () async {
      final store = _FakeWorkflowStore();
      final workflows = await runtime.openWorkflow(
        store: store,
        executors: const [],
      );

      expect(store.initializeCalls, 1);
      await runtime.close();

      await expectLater(
        workflows.createTask(id: 'late-task', kind: 'test', title: 'Too late'),
        throwsStateError,
      );
    });
  });
}

const _configuration = OmnixConversationConfiguration(
  modelTemplate: OmnixModelTemplate.general,
);

const _agentConfiguration = OmnixAgentConfiguration(
  modelTemplate: OmnixModelTemplate.gemma4,
);

OmnixTool _tool() => OmnixTool(
  metadata: OmnixCapabilityMetadata(
    id: 'clock',
    kind: OmnixCapabilityKind.tool,
    name: 'Clock',
    description: 'Returns the current time.',
  ),
  execute: (_) => const OmnixToolSuccess('12:00'),
);

final class _FakeEngine implements OmnixEngine {
  int initializeCalls = 0;
  int closeCalls = 0;
  OmnixEngineState _state = OmnixEngineState.created;

  @override
  Stream<OmnixEngineEvent> get events => const Stream.empty();

  @override
  OmnixEngineState get state => _state;

  @override
  Future<OmnixRuntimeInfo> initialize() async {
    initializeCalls++;
    _state = OmnixEngineState.ready;
    return const OmnixRuntimeInfo(
      apiVersion: 1,
      engineName: 'Fake Omnix',
      engineVersion: '1.0.0',
    );
  }

  @override
  Future<void> close() async {
    closeCalls++;
    _state = OmnixEngineState.closed;
  }
}

final class _FakeInferenceBackend implements OmnixInferenceBackend {
  final _FakeConversation conversation = _FakeConversation();
  int openCalls = 0;
  OmnixInferenceProviderCapabilities capabilitiesOverride =
      const OmnixInferenceProviderCapabilities(
        providerId: 'fake',
        formats: {OmnixModelFormat.liteRtLm},
        inputModalities: {
          OmnixInputModality.text,
          OmnixInputModality.image,
          OmnixInputModality.audio,
        },
        platform: OmnixTargetPlatform.android,
        supportsThinking: true,
        supportsFunctionCalls: true,
      );

  @override
  OmnixInferenceProviderCapabilities get capabilities => capabilitiesOverride;

  @override
  Future<OmnixConversation> openConversation(
    OmnixConversationConfiguration configuration,
  ) async {
    openCalls++;
    return conversation;
  }
}

final class _FakeConversation implements OmnixConversation {
  int stopCalls = 0;
  int closeCalls = 0;
  bool throwOnClose = false;
  List<OmnixMessage> _history = [];
  Uint8List? lastImageBytes;
  Uint8List? lastAudioBytes;
  void Function()? onSend;
  void Function()? onReplaceHistory;
  bool blockUntilStopped = false;
  Completer<void> sendStarted = Completer<void>();
  final Completer<void> _sendRelease = Completer<void>();

  @override
  List<OmnixMessage> get history => List.unmodifiable(_history);

  @override
  Future<void> replaceHistory(List<OmnixMessage> messages) async {
    onReplaceHistory?.call();
    _history = List.of(messages);
  }

  @override
  Stream<OmnixConversationEvent> send(
    String prompt, {
    Uint8List? imageBytes,
    Uint8List? audioBytes,
  }) async* {
    onSend?.call();
    if (!sendStarted.isCompleted) sendStarted.complete();
    if (blockUntilStopped) await _sendRelease.future;
    lastImageBytes = imageBytes;
    lastAudioBytes = audioBytes;
    yield OmnixTextDelta(prompt);
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    if (!_sendRelease.isCompleted) _sendRelease.complete();
  }

  @override
  Future<void> close() async {
    closeCalls++;
    if (throwOnClose) throw StateError('close failed');
  }
}

final class _FakeAgentBackend implements OmnixAgentBackend {
  final _FakeAgentSession session = _FakeAgentSession();
  int openCalls = 0;
  OmnixCapabilityRegistrySnapshot? snapshot;

  @override
  Future<OmnixAgentSession> openAgent(
    OmnixAgentConfiguration configuration,
    OmnixCapabilityRegistrySnapshot capabilities,
  ) async {
    openCalls++;
    snapshot = capabilities;
    return session;
  }
}

final class _FakeAgentSession implements OmnixAgentSession {
  int stopCalls = 0;
  int closeCalls = 0;
  int askCalls = 0;
  List<OmnixMessage> _history = [];

  @override
  List<OmnixMessage> get history => List.unmodifiable(_history);

  @override
  Future<void> replaceHistory(List<OmnixMessage> messages) async {
    _history = List.of(messages);
  }

  @override
  Stream<OmnixAgentEvent> ask(String prompt, {Uint8List? imageBytes}) async* {
    askCalls++;
    yield OmnixAgentTextDelta(prompt);
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

final class _FakeModelManager implements OmnixModelManager {
  int initializeCalls = 0;

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> cleanup() async {}

  @override
  Future<void> clearActiveModel() async {}

  @override
  Future<String> getPath(String artifactName) async => artifactName;

  @override
  Future<OmnixModelInstallation> install(
    OmnixModelInstallRequest request, {
    void Function(int progress)? onProgress,
    OmnixCancellationToken? cancellationToken,
  }) async => OmnixModelInstallation(
    artifactName: 'model.litertlm',
    template: request.template,
    format: request.format,
    capabilities: request.capabilities,
  );

  @override
  Future<bool> isInstalled(String artifactName) async => false;

  @override
  Future<List<String>> listInstalled() async => const [];

  @override
  Future<void> uninstall(String artifactName) async {}
}

final class _FakeWorkflowStore implements OmnixWorkflowStore {
  int initializeCalls = 0;
  final Map<String, OmnixWorkflowTask> tasks = {};
  final Map<String, List<OmnixWorkflowEvent>> events = {};

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<List<OmnixWorkflowEvent>> readEvents(String taskId) async =>
      List.unmodifiable(events[taskId] ?? const []);

  @override
  Future<OmnixWorkflowTask?> readTask(String taskId) async => tasks[taskId];

  @override
  Future<List<OmnixWorkflowTask>> readTasks() async =>
      List.unmodifiable(tasks.values);

  @override
  Future<void> persistTransition(
    OmnixWorkflowTask task,
    OmnixWorkflowEvent event,
  ) async {
    tasks[task.id] = task;
    events.putIfAbsent(task.id, () => []).add(event);
  }
}

final class _MessageTextLengthEstimator implements OmnixTokenEstimator {
  const _MessageTextLengthEstimator();

  @override
  int estimateMessage(OmnixMessage message) => message.text.length;

  @override
  int estimateText(String text) => text.length;
}
