// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  group('OmnixInferenceProviderCapabilities', () {
    const provider = OmnixInferenceProviderCapabilities(
      providerId: 'test-provider',
      formats: {OmnixModelFormat.liteRtLm},
      inputModalities: {OmnixInputModality.text, OmnixInputModality.image},
      platform: OmnixTargetPlatform.android,
      supportsThinking: true,
      supportsFunctionCalls: false,
    );

    test('accepts a compatible model', () {
      final result = provider.evaluate(
        _manifest(
          capabilities: const OmnixModelCapabilities(
            inputModalities: {
              OmnixInputModality.text,
              OmnixInputModality.image,
            },
            supportsThinking: true,
            targetPlatforms: {OmnixTargetPlatform.android},
          ),
        ),
      );

      expect(result.isCompatible, isTrue);
      expect(result.isFullySupported, isTrue);
      expect(result.issues, isEmpty);
    });

    test('reports every incompatible capability', () {
      final result = provider.evaluate(
        _manifest(
          capabilities: const OmnixModelCapabilities(
            inputModalities: {
              OmnixInputModality.text,
              OmnixInputModality.audio,
            },
            supportsFunctionCalls: true,
            targetPlatforms: {OmnixTargetPlatform.windows},
          ),
        ),
      );

      expect(result.isCompatible, isFalse);
      expect(result.isFullySupported, isFalse);
      expect(result.issues, hasLength(1));
      expect(result.unavailableCapabilities, hasLength(2));
      expect(result.issues.join(' '), contains('android'));
      expect(result.unavailableCapabilities.join(' '), contains('audio'));
      expect(
        result.unavailableCapabilities.join(' '),
        contains('Function calling'),
      );
    });
  });

  group('OmnixConversationConfiguration.fromManifest', () {
    test('derives generation and modality settings', () {
      final manifest = _manifest(
        capabilities: const OmnixModelCapabilities(
          inputModalities: {OmnixInputModality.text, OmnixInputModality.audio},
          supportsThinking: true,
          requiresThinking: true,
        ),
      );

      final configuration = OmnixConversationConfiguration.fromManifest(
        manifest,
      );

      expect(configuration.modelTemplate, manifest.template);
      expect(configuration.maxTokens, 4096);
      expect(configuration.temperature, 0.8);
      expect(configuration.supportsAudio, isTrue);
      expect(configuration.supportsImages, isFalse);
      expect(configuration.thinking, isTrue);
      expect(configuration.modelCapabilities, same(manifest.capabilities));
    });

    test('rejects disabling required thinking', () {
      final manifest = _manifest(
        capabilities: const OmnixModelCapabilities(
          supportsThinking: true,
          requiresThinking: true,
        ),
      );

      expect(
        () => OmnixConversationConfiguration.fromManifest(
          manifest,
          thinking: false,
        ),
        throwsArgumentError,
      );
    });
  });
}

OmnixModelManifest _manifest({required OmnixModelCapabilities capabilities}) =>
    OmnixModelManifest(
      source: Uri.parse('https://registry.example/model/manifest.json'),
      id: 'test-model',
      version: '1.0.0',
      displayName: 'Test model',
      description: 'A model used by capability tests.',
      template: OmnixModelTemplate.gemma4,
      format: OmnixModelFormat.liteRtLm,
      preferredBackend: OmnixBackendPreference.cpu,
      downloadUri: Uri.parse('https://example.com/model.litertlm'),
      sizeBytes: 2000000,
      sha256: 'a' * 64,
      license: 'Apache-2.0',
      capabilities: capabilities,
      generationDefaults: const OmnixGenerationDefaults(
        temperature: 0.8,
        topK: 40,
        topP: 0.95,
        maxTokens: 4096,
      ),
    );
