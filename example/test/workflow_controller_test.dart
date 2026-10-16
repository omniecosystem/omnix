import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/workflow/domain/workflow_backend.dart';
import 'package:omnix_example/features/workflow/presentation/controllers/workflow_controller.dart';

final snapshot = OmnixWorkflowProgress.decode(
  '{"version":1,"id":"demo-test","cancelled":false,"steps":[]}',
);

class FakeBackend implements WorkflowBackend {
  final result = Completer<OmnixWorkflowProgress>();
  int executions = 0;
  bool cancelled = false;
  bool closed = false;
  @override
  Future<OmnixWorkflowProgress> open() async => snapshot;
  @override
  Future<OmnixWorkflowProgress> newDemo() async => snapshot;
  @override
  Future<OmnixWorkflowProgress> runNext() {
    executions++;
    return result.future;
  }

  @override
  Future<OmnixWorkflowProgress> recover() async => snapshot;
  @override
  Future<OmnixWorkflowProgress> reopen() async => snapshot;
  @override
  Future<OmnixWorkflowProgress> confirmSimulation() async => snapshot;
  @override
  void cancel() {
    cancelled = true;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  test('UI blocks duplicate execution and waits before closing', () async {
    final backend = FakeBackend();
    final controller = WorkflowController(backend);
    await controller.initialize();
    final active = controller.runNext();
    await controller.runNext();
    expect(backend.executions, 1);
    expect(controller.executing, isTrue);
    final closing = controller.shutdown();
    expect(backend.cancelled, isTrue);
    expect(backend.closed, isFalse);
    backend.result.complete(snapshot);
    await active;
    await closing;
    expect(backend.closed, isTrue);
    controller.dispose();
  });
  test('idle shutdown preserves resumable work', () async {
    final backend = FakeBackend();
    final controller = WorkflowController(backend);
    await controller.initialize();
    await controller.shutdown();
    expect(backend.cancelled, isFalse);
    expect(backend.closed, isTrue);
    controller.dispose();
  });
}
