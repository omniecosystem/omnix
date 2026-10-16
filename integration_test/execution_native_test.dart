import 'dart:async';
import 'dart:io';
import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  final bridge = Platform.environment['OMNIX_SESSION_TEST_BRIDGE'];
  final runtime = Platform.environment['OMNIX_SESSION_TEST_RUNTIME'];
  final model = Platform.environment['OMNIX_SESSION_TEST_MODEL'];
  final skip = bridge == null || runtime == null || model == null
      ? 'Supply existing trusted bridge, runtime and model paths.'
      : false;

  Future<void> waitFor(
    OmnixCognitiveEngine engine,
    bool Function(OmnixExecutionSnapshot) predicate,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      if (predicate(await engine.executionSnapshot())) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Expected native admission state was not observed.');
  }

  test(
    'native waiting cancellation and workflow inference share admission',
    () async {
      await initializeOmnixSessionLibrary(bridge!);
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        libraryPath: runtime!,
        contextTokens: 4096,
        execution: const OmnixExecutionOptions(
          maxWaiting: 1,
          wait: Duration(seconds: 30),
        ),
      );
      final sessions = <OmnixInteractionSession>[];
      OmnixWorkflow? workflow;
      final data = await Directory.systemTemp.createTemp('omnix-admission-');
      Future<String>? interactive;
      try {
        Future<OmnixInteractionSession> open(int budget) async {
          final session = await engine.startSession(
            modelPath: model!,
            maxOutputTokens: budget,
          );
          sessions.add(session);
          return session;
        }

        final home = await open(512);
        final waiting = await open(64);
        final overflow = await open(64);
        final worker = await open(64);
        var toolCalls = 0;
        workflow = await engine.startWorkflow(
          databasePath: '${data.path}${Platform.pathSeparator}workflow.sqlite',
          definition: OmnixWorkflowDefinition(
            id: 'shared-inference',
            steps: [
              OmnixWorkflowStep(
                id: 'answer',
                tool: 'host_infer',
                arguments: {},
                retry: OmnixRetrySafety.safeToRepeat,
              ),
            ],
          ),
          extensions: OmnixAgentExtensions(
            grants: ['host_infer'],
            tools: [
              OmnixHostTool(
                name: 'host_infer',
                description: 'Host-selected inference executor.',
                parameters: {
                  'type': 'object',
                  'properties': <String, Object?>{},
                  'required': <String>[],
                  'additionalProperties': false,
                },
                execute: (_) async {
                  toolCalls++;
                  final answer = await worker.send('Reply with the word OK.');
                  return {'status': 'succeeded', 'answer': answer};
                },
              ),
            ],
          ),
        );
        interactive = home.send(
          'Write a detailed numbered list of 100 facts about the oceans. Do not stop after a short introduction.',
        );
        // Attach error handling immediately; failed native streams are not ignored.
        final homeResult = interactive.then<Object>(
          (s) => s,
          onError: (Object e) => e,
        );
        await waitFor(engine, (s) => s.active == 1);
        final cancelled = waiting.send('Reply with the word CANCELLED.');
        final cancellation = expectLater(
          cancelled,
          throwsA(
            isA<OmnixExecutionException>().having(
              (e) => e.failure,
              'failure',
              OmnixExecutionFailure.cancelled,
            ),
          ),
        );
        await waitFor(engine, (s) => s.waiting == 1);
        await expectLater(
          overflow.send('Reply with the word OVERFLOW.'),
          throwsA(
            isA<OmnixExecutionException>().having(
              (e) => e.failure,
              'failure',
              OmnixExecutionFailure.queueFull,
            ),
          ),
        );
        waiting.cancelGeneration();
        await cancellation;
        await waitFor(engine, (s) => s.active == 1 && s.waiting == 0);
        final run = workflow.runUntilBlocked();
        await waitFor(engine, (s) => s.waiting == 1);
        home.cancelGeneration();
        await homeResult;
        final result = await run;
        expect(toolCalls, 1);
        expect(result.steps.single.state, OmnixWorkflowStepState.succeeded);
        expect((result.steps.single.output as Map)['answer'], isNotEmpty);
        final workerHistory = await worker.exportHistory();
        expect(workerHistory, contains('Reply with the word OK.'));
        expect(workerHistory, isNot(contains('100 facts about the oceans')));
        await waitFor(engine, (s) => s.active == 0 && s.waiting == 0);
      } finally {
        for (final session in sessions) {
          session.cancelGeneration();
        }
        if (interactive != null) {
          try {
            await interactive;
          } catch (_) {}
        }
        await workflow?.close();
        for (final session in sessions) {
          await session.close();
        }
        await engine.close();
        // Only the dedicated disposable directory created by this test is removed.
        await data.delete(recursive: true);
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
