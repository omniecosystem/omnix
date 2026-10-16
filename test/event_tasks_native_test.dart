// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'dart:io';
import 'package:omnix/omnix.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  setUpAll(() async {
    final library = Platform.environment['OMNIX_WORKFLOW_NATIVE_TEST_DLL'];
    if (library != null) await initializeOmnixSessionLibrary(library);
  });
  test(
    'manual start runs only the selected accepted plan through the native bridge',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'omnix-manual-run-',
      );
      try {
        final tasks = OmnixEventTasks(
          databasePath: p.join(directory.path, 'tasks.sqlite'),
        );
        for (final id in ['chosen', 'other']) {
          await tasks.command({
            'operation': 'propose',
            'contracts': {'host_test': 'SafeToRepeat'},
            'task': {
              'id': id,
              'goal': 'Read a host value',
              'trigger': {'source': 'simulation', 'kind': 'tick', 'match': {}},
              'plan': [
                {'id': 'read', 'executor': 'host_test', 'input': {}},
              ],
            },
          });
          await tasks.command({
            'operation': 'accept',
            'id': id,
            'contracts': {'host_test': 'SafeToRepeat'},
          });
        }
        final request = {
          'operation': 'start',
          'id': 'run1',
          'taskId': 'chosen',
        };
        final receipt = await tasks.command(request);
        expect(receipt['jobs'], hasLength(1));
        expect((await tasks.command(request))['duplicate'], true);
        await expectLater(
          tasks.command({
            'operation': 'event',
            'id': 'run1',
            'source': 'simulation',
            'kind': 'tick',
            'metadata': {},
            'payload': {},
          }),
          throwsA(contains('Job identity already belongs to another event')),
        );
        var calls = 0;
        final owner = await tasks.openJob(
          id: receipt['jobs'][0]['id'] as String,
          extensions: OmnixAgentExtensions(
            tools: [
              OmnixHostTool(
                name: 'host_test',
                description: 'Read host value',
                parameters: {
                  'type': 'object',
                  'properties': {},
                  'required': [],
                  'additionalProperties': false,
                },
                execute: (_) async {
                  calls++;
                  return {'status': 'succeeded', 'value': 42};
                },
              ),
            ],
            grants: ['host_test'],
            approvalPolicy: OmnixApprovalPolicy(
              mode: OmnixAutonomyMode.scopedAssistance,
              automaticTools: ['host_test'],
            ),
          ),
        );
        try {
          expect((await owner.runUntilBlocked()).completed, true);
          expect((await owner.runUntilBlocked()).completed, true);
        } finally {
          await owner.close();
        }
        expect(calls, 1);
        final other = await tasks.command({
          'operation': 'inspect',
          'id': 'other',
        });
        expect(other['tasks'][0]['jobs'], isEmpty);
        await tasks.command({'operation': 'stop', 'id': 'chosen'});
        await expectLater(
          tasks.command({
            'operation': 'start',
            'id': 'run2',
            'taskId': 'chosen',
          }),
          throwsA(anything),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
    skip: Platform.environment['OMNIX_WORKFLOW_NATIVE_TEST_DLL'] == null
        ? 'Set native test library.'
        : false,
  );
  final library = Platform.environment['OMNIX_WORKFLOW_NATIVE_TEST_DLL'];
  test(
    'real bridge accepts proposals, runs authorized jobs and resumes evidence',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'omnix-event-task-test-',
      );
      try {
        final path = p.join(root.path, 'tasks.sqlite');
        var tasks = OmnixEventTasks(databasePath: path);
        final invalid = await tasks.command({
          'operation': 'propose',
          'task': {
            'id': 'invalid',
            'goal': 'Private goal not for logs',
            'trigger': {'source': 'host', 'kind': 'signal', 'match': {}},
            'plan': [
              {'id': 'one', 'executor': 'host_inspect', 'input': {}},
            ],
          },
        });
        expect(invalid['status'], 'invalid_arguments');
        expect(invalid['reason'], contains('plan[0].retry'));
        expect(invalid.toString(), isNot(contains('Private goal')));
        expect(await File(path).exists(), false);
        final result = await tasks.command({
          'operation': 'propose',
          'contracts': {'host_inspect': 'SafeToRepeat'},
          'task': {
            'id': 'watch1',
            'goal': 'Inspect a resource event',
            'trigger': {
              'source': 'host',
              'kind': 'signal',
              'match': {'resource': 'A'},
            },
            'plan': [
              {
                'id': 'inspect',
                'executor': 'host_inspect',
                'input': {},
                'bindings': {'sample': '/payload/value'},
              },
              {
                'id': 'inspect-again',
                'executor': 'host_inspect',
                'input': {},
                'outputBindings': {
                  'sample': {'step': 'inspect', 'pointer': '/sample'},
                },
              },
            ],
          },
        });
        expect(result['executionStarted'], false);
        expect(result['accepted'], false);
        expect(result['proposal']['plan'][0]['retry'], 'SafeToRepeat');
        expect((await tasks.command({'operation': 'list'}))['tasks'], isEmpty);
        await tasks.command({
          'operation': 'accept',
          'id': 'watch1',
          'contracts': {'host_inspect': 'SafeToRepeat'},
        });
        tasks = OmnixEventTasks(databasePath: path);
        expect(
          (await tasks.command({'operation': 'list'}))['tasks'],
          hasLength(1),
        );
        final event = {
          'operation': 'event',
          'id': 'event1',
          'source': 'host',
          'kind': 'signal',
          'metadata': {'resource': 'A'},
          'payload': {'value': 42},
        };
        expect(
          (await tasks.command({
            ...event,
            'metadata': {'resource': 'B'},
          }))['status'],
          'ignored',
        );
        final admitted = await tasks.command(event);
        expect(admitted['jobs'], hasLength(1));
        final jobId = (admitted['jobs'] as List).single['id'] as String;
        var calls = 0;
        final extensions = OmnixAgentExtensions(
          tools: [
            OmnixHostTool(
              name: 'host_inspect',
              description: 'Inspect a sample.',
              parameters: {
                'type': 'object',
                'properties': {
                  'sample': {'type': 'integer'},
                },
                'required': ['sample'],
                'additionalProperties': false,
              },
              execute: (request) async {
                calls++;
                expect(request.arguments['sample'], 42);
                return {'status': 'succeeded', 'sample': 42};
              },
            ),
          ],
          grants: ['host_inspect'],
          approvalPolicy: OmnixApprovalPolicy(
            mode: OmnixAutonomyMode.scopedAssistance,
            automaticTools: ['host_inspect'],
          ),
        );
        var owner = await tasks.openJob(id: jobId, extensions: extensions);
        try {
          final progress = await owner.runNext();
          expect(progress.completed, false);
          expect(progress.steps.first.output, {
            'status': 'succeeded',
            'sample': 42,
          });
        } finally {
          await owner.close();
        }
        expect(calls, 1);
        final partial = await tasks.command({
          'operation': 'inspect',
          'id': 'watch1',
        });
        expect(partial['tasks'][0]['jobs'][0]['state'], 'Pending');
        expect(partial['tasks'][0]['jobs'][0]['checkpointed'], true);
        expect(
          partial['tasks'][0]['jobs'][0]['steps'][0]['output']['sample'],
          42,
        );
        expect((await tasks.command(event))['duplicate'], true);
        owner = await tasks.openJob(id: jobId, extensions: extensions);
        try {
          expect((await owner.runNext()).completed, true);
        } finally {
          await owner.close();
        }
        expect(
          calls,
          2,
          reason: 'Redelivery and reopen must not replay completed work.',
        );
        owner = await tasks.openJob(id: jobId, extensions: extensions);
        try {
          expect((await owner.runNext()).completed, true);
        } finally {
          await owner.close();
        }
        expect(calls, 2, reason: 'A completed job must not execute again.');
        final completed = await tasks.command({
          'operation': 'inspect',
          'id': 'watch1',
        });
        expect(completed['tasks'][0]['completedJobs'], 1);
        expect(completed['tasks'][0]['jobs'][0]['state'], 'Completed');
        expect(completed['tasks'][0]['futureTriggersEnabled'], true);
        final catalogue = await tasks.command({'operation': 'list'});
        expect(
          catalogue['events'][0]['jobs'][0]['steps'][0]['state'],
          'Succeeded',
        );
        await expectLater(
          tasks.command({
            ...event,
            'payload': {'value': 43},
          }),
          throwsA(contains('Event identity reused with different content')),
        );
        final stopped = await tasks.command({
          'operation': 'stop',
          'id': 'watch1',
        });
        expect(stopped['futureTriggersStopped'], true);
        expect(stopped['existingJobsCancelled'], false);
        final afterStop = await tasks.command({
          'operation': 'inspect',
          'id': 'watch1',
        });
        expect(afterStop['tasks'][0]['jobs'], completed['tasks'][0]['jobs']);
        expect(afterStop['tasks'][0]['futureTriggersEnabled'], false);
        expect(
          (await tasks.command({...event, 'id': 'event2'}))['status'],
          'ignored',
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
    skip: library == null
        ? 'Set OMNIX_WORKFLOW_NATIVE_TEST_DLL to qualify the real bridge.'
        : false,
  );
}
