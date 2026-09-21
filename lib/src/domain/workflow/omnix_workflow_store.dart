// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'omnix_workflow_event.dart';
import 'omnix_workflow_task.dart';

/// Persistence port for workflow tasks and their append-only event history.
abstract interface class OmnixWorkflowStore {
  Future<void> initialize();

  Future<OmnixWorkflowTask?> readTask(String taskId);

  Future<List<OmnixWorkflowTask>> readTasks();

  Future<List<OmnixWorkflowEvent>> readEvents(String taskId);

  /// Atomically saves [task] and appends [event].
  ///
  /// Implementations must not commit one without the other. This invariant
  /// allows the runtime to recover a trustworthy task state after a crash.
  Future<void> persistTransition(
    OmnixWorkflowTask task,
    OmnixWorkflowEvent event,
  );
}
