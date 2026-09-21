// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import '../models/omnix_model_capabilities.dart';
import '../models/omnix_model_manifest.dart';

/// Capabilities exposed by one inference provider in the current environment.
final class OmnixInferenceProviderCapabilities {
  const OmnixInferenceProviderCapabilities({
    required this.providerId,
    required this.formats,
    required this.inputModalities,
    required this.platform,
    required this.supportsThinking,
    required this.supportsFunctionCalls,
  });

  final String providerId;
  final Set<OmnixModelFormat> formats;
  final Set<OmnixInputModality> inputModalities;
  final OmnixTargetPlatform platform;
  final bool supportsThinking;
  final bool supportsFunctionCalls;

  /// Evaluates a model without loading native resources.
  OmnixModelCompatibility evaluate(OmnixModelManifest model) {
    final issues = <String>[];
    final unavailableCapabilities = <String>[];
    if (!formats.contains(model.format)) {
      issues.add('Format ${model.format.name} is not supported.');
    }
    if (model.capabilities.targetPlatforms.isNotEmpty &&
        !model.capabilities.targetPlatforms.contains(platform)) {
      issues.add('The model does not target ${platform.name}.');
    }
    for (final modality in model.capabilities.inputModalities) {
      if (!inputModalities.contains(modality)) {
        unavailableCapabilities.add(
          'Input modality ${modality.name} is not supported.',
        );
      }
    }
    if (model.capabilities.supportsThinking && !supportsThinking) {
      final message = 'Thinking output is not supported.';
      if (model.capabilities.requiresThinking) {
        issues.add(message);
      } else {
        unavailableCapabilities.add(message);
      }
    }
    if (model.capabilities.supportsFunctionCalls && !supportsFunctionCalls) {
      unavailableCapabilities.add('Function calling is not supported.');
    }
    return OmnixModelCompatibility(
      providerId: providerId,
      modelId: model.id,
      issues: List.unmodifiable(issues),
      unavailableCapabilities: List.unmodifiable(unavailableCapabilities),
    );
  }
}

/// Result of comparing a model artifact with an inference provider.
final class OmnixModelCompatibility {
  const OmnixModelCompatibility({
    required this.providerId,
    required this.modelId,
    required this.issues,
    this.unavailableCapabilities = const [],
  });

  final String providerId;
  final String modelId;
  final List<String> issues;
  final List<String> unavailableCapabilities;

  bool get isCompatible => issues.isEmpty;
  bool get isFullySupported =>
      issues.isEmpty && unavailableCapabilities.isEmpty;
}
