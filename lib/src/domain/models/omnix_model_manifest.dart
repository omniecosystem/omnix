// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

/// Model prompt/template family understood by an inference adapter.
enum OmnixModelTemplate { general, gemma4, qwen3, phi }

/// Downloaded model artifact format understood by Omnix.
enum OmnixModelFormat { liteRtLm }

/// Preferred inference accelerator for a model.
enum OmnixBackendPreference { cpu, gpu, npu }

/// Decoding and context defaults declared by a model publisher.
final class OmnixGenerationDefaults {
  const OmnixGenerationDefaults({
    required this.temperature,
    required this.topK,
    required this.topP,
    required this.maxTokens,
  });

  final double temperature;
  final int topK;
  final double topP;
  final int maxTokens;
}

/// A validated, portable description of a model published to an Omnix registry.
///
/// This deliberately has no dependency on a particular inference plugin. An
/// infrastructure adapter maps these values to the plugin it uses at runtime.
final class OmnixModelManifest {
  const OmnixModelManifest({
    required this.source,
    required this.id,
    required this.version,
    required this.displayName,
    required this.description,
    required this.template,
    required this.format,
    required this.preferredBackend,
    required this.downloadUri,
    required this.sizeBytes,
    required this.sha256,
    required this.license,
    required this.supportsThinking,
    required this.requiresThinking,
    required this.generationDefaults,
  });

  final Uri source;
  final String id;
  final String version;
  final String displayName;
  final String description;
  final OmnixModelTemplate template;
  final OmnixModelFormat format;
  final OmnixBackendPreference preferredBackend;
  final Uri downloadUri;
  final int sizeBytes;
  final String sha256;
  final String license;
  final bool supportsThinking;
  final bool requiresThinking;
  final OmnixGenerationDefaults generationDefaults;
}
