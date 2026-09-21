// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import '../../domain/scheduling/inference_scheduler_snapshot.dart';

/// Non-preemptive priority scheduler for local model work.
/// Chat/Agent has priority, but a running turn is never interrupted.
final class InferenceScheduler {
  /// Process-wide convenience instance for hosts that need one shared queue.
  ///
  /// Hosts may instantiate isolated schedulers when workloads do not share an
  /// inference runtime.
  static final shared = InferenceScheduler();

  final List<_QueuedJob> _pending = [];
  final StreamController<InferenceSchedulerSnapshot> _snapshots =
      StreamController<InferenceSchedulerSnapshot>.broadcast(sync: true);

  bool _pumping = false;
  bool _running = false;
  bool _closed = false;
  int _sequence = 0;
  String? _activeTaskId;
  Completer<void>? _idleCompleter;

  bool get isRunning => _running;
  String? get activeTaskId => _activeTaskId;
  int get pendingCount => _pending.length;

  /// Immutable state updates for hosts that render scheduler activity.
  Stream<InferenceSchedulerSnapshot> get snapshots => _snapshots.stream;

  InferenceSchedulerSnapshot get snapshot => InferenceSchedulerSnapshot(
    isRunning: _running,
    activeTaskId: _activeTaskId,
    pendingCount: _pending.length,
  );

  /// Completes when the running job and every currently queued job finish.
  Future<void> waitForIdle() {
    if (!_running && _pending.isEmpty) return Future.value();
    return (_idleCompleter ??= Completer<void>()).future;
  }

  Future<T> enqueue<T>({
    required String taskId,
    required Future<T> Function() generation,
  }) {
    if (_closed) {
      return Future<T>.error(StateError('Inference scheduler is closed.'));
    }
    final completer = Completer<T>();
    _add(
      _QueuedJob(
        taskId: taskId,
        priority: _priorityFor(taskId),
        sequence: _sequence++,
        run: () async {
          try {
            completer.complete(await generation());
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        },
      ),
    );
    return completer.future;
  }

  Stream<T> enqueueStream<T>({
    required String taskId,
    required Stream<T> Function() generation,
  }) {
    if (_closed) {
      return Stream<T>.error(StateError('Inference scheduler is closed.'));
    }
    final controller = StreamController<T>();
    _add(
      _QueuedJob(
        taskId: taskId,
        priority: _priorityFor(taskId),
        sequence: _sequence++,
        run: () async {
          try {
            await for (final value in generation()) {
              controller.add(value);
            }
            await controller.close();
          } catch (error, stackTrace) {
            controller.addError(error, stackTrace);
            await controller.close();
          }
        },
      ),
    );
    return controller.stream;
  }

  /// Closes an idle scheduler. Running and queued work is never abandoned.
  Future<void> close() async {
    if (_closed) return;
    if (_running || _pending.isNotEmpty) {
      throw StateError(
        'Cannot close an inference scheduler with pending work.',
      );
    }
    _closed = true;
    await _snapshots.close();
  }

  void _add(_QueuedJob job) {
    if (_idleCompleter?.isCompleted ?? false) {
      _idleCompleter = null;
    }
    _idleCompleter ??= Completer<void>();
    _pending.add(job);
    _emitSnapshot();
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_pending.isNotEmpty) {
        _pending.sort((a, b) {
          final priority = b.priority.compareTo(a.priority);
          return priority == 0 ? a.sequence.compareTo(b.sequence) : priority;
        });
        final job = _pending.removeAt(0);
        _running = true;
        _activeTaskId = job.taskId;
        _emitSnapshot();
        try {
          await job.run();
        } finally {
          _running = false;
          _activeTaskId = null;
          _emitSnapshot();
        }
      }
    } finally {
      _pumping = false;
      if (!_running && _pending.isEmpty) {
        final idle = _idleCompleter;
        if (idle != null && !idle.isCompleted) idle.complete();
      }
    }
  }

  int _priorityFor(String taskId) => taskId == 'chat' ? 1 : 0;

  void _emitSnapshot() {
    if (!_snapshots.isClosed) _snapshots.add(snapshot);
  }
}

final class _QueuedJob {
  const _QueuedJob({
    required this.taskId,
    required this.priority,
    required this.sequence,
    required this.run,
  });

  final String taskId;
  final int priority;
  final int sequence;
  final Future<void> Function() run;
}
