import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/workflow/data/repositories/event_task_repository.dart';

void main() {
  test(
    'Home activation uses host contracts and manual starts preserve callback identity',
    () async {
      final commands = <Map<String, dynamic>>[];
      final repository = EventTaskRepository(
        android: false,
        taskStore: () async => OmnixEventTasks(
          databasePath: 'unused',
          dispatch: (_, raw) async {
            commands.add(jsonDecode(raw) as Map<String, dynamic>);
            return '{"status":"succeeded","jobs":[]}';
          },
        ),
      );
      OmnixToolRequest request(String tool) => OmnixToolRequest.fromJson({
        'requestId': 'same-delivery',
        'callId': 'call1',
        'toolName': tool,
        'arguments': {'id': 'saved1'},
      });
      await repository.acceptTool.execute(request('host_accept_event_task'));
      expect(commands.first['contracts'], EventTaskRepository.retryContracts);
      expect(commands.first['schemas'], repository.executionSchemas);
      await repository.startTool.execute(request('host_start_event_task'));
      await repository.startTool.execute(request('host_start_event_task'));
      expect(commands[1], commands[2]);
      expect(commands[1]['operation'], 'start');
      expect(commands[1]['taskId'], 'saved1');
      expect(commands[1].containsKey('source'), false);
    },
  );
  test(
    'execution failures never claim success or leak private paths',
    () async {
      final repository = EventTaskRepository(
        taskStore: () async => throw StateError('C:/private/tasks.sqlite'),
      );
      final result =
          await repository.runTool.execute(
                OmnixToolRequest.fromJson({
                  'requestId': 'run',
                  'toolName': 'host_run_workflow_job',
                  'arguments': {'id': 'job1'},
                }),
              )
              as Map;
      expect(result['status'], 'unavailable');
      expect(result.toString(), isNot(contains('C:/private')));
      expect(result['reason'], contains('do not queue a replacement'));
    },
  );
  test(
    'Android workflow catalogue supplies native recovery contracts only on Android',
    () {
      final android = EventTaskRepository(android: true);
      final portable = EventTaskRepository(android: false);
      expect(android.executionContracts['host_battery_status'], 'SafeToRepeat');
      expect(
        android.executionContracts['host_share_text'],
        'RequiresReconciliation',
      );
      expect(
        android.executionContracts['host_open_app'],
        'RequiresReconciliation',
      );
      expect(
        android.executionTools.map((tool) => tool.name).toSet(),
        android.executionContracts.keys.toSet(),
      );
      expect(portable.executionContracts, EventTaskRepository.retryContracts);
      expect(portable.executionTools.map((tool) => tool.name), [
        'host_time',
        'host_format_utc',
      ]);
      expect(
        portable.proposeTool.description,
        isNot(contains('host_share_text')),
      );
    },
  );
  test(
    'battery sharing fixture binds saved native report, never invented text or retry',
    () {
      final fixture =
          jsonDecode(
                File(
                  'assets/skills/device-report-workflow/examples/battery-to-share.json',
                ).readAsStringSync(),
              )
              as Map;
      final plan = jsonDecode(fixture['planJson'] as String) as List;
      expect(plan[0]['executor'], 'host_battery_status');
      expect(plan[1]['executor'], 'host_share_text');
      expect(plan[1]['input'], isEmpty);
      expect(plan[1]['outputBindings'], {
        'text': {'step': 'battery', 'pointer': '/report'},
      });
      expect(plan.every((step) => !(step as Map).containsKey('retry')), true);
    },
  );
  test(
    'clock-to-format fixture declares saved data flow and formatter uses supplied value',
    () async {
      final arguments =
          jsonDecode(
                File(
                  'assets/skills/workflow-planning/examples/clock-to-format.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final plan = jsonDecode(arguments['planJson'] as String) as List;
      expect(plan[1]['input'], isEmpty);
      expect(plan[1]['outputBindings'], {
        'utc': {'step': 'read', 'pointer': '/utc'},
      });
      final result =
          await EventTaskRepository.formatUtcTool.execute(
                OmnixToolRequest.fromJson({
                  'requestId': 'format',
                  'toolName': 'host_format_utc',
                  'arguments': {'utc': '2025-01-01T00:00:00.000Z'},
                }),
              )
              as Map;
      expect(result['status'], 'succeeded');
      expect(result['utc'], '2025-01-01T00:00:00.000Z');
      expect(result['text'], contains('2025-01-01'));
      final invalid =
          await EventTaskRepository.formatUtcTool.execute(
                OmnixToolRequest.fromJson({
                  'requestId': 'invalid',
                  'toolName': 'host_format_utc',
                  'arguments': {'utc': 'invented'},
                }),
              )
              as Map;
      expect(invalid['status'], 'invalid_arguments');
      expect(invalid['executionStarted'], false);
    },
  );
  test('management tools forward exact IDs and preserve native evidence', () async {
    final commands = <Map<String, dynamic>>[];
    final repository = EventTaskRepository(
      taskStore: () async => OmnixEventTasks(
        databasePath: 'unused',
        dispatch: (_, raw) async {
          final command = jsonDecode(raw) as Map<String, dynamic>;
          commands.add(command);
          if (command['operation'] == 'stop') {
            return '{"status":"succeeded","futureTriggersStopped":true,"existingJobsCancelled":false}';
          }
          return '{"status":"succeeded","tasks":[{"id":"saved1","jobs":[{"state":"Failed","checkpointed":true}]}],"readOnly":true}';
        },
      ),
    );
    final extensions = OmnixAgentExtensions(
      tools: repository.managementTools,
      grants: ['host_inspect_event_tasks', 'host_stop_event_task'],
    );
    final raw = await extensions.executeRequest(
      jsonEncode({
        'requestId': 'inspect',
        'toolName': 'host_inspect_event_tasks',
        'arguments': {'id': 'saved1'},
      }),
    );
    expect(raw, contains('Failed'));
    expect(raw, contains('checkpointed'));
    final stopped =
        await repository.stopTool.execute(
              OmnixToolRequest.fromJson({
                'requestId': 'stop',
                'toolName': 'host_stop_event_task',
                'arguments': {'id': 'saved1'},
              }),
            )
            as Map;
    expect(stopped['existingJobsCancelled'], false);
    expect(commands, [
      {'operation': 'inspect', 'id': 'saved1'},
      {'operation': 'stop', 'id': 'saved1'},
    ]);
  });
  test(
    'management service failures never invent confirmation or echo paths',
    () async {
      final repository = EventTaskRepository(
        taskStore: () async => throw StateError('C:/private/tasks.sqlite'),
      );
      for (final tool in repository.managementTools) {
        final receipt =
            await tool.execute(
                  OmnixToolRequest.fromJson({
                    'requestId': 'error',
                    'toolName': tool.name,
                    'arguments': {'id': 'saved1'},
                  }),
                )
                as Map;
        expect(receipt['status'], 'unavailable');
        expect(receipt.toString(), isNot(contains('C:/private')));
        expect(receipt.containsKey('futureTriggersStopped'), false);
      }
    },
  );
  test('skill example supplies plans while host supplies retry metadata', () async {
    final arguments =
        jsonDecode(
              File(
                'assets/skills/workflow-planning/examples/two-clock-reads.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    Map<String, dynamic>? submitted;
    final repository = EventTaskRepository(
      android: false,
      taskStore: () async => OmnixEventTasks(
        databasePath: 'unused',
        dispatch: (_, raw) async {
          submitted = jsonDecode(raw) as Map<String, dynamic>;
          return '{"status":"succeeded","accepted":false,"executionStarted":false}';
        },
      ),
    );
    final result =
        await repository.proposeTool.execute(
              OmnixToolRequest.fromJson({
                'requestId': 'fixture',
                'toolName': 'host_propose_event_task',
                'arguments': arguments,
              }),
            )
            as Map;
    expect(result['status'], 'succeeded');
    expect(submitted!['contracts'], EventTaskRepository.retryContracts);
    expect(submitted!['schemas'], repository.executionSchemas);
    final steps = (submitted!['task'] as Map)['plan'] as List;
    expect(steps.length, 2);
    expect(steps.every((step) => !(step as Map).containsKey('retry')), true);
    final skill = File(
      'assets/skills/workflow-planning/SKILL.md',
    ).readAsStringSync();
    final documented = skill.split('```json\n')[1].split('```')[0];
    expect(jsonDecode(documented), arguments);
  });
  OmnixToolRequest request() => OmnixToolRequest.fromJson({
    'requestId': '1',
    'toolName': 'host_propose_event_task',
    'arguments': {
      'goal': 'Read clock',
      'triggerJson': '{"source":"simulation","kind":"tick","match":{}}',
      'planJson': '[{"id":"one","executor":"host_time","input":{}}]',
    },
  });
  test('native validation feedback reaches the agent unchanged', () async {
    final repository = EventTaskRepository(
      taskStore: () async => OmnixEventTasks(
        databasePath: 'unused',
        dispatch: (_, _) async =>
            '{"status":"invalid_arguments","code":"TASK_PROPOSAL_INVALID","reason":"plan[0].retry must be SafeToRepeat or RequiresReconciliation."}',
      ),
    );
    final extensions = OmnixAgentExtensions(
      tools: [repository.proposeTool],
      grants: ['host_propose_event_task'],
    );
    final raw = await extensions.executeRequest(
      '{"requestId":"1","toolName":"host_propose_event_task","arguments":'
      '{"goal":"Read clock","triggerJson":"{}","planJson":"[]"}}',
    );
    expect(raw, contains('invalid_arguments'));
    expect(raw, contains('plan[0].retry'));
    expect(raw, isNot(contains('Host tool failed')));
  });
  test(
    'service failures remain distinct and never echo private errors',
    () async {
      final repository = EventTaskRepository(
        taskStore: () async =>
            throw StateError('C:/private/account/model.sqlite'),
      );
      final result = await repository.proposeTool.execute(request()) as Map;
      expect(result['status'], 'unavailable');
      expect(result['code'], 'TASK_PROPOSAL_SERVICE_UNAVAILABLE');
      expect(result.toString(), isNot(contains('C:/private')));
    },
  );
  test(
    'malformed proposed JSON returns repair feedback before opening storage',
    () async {
      final result = await EventTaskRepository().proposeTool.execute(
        OmnixToolRequest.fromJson({
          'requestId': '1',
          'toolName': 'host_propose_event_task',
          'arguments': {
            'goal': 'Read clock',
            'triggerJson': '{',
            'planJson': '[]',
          },
        }),
      );
      expect(result, isA<Map>());
      expect((result as Map)['status'], 'invalid_arguments');
      expect(result['reason'], contains('No plan was saved'));
    },
  );
  test(
    'example clock returns explicit host success rather than model prose',
    () async {
      final result = await EventTaskRepository.clockTool.execute(
        OmnixToolRequest.fromJson({
          'requestId': '1',
          'toolName': 'host_time',
          'arguments': <String, Object?>{},
        }),
      );
      expect((result as Map)['status'], 'succeeded');
      expect(DateTime.parse(result['utc'] as String).isUtc, true);
    },
  );
}
