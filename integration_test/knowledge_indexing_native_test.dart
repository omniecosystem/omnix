import 'dart:async';
import 'dart:io';
import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  final bridge = Platform.environment['OMNIX_SESSION_TEST_BRIDGE'];
  final runtime = Platform.environment['OMNIX_SESSION_TEST_RUNTIME'];
  final model = Platform.environment['OMNIX_SESSION_TEST_MODEL'];
  final encoder = Platform.environment['OMNIX_EMBEDDING2_MODEL'];
  test(
    'root indexing waits for chat and persists with public filtering',
    () async {
      await initializeOmnixSessionLibrary(bridge!);
      final data = await Directory.systemTemp.createTemp(
        'omnix-root-indexing-',
      );
      OmnixCognitiveEngine? engine;
      OmnixInteractionSession? chat;
      Future<String>? generation;
      try {
        final config = OmnixLocalKnowledge(
          embeddingModel: encoder!,
          storePath: data.path,
          createStore: true,
          threshold: 0,
        );
        engine = await OmnixCognitiveEngine.open(
          runtimes: ['litertlm'],
          libraryPath: runtime!,
          knowledge: config,
          execution: const OmnixExecutionOptions(
            maxWaiting: 1,
            wait: Duration(seconds: 30),
          ),
        );
        chat = await engine.startSession(
          modelPath: model!,
          maxOutputTokens: 512,
        );
        generation = chat.send(
          'Write a detailed numbered list of 100 facts about the oceans.',
        );
        final generationResult = generation.then<Object>(
          (value) => value,
          onError: (Object error, StackTrace _) => error,
        );
        Future<void> waitFor(
          bool Function(OmnixExecutionSnapshot) check,
        ) async {
          final deadline = DateTime.now().add(const Duration(seconds: 20));
          while (DateTime.now().isBefore(deadline)) {
            if (check(await engine!.executionSnapshot())) return;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          fail('Expected shared admission state was not observed.');
        }

        await waitFor((snapshot) => snapshot.active == 1);
        final indexing = engine.indexDocument(
          const OmnixKnowledgeDocument(
            id: 'public',
            documentId: 'manual',
            title: 'Router manual',
            content:
                'Hold the router reset button for ten seconds until its indicator turns blue.',
            public: true,
          ),
        );
        final indexingResult = indexing.then<Object?>(
          (_) => null,
          onError: (Object error, StackTrace _) => error,
        );
        await waitFor((snapshot) => snapshot.waiting == 1);
        // The encoder owner is waiting for admission: pressure must not unload it.
        final deferred = await engine.releaseIdleResources();
        expect(deferred.knowledge, OmnixIdleRelease.busy);
        expect(deferred.retainedChatModels, 1);
        chat.cancelGeneration();
        await generationResult;
        expect(await indexingResult, isNull);
        await engine.indexDocument(
          const OmnixKnowledgeDocument(
            id: 'private',
            documentId: 'private',
            title: 'Private note',
            content:
                'Hold the router reset button for ten seconds until its indicator turns blue.',
          ),
        );
        final hits = await engine.retrieveSources('How do I reset the router?');
        expect(hits.map((hit) => hit.title), contains('Router manual'));
        expect(hits.map((hit) => hit.title), isNot(contains('Private note')));
        // Cancellation invalidates the interrupted conversation and releases its
        // model lease. Open a live conversation for the preservation check.
        await chat.close();
        chat = await engine.startSession(modelPath: model, maxOutputTokens: 64);
        final released = await engine.releaseIdleResources();
        expect(released.knowledge, OmnixIdleRelease.released);
        expect(released.retainedChatModels, 1);
        expect(
          (await engine.releaseIdleResources()).knowledge,
          OmnixIdleRelease.alreadyReleased,
        );
        // Keep the index and conversation alive while the native encoder reloads.
        expect(
          (await engine.retrieveSources(
            'How do I reset the router?',
          )).map((hit) => hit.title),
          contains('Router manual'),
        );
        expect(
          (await engine.releaseIdleResources()).knowledge,
          OmnixIdleRelease.released,
        );
        expect(await chat.send('Reply only with hello.'), isNotEmpty);
        expect((await engine.executionSnapshot()).active, 0);
        await chat.close();
        chat = null;
        await engine.close();
        engine = await OmnixCognitiveEngine.open(
          runtimes: ['litertlm'],
          libraryPath: runtime,
          knowledge: OmnixLocalKnowledge(
            embeddingModel: encoder,
            storePath: data.path,
            threshold: 0,
          ),
        );
        expect(
          (await engine.retrieveSources(
            'How do I reset the router?',
          )).map((hit) => hit.title),
          contains('Router manual'),
        );
      } finally {
        chat?.cancelGeneration();
        if (generation != null) {
          try {
            await generation;
          } catch (_) {}
        }
        await chat?.close();
        await engine?.close();
        // Delete only the disposable directory created by this test.
        await data.delete(recursive: true);
      }
    },
    skip: bridge == null || runtime == null || model == null || encoder == null
        ? 'Supply trusted root bridge, packaged runtime and model paths.'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
