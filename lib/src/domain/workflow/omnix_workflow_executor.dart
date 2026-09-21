// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:collection';

import 'omnix_workflow_task.dart';

/// Cooperative cancellation signal supplied to workflow executors.
final class OmnixWorkflowCancellationToken {
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void throwIfCancelled() {
    if (_isCancelled) throw const OmnixWorkflowCancelledException();
  }

  void cancel() => _isCancelled = true;
}

final class OmnixWorkflowCancelledException implements Exception {
  const OmnixWorkflowCancelledException();

  @override
  String toString() => 'Workflow execution was cancelled.';
}

/// Host-provided implementation for a workflow task [kind].
abstract interface class OmnixWorkflowExecutor {
  String get kind;

  Stream<OmnixWorkflowExecutionUpdate> execute(
    OmnixWorkflowTask task,
    OmnixWorkflowCancellationToken cancellationToken,
  );
}

sealed class OmnixWorkflowExecutionUpdate {
  const OmnixWorkflowExecutionUpdate();
}

/// An intermediate update that becomes part of the durable event timeline.
final class OmnixWorkflowProgress extends OmnixWorkflowExecutionUpdate {
  OmnixWorkflowProgress({
    required this.message,
    Map<String, Object?> data = const {},
  }) : data = UnmodifiableMapView(Map<String, Object?>.from(data));

  final String message;
  final Map<String, Object?> data;
}

/// The successful output of one workflow execution.
final class OmnixWorkflowResult extends OmnixWorkflowExecutionUpdate {
  const OmnixWorkflowResult({this.output});

  final String? output;
}
