// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

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

    test('does not close a conversation twice', () async {
      final conversation = await runtime.openConversation(_configuration);

      await conversation.close();
      await runtime.close();

      expect(backend.conversation.closeCalls, 1);
      expect(engine.closeCalls, 1);
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
  });
}

const _configuration = OmnixConversationConfiguration(
  modelTemplate: OmnixModelTemplate.general,
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
    if (throwOnClose) throw StateError('close failed');
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
  );

  @override
  Future<bool> isInstalled(String artifactName) async => false;

  @override
  Future<List<String>> listInstalled() async => const [];

  @override
  Future<void> uninstall(String artifactName) async {}
}
