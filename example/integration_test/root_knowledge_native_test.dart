// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix/omnix.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'root Knowledge admission, idle reload, visibility and context reopen',
    (tester) async {
      const encoder = String.fromEnvironment('OMNIX_EMBEDDING_MODEL');
      const generationModel = String.fromEnvironment('OMNIX_GENERATION_MODEL');
      // Missing inputs are a failed qualification, never a skipped success.
      expect(
        encoder,
        isNotEmpty,
        reason: 'Supply an existing app-readable embedding bundle.',
      );
      expect(
        generationModel,
        isNotEmpty,
        reason: 'Supply an existing app-readable chat bundle.',
      );
      await tester.runAsync(() async {
        expect(await File(encoder).exists(), isTrue);
        expect(await File(generationModel).exists(), isTrue);
        final directory = await Directory.systemTemp.createTemp(
          'omnix-root-knowledge-',
        );
        OmnixCognitiveEngine? engine;
        OmnixInteractionSession? chat;
        Future<Object>? generation;
        final path = p.join(directory.path, 'index');
        Future<OmnixCognitiveEngine> open(bool create) =>
            OmnixCognitiveEngine.open(
              runtimes: ['litertlm'],
              contextTokens: 2048,
              knowledge: OmnixLocalKnowledge(
                embeddingModel: encoder,
                storePath: path,
                createStore: create,
                threshold: 0,
              ),
              execution: const OmnixExecutionOptions(
                maxWaiting: 1,
                wait: Duration(seconds: 60),
              ),
            );
        Future<void> waitFor(
          bool Function(OmnixExecutionSnapshot) check,
        ) async {
          final deadline = DateTime.now().add(const Duration(seconds: 30));
          while (DateTime.now().isBefore(deadline)) {
            if (check(await engine!.executionSnapshot())) return;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          fail('Expected shared admission state was not observed.');
        }

        try {
          engine = await open(true);
          chat = await engine.startSession(
            modelPath: generationModel,
            maxOutputTokens: 512,
          );
          generation = chat
              .send(
                'Write a detailed numbered list of 100 facts about the oceans.',
              )
              .then<Object>(
                (reply) => reply,
                onError: (Object error, StackTrace _) => error,
              );
          await waitFor((state) => state.active == 1);
          final indexing = engine.indexDocument(
            const OmnixKnowledgeDocument(
              id: 'public',
              documentId: 'manual',
              title: 'Router manual',
              content:
                  'Hold the reset button for ten seconds until the indicator turns blue.',
              public: true,
            ),
          );
          // Attach an error handler immediately; failures must not escape the test.
          final indexed = indexing.then<Object?>(
            (_) => null,
            onError: (Object error, StackTrace _) => error,
          );
          await waitFor((state) => state.waiting == 1);
          expect(
            (await engine.releaseIdleResources()).knowledge,
            OmnixIdleRelease.busy,
          );
          chat.cancelGeneration();
          await generation;
          expect(await indexed, isNull);
          await engine.indexDocument(
            const OmnixKnowledgeDocument(
              id: 'private',
              documentId: 'private',
              title: 'Private note',
              content:
                  'Hold the reset button for ten seconds until the indicator turns blue.',
            ),
          );
          await chat.close();
          chat = await engine.startSession(
            modelPath: generationModel,
            maxOutputTokens: 64,
          );
          final released = await engine.releaseIdleResources();
          expect(released.knowledge, OmnixIdleRelease.released);
          expect(released.retainedChatModels, 1);
          expect(
            (await engine.releaseIdleResources()).knowledge,
            OmnixIdleRelease.alreadyReleased,
          );
          final hits = await engine.retrieveSources(
            'How do I reset the router?',
          );
          expect(hits.map((hit) => hit.title), contains('Router manual'));
          expect(hits.map((hit) => hit.title), isNot(contains('Private note')));
          expect(
            await chat.send(
              'How do I reset the router?',
              knowledge: OmnixKnowledgeUse.required,
            ),
            isNotEmpty,
          );
          expect(
            chat.sources.map((source) => source.title),
            contains('Router manual'),
          );
          final history = await chat.exportHistory();
          await chat.close();
          chat = null;
          await engine.close();
          engine = await open(false);
          expect(
            (await engine.retrieveSources(
              'How do I reset the router?',
            )).map((hit) => hit.title),
            contains('Router manual'),
          );
          chat = await engine.startSession(
            modelPath: generationModel,
            maxOutputTokens: 64,
          );
          await chat.restoreHistory(history);
          expect(await chat.exportHistory(), history);
          expect(await chat.send('Reply only with hello.'), isNotEmpty);
        } finally {
          chat?.cancelGeneration();
          await generation;
          await chat?.close();
          await engine?.close();
          // Only this invocation's disposable index is removed, never installed models.
          await directory.delete(recursive: true);
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
