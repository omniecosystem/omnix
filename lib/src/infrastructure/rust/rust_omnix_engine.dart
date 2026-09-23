// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import '../../domain/engine/omnix_engine.dart';
import '../../domain/engine/omnix_engine_event.dart';
import '../../domain/engine/omnix_engine_state.dart';
import '../../domain/engine/omnix_runtime_info.dart';
import '../../rust/api/simple.dart' as native;
import '../../rust/frb_generated.dart' show RustLib;

/// Native implementation kept behind the public [OmnixEngine] contract.
final class RustOmnixEngine implements OmnixEngine {
  static Future<void>? _rustInitialization;

  final StreamController<OmnixEngineEvent> _events =
      StreamController<OmnixEngineEvent>.broadcast();

  OmnixEngineState _state = OmnixEngineState.created;
  Future<OmnixRuntimeInfo>? _initialization;

  @override
  OmnixEngineState get state => _state;

  @override
  Stream<OmnixEngineEvent> get events => _events.stream;

  @override
  Future<OmnixRuntimeInfo> initialize() {
    if (_state == OmnixEngineState.closed) {
      throw StateError('A closed Omnix engine cannot be initialized.');
    }
    return _initialization ??= _initializeOnce();
  }

  Future<OmnixRuntimeInfo> _initializeOnce() async {
    _transitionTo(OmnixEngineState.initializing);
    try {
      await (_rustInitialization ??= RustLib.init());
      if (_state == OmnixEngineState.closed) {
        throw StateError('The Omnix engine was closed during initialization.');
      }
      final handshake = native.greet(name: 'Omnix');
      if (handshake != 'Hello, Omnix!') {
        throw StateError('The native Omnix runtime handshake failed.');
      }
      const info = OmnixRuntimeInfo(
        apiVersion: 1,
        engineName: 'Omnix',
        engineVersion: '0.1.0-dev.3',
      );
      _transitionTo(OmnixEngineState.ready);
      return info;
    } catch (error) {
      _transitionTo(OmnixEngineState.failed, error: error);
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    if (_state == OmnixEngineState.closed) return;
    _transitionTo(OmnixEngineState.closed);
    await _events.close();
  }

  void _transitionTo(OmnixEngineState state, {Object? error}) {
    if (_state == OmnixEngineState.closed && state != OmnixEngineState.closed) {
      return;
    }
    _state = state;
    if (!_events.isClosed) {
      _events.add(
        OmnixEngineEvent(
          state: state,
          occurredAt: DateTime.now().toUtc(),
          error: error,
        ),
      );
    }
  }
}
