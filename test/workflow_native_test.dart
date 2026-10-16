// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:io';
import 'package:omnix/omnix.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final library = Platform.environment['OMNIX_WORKFLOW_NATIVE_TEST_DLL'];
  group(
    'real native Workflow bridge',
    () {
      setUpAll(() async {
        await initializeOmnixSessionLibrary(library!);
      });
      late Directory directory;
      setUp(() async {
        directory = await Directory.systemTemp.createTemp(
          'omnix-workflow-test-',
        );
      });
      // Each test exclusively owns this newly created temporary directory.
      tearDown(() async {
        await directory.delete(recursive: true);
      });
      String database() => p.join(directory.path, 'jobs.sqlite');
      OmnixWorkflowDefinition definition({
        Map<String, Object?> arguments = const {},
      }) => OmnixWorkflowDefinition(
        id: 'test-job',
        steps: [
          OmnixWorkflowStep(
            id: 'one',
            tool: 'host_test',
            arguments: arguments,
            retry: OmnixRetrySafety.requiresReconciliation,
          ),
          OmnixWorkflowStep(
            id: 'two',
            tool: 'host_test',
            arguments: {},
            retry: OmnixRetrySafety.safeToRepeat,
          ),
        ],
      );
      OmnixAgentExtensions extensions(
        OmnixToolHandler handler, {
        List<String> grants = const ['host_test'],
        OmnixToolApprovalHandler? approve,
      }) => OmnixAgentExtensions(
        tools: [
          OmnixHostTool(
            name: 'host_test',
            description: 'Workflow qualification',
            parameters: {
              'type': 'object',
              'properties': {},
              'required': [],
              'additionalProperties': false,
            },
            execute: handler,
          ),
        ],
        grants: grants,
        approvalPolicy: approve == null
            ? null
            : OmnixApprovalPolicy(mode: OmnixAutonomyMode.reviewEveryCall),
        approve: approve,
      );

      test(
        'native runner completes ready steps and never replays them',
        () async {
          var calls = 0;
          final job = await OmnixWorkflow.open(
            databasePath: database(),
            definition: definition(),
            extensions: extensions((_) async {
              calls++;
              return {'status': 'succeeded'};
            }),
          );
          try {
            expect((await job.runUntilBlocked()).completed, true);
            expect((await job.runUntilBlocked()).completed, true);
            expect(calls, 2);
          } finally {
            await job.close();
          }
        },
      );
      test(
        'restart skips completed steps and rejects a second owner',
        () async {
          final ids = <String?>[];
          final host = extensions((r) async {
            ids.add(r.callId);
            return {'status': 'succeeded'};
          });
          var job = await OmnixWorkflow.open(
            databasePath: database(),
            definition: definition(),
            extensions: host,
          );
          expect(
            (await job.progress()).steps.first.state,
            OmnixWorkflowStepState.pending,
          );
          await expectLater(
            OmnixWorkflow.open(
              databasePath: database(),
              definition: definition(),
              extensions: host,
            ),
            throwsA(anything),
          );
          await job.runNext();
          await job.close();
          job = await OmnixWorkflow.open(
            databasePath: database(),
            definition: definition(),
            extensions: host,
          );
          expect((await job.runNext()).completed, isTrue);
          expect((await job.runNext()).completed, isTrue);
          expect(ids, ['["test-job","one"]', '["test-job","two"]']);
          await job.close();
          await expectLater(job.progress(), throwsStateError);
        },
      );
      test('invalid schema fails before approval and execution', () async {
        var calls = 0;
        var reviews = 0;
        final job = await OmnixWorkflow.open(
          databasePath: database(),
          definition: definition(arguments: {'extra': 'invalid'}),
          extensions: extensions(
            (_) async {
              calls++;
              return {'status': 'succeeded'};
            },
            approve: (_) async {
              reviews++;
              return true;
            },
          ),
        );
        expect(
          (await job.runNext()).steps.first.state,
          OmnixWorkflowStepState.failed,
        );
        expect(calls, 0);
        expect(reviews, 0);
        await job.close();
      });
      test('refused approval never executes a host action', () async {
        var calls = 0;
        var reviews = 0;
        final job = await OmnixWorkflow.open(
          databasePath: database(),
          definition: definition(),
          extensions: extensions(
            (_) async {
              calls++;
              return {'status': 'succeeded'};
            },
            approve: (_) async {
              reviews++;
              return false;
            },
          ),
        );
        expect(
          (await job.runNext()).steps.first.state,
          OmnixWorkflowStepState.failed,
        );
        expect(calls, 0);
        expect(reviews, 1);
        await job.close();
      });
      test(
        'reopen requires fresh grants rather than persisted permission',
        () async {
          var calls = 0;
          Future<Object?> handler(OmnixToolRequest _) async {
            calls++;
            return {'status': 'succeeded'};
          }

          var job = await OmnixWorkflow.open(
            databasePath: database(),
            definition: definition(),
            extensions: extensions(handler),
          );
          await job.runNext();
          await job.close();
          job = await OmnixWorkflow.open(
            databasePath: database(),
            definition: definition(),
            extensions: extensions(handler, grants: []),
          );
          expect(
            (await job.runNext()).steps.last.state,
            OmnixWorkflowStepState.failed,
          );
          expect(calls, 1);
          await job.close();
        },
      );
      test(
        'uncertain host effect blocks until explicit reconciliation',
        () async {
          var calls = 0;
          final host = extensions((_) async {
            calls++;
            if (calls == 1) throw StateError('Confirmation lost');
            return {'status': 'succeeded'};
          });
          var job = await OmnixWorkflow.open(
            databasePath: database(),
            definition: definition(),
            extensions: host,
          );
          expect(
            (await job.runNext()).steps.first.state,
            OmnixWorkflowStepState.running,
          );
          await job.close();
          job = await OmnixWorkflow.open(
            databasePath: database(),
            definition: definition(),
            extensions: host,
          );
          expect(
            (await job.recover()).steps.first.state,
            OmnixWorkflowStepState.needsReconciliation,
          );
          await expectLater(job.runNext(), throwsA(anything));
          expect(calls, 1);
          await job.reconcile(
            stepId: 'one',
            succeeded: true,
            evidence: {'hostConfirmed': true},
          );
          expect((await job.runNext()).completed, isTrue);
          expect(calls, 2);
          await job.close();
        },
      );
      test('idle cancellation is durable across reopen', () async {
        var calls = 0;
        final host = extensions((_) async {
          calls++;
          return {'status': 'succeeded'};
        });
        var job = await OmnixWorkflow.open(
          databasePath: database(),
          definition: definition(),
          extensions: host,
        );
        job.cancel();
        await job.close();
        job = await OmnixWorkflow.open(
          databasePath: database(),
          definition: definition(),
          extensions: host,
        );
        expect((await job.runNext()).cancelled, isTrue);
        expect(calls, 0);
        await job.close();
      });
      test(
        'active cancellation does not block the bridge or release ownership early',
        () async {
          final started = Completer<void>();
          final result = Completer<Object?>();
          final job = await OmnixWorkflow.open(
            databasePath: database(),
            definition: definition(),
            extensions: extensions((_) async {
              started.complete();
              return result.future;
            }),
          );
          final running = job.runNext();
          await started.future;
          await expectLater(job.close(), throwsA(anything));
          job.cancel();
          final snapshot = await running;
          expect(snapshot.cancelled, isTrue);
          expect(snapshot.steps.first.state, OmnixWorkflowStepState.running);
          result.complete({'status': 'succeeded'});
          await job.close();
        },
      );
    },
    skip: library == null
        ? 'Set OMNIX_WORKFLOW_NATIVE_TEST_DLL to a workflow-local root library.'
        : false,
  );
}
