// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  group('OmnixConversationCoordinator', () {
    late _MemoryConversationStore store;
    late _FakeConversation conversation;
    late OmnixRuntime runtime;

    setUp(() {
      store = _MemoryConversationStore();
      conversation = _FakeConversation();
      runtime = OmnixRuntime(
        engine: _FakeEngine(),
        inferenceBackend: _FakeInferenceBackend(conversation),
      );
    });

    tearDown(() async {
      await runtime.close();
    });

    test('creates a record and atomically persists a complete turn', () async {
      conversation.events = const [
        OmnixThinkingDelta('plan '),
        OmnixThinkingDelta('carefully'),
        OmnixToolCall(name: 'clock', arguments: {'zone': 'UTC'}),
        OmnixTextDelta('Hello '),
        OmnixTextDelta('world'),
      ];
      final coordinator = await _open(runtime: runtime, store: store);

      expect(store.initializeCalls, 1);
      expect(store.writeCalls, 1);

      expect(await coordinator.send('What time is it?').toList(), hasLength(5));

      expect(store.writeCalls, 2);
      expect(coordinator.history, hasLength(4));
      expect(coordinator.history[0].text, 'What time is it?');
      expect(coordinator.history[1].kind, OmnixMessageKind.thinking);
      expect(coordinator.history[1].text, 'plan carefully');
      expect(coordinator.history[2].kind, OmnixMessageKind.toolCall);
      expect(coordinator.history[2].toolName, 'clock');
      expect(coordinator.history[2].text, '{"zone":"UTC"}');
      expect(coordinator.history[3].text, 'Hello world');
      expect(coordinator.record.updatedAt, DateTime.utc(2026, 9, 21, 12));
    });

    test('trims active replay without deleting durable history', () async {
      final original = [
        OmnixMessage.text(text: 'old message', role: OmnixMessageRole.user),
        OmnixMessage.text(text: 'new', role: OmnixMessageRole.assistant),
      ];
      store.snapshots['conversation-1'] = OmnixConversationSnapshot(
        record: _record,
        messages: original,
      );
      conversation.events = const [OmnixTextDelta('done')];
      final coordinator = await _open(
        runtime: runtime,
        store: store,
        contextPolicy: const OmnixRecentContextPolicy(
          budget: OmnixContextBudget(
            contextWindowTokens: 8,
            reservedOutputTokens: 0,
          ),
          estimator: _TextLengthEstimator(),
          preserveSystemInformation: false,
        ),
      );

      await coordinator.send('ask').drain<void>();

      expect(conversation.historyWhenSent.map((message) => message.text), [
        'new',
      ]);
      expect(coordinator.lastContextSelection?.omittedMessageCount, 1);
      expect(coordinator.history.map((message) => message.text), [
        'old message',
        'new',
        'ask',
        'done',
      ]);
      expect(
        store.snapshots['conversation-1']!.messages.map(
          (message) => message.text,
        ),
        ['old message', 'new', 'ask', 'done'],
      );
    });

    test('does not persist an incomplete failed turn', () async {
      conversation.errorAfterFirstEvent = StateError('generation failed');
      final coordinator = await _open(runtime: runtime, store: store);

      await expectLater(
        coordinator.send('hello'),
        emitsInOrder([isA<OmnixTextDelta>(), emitsError(isStateError)]),
      );

      expect(store.writeCalls, 1);
      expect(coordinator.history, isEmpty);
      expect(coordinator.isGenerating, isFalse);
    });

    test(
      'persists the visible prompt instead of augmented model input',
      () async {
        final coordinator = await _open(runtime: runtime, store: store);

        await coordinator
            .send(
              'Context: private retrieval\n\nQuestion: Hello',
              durablePrompt: 'Hello',
            )
            .drain<void>();

        expect(coordinator.history.first.text, 'Hello');
        expect(conversation.lastPrompt, contains('private retrieval'));
      },
    );

    test('rejects overlapping turns', () async {
      conversation.block = true;
      final coordinator = await _open(runtime: runtime, store: store);
      final first = coordinator.send('first').drain<void>();
      await conversation.sendStarted.future;

      await expectLater(coordinator.send('second'), emitsError(isStateError));

      conversation.release.complete();
      await first;
      expect(coordinator.history.first.text, 'first');
    });

    test('rejects a configuration for another model template', () async {
      await expectLater(
        OmnixConversationCoordinator.open(
          runtime: runtime,
          store: store,
          record: _record,
          configuration: const OmnixConversationConfiguration(
            modelTemplate: OmnixModelTemplate.gemma4,
          ),
          contextPolicy: _policy,
        ),
        throwsArgumentError,
      );
    });
  });
}

