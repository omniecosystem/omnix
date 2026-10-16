import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnix/omnix.dart';
import 'package:path/path.dart' as p;
import 'package:omnix_example/features/workflow/data/repositories/event_task_repository.dart';

class RecordingRepository extends EventTaskRepository {
  RecordingRepository(OmnixEventTasks store)
    : super(android: false, taskStore: () async => store);
  final runs = <String>[];
  @override
  Future<OmnixWorkflowProgress> act(String id, String operation) async {
    runs.add(id);
    expect(operation, 'runAll');
    return OmnixWorkflowProgress.decode(
      jsonEncode({
        'version': 2,
        'id': id,
        'cancelled': false,
        'steps': [
          {
            'id': 'read',
            'executor': 'host_time',
            'state': 'Succeeded',
            'output': {
              'value': {'status': 'succeeded', 'utc': 'saved-value'},
            },
          },
        ],
      }),
    );
  }
}

OmnixToolRequest runRequest([String requestId = 'run1']) =>
    OmnixToolRequest.fromJson({
      'requestId': requestId,
      'callId': 'call1',
      'toolName': 'host_execute_event_task',
      'arguments': {'id': 'task1'},
    });

void main() {
  final library = Platform.environment['OMNIX_WORKFLOW_NATIVE_TEST_DLL'];
  setUpAll(() async {
    if (library != null) await initializeOmnixSessionLibrary(library);
  });
  group('One-interaction workflow host tool', () {
    late List<String> operations;
    late Map<String, Object?> task;
    late RecordingRepository repository;
    String? failure;
    Completer<void>? inspectionWait;
    setUp(() {
      operations = [];
      failure = null;
      inspectionWait = null;
      task = {
        'id': 'task1',
        'phase': 'Proposed',
        'plan': [],
        'jobsTotal': 0,
        'jobs': [],
        'jobsOmitted': 0,
        'futureTriggersEnabled': false,
      };
      repository = RecordingRepository(
        OmnixEventTasks(
          databasePath: 'unused',
          dispatch: (_, raw) async {
            final command = jsonDecode(raw) as Map;
            final operation = command['operation'] as String;
            operations.add(operation);
            if (operation == 'inspect') {
              await inspectionWait?.future;
              return jsonEncode({
                'status': 'succeeded',
                'tasks': [task],
              });
            }
            if (operation == failure) return '{"status":"unavailable"}';
            if (operation == 'accept') {
              task['phase'] = 'Accepted';
              task['futureTriggersEnabled'] = true;
              return '{"status":"succeeded","accepted":true,"task":{"id":"task1"}}';
            }
            expect(operation, 'start');
            task['jobsTotal'] = 1;
            task['jobs'] = [
              {'id': 'job1', 'state': 'Completed'},
            ];
            return '{"status":"succeeded","duplicate":false,"jobs":[{"id":"job1"}]}';
          },
        ),
      );
    });

    test(
      'accepts, admits and executes without another model request',
      () async {
        final receipt =
            await repository.executeTaskTool.execute(runRequest()) as Map;
        expect(operations, ['inspect', 'accept', 'start']);
        expect(repository.runs, ['job1']);
        expect(receipt['status'], 'succeeded');
        expect(receipt['completed'], true);
        expect(receipt['steps'][0]['output']['utc'], 'saved-value');
      },
    );
    test('concurrent callback redelivery executes only once', () async {
      await Future.wait([
        repository.executeTaskTool.execute(runRequest()),
        repository.executeTaskTool.execute(runRequest()),
      ]);
      expect(repository.runs, ['job1']);
      expect(operations, ['inspect', 'accept', 'start']);
    });
    test('a new callback does not replay existing completed work', () async {
      await repository.executeTaskTool.execute(runRequest());
      final result =
          await repository.executeTaskTool.execute(runRequest('run2')) as Map;
      expect(result['status'], 'existing_run');
      expect(repository.runs, ['job1']);
      expect(operations.where((op) => op == 'start').length, 1);
    });
    test('resumes one pending job without another admission', () async {
      task.addAll({
        'phase': 'Accepted',
        'futureTriggersEnabled': true,
        'jobsTotal': 1,
        'jobs': [
          {'id': 'old-job', 'state': 'Pending'},
        ],
      });
      await repository.executeTaskTool.execute(runRequest());
      expect(operations, ['inspect']);
      expect(repository.runs, ['old-job']);
    });
    for (final state in [
      'Failed',
      'NeedsReconciliation',
      'RunningCheckpoint',
    ]) {
      test('$state cannot silently become a new execution', () async {
        task.addAll({
          'jobsTotal': 1,
          'jobs': [
            {'id': 'old', 'state': state},
          ],
        });
        final result =
            await repository.executeTaskTool.execute(runRequest()) as Map;
        expect(result['status'], 'existing_run');
        expect(operations, ['inspect']);
        expect(repository.runs, isEmpty);
      });
    }
    for (final operation in ['accept', 'start']) {
      test('$operation failure stops before execution', () async {
        failure = operation;
        final result =
            await repository.executeTaskTool.execute(runRequest()) as Map;
        expect(result['status'], 'unavailable');
        expect(repository.runs, isEmpty);
        if (operation == 'accept') expect(operations, ['inspect', 'accept']);
      });
    }
    test('Stop during inspection prevents acceptance and execution', () async {
      inspectionWait = Completer<void>();
      final result = repository.executeTaskTool.execute(runRequest());
      repository.cancelActive();
      inspectionWait!.complete();
      expect((await result as Map)['status'], 'cancelled');
      expect(operations, ['inspect']);
      expect(repository.runs, isEmpty);
    });
    test('distinct overlapping requests cannot admit two runs', () async {
      inspectionWait = Completer<void>();
      final first = repository.executeTaskTool.execute(runRequest());
      final second =
          await repository.executeTaskTool.execute(runRequest('overlap'))
              as Map;
      expect(second['status'], 'blocked');
      inspectionWait!.complete();
      await first;
      expect(repository.runs, ['job1']);
      expect(operations.where((op) => op == 'start').length, 1);
    });
    test('disabled tasks and omitted plans do not execute', () async {
      task['phase'] = 'Accepted';
      expect(
        (await repository.executeTaskTool.execute(runRequest())
            as Map)['status'],
        'blocked',
      );
      task['phase'] = 'Proposed';
      task['planOmitted'] = true;
      expect(
        (await repository.executeTaskTool.execute(runRequest('second'))
            as Map)['status'],
        'blocked',
      );
      expect(repository.runs, isEmpty);
    });
  });

  test(
    'consumer convenience runs and checkpoints through the real Rust bridge',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'omnix-home-flow-',
      );
      try {
        final store = OmnixEventTasks(
          databasePath: p.join(directory.path, 'tasks.sqlite'),
        );
        final repository = EventTaskRepository(
          android: false,
          taskStore: () async => store,
        );
        final proposed =
            await repository.proposeTool.execute(
                  OmnixToolRequest.fromJson({
                    'requestId': 'proposal',
                    'toolName': 'host_propose_event_task',
                    'arguments': {
                      'goal': 'Read UTC and format the saved value',
                      'triggerJson':
                          '{"source":"simulation","kind":"tick","match":{}}',
                      'planJson':
                          '[{"id":"read","executor":"host_time","input":{}},{"id":"format","executor":"host_format_utc","input":{},"outputBindings":{"utc":{"step":"read","pointer":"/utc"}}}]',
                    },
                  }),
                )
                as Map;
        expect(proposed['status'], 'succeeded');
        final listed = await repository.list();
        final id = listed['proposals'][0]['id'];
        final result =
            await repository.executeTaskTool.execute(
                  OmnixToolRequest.fromJson({
                    'requestId': 'execute',
                    'toolName': 'host_execute_event_task',
                    'arguments': {'id': id},
                  }),
                )
                as Map;
        expect(result['completed'], true);
        expect(
          result['steps'][1]['output']['utc'],
          result['steps'][0]['output']['utc'],
        );
        final saved = await repository.inspection(id as String);
        expect(saved['tasks'][0]['completedJobs'], 1);
        final second =
            await repository.executeTaskTool.execute(
                  OmnixToolRequest.fromJson({
                    'requestId': 'another-call',
                    'toolName': 'host_execute_event_task',
                    'arguments': {'id': id},
                  }),
                )
                as Map;
        expect(second['status'], 'existing_run');
      } finally {
        await directory.delete(recursive: true);
      }
    },
    skip: library == null
        ? 'Set OMNIX_WORKFLOW_NATIVE_TEST_DLL to test native execution.'
        : false,
  );
  for (final allow in [false, true]) {
    test(
      'Rust runner waits for approval and honors Allow=$allow',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'omnix-run-approval-',
        );
        try {
          final store = OmnixEventTasks(
            databasePath: p.join(directory.path, 'tasks.sqlite'),
          );
          final arrived = Completer<void>();
          final decision = Completer<bool>();
          final approvedCalls = <String>[];
          final repository = EventTaskRepository(
            android: false,
            taskStore: () async => store,
            executionPolicy: OmnixApprovalPolicy(
              mode: OmnixAutonomyMode.reviewEveryCall,
            ),
            approve: (request) async {
              approvedCalls.add(request.toolName);
              if (!arrived.isCompleted) arrived.complete();
              return decision.future;
            },
          );
          await store.command({
            'operation': 'propose',
            'contracts': repository.executionContracts,
            'task': {
              'id': 'task1',
              'goal': 'Two clock readings',
              'trigger': {'source': 'simulation', 'kind': 'tick', 'match': {}},
              'plan': [
                {'id': 'one', 'executor': 'host_time', 'input': {}},
                {'id': 'two', 'executor': 'host_time', 'input': {}},
              ],
            },
          });
          var finished = false;
          final running = repository.executeTaskTool.execute(runRequest()).then(
            (value) {
              finished = true;
              return value;
            },
          );
          await arrived.future.timeout(const Duration(seconds: 10));
          expect(finished, false);
          expect(approvedCalls, ['host_time']);
          decision.complete(allow);
          final result = await running as Map;
          expect(result['completed'], allow);
          expect(result['status'], allow ? 'succeeded' : 'blocked');
          expect(approvedCalls.length, allow ? 2 : 1);
          expect(result['steps'][0]['state'], allow ? 'succeeded' : 'failed');
          expect(result['steps'][1]['state'], allow ? 'succeeded' : 'pending');
        } finally {
          await directory.delete(recursive: true);
        }
      },
      skip: library == null ? 'Set OMNIX_WORKFLOW_NATIVE_TEST_DLL.' : false,
    );
  }
}
