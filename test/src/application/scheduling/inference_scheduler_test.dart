import 'dart:async';

import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  group('InferenceScheduler', () {
    late InferenceScheduler scheduler;

    setUp(() {
      scheduler = InferenceScheduler();
    });

    tearDown(() async {
      await scheduler.close();
    });

    test('does not preempt a running task and prioritizes chat next', () async {
      final releaseFirstTask = Completer<void>();
      final firstTaskStarted = Completer<void>();
      final execution = <String>[];

      final firstTask = scheduler.enqueue<void>(
        taskId: 'task-1',
        generation: () async {
          execution.add('task-1:start');
          firstTaskStarted.complete();
          await releaseFirstTask.future;
          execution.add('task-1:end');
        },
      );
      await firstTaskStarted.future;

      final secondTask = scheduler.enqueue<void>(
        taskId: 'task-2',
        generation: () async {
          execution.add('task-2');
        },
      );
      final chat = scheduler.enqueue<void>(
        taskId: 'chat',
        generation: () async {
          execution.add('chat');
        },
      );

      expect(execution, ['task-1:start']);
      expect(scheduler.activeTaskId, 'task-1');
      expect(scheduler.pendingCount, 2);

      releaseFirstTask.complete();
      await Future.wait([firstTask, secondTask, chat]);

      expect(execution, ['task-1:start', 'task-1:end', 'chat', 'task-2']);
      expect(scheduler.isRunning, isFalse);
      expect(scheduler.activeTaskId, isNull);
      expect(scheduler.pendingCount, 0);
    });

    test('keeps FIFO order among jobs with the same priority', () async {
      final releaseFirstTask = Completer<void>();
      final firstTaskStarted = Completer<void>();
      final execution = <String>[];

      final first = scheduler.enqueue<void>(
        taskId: 'task-1',
        generation: () async {
          execution.add('task-1');
          firstTaskStarted.complete();
          await releaseFirstTask.future;
        },
      );
      await firstTaskStarted.future;

      final second = scheduler.enqueue<void>(
        taskId: 'task-2',
        generation: () async => execution.add('task-2'),
      );
      final third = scheduler.enqueue<void>(
        taskId: 'task-3',
        generation: () async => execution.add('task-3'),
      );

      releaseFirstTask.complete();
      await Future.wait([first, second, third]);

      expect(execution, ['task-1', 'task-2', 'task-3']);
    });

    test('continues pumping after a queued job fails', () async {
      final execution = <String>[];

      final failed = scheduler.enqueue<void>(
        taskId: 'task-1',
        generation: () async {
          execution.add('failed');
          throw StateError('generation failed');
        },
      );
      final successful = scheduler.enqueue<String>(
        taskId: 'task-2',
        generation: () async {
          execution.add('successful');
          return 'done';
        },
      );

      await expectLater(failed, throwsStateError);
      await expectLater(successful, completion('done'));
      expect(execution, ['failed', 'successful']);
      expect(scheduler.isRunning, isFalse);
    });

    test('streams every value before releasing inference ownership', () async {
      final releaseStream = Completer<void>();
      final streamStarted = Completer<void>();
      var followingJobStarted = false;

      final values = scheduler.enqueueStream<int>(
        taskId: 'task-1',
        generation: () async* {
          streamStarted.complete();
          yield 1;
          yield 2;
          await releaseStream.future;
          yield 3;
        },
      );
      await streamStarted.future;

      final followingJob = scheduler.enqueue<void>(
        taskId: 'task-2',
        generation: () async {
          followingJobStarted = true;
        },
      );
      final collected = values.toList();

      await Future<void>.delayed(Duration.zero);
      expect(followingJobStarted, isFalse);

      releaseStream.complete();
      expect(await collected, [1, 2, 3]);
      await followingJob;
      expect(followingJobStarted, isTrue);
    });

    test('emits immutable ownership snapshots', () async {
      final release = Completer<void>();
      final started = Completer<void>();
      final snapshots = <InferenceSchedulerSnapshot>[];
      final subscription = scheduler.snapshots.listen(snapshots.add);

      final job = scheduler.enqueue<void>(
        taskId: 'task-1',
        generation: () async {
          started.complete();
          await release.future;
        },
      );
      await started.future;

      expect(snapshots.last.isRunning, isTrue);
      expect(snapshots.last.activeTaskId, 'task-1');

      release.complete();
      await job;

      expect(snapshots.last.isRunning, isFalse);
      expect(snapshots.last.activeTaskId, isNull);
      expect(snapshots.last.pendingCount, 0);
      await subscription.cancel();
    });

    test('does not close while work is active', () async {
      final release = Completer<void>();
      final started = Completer<void>();
      final job = scheduler.enqueue<void>(
        taskId: 'task-1',
        generation: () async {
          started.complete();
          await release.future;
        },
      );
      await started.future;

      await expectLater(scheduler.close(), throwsStateError);

      release.complete();
      await job;
      await scheduler.close();
      await expectLater(
        scheduler.enqueue<void>(taskId: 'task-2', generation: () async {}),
        throwsStateError,
      );
    });
  });
}
