// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:omnix_core/model_installation_types.dart';

abstract interface class ModelLibraryBackend {
  Future<List<OmnixInstalledModel>> installed();
  Stream<OmnixInstallationProgress> install(
    OmnixModelSpec spec,
    String source, {
    required bool network,
    String? token,
  });
  Future<void> cancel();
  Future<String?> pickFile();
}

abstract interface class RecoverableModelLibraryBackend
    implements ModelLibraryBackend {
  Future<Stream<OmnixInstallationProgress>?> recover();
  Future<void> detach();
  Future<void> background();
  Future<void> resume();
}

class ModelLibraryController extends ChangeNotifier {
  ModelLibraryController(this.backend);
  final ModelLibraryBackend backend;
  List<OmnixInstalledModel> models = [];
  OmnixInstallationProgress? progress;
  String? error;
  bool busy = false;
  bool _disposed = false;
  Future<void>? _pending;
  Future<void>? _initializing;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    try {
      models = await backend.installed();
    } catch (e) {
      error = e.toString();
    }
    _notify();
  }

  Future<void> initialize() => _initializing ??= _initialize().whenComplete(() {
    _initializing = null;
  });

  Future<void> _initialize() async {
    await refresh();
    if (busy || _disposed) return;
    final backend = this.backend;
    if (backend is RecoverableModelLibraryBackend) {
      try {
        final recovered = await backend.recover();
        if (recovered != null && !_disposed) {
          busy = true;
          _notify();
          _pending = _consume(recovered);
        }
      } catch (e) {
        error = e.toString();
        _notify();
      }
    }
  }

  Future<void> background() async {
    final backend = this.backend;
    if (backend is RecoverableModelLibraryBackend) {
      await backend.background();
    } else {
      await cancel();
    }
  }

  Future<void> resume() async {
    final backend = this.backend;
    if (backend is RecoverableModelLibraryBackend) {
      try {
        await backend.resume();
      } catch (e) {
        error = e.toString();
        _notify();
      }
    }
  }

  Future<void> install(
    OmnixModelSpec spec,
    String source, {
    required bool network,
    String? token,
  }) {
    if (busy || _disposed || _initializing != null) return Future.value();
    busy = true;
    error = null;
    progress = null;
    _notify();
    return _pending = _install(spec, source, network: network, token: token);
  }

  Future<void> _install(
    OmnixModelSpec spec,
    String source, {
    required bool network,
    String? token,
  }) async {
    await _consume(
      backend.install(spec, source, network: network, token: token),
    );
  }

  Future<void> _consume(Stream<OmnixInstallationProgress> updates) async {
    try {
      await for (final update in updates) {
        progress = update;
        if (update.error != null) error = update.error;
        _notify();
      }
      await refresh();
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> cancel() async {
    try {
      await backend.cancel();
    } catch (e) {
      error = e.toString();
      _notify();
    }
  }

  Future<void> close() async {
    final backend = this.backend;
    if (backend is RecoverableModelLibraryBackend) {
      await backend.detach();
    } else {
      await cancel();
    }
    await _pending;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
