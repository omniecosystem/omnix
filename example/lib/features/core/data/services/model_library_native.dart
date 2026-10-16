// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:file_picker/file_picker.dart';
import 'package:omnix_core/omnix_core.dart';
import 'package:omnix_example/features/core/presentation/controllers/model_library_controller.dart';
import 'package:omnix_example/features/core/data/services/background_model_transfer.dart';
import 'package:omnix_example/features/core/data/services/model_download_transport.dart';

final class NativeModelLibraryBackend
    implements ModelLibraryBackend, RecoverableModelLibraryBackend {
  NativeModelLibraryBackend(String root)
    : installer = OmnixModelInstaller(root: root);
  final OmnixModelInstaller installer;
  late final _background = BackgroundModelTransfer(
    NativeModelInstallationPort(installer),
    PluginModelTransferPort(),
  );
  OmnixModelInstallation? _active;
  bool _cancelRequested = false;
  @override
  Future<List<OmnixInstalledModel>> installed() => installer.installed();
  @override
  Stream<OmnixInstallationProgress> install(
    OmnixModelSpec spec,
    String source, {
    required bool network,
    String? token,
  }) async* {
    if (network) {
      yield* _background.download(spec, source, token);
      return;
    }
    _cancelRequested = false;
    final job = await installer.install(
      spec: spec,
      source: source,
      network: network,
      token: token,
    );
    _active = job;
    if (_cancelRequested) await job.cancel();
    try {
      yield* job.updates;
    } finally {
      _active = null;
    }
  }

  @override
  Future<void> cancel() async {
    _cancelRequested = true;
    await _active?.cancel();
    await _background.cancel();
  }

  @override
  Future<Stream<OmnixInstallationProgress>?> recover() => _background.recover();
  @override
  Future<void> detach() async {
    _cancelRequested = true;
    _background.detach();
    await _active
        ?.cancel(); // Local file copying still requires a live process.
  }

  @override
  Future<void> background() async {
    _cancelRequested = true;
    await _active?.cancel();
  }

  @override
  Future<void> resume() => _background.resume();

  @override
  Future<String?> pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['litertlm', 'gguf'],
      withData: false,
    );
    if (result == null) return null;
    final path = result.files.single.path;
    if (path == null) {
      throw StateError('The selected file is not readable locally.');
    }
    return path;
  }
}
