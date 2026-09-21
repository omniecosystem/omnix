// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../../domain/inference/omnix_inference_provider_capabilities.dart';
import '../../domain/models/omnix_model_capabilities.dart';
import '../../domain/models/omnix_model_manifest.dart';

/// Flutter Gemma capabilities for the platform running this application.
OmnixInferenceProviderCapabilities flutterGemmaInferenceCapabilities() {
  final platform = _targetPlatform();
  return OmnixInferenceProviderCapabilities(
    providerId: 'flutter_gemma_litertlm',
    formats: const {OmnixModelFormat.liteRtLm},
    inputModalities: {
      OmnixInputModality.text,
      OmnixInputModality.image,
      if (platform != OmnixTargetPlatform.web) OmnixInputModality.audio,
    },
    platform: platform,
    supportsThinking: true,
    supportsFunctionCalls: true,
  );
}

OmnixTargetPlatform _targetPlatform() {
  if (kIsWeb) return OmnixTargetPlatform.web;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => OmnixTargetPlatform.android,
    TargetPlatform.iOS => OmnixTargetPlatform.ios,
    TargetPlatform.macOS => OmnixTargetPlatform.macos,
    TargetPlatform.windows => OmnixTargetPlatform.windows,
    TargetPlatform.linux => OmnixTargetPlatform.linux,
    TargetPlatform.fuchsia => throw UnsupportedError(
      'Flutter Gemma does not support Fuchsia.',
    ),
  };
}

Future<InferenceModel> getActiveFlutterGemmaModel({
  required int maxTokens,
  required OmnixBackendPreference preferredBackend,
  bool supportImage = false,
  bool supportAudio = false,
}) async {
  final attempts = <String>[];
  for (final backend in flutterGemmaBackendOrder(preferredBackend)) {
    try {
      return await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
        preferredBackend: backend,
        supportImage: supportImage,
        supportAudio: supportAudio,
      );
    } catch (error) {
      attempts.add('${backend.name}: $error');
    }
  }
  throw StateError(
    'No inference backend could load the active model. '
    'Attempts: ${attempts.join(' | ')}',
  );
}

List<PreferredBackend> flutterGemmaBackendOrder(
  OmnixBackendPreference preferred,
) {
  if (kIsWeb) return const [PreferredBackend.gpu];
  final candidates = switch (preferred) {
    OmnixBackendPreference.cpu => const [
      PreferredBackend.cpu,
      PreferredBackend.gpu,
    ],
    OmnixBackendPreference.gpu => const [
      PreferredBackend.gpu,
      PreferredBackend.cpu,
    ],
    OmnixBackendPreference.npu => const [
      PreferredBackend.npu,
      PreferredBackend.gpu,
      PreferredBackend.cpu,
    ],
  };
  if (defaultTargetPlatform == TargetPlatform.android) return candidates;
  return candidates
      .where((backend) => backend != PreferredBackend.npu)
      .toList(growable: false);
}

ModelType flutterGemmaModelType(OmnixModelTemplate template) =>
    switch (template) {
      OmnixModelTemplate.general => ModelType.general,
      OmnixModelTemplate.gemma4 => ModelType.gemma4,
      OmnixModelTemplate.qwen3 => ModelType.qwen3,
      OmnixModelTemplate.phi => ModelType.phi,
    };
