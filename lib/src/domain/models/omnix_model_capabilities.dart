// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

/// Input modalities a model or inference provider can consume.
enum OmnixInputModality { text, image, audio }

/// Flutter targets on which a model artifact can run.
enum OmnixTargetPlatform { android, ios, macos, windows, linux, web }

/// Provider-neutral capabilities declared by one model artifact.
final class OmnixModelCapabilities {
  const OmnixModelCapabilities({
    this.inputModalities = const {OmnixInputModality.text},
    this.supportsThinking = false,
    this.requiresThinking = false,
    this.supportsFunctionCalls = false,
    this.targetPlatforms = const {},
  }) : assert(
         !requiresThinking || supportsThinking,
         'Mandatory thinking requires thinking support.',
       );

  /// Modalities accepted by this particular model artifact.
  final Set<OmnixInputModality> inputModalities;

  /// Whether the model can emit a separate reasoning stream.
  final bool supportsThinking;

  /// Whether the model must run with reasoning enabled.
  final bool requiresThinking;

  /// Whether the model is trained to emit structured function calls.
  final bool supportsFunctionCalls;

  /// Compatible targets, or an empty set when the publisher did not constrain
  /// the artifact to particular platforms.
  final Set<OmnixTargetPlatform> targetPlatforms;

  bool get supportsImages => inputModalities.contains(OmnixInputModality.image);
  bool get supportsAudio => inputModalities.contains(OmnixInputModality.audio);
}
