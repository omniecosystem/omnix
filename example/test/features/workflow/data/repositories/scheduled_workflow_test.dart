import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/home/data/services/device_tools.dart';
import 'package:omnix_example/features/workflow/data/repositories/event_task_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('xyz.omniecosystem.omnix/agent_host');
  final native = <MethodCall>[];
  setUp(() {
    native.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          native.add(call);
          return {'status': 'scheduled'};
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  OmnixToolRequest request(int delay) => OmnixToolRequest.fromJson({
    'requestId': 'schedule1',
    'callId': 'call1',
    'toolName': 'host_schedule_event_task',
    'arguments': {'id': 'task1', 'delaySeconds': delay},
  });
  final plan = [
    {
      'id': 'read',
      'executor': 'host_battery_status',
      'input': <String, Object?>{},
    },
    {
      'id': 'notify',
      'executor': 'host_notify_text',
      'input': <String, Object?>{},
      'outputBindings': {
        'text': {'step': 'read', 'pointer': '/report'},
      },
    },
  ];
  test('background catalogue excludes UI and scopes execution grants', () {
    expect(EventTaskRepository.backgroundCompatible(plan), true);
    expect(
      EventTaskRepository.backgroundCompatible([
        {'executor': 'host_share_text'},
      ]),
      false,
    );
    expect(EventTaskRepository.backgroundCompatible([]), false);
    final tools = const ExampleDeviceTools().tools
        .where(
          (tool) => EventTaskRepository.backgroundExecutors.contains(tool.name),
        )
        .toList();
    expect(
      EventTaskRepository(
        android: true,
        backgroundTools: tools,
      ).executionContracts.keys.toSet(),
      EventTaskRepository.backgroundExecutors,
    );
  });
  test(
    'delayed request accepts then admits once without running tools',
    () async {
      final operations = <String>[];
      final repository = EventTaskRepository(
        android: true,
        taskStore: () async => OmnixEventTasks(
          databasePath: 'unused',
          dispatch: (_, raw) async {
            final command = jsonDecode(raw) as Map;
            operations.add(command['operation'] as String);
            return jsonEncode(switch (command['operation']) {
              'inspect' => {
                'status': 'succeeded',
                'tasks': [
                  {'phase': 'Proposed', 'plan': plan, 'jobsTotal': 0},
                ],
              },
              'start' => {
                'status': 'succeeded',
                'jobs': [
                  {'id': 'job1'},
                ],
              },
              _ => {'status': 'succeeded'},
            });
          },
        ),
      );
      final result = await repository.scheduleTool.execute(request(60)) as Map;
      expect(result['status'], 'scheduled');
      expect(operations, ['inspect', 'accept', 'start']);
      expect(native.single.method, 'scheduleWorkflow');
      expect(native.single.arguments, {
        'taskId': 'task1',
        'jobId': 'job1',
        'delaySeconds': 60,
      });
    },
  );
  test(
    'invalid delay and interactive review do not reach storage or Android',
    () async {
      final repository = EventTaskRepository(
        android: true,
        executionPolicy: OmnixApprovalPolicy(
          mode: OmnixAutonomyMode.reviewEveryCall,
        ),
        taskStore: () async => throw StateError('Must not admit'),
      );
      expect(
        (await repository.scheduleTool.execute(request(1)) as Map)['status'],
        'invalid_arguments',
      );
      expect(
        (await repository.scheduleTool.execute(request(60)) as Map)['status'],
        'blocked',
      );
      expect(native, isEmpty);
    },
  );
}
