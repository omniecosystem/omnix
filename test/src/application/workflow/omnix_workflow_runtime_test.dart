import 'dart:async';

import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  group('OmnixWorkflowRuntime', () {
    late InferenceScheduler scheduler;
    late _MemoryWorkflowStore store;

    setUp(() {
      scheduler = InferenceScheduler();
      store = _MemoryWorkflowStore();
    });

    tearDown(() async {
      if (!scheduler.isRunning && scheduler.pendingCount == 0) {
        await scheduler.close();
      }
    });

    test('persists task progress and successful output', () async {
      final runtime = OmnixWorkflowRuntime(
        store: store,
        scheduler: scheduler,
        executors: [_SuccessfulExecutor()],
      );
      await runtime.initialize();

      await runtime.createTask(
        id: 'task-1',
        kind: 'test',
        title: 'Do useful work',
      );
      await runtime.waitForIdle();

      final task = await store.readTask('task-1');
      expect(task?.status, OmnixWorkflowTaskStatus.completed);
      expect(task?.attempt, 1);
      expect(task?.output, 'done');
      expect((await store.readEvents('task-1')).map((event) => event.kind), [
        OmnixWorkflowEventKind.queued,
        OmnixWorkflowEventKind.started,
        OmnixWorkflowEventKind.progress,
        OmnixWorkflowEventKind.completed,
      ]);
      await runtime.close();
    });

    test(
      'releases inference between attempts and honors chat priority',
      () async {
        final firstAttempt = Completer<void>();
        final releaseFailure = Completer<void>();
        final executionOrder = <String>[];
        final runtime = OmnixWorkflowRuntime(
          store: store,
          scheduler: scheduler,
          executors: [
            _CallbackExecutor((task, token) async* {
              executionOrder.add('task:${task.attempt}');
              if (task.attempt == 1) {
                firstAttempt.complete();
                await releaseFailure.future;
                throw StateError('retry me');
              }
              yield const OmnixWorkflowResult(output: 'recovered');
            }),
          ],
        );
        await runtime.initialize();
        await runtime.createTask(
          id: 'task-1',
          kind: 'callback',
          title: 'Retry safely',
          maxAttempts: 2,
        );
        await firstAttempt.future;
        final chat = scheduler.enqueue<void>(
          taskId: 'chat',
          generation: () async => executionOrder.add('chat'),
        );

        releaseFailure.complete();
        await chat;
        await runtime.waitForIdle();

        expect(executionOrder, ['task:1', 'chat', 'task:2']);
        expect(
          (await store.readTask('task-1'))?.status,
          OmnixWorkflowTaskStatus.completed,
        );
        expect(
          (await store.readEvents('task-1')).map((event) => event.kind),
          contains(OmnixWorkflowEventKind.retryScheduled),
        );
        await runtime.close();
      },
    );

    test('cancels a running task without later completing it', () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final runtime = OmnixWorkflowRuntime(
        store: store,
        scheduler: scheduler,
        executors: [
          _CallbackExecutor((task, token) async* {
            started.complete();
            await release.future;
            token.throwIfCancelled();
            yield const OmnixWorkflowResult(output: 'should not persist');
          }),
        ],
      );
      await runtime.initialize();
      await runtime.createTask(
        id: 'task-1',
        kind: 'callback',
        title: 'Cancelable work',
      );
      await started.future;

      await runtime.cancel('task-1');
      release.complete();
      await runtime.waitForIdle();

      final task = await store.readTask('task-1');
      expect(task?.status, OmnixWorkflowTaskStatus.cancelled);
      expect(task?.output, isNull);
      expect(
        (await store.readEvents('task-1')).last.kind,
        OmnixWorkflowEventKind.cancelled,
      );
      await runtime.close();
    });

    test('recovers an interrupted task during initialization', () async {
      final timestamp = DateTime.utc(2026, 9, 21);
      final interrupted = OmnixWorkflowTask(
        id: 'task-1',
        kind: 'test',
        title: 'Interrupted work',
        status: OmnixWorkflowTaskStatus.running,
        attempt: 1,
        maxAttempts: 2,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      await store.initialize();
      await store.persistTransition(
        interrupted,
        OmnixWorkflowEvent(
          taskId: interrupted.id,
          kind: OmnixWorkflowEventKind.started,
          timestamp: timestamp,
          message: 'Task processing started.',
        ),
      );
      final runtime = OmnixWorkflowRuntime(
        store: store,
        scheduler: scheduler,
        executors: [_SuccessfulExecutor()],
      );

      await runtime.initialize();
      await runtime.waitForIdle();

      final task = await store.readTask('task-1');
      expect(task?.status, OmnixWorkflowTaskStatus.completed);
      expect(task?.attempt, 2);
      expect(
        (await store.readEvents('task-1')).map((event) => event.kind),
        contains(OmnixWorkflowEventKind.recovered),
      );
      await runtime.close();
    });
  });
}

final class _SuccessfulExecutor implements OmnixWorkflowExecutor {
  @override
  String get kind => 'test';

  @override
  Stream<OmnixWorkflowExecutionUpdate> execute(
    OmnixWorkflowTask task,
    OmnixWorkflowCancellationToken cancellationToken,
  ) async* {
    yield OmnixWorkflowProgress(message: 'Working.');
    yield const OmnixWorkflowResult(output: 'done');
  }
}

final class _CallbackExecutor implements OmnixWorkflowExecutor {
  _CallbackExecutor(this.callback);

  final Stream<OmnixWorkflowExecutionUpdate> Function(
    OmnixWorkflowTask,
    OmnixWorkflowCancellationToken,
  )
  callback;

  @override
  String get kind => 'callback';

  @override
  Stream<OmnixWorkflowExecutionUpdate> execute(
    OmnixWorkflowTask task,
    OmnixWorkflowCancellationToken cancellationToken,
  ) => callback(task, cancellationToken);
}

final class _MemoryWorkflowStore implements OmnixWorkflowStore {
  final Map<String, OmnixWorkflowTask> tasks = {};
  final Map<String, List<OmnixWorkflowEvent>> events = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<List<OmnixWorkflowEvent>> readEvents(String taskId) async =>
      List.unmodifiable(events[taskId] ?? const []);

  @override
  Future<OmnixWorkflowTask?> readTask(String taskId) async => tasks[taskId];

  @override
  Future<List<OmnixWorkflowTask>> readTasks() async =>
      List.unmodifiable(tasks.values);

  @override
  Future<void> persistTransition(
    OmnixWorkflowTask task,
    OmnixWorkflowEvent event,
  ) async {
    tasks[task.id] = task;
    events.putIfAbsent(task.id, () => []).add(event);
  }
}
