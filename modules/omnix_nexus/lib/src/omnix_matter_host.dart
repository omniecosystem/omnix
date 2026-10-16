// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'rust/api/matter_host.dart' as native;
import 'rust_initialization.dart';

/// A typed bridge transport for a retained Matter host session.
///
/// Implementations must preserve Rust validation, deadlines and host ownership.
/// This interface contains no commissioning or platform-service implementation.
abstract interface class OmnixMatterHostTransport {
  /// Sends an On/Off command without claiming attribute readback.
  Future<void> setOnOff(bool on);

  /// Reads the device's current On/Off attribute.
  Future<bool> readOnOff();

  /// Detaches the frontend and reports host shutdown failures.
  Future<void> close();
}

/// A Dart frontend for platform-owned Matter host commands.
///
/// The Windows factory controls a disposable software light, not a production
/// device. Android requires explicit registration of its retained JNI owner.
/// Platform services remain host-owned; this class implements no
/// Matter protocol. Concurrent calls are rejected instead of queued unboundedly.
final class OmnixMatterHost {
  /// Attaches an explicitly supplied typed transport.
  OmnixMatterHost.fromTransport(OmnixMatterHostTransport transport)
    : _transport = transport;

  final OmnixMatterHostTransport _transport;
  bool _busy = false;
  Future<void>? _closing;

  /// Opens an explicitly selected Windows software-light qualification session.
  ///
  /// Requires `matter_backend: windows_qualification` and Windows. The caller
  /// must verify [bundle] provenance and provide an empty private [storage]
  /// directory. No global runtime, alternate platform or simulator fallback
  /// is used. This is not real-device commissioning or Android registration.
  static Future<OmnixMatterHost> openWindowsFixture({
    required String bundle,
    required String storage,
  }) async {
    await ensureRustInitialized();
    final session = await native.matterHostOpenWindowsFixture(
      bundle: bundle,
      storage: storage,
    );
    return OmnixMatterHost.fromTransport(_NativeHostTransport(session));
  }

  /// Attaches to an already commissioned Android device through a registered host.
  ///
  /// Requires `matter_backend: android_host`. The application registers its
  /// process-scoped Java owner before calling this method; no Flutter channel,
  /// SDK download or commissioning is implemented by this Dart API. [nodeId]
  /// is an operational unsigned 64-bit ID and [endpoint] is a non-root endpoint.
  /// Closing detaches this frontend, not the SDK's process-owned native state.
  static Future<OmnixMatterHost> openAndroid({
    required BigInt nodeId,
    required int endpoint,
  }) async {
    await ensureRustInitialized();
    final session = await native.matterHostOpenAndroid(
      nodeId: nodeId,
      endpoint: endpoint,
    );
    return OmnixMatterHost.fromTransport(_NativeHostTransport(session));
  }

  Future<T> _run<T>(Future<T> Function() operation) async {
    if (_closing != null) throw StateError('Matter host is closed.');
    if (_busy) throw StateError('Matter host is busy.');
    _busy = true;
    try {
      return await operation();
    } finally {
      _busy = false;
    }
  }

  /// Sends an On/Off command through the Rust-owned host session.
  Future<void> setOnOff({required bool on}) =>
      _run(() => _transport.setOnOff(on));

  /// Reads the device attribute independently of command acknowledgement.
  Future<bool> readOnOff() => _run(_transport.readOnOff);

  /// Closes the frontend once and propagates shutdown failure.
  ///
  /// Waits for repeated close callers, but rejects closing during an active
  /// command. Further commands are rejected even if shutdown fails.
  Future<void> close() {
    final pending = _closing;
    if (pending != null) return pending;
    if (_busy) return Future.error(StateError('Matter host is busy.'));
    return _closing = Future<void>.sync(_transport.close);
  }
}

final class _NativeHostTransport implements OmnixMatterHostTransport {
  _NativeHostTransport(this.session);
  final native.MatterHostSession session;

  @override
  Future<void> setOnOff(bool on) => session.setOnOff(on_: on);

  @override
  Future<bool> readOnOff() => session.readOnOff();

  @override
  Future<void> close() async {
    try {
      await session.close();
    } finally {
      session.dispose();
    }
  }
}
