// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

/// Immutable observation of local inference ownership and queued work.
final class InferenceSchedulerSnapshot {
  const InferenceSchedulerSnapshot({
    required this.isRunning,
    required this.activeTaskId,
    required this.pendingCount,
  });

  final bool isRunning;
  final String? activeTaskId;
  final int pendingCount;
}
