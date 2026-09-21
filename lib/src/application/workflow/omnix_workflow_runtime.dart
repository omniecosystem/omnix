// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import '../../domain/workflow/omnix_workflow_event.dart';
import '../../domain/workflow/omnix_workflow_executor.dart';
import '../../domain/workflow/omnix_workflow_store.dart';
import '../../domain/workflow/omnix_workflow_task.dart';
import '../scheduling/inference_scheduler.dart';

/// Coordinates durable workflow execution through the shared inference queue.
final class OmnixWorkflowRuntime {
  factory OmnixWorkflowRuntime({
    required OmnixWorkflowStore store,
    required InferenceScheduler scheduler,
    required Iterable<OmnixWorkflowExecutor> executors,
    DateTime Function()? now,
  }) {
    return OmnixWorkflowRuntime._(store, scheduler, {
      for (final executor in executors) executor.kind: executor,
    }, now ?? DateTime.now);
  }

  OmnixWorkflowRuntime._(
    this._store,
    this._scheduler,
    this._executors,
    this._now,
  );

  final OmnixWorkflowStore _store;
  final InferenceScheduler _scheduler;
  final Map<String, OmnixWorkflowExecutor> _executors;
  final DateTime Function() _now;
  final StreamController<OmnixWorkflowEvent> _events =
      StreamController<OmnixWorkflowEvent>.broadcast(sync: true);
  final Map<String, OmnixWorkflowCancellationToken> _cancellations = {};
  final Map<String, Future<void>> _scheduled = {};

  bool _initialized = false;
  bool _closed = false;

  Stream<OmnixWorkflowEvent> get events => _events.stream;

  /// Opens the store and resumes tasks interrupted by a previous process.
  Future<void> initialize() async {
    _ensureOpen();
    if (_initialized) return;
    await _store.initialize();
    _initialized = true;
    final tasks = await _store.readTasks();
    for (final task in tasks) {
      if (task.status == OmnixWorkflowTaskStatus.running) {
        final recovered = task.copyWith(
          status: OmnixWorkflowTaskStatus.queued,
          updatedAt: _now(),
          clearError: true,
        );
        await _transition(
          recovered,
          OmnixWorkflowEventKind.recovered,
          'Interrupted task recovered and queued.',
        );
        _schedule(recovered.id);
      } else if (task.status == OmnixWorkflowTaskStatus.queued) {
        _schedule(task.id);
      }
    }
  }

  Future<OmnixWorkflowTask> createTask({
    required String id,
    required String kind,
    required String title,
    String? description,
    Map<String, Object?> input = const {},
    int maxAttempts = 1,
  }) async {
    _ensureInitialized();
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id');
    }
    if (kind.trim().isEmpty) throw ArgumentError.value(kind, 'kind');
    if (title.trim().isEmpty) throw ArgumentError.value(title, 'title');
    if (maxAttempts < 1) {
      throw ArgumentError.value(
        maxAttempts,
        'maxAttempts',
        'Must be positive.',
      );
    }
    if (await _store.readTask(id) != null) {
      throw StateError('Workflow task "$id" already exists.');
    }
    final timestamp = _now();
    final task = OmnixWorkflowTask(
      id: id,
      kind: kind,
      title: title.trim(),
      description: description?.trim(),
      input: input,
      status: OmnixWorkflowTaskStatus.queued,
      attempt: 0,
      maxAttempts: maxAttempts,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    await _transition(task, OmnixWorkflowEventKind.queued, 'Task queued.');
    _schedule(task.id);
    return task;
  }

  Future<void> cancel(String taskId) async {
    _ensureInitialized();
    final task = await _store.readTask(taskId);
    if (task == null) {
      throw StateError('Workflow task "$taskId" was not found.');
    }
    if (task.isTerminal) {
      return;
    }
    _cancellations
        .putIfAbsent(taskId, OmnixWorkflowCancellationToken.new)
        .cancel();
    await _transition(
      task.copyWith(
        status: OmnixWorkflowTaskStatus.cancelled,
        updatedAt: _now(),
      ),
      OmnixWorkflowEventKind.cancelled,
      'Task cancelled.',
    );
  }

