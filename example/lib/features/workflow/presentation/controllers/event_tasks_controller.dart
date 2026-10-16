import 'package:flutter/foundation.dart';
import '../../data/repositories/event_task_repository.dart';

class EventTasksController extends ChangeNotifier {
  EventTasksController(this.repository);
  final EventTaskRepository repository;
  List<Map<String, dynamic>> tasks = [];
  List<Map<String, dynamic>> proposals = [];
  List<Map<String, dynamic>> jobs = [];
  int queuedJobs = 0;
  bool busy = false;
  bool _disposed = false;
  String? error;
  String? notice;
  String? activeJob;
  void cancelActive() {
    try {
      repository.cancelActive();
      notice =
          'Cancellation requested. An active tool may finish; effects cannot be undone.';
    } catch (e) {
      error = e.toString();
    }
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    notice = null;
    _changed();
    try {
      await action();
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> _load() async {
    final result = await repository.list();
    proposals = (result['proposals'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    jobs = (result['events'] as List)
        .expand((event) => ((event as Map)['jobs'] as List))
        .cast<Map<String, dynamic>>()
        .toList();
    // This view is a consumer's message simulation, not the engine's task schema.
    tasks = (result['tasks'] as List).map((value) {
      final task = value as Map<String, dynamic>;
      return <String, dynamic>{
        'id': task['id'],
        'enabled': task['enabled'],
        'instructions': task['goal'],
        'sender':
            ((task['trigger'] as Map)['match'] as Map)['sender'] ??
            (task['trigger'] as Map)['kind'],
      };
    }).toList();
    queuedJobs = (result['events'] as List).fold(
      0,
      (count, e) => count + ((e as Map)['jobs'] as List).length,
    );
  }

  Future<void> refresh() => _perform(_load);
  Future<void> accept(String id) => _perform(() async {
    _requireSuccess(await repository.accept(id));
    notice = 'Plan accepted. A matching host event is still required.';
    await _load();
  });
  Future<void> tick() => _perform(() async {
    final result = await repository.tick();
    if (result['status'] != 'ignored') _requireSuccess(result);
    notice = result['status'] == 'ignored'
        ? 'No accepted tick task matched.'
        : 'Tick admitted. Select Run workflow on the queued job below.';
    await _load();
  });
  Future<void> act(String id, String operation) => _perform(() async {
    activeJob = id;
    _changed();
    try {
      final result = await repository.act(id, operation);
      final done = result.steps
          .where((s) => s.state.name == 'succeeded')
          .length;
      final blocked = result.steps
          .where((s) => s.state.name != 'succeeded')
          .firstOrNull;
      notice = result.cancelled
          ? 'Job cancelled. Completed effects are not undone.'
          : result.completed
          ? 'Workflow completed: $done/${result.steps.length} steps confirmed. Review the receipts below.'
          : 'Workflow paused: $done/${result.steps.length} steps confirmed; ${blocked?.id ?? 'job'} is ${blocked?.state.name ?? 'unknown'}.';
    } finally {
      activeJob = null;
      await _load();
    }
  });
  Future<void> stop(String id) => _perform(() async {
    _requireSuccess(await repository.stop(id));
    notice = 'Future triggers stopped. Existing jobs are unchanged.';
    await _load();
  });
  Future<void> simulate(String sender, String text) => _perform(() async {
    final result = await repository.simulate(sender, text);
    if (result['status'] != 'ignored') _requireSuccess(result);
    notice = result['status'] == 'ignored'
        ? 'No enabled subscription matched this exact sender.'
        : 'Message admitted to durable work. Draft execution is not connected yet.';
    await _load();
  });
  void _requireSuccess(Map<String, dynamic> receipt) {
    if (receipt['status'] != 'succeeded') {
      throw StateError(
        receipt['reason'] as String? ??
            'Task operation was not confirmed (${receipt['status']}).',
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
