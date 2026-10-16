import 'package:flutter_test/flutter_test.dart';
import 'package:omnix/omnix.dart';
import 'dart:convert';
import 'package:omnix_example/features/workflow/data/repositories/event_task_repository.dart';
import 'package:omnix_example/features/workflow/presentation/controllers/event_tasks_controller.dart';

class ReceiptRepository extends EventTaskRepository {
  String stepState = 'Succeeded';
  String? operation;
  @override
  Future<OmnixWorkflowProgress> act(String id, String operation) async {
    this.operation = operation;
    return OmnixWorkflowProgress.decode(
      jsonEncode({
        'version': 1,
        'id': id,
        'cancelled': false,
        'steps': [
          {
            'id': 'one',
            'executor': 'host_test',
            'state': stepState,
            'output': null,
          },
        ],
      }),
    );
  }

  Map<String, dynamic> receipt = {
    'status': 'invalid_arguments',
    'reason': 'Contract changed',
  };
  @override
  Future<Map<String, dynamic>> accept(String id) async => receipt;
  @override
  Future<Map<String, dynamic>> tick() async => receipt;
  @override
  Future<Map<String, dynamic>> stop(String id) async => receipt;
  @override
  Future<Map<String, dynamic>> list() async => {
    'proposals': [],
    'events': [],
    'tasks': [],
  };
}

void main() {
  test(
    'runner outcomes report completion or pause from native state only',
    () async {
      final repository = ReceiptRepository();
      final controller = EventTasksController(repository);
      addTearDown(controller.dispose);
      await controller.act('job', 'runAll');
      expect(repository.operation, 'runAll');
      expect(controller.notice, contains('Workflow completed: 1/1'));
      for (final state in ['Failed', 'Running', 'NeedsReconciliation']) {
        repository.stepState = state;
        await controller.act('job', 'runAll');
        expect(controller.notice, contains('Workflow paused: 0/1'));
        expect(controller.activeJob, isNull);
        expect(controller.busy, false);
      }
    },
  );
  test('rejected receipts cannot appear as accepted or admitted', () async {
    final repository = ReceiptRepository();
    final controller = EventTasksController(repository);
    addTearDown(controller.dispose);
    await controller.accept('job');
    expect(controller.error, contains('Contract changed'));
    expect(controller.notice, isNull);
    await controller.tick();
    expect(controller.error, contains('Contract changed'));
    expect(controller.notice, isNull);
    await controller.stop('job');
    expect(controller.notice, isNull);
    repository.receipt = {'status': 'succeeded'};
    await controller.accept('job');
    expect(controller.error, isNull);
    expect(controller.notice, contains('Plan accepted'));
  });
}