  Future<void> waitForIdle() async {
    while (_scheduled.isNotEmpty) {
      await Future.wait(_scheduled.values.toList(growable: false));
    }
  }

  Future<void> close() async {
    if (_closed) return;
    await waitForIdle();
    _closed = true;
    await _events.close();
  }

  void _schedule(String taskId) {
    if (_closed || _scheduled.containsKey(taskId)) return;
    final execution = _scheduler
        .enqueue<bool>(taskId: taskId, generation: () => _executeOne(taskId))
        .then((retry) async {
          _scheduled.remove(taskId);
          if (retry && !_closed) _schedule(taskId);
        });
    _scheduled[taskId] = execution;
  }

  Future<bool> _executeOne(String taskId) async {
    final queued = await _store.readTask(taskId);
    if (queued == null || queued.status != OmnixWorkflowTaskStatus.queued) {
      return false;
    }
    final token = _cancellations.putIfAbsent(
      taskId,
      OmnixWorkflowCancellationToken.new,
    );
    if (token.isCancelled) return false;

    final executor = _executors[queued.kind];
    if (executor == null) {
      await _fail(
        queued,
        'No workflow executor is registered for ${queued.kind}.',
      );
      return false;
    }

    var running = queued.copyWith(
      status: OmnixWorkflowTaskStatus.running,
      attempt: queued.attempt + 1,
      updatedAt: _now(),
      clearError: true,
    );
    await _transition(
      running,
      OmnixWorkflowEventKind.started,
      'Task processing started.',
    );

    String? output;
    try {
      await for (final update in executor.execute(running, token)) {
        token.throwIfCancelled();
        switch (update) {
          case OmnixWorkflowProgress(:final message, :final data):
            await _transition(
              running.copyWith(updatedAt: _now()),
              OmnixWorkflowEventKind.progress,
              message,
              data: data,
            );
          case OmnixWorkflowResult(output: final result):
            output = result;
        }
      }
      token.throwIfCancelled();
      running = running.copyWith(
        status: OmnixWorkflowTaskStatus.completed,
        updatedAt: _now(),
        output: output,
        clearError: true,
      );
      await _transition(
        running,
        OmnixWorkflowEventKind.completed,
        'Task processing completed.',
      );
      _cancellations.remove(taskId);
      return false;
    } on OmnixWorkflowCancelledException {
      final latest = await _store.readTask(taskId);
      if (latest != null &&
          latest.status != OmnixWorkflowTaskStatus.cancelled) {
        await _transition(
          latest.copyWith(
            status: OmnixWorkflowTaskStatus.cancelled,
            updatedAt: _now(),
          ),
          OmnixWorkflowEventKind.cancelled,
          'Task cancelled.',
        );
      }
      return false;
    } catch (error) {
      if (running.attempt < running.maxAttempts) {
        await _transition(
          running.copyWith(
            status: OmnixWorkflowTaskStatus.queued,
            updatedAt: _now(),
            error: error.toString(),
          ),
          OmnixWorkflowEventKind.retryScheduled,
          'Task attempt failed; retry queued.',
          data: {'error': error.toString(), 'attempt': running.attempt},
        );
        return true;
      }
      await _fail(running, error.toString());
      _cancellations.remove(taskId);
      return false;
    }
  }

  Future<void> _fail(OmnixWorkflowTask task, String error) {
    return _transition(
      task.copyWith(
        status: OmnixWorkflowTaskStatus.failed,
        updatedAt: _now(),
        error: error,
      ),
      OmnixWorkflowEventKind.failed,
      'Task failed.',
      data: {'error': error},
    );
  }

  Future<void> _transition(
    OmnixWorkflowTask task,
    OmnixWorkflowEventKind kind,
    String message, {
    Map<String, Object?> data = const {},
  }) async {
    final event = OmnixWorkflowEvent(
      taskId: task.id,
      kind: kind,
      timestamp: task.updatedAt,
      message: message,
      data: data,
    );
    await _store.persistTransition(task, event);
    if (!_events.isClosed) _events.add(event);
  }

  void _ensureInitialized() {
    _ensureOpen();
    if (!_initialized) {
      throw StateError('Workflow runtime has not been initialized.');
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Workflow runtime is closed.');
  }
}
