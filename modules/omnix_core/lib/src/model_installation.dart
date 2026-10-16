// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import '../model_installation_types.dart';
import 'rust/api/installation.dart' as native;
import 'rust_initialization.dart';

/// Installs explicit model artifacts through the optional Rust acquisition API.
///
/// The host supplies an app-private absolute [root]. The built-in [install]
/// transfer is foreground-only. Reservations allow an independent platform
/// adapter to schedule delivery; they do not themselves create background tasks.
/// Inference never invokes this installer.
final class OmnixModelInstaller {
  OmnixModelInstaller({required this.root});
  final String root;

  /// Reserves a durable destination without starting a transfer.
  ///
  /// The host adapter writes to the returned path, or moves its completed file
  /// there on the same filesystem. Platform scheduling stays outside this API.
  Future<OmnixTransferReservation> reserveTransfer(OmnixModelSpec spec) async {
    await ensureRustInitialized();
    return OmnixTransferReservation.fromJson(
      jsonDecode(
            await native.modelTransferReserve(
              root: root,
              spec: jsonEncode(spec.toJson()),
            ),
          )
          as Map<String, dynamic>,
    );
  }

  /// Recovers reservations, not the platform adapter's task handles.
  Future<List<OmnixTransferReservation>> pendingTransfers() async {
    await ensureRustInitialized();
    final records =
        jsonDecode(await native.modelTransferPending(root: root))
            as List<dynamic>;
    return records
        .map(
          (record) =>
              OmnixTransferReservation.fromJson(record as Map<String, dynamic>),
        )
        .toList();
  }

  /// Verifies and publishes a completed transfer without copying its model.
  ///
  /// The adapter must stop writing before this call. Rust loads the persisted
  /// artifact specification; callers cannot replace it at completion. Failure
  /// preserves the reservation. Publication consumes it, so a repeated call is
  /// not idempotent; inspect [installed] after an uncertain completion result.
  /// Hashing runs on the native bridge worker, not the Dart UI isolate.
  Future<OmnixInstalledModel> completeTransfer(String id) async {
    await ensureRustInitialized();
    return OmnixInstalledModel.fromJson(
      jsonDecode(await native.modelTransferComplete(root: root, id: id))
          as Map<String, dynamic>,
    );
  }

  Future<List<OmnixInstalledModel>> installed() async {
    await ensureRustInitialized();
    final records =
        jsonDecode(await native.modelInstallList(root: root)) as List<dynamic>;
    return records
        .map(
          (record) =>
              OmnixInstalledModel.fromJson(record as Map<String, dynamic>),
        )
        .toList();
  }

  /// Removes a model registration and deletes only engine-owned model bytes.
  ///
  /// Release model and transfer handles first. For adopted files the returned
  /// path remains host-owned and is not deleted. The host decides separately
  /// whether an explicit user removal should delete that file.
  Future<String?> remove(OmnixModelSpec spec) async {
    await ensureRustInitialized();
    return native.modelInstallRemove(
      root: root,
      spec: jsonEncode(spec.toJson()),
    );
  }

  /// Registers an existing host-owned model without copying or moving it.
  ///
  /// Rust verifies [spec]'s size, SHA-256 and container on the bridge worker.
  /// The host must stop writers before calling and keep [path] available.
  /// Registration does not transfer file ownership to the engine.
  Future<OmnixInstalledModel> adoptFile({
    required OmnixModelSpec spec,
    required String path,
  }) async {
    await ensureRustInitialized();
    return OmnixInstalledModel.fromJson(
      jsonDecode(
            await native.modelInstallAdopt(
              root: root,
              spec: jsonEncode(spec.toJson()),
              path: path,
            ),
          )
          as Map<String, dynamic>,
    );
  }

  /// Starts downloading or importing [source] with mandatory integrity checks.
  ///
  /// Set [network] to `false` for an absolute readable local file. Authentication
  /// [token] is optional and never included in persisted installation records.
  Future<OmnixModelInstallation> install({
    required OmnixModelSpec spec,
    required String source,
    bool network = true,
    String? token,
  }) async {
    await ensureRustInitialized();
    final id = await native.modelInstallStart(
      root: root,
      spec: jsonEncode(spec.toJson()),
      source: source,
      network: network,
      token: token,
    );
    return OmnixModelInstallation._(id);
  }
}

/// Owns one native acquisition job until completion and registry release.
final class OmnixModelInstallation {
  OmnixModelInstallation._(this._id);
  final String _id;
  bool _consumed = false;

  /// Requests cancellation without waiting for the next progress update.
  Future<void> cancel() => native.modelInstallCancel(id: _id);

  /// Delivers progress and releases the job after its terminal snapshot.
  ///
  /// This stream can only be consumed once. Cancelling the subscription requests
  /// native cancellation and waits for cleanup before releasing the handle.
  Stream<OmnixInstallationProgress> get updates async* {
    if (_consumed) {
      throw StateError('Installation updates were already consumed.');
    }
    _consumed = true;
    var terminal = false;
    try {
      while (true) {
        final update = await _status();
        terminal = update.terminal;
        yield update;
        if (terminal) break;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    } finally {
      if (!terminal) {
        await cancel();
        while (!(await _status()).terminal) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      await native.modelInstallRelease(id: _id);
    }
  }

  Future<OmnixInstallationProgress> _status() async =>
      OmnixInstallationProgress.fromJson(
        jsonDecode(await native.modelInstallStatus(id: _id))
            as Map<String, dynamic>,
      );
}
