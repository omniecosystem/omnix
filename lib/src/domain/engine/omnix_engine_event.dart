// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'omnix_engine_state.dart';

/// A lifecycle transition emitted by an Omnix engine.
final class OmnixEngineEvent {
  const OmnixEngineEvent({
    required this.state,
    required this.occurredAt,
    this.error,
  });

  final OmnixEngineState state;
  final DateTime occurredAt;
  final Object? error;
}
