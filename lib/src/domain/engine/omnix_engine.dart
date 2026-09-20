// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'omnix_engine_event.dart';
import 'omnix_engine_state.dart';
import 'omnix_runtime_info.dart';

/// Headless contract implemented by an Omnix engine backend.
abstract interface class OmnixEngine {
  OmnixEngineState get state;

  Stream<OmnixEngineEvent> get events;

  /// Initializes the engine and returns its compatibility information.
  Future<OmnixRuntimeInfo> initialize();

  /// Releases resources owned by this engine instance.
  Future<void> close();
}
