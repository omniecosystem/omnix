// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../../domain/models/omnix_model_manifest.dart';

Future<InferenceModel> getActiveFlutterGemmaModel({
  required int maxTokens,
  required OmnixBackendPreference preferredBackend,
}) async {
  final attempts = <String>[];
  for (final backend in flutterGemmaBackendOrder(preferredBackend)) {
    try {
      return await FlutterGemma.getActiveModel(
        maxTokens: maxTokens,
        preferredBackend: backend,
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
