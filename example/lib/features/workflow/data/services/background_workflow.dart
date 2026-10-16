import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../home/data/services/device_tools.dart';
import '../repositories/event_task_repository.dart';

const _background = MethodChannel(
  'xyz.omniecosystem.omnix/workflow_background',
);

Future<void> runBackgroundWorkflow() async {
  WidgetsFlutterBinding.ensureInitialized();
  var completed = false;
  try {
    final input = await _background.invokeMapMethod<String, Object?>('input');
    final jobId = input?['jobId'] as String;
    final taskId = input?['taskId'] as String;
    final tools = const ExampleDeviceTools(channel: _background).tools
        .where(
          (tool) => EventTaskRepository.backgroundExecutors.contains(tool.name),
        )
        .toList();
    final repository = EventTaskRepository(
      android: true,
      backgroundTools: tools,
    );
    final saved = await repository.inspection(taskId);
    final tasks = saved['tasks'];
    if (saved['status'] == 'succeeded' && tasks is List && tasks.length == 1) {
      final task = tasks.single as Map;
      // Reload authorization and the plan immediately before execution. Stopping
      // the task prevents the queued worker from dispatching any tool.
      if (task['futureTriggersEnabled'] == true &&
          EventTaskRepository.backgroundCompatible(task['plan']) &&
          (task['jobs'] as List).any((job) => (job as Map)['id'] == jobId)) {
        completed = (await repository.act(jobId, 'runAll')).completed;
      }
    }
  } catch (_) {
    debugPrint(
      '[Omnix][background-workflow] Execution not confirmed; inspect saved job.',
    );
  } finally {
    await _background.invokeMethod<void>('complete', {'succeeded': completed});
  }
}
