// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:collection';

/// Persisted events emitted over a workflow task's lifecycle.
enum OmnixWorkflowEventKind {
  queued,
  recovered,
  started,
  progress,
  retryScheduled,
  completed,
  failed,
  cancelled,
}

/// An append-only record of a workflow state transition or progress update.
final class OmnixWorkflowEvent {
  OmnixWorkflowEvent({
    required this.taskId,
    required this.kind,
    required this.timestamp,
    required this.message,
    Map<String, Object?> data = const {},
  }) : data = UnmodifiableMapView(Map<String, Object?>.from(data));

  final String taskId;
  final OmnixWorkflowEventKind kind;
  final DateTime timestamp;
  final String message;
  final Map<String, Object?> data;
}
