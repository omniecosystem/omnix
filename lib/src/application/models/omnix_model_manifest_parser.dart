// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import '../../domain/models/omnix_model_manifest.dart';
import '../../domain/models/omnix_model_capabilities.dart';

/// Validates marketplace manifests before an inference adapter downloads them.
///
/// The current public registry contract accepts pinned, public LiteRT-LM files
/// from Hugging Face. Other formats can be added explicitly in a future schema
/// version rather than being accepted accidentally.
final class OmnixModelManifestParser {
  const OmnixModelManifestParser({required this.trustedMarketplaceHost});

  final String trustedMarketplaceHost;

  /// Validates a registry location before a host downloads its manifest.
  void validateSource(Uri source) => _validateSource(source);

  OmnixModelManifest parse({
    required Uri source,
    required Map<String, dynamic> manifest,
  }) {
    _validateSource(source);
    if (manifest['schema_version'] != null && manifest['schema_version'] != 1) {
      throw StateError('Unsupported model manifest version.');
    }

    final id = _requiredString(manifest, 'id');
    final version = _requiredString(manifest, 'version');
    final downloadUri = Uri.tryParse(_requiredString(manifest, 'url'));
    final sizeBytes = _requiredInt(manifest, 'size_bytes');
    final sha256 = _requiredString(manifest, 'sha256').toLowerCase();

    if (!RegExp(r'^[a-z0-9][a-z0-9.-]{1,63}$').hasMatch(id)) {
      throw StateError('The model has an invalid identifier.');
    }
    if (!RegExp(r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$').hasMatch(version)) {
      throw StateError('The model has an invalid version.');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw StateError('The model has an invalid SHA-256 digest.');
    }
    if (sizeBytes < 1024 * 1024 || sizeBytes > 16 * 1024 * 1024 * 1024) {
      throw StateError('The model size is outside the supported range.');
    }
    if (downloadUri == null ||
        downloadUri.scheme != 'https' ||
        downloadUri.host != 'huggingface.co' ||
        !RegExp(
          r'^/[^/]+/[^/]+/resolve/[0-9a-f]{40}/.+\.litertlm$',
        ).hasMatch(downloadUri.path)) {
      throw StateError(
        'Models must use a pinned public Hugging Face .litertlm URL.',
      );
    }

    final defaults = OmnixGenerationDefaults(
      temperature: _number(manifest, 'temperature', 0.7),
      topK: _integer(manifest, 'top_k', 40),
      topP: _number(manifest, 'top_p', 0.95),
      maxTokens: _integer(manifest, 'max_tokens', 4096),
    );
    if (defaults.temperature < 0 ||
        defaults.temperature > 2 ||
        defaults.topK < 1 ||
        defaults.topK > 100 ||
        defaults.topP < 0 ||
        defaults.topP > 1 ||
        defaults.maxTokens < 1024 ||
        defaults.maxTokens > 4096) {
      throw StateError('The model generation defaults are unsupported.');
    }

    final supportsThinking = manifest['thinking'] == true;
    final requiresThinking = manifest['thinking_mandatory'] == true;
    if (requiresThinking && !supportsThinking) {
      throw StateError('Mandatory thinking requires thinking support.');
    }
    final inputModalities = _inputModalities(manifest['input_modalities']);
    final targetPlatforms = _targetPlatforms(manifest['platforms']);

    return OmnixModelManifest(
      source: source,
      id: id,
      version: version,
      displayName: _requiredString(manifest, 'display_name'),
      description: _requiredString(manifest, 'description'),
      template: _template(_requiredString(manifest, 'model_type')),
      format: _format(_requiredString(manifest, 'file_type')),
      preferredBackend: _backend(
        _requiredString(manifest, 'preferred_backend'),
      ),
      downloadUri: downloadUri,
      sizeBytes: sizeBytes,
      sha256: sha256,
      license: _requiredString(manifest, 'license'),
      capabilities: OmnixModelCapabilities(
        inputModalities: inputModalities,
        supportsThinking: supportsThinking,
        requiresThinking: requiresThinking,
        supportsFunctionCalls: manifest['function_calls'] == true,
        targetPlatforms: targetPlatforms,
      ),
      generationDefaults: defaults,
    );
  }

  Set<OmnixInputModality> _inputModalities(Object? value) {
    if (value == null) return const {OmnixInputModality.text};
    if (value is! List) {
      throw const FormatException('input_modalities must be a list.');
    }
    final modalities = value.map((item) {
      if (item is! String) {
        throw const FormatException('Invalid input modality.');
      }
      return switch (item) {
        'text' => OmnixInputModality.text,
        'image' => OmnixInputModality.image,
        'audio' => OmnixInputModality.audio,
        _ => throw FormatException('Unsupported input modality: $item'),
      };
    }).toSet();
    if (!modalities.contains(OmnixInputModality.text)) {
      throw const FormatException('Models must declare text input.');
    }
    return Set.unmodifiable(modalities);
  }

  Set<OmnixTargetPlatform> _targetPlatforms(Object? value) {
    if (value == null) return const {};
    if (value is! List) {
      throw const FormatException('platforms must be a list.');
    }
    final platforms = value.map((item) {
      if (item is! String) {
        throw const FormatException('Invalid target platform.');
      }
      return switch (item) {
        'android' => OmnixTargetPlatform.android,
        'ios' => OmnixTargetPlatform.ios,
        'macos' => OmnixTargetPlatform.macos,
        'windows' => OmnixTargetPlatform.windows,
        'linux' => OmnixTargetPlatform.linux,
        'web' => OmnixTargetPlatform.web,
        _ => throw FormatException('Unsupported target platform: $item'),
      };
    }).toSet();
    return Set.unmodifiable(platforms);
  }

  void _validateSource(Uri source) {
    if (source.scheme != 'https' || source.host != trustedMarketplaceHost) {
      throw StateError('Models must come from the trusted Omnies marketplace.');
    }
    if (!source.path.endsWith('/manifest.json')) {
      throw StateError('The install link must point to a model manifest.');
    }
  }

  OmnixModelTemplate _template(String value) => switch (value) {
    'general' => OmnixModelTemplate.general,
    'gemma4' => OmnixModelTemplate.gemma4,
    'qwen3' => OmnixModelTemplate.qwen3,
    'phi' => OmnixModelTemplate.phi,
    _ => throw StateError('Unsupported model template: $value'),
  };

  OmnixModelFormat _format(String value) => switch (value) {
    'litertlm' => OmnixModelFormat.liteRtLm,
    _ => throw StateError('Only .litertlm models are supported.'),
  };

  OmnixBackendPreference _backend(String value) => switch (value) {
    'cpu' => OmnixBackendPreference.cpu,
    'gpu' => OmnixBackendPreference.gpu,
    'npu' => OmnixBackendPreference.npu,
    _ => throw StateError('Unsupported model backend: $value'),
  };

  String _requiredString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Missing model field: $key');
    }
    return value.trim();
  }

  int _requiredInt(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! num || value.toInt() != value) {
      throw FormatException('Invalid model field: $key');
    }
    return value.toInt();
  }

  double _number(Map<String, dynamic> map, String key, double fallback) {
    final value = map[key];
    return value is num ? value.toDouble() : fallback;
  }

  int _integer(Map<String, dynamic> map, String key, int fallback) {
    final value = map[key];
    return value is num ? value.toInt() : fallback;
  }
}
