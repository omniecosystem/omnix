import 'dart:async';

import 'package:background_downloader/background_downloader.dart';
import 'package:omnix_core/model_installation_types.dart';

const modelTransferGroup = 'omnix-example-models-v1';
String modelTaskId(String reservationId) => 'omnix-model-$reservationId';

abstract interface class ModelInstallationPort {
  Future<List<OmnixInstalledModel>> installed();
  Future<List<OmnixTransferReservation>> pending();
  Future<OmnixTransferReservation> reserve(OmnixModelSpec spec);
  Future<OmnixInstalledModel> complete(String id);
}

abstract interface class ModelTransferPort {
  Future<void> initialize();
  Future<bool> enqueue(
    OmnixTransferReservation reservation,
    String url,
    String? token,
  );
  Future<TaskRecord?> record(String id);
  Future<void> cancel(String id);
  Future<void> forget(String id);
  Future<bool> resume(String id);
}

/// Coordinates a Flutter host's transport with Rust-owned model installation.
///
/// No hashing, model copying or catalog publication is implemented here.
final class BackgroundModelTransfer {
  BackgroundModelTransfer(
    this.installations,
    this.transfers, {
    this.pollInterval = const Duration(milliseconds: 500),
  });
  final ModelInstallationPort installations;
  final ModelTransferPort transfers;
  final Duration pollInterval;
  String? _active;
  bool _detached = false;
  bool _cancelRequested = false;

  Future<Stream<OmnixInstallationProgress>?> recover() async {
    await transfers.initialize();
    OmnixTransferReservation? interrupted;
    for (final pending in await installations.pending()) {
      final record = await transfers.record(modelTaskId(pending.id));
      if (record != null &&
          (record.status == TaskStatus.complete ||
              !record.status.isFinalState)) {
        return _observe(pending);
      }
      interrupted ??= pending;
    }
    if (interrupted != null) return _observe(interrupted, recovering: true);
    return null;
  }

  Stream<OmnixInstallationProgress> download(
    OmnixModelSpec spec,
    String url,
    String? token,
  ) async* {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError(
        'Model downloads require HTTPS without URL credentials.',
      );
    }
    _cancelRequested = false;
    await transfers.initialize();
    for (final model in await installations.installed()) {
      if (_sameSpec(model.spec, spec)) {
        yield OmnixInstallationProgress(
          phase: 'installed',
          received: spec.bytes,
          total: spec.bytes,
          path: model.path,
        );
        return;
      }
    }
    OmnixTransferReservation? reservation;
    for (final pending in await installations.pending()) {
      if (_sameSpec(pending.spec, spec)) {
        reservation = pending;
        break;
      }
    }
    reservation ??= await installations.reserve(spec);
    _active = modelTaskId(reservation.id);
    final record = await transfers.record(_active!);
    if (record == null ||
        (record.status.isFinalState && record.status != TaskStatus.complete)) {
      if (_cancelRequested) {
        yield OmnixInstallationProgress(
          phase: 'cancelled',
          received: 0,
          total: spec.bytes,
        );
        _active = null;
        return;
      }
      if (!await transfers.enqueue(reservation, url, token)) {
        _active = null;
        throw StateError(
          'The OS did not accept this download. Its reservation was preserved.',
        );
      }
    }
    if (_cancelRequested) await transfers.cancel(_active!);
    yield* _observe(reservation);
  }

  Stream<OmnixInstallationProgress> _observe(
    OmnixTransferReservation reservation, {
    bool recovering = false,
  }) async* {
    final id = modelTaskId(reservation.id);
    _active = id;
    var missing = 0;
    try {
      while (!_detached) {
        final record = await transfers.record(id);
        if (record == null) {
          if (recovering) {
            yield OmnixInstallationProgress(
              phase: 'failed',
              received: 0,
              total: reservation.spec.bytes,
              error:
                  'Download tracking was interrupted. Retry explicitly to download this model; its reservation was retained.',
            );
            return;
          }
          // Enqueue can precede the persistent tracking event by a few ticks.
          if (++missing > 20) {
            throw StateError(
              'Download tracking is unavailable. Reopen Core to recover.',
            );
          }
        } else {
          missing = 0;
          final received =
              (record.progress.clamp(0, 1) * reservation.spec.bytes).round();
          final exception = record.exception;
          if (exception is TaskHttpException &&
              const [401, 403, 404].contains(exception.httpResponseCode)) {
            await transfers.cancel(id);
            yield OmnixInstallationProgress(
              phase: 'failed',
              received: received,
              total: reservation.spec.bytes,
              error:
                  'Model server returned HTTP ${exception.httpResponseCode}. Check the URL, token and model access.',
            );
            return;
          }
          if (record.status == TaskStatus.complete) {
            yield OmnixInstallationProgress(
              phase: 'verifying',
              received: reservation.spec.bytes,
              total: reservation.spec.bytes,
            );
            late final OmnixInstalledModel model;
            try {
              model = await installations.complete(reservation.id);
            } catch (_) {
              // Keep Rust's reservation, but permit an explicit fresh transfer.
              await _forget(id);
              rethrow;
            }
            final cleaned = await _forget(id);
            yield OmnixInstallationProgress(
              phase: 'installed',
              received: model.spec.bytes,
              total: model.spec.bytes,
              path: model.path,
              error: cleaned
                  ? null
                  : 'Model installed and verified, but download-record cleanup failed. The saved download URL and headers may remain on this device.',
            );
            return;
          }
          if (record.status.isFinalState) {
            yield OmnixInstallationProgress(
              phase: record.status == TaskStatus.canceled
                  ? 'cancelled'
                  : 'failed',
              received: received,
              total: reservation.spec.bytes,
              error: record.status == TaskStatus.canceled
                  ? null
                  : 'Download ${record.status.name}. Check connectivity, storage and access permissions; the reservation was retained.',
            );
            return;
          }
          yield OmnixInstallationProgress(
            phase: record.status.name,
            received: received,
            total: reservation.spec.bytes,
          );
        }
        await Future<void>.delayed(pollInterval);
      }
    } finally {
      if (_active == id) _active = null;
    }
  }

  Future<void> cancel() async {
    _cancelRequested = true;
    final id = _active;
    if (id != null) await transfers.cancel(id);
  }

  Future<bool> _forget(String id) async {
    try {
      await transfers.forget(id);
      return true;
    } catch (_) {
      // Cleanup must not hide an integrity error or undo a verified publication.
      return false;
    }
  }

  Future<void> resume() async {
    final id = _active;
    if (id == null || !await transfers.resume(id)) {
      throw StateError(
        'This transfer cannot resume. Cancel and retry the download.',
      );
    }
  }

  // Detaching UI observation must not cancel an OS transfer.
  void detach() {
    _detached = true;
  }
}

bool _sameSpec(OmnixModelSpec a, OmnixModelSpec b) =>
    a.sha256 == b.sha256 &&
    a.filename == b.filename &&
    a.bytes == b.bytes &&
    a.role == b.role;