const _configuration = OmnixConversationConfiguration(
  modelTemplate: OmnixModelTemplate.general,
);

final _record = OmnixConversationRecord(
  id: 'conversation-1',
  title: 'Test',
  modelTemplate: OmnixModelTemplate.general,
  createdAt: DateTime.utc(2026, 9, 21),
  updatedAt: DateTime.utc(2026, 9, 21),
);

const _policy = OmnixRecentContextPolicy(
  budget: OmnixContextBudget(
    contextWindowTokens: 1024,
    reservedOutputTokens: 128,
  ),
);

Future<OmnixConversationCoordinator> _open({
  required OmnixRuntime runtime,
  required _MemoryConversationStore store,
  OmnixContextPolicy contextPolicy = _policy,
}) => OmnixConversationCoordinator.open(
  runtime: runtime,
  store: store,
  record: _record,
  configuration: _configuration,
  contextPolicy: contextPolicy,
  now: () => DateTime.utc(2026, 9, 21, 12),
);

final class _MemoryConversationStore implements OmnixConversationStore {
  final Map<String, OmnixConversationSnapshot> snapshots = {};
  int initializeCalls = 0;
  int writeCalls = 0;

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> delete(String conversationId) async {
    snapshots.remove(conversationId);
  }

  @override
  Future<OmnixConversationSnapshot?> read(String conversationId) async =>
      snapshots[conversationId];

  @override
  Future<List<OmnixConversationRecord>> readConversations() async =>
      snapshots.values.map((snapshot) => snapshot.record).toList();

  @override
  Future<void> write(OmnixConversationSnapshot snapshot) async {
    writeCalls++;
    snapshots[snapshot.record.id] = snapshot;
  }
}

final class _FakeEngine implements OmnixEngine {
  @override
  Stream<OmnixEngineEvent> get events => const Stream.empty();

  @override
  OmnixEngineState get state => OmnixEngineState.ready;

  @override
  Future<void> close() async {}

  @override
  Future<OmnixRuntimeInfo> initialize() async => const OmnixRuntimeInfo(
    apiVersion: 1,
    engineName: 'Fake',
    engineVersion: '1',
  );
}

final class _FakeInferenceBackend implements OmnixInferenceBackend {
  _FakeInferenceBackend(this.conversation);

  final _FakeConversation conversation;

  @override
  OmnixInferenceProviderCapabilities get capabilities =>
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
  Future<OmnixConversation> openConversation(
    OmnixConversationConfiguration configuration,
  ) async => conversation;
}

final class _FakeConversation implements OmnixConversation {
  List<OmnixConversationEvent> events = const [OmnixTextDelta('response')];
  List<OmnixMessage> _history = [];
  List<OmnixMessage> historyWhenSent = [];
  Object? errorAfterFirstEvent;
  String? lastPrompt;
  bool block = false;
  final Completer<void> sendStarted = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  List<OmnixMessage> get history => List.unmodifiable(_history);

  @override
  Future<void> replaceHistory(List<OmnixMessage> messages) async {
    _history = List.of(messages);
  }

  @override
  Stream<OmnixConversationEvent> send(
    String prompt, {
    dynamic imageBytes,
    dynamic audioBytes,
  }) async* {
    lastPrompt = prompt;
    historyWhenSent = List.of(_history);
    if (!sendStarted.isCompleted) sendStarted.complete();
    if (block) await release.future;
    for (var index = 0; index < events.length; index++) {
      yield events[index];
      if (index == 0) {
        final error = errorAfterFirstEvent;
        if (error != null) throw error;
      }
    }
  }

  @override
  Future<void> stop() async {
    if (!release.isCompleted) release.complete();
  }

  @override
  Future<void> close() async {
    if (!release.isCompleted) release.complete();
  }
}

final class _TextLengthEstimator implements OmnixTokenEstimator {
  const _TextLengthEstimator();

  @override
  int estimateMessage(OmnixMessage message) => message.text.length;

  @override
  int estimateText(String text) => text.length;
}
