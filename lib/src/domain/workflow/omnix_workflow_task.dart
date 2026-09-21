// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:collection';

/// Durable lifecycle states for an Omnix workflow task.
enum OmnixWorkflowTaskStatus { queued, running, completed, failed, cancelled }

/// A persistable unit of background or deferred work.
final class OmnixWorkflowTask {
  OmnixWorkflowTask({
    required this.id,
    required this.kind,
    required this.title,
    required this.status,
    required this.attempt,
    required this.maxAttempts,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    Map<String, Object?> input = const {},
    this.output,
    this.error,
  }) : input = UnmodifiableMapView(Map<String, Object?>.from(input));

  final String id;
  final String kind;
  final String title;
  final String? description;
  final Map<String, Object?> input;
  final OmnixWorkflowTaskStatus status;
  final int attempt;
  final int maxAttempts;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? output;
  final String? error;

  bool get isTerminal => switch (status) {
    OmnixWorkflowTaskStatus.completed ||
    OmnixWorkflowTaskStatus.failed ||
    OmnixWorkflowTaskStatus.cancelled => true,
    OmnixWorkflowTaskStatus.queued || OmnixWorkflowTaskStatus.running => false,
  };

  OmnixWorkflowTask copyWith({
    OmnixWorkflowTaskStatus? status,
    int? attempt,
    DateTime? updatedAt,
    String? output,
    String? error,
    bool clearOutput = false,
    bool clearError = false,
  }) {
    return OmnixWorkflowTask(
      id: id,
      kind: kind,
      title: title,
      description: description,
      input: input,
      status: status ?? this.status,
      attempt: attempt ?? this.attempt,
      maxAttempts: maxAttempts,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      output: clearOutput ? null : output ?? this.output,
      error: clearError ? null : error ?? this.error,
    );
  }
}
