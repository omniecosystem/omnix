import 'package:omnix/omnix.dart';

// Consumer adapter only. Native Workflow owns all execution transitions.
abstract interface class WorkflowBackend {
  Future<OmnixWorkflowProgress> open();
  Future<OmnixWorkflowProgress> newDemo();
  Future<OmnixWorkflowProgress> runNext();
  Future<OmnixWorkflowProgress> recover();
  Future<OmnixWorkflowProgress> reopen();
  Future<OmnixWorkflowProgress> confirmSimulation();
  void cancel();
  Future<void> close();
}
