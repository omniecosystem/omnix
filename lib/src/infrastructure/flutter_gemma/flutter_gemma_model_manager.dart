// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';

import '../../domain/models/omnix_model_manager.dart';
import '../../domain/models/omnix_model_manifest.dart';
import 'model_artifact_verifier.dart';

/// LiteRT-LM model bootstrap and installation backed by Flutter Gemma.
final class FlutterGemmaModelManager implements OmnixModelManager {
  FlutterGemmaModelManager({
    this.huggingFaceToken,
    this.maxDownloadRetries = 10,
  }) {
    if (maxDownloadRetries < 1) {
      throw ArgumentError.value(
        maxDownloadRetries,
        'maxDownloadRetries',
        'must be positive',
      );
    }
  }

  final String? huggingFaceToken;
  final int maxDownloadRetries;
  Future<void>? _initialization;

  @override
  Future<void> initialize() {
    final pending = _initialization;
    if (pending != null) return pending;
    final initialization = _initializeOnce();
    _initialization = initialization;
    return initialization;
  }

  Future<void> _initializeOnce() async {
    try {
      await FlutterGemma.initialize(
        huggingFaceToken: _nonEmpty(huggingFaceToken),
        maxDownloadRetries: maxDownloadRetries,
        inferenceEngines: const [LiteRtLmEngine()],
      );
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  @override
  Future<OmnixModelInstallation> install(
    OmnixModelInstallRequest request, {
    void Function(int progress)? onProgress,
    OmnixCancellationToken? cancellationToken,
  }) async {
    await initialize();
    cancellationToken?.throwIfCancelled();
    if (request.requiresIntegrityVerification &&
        !supportsModelArtifactVerification) {
      throw UnsupportedError(
        'This platform cannot verify downloaded model artifacts.',
      );
    }

    var builder = FlutterGemma.installModel(
      modelType: _modelType(request.template),
      fileType: _fileType(request.format),
    );
    builder = switch (request.source) {
      OmnixNetworkModelSource(
        :final uri,
        :final authToken,
        :final foreground,
      ) =>
        builder.fromNetwork(
          uri.toString(),
          token: _nonEmpty(authToken),
          foreground: foreground,
        ),
      OmnixAssetModelSource(:final path) => builder.fromAsset(path),
      OmnixFileModelSource(:final path) => builder.fromFile(path),
      OmnixBundledModelSource(:final name) => builder.fromBundled(name),
    };

    if (onProgress != null) builder.withProgress(onProgress);

    final pluginCancellation = CancelToken();
    StreamSubscription<String>? cancellationSubscription;
    if (cancellationToken != null) {
      builder.withCancelToken(pluginCancellation);
      cancellationSubscription = cancellationToken.cancellations.listen(
        pluginCancellation.cancel,
      );
    }

    try {
      final installation = await builder.install();
      final artifactName = installation.spec.files.first.filename;
      if (request.requiresIntegrityVerification) {
        try {
          await verifyModelArtifact(
            path: await FlutterGemma.getModelPath(artifactName),
            expectedSize: request.expectedSizeBytes!,
            expectedSha256: request.expectedSha256!,
          );
        } catch (_) {
          try {
            await FlutterGemma.clearActiveInferenceIdentity();
          } catch (_) {
            // Continue cleanup even if the active identity cannot be cleared.
          }
          try {
            await FlutterGemma.uninstallModel(artifactName);
          } catch (_) {
            // Preserve the verification failure as the actionable error.
          }
          rethrow;
        }
      }
      return OmnixModelInstallation(
        artifactName: artifactName,
        template: request.template,
        format: request.format,
        notes: installation.notes,
      );
    } on DownloadCancelledException catch (error) {
      throw OmnixOperationCancelled(error.message);
    } finally {
      await cancellationSubscription?.cancel();
    }
  }

  @override
  Future<bool> isInstalled(String artifactName) async {
    await initialize();
    return FlutterGemma.isModelInstalled(artifactName);
  }

  @override
  Future<List<String>> listInstalled() async {
    await initialize();
    return FlutterGemma.listInstalledModels();
  }

  @override
  Future<String> getPath(String artifactName) async {
    await initialize();
    return FlutterGemma.getModelPath(artifactName);
  }

  @override
  Future<void> clearActiveModel() async {
    await initialize();
    await FlutterGemma.clearActiveInferenceIdentity();
  }

  @override
  Future<void> uninstall(String artifactName) async {
    await initialize();
    final active = FlutterGemma.activeModelSpec;
    if (active?.files.any((file) => file.filename == artifactName) ?? false) {
      await FlutterGemma.clearActiveInferenceIdentity();
    }
    await FlutterGemma.uninstallModel(artifactName);
  }

  @override
  Future<void> cleanup() async {
    await initialize();
    await FlutterGemma.performCleanup();
  }
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

ModelType _modelType(OmnixModelTemplate template) => switch (template) {
  OmnixModelTemplate.general => ModelType.general,
  OmnixModelTemplate.gemma4 => ModelType.gemma4,
  OmnixModelTemplate.qwen3 => ModelType.qwen3,
  OmnixModelTemplate.phi => ModelType.phi,
};

ModelFileType _fileType(OmnixModelFormat format) => switch (format) {
  OmnixModelFormat.liteRtLm => ModelFileType.litertlm,
};
