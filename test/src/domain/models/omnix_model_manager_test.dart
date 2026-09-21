// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  group('OmnixModelInstallRequest', () {
    test('creates a network request from a validated manifest', () {
      final request = OmnixModelInstallRequest.fromManifest(
        _manifest,
        foreground: true,
      );

      expect(request.template, OmnixModelTemplate.gemma4);
      expect(request.format, OmnixModelFormat.liteRtLm);
      final source = request.source as OmnixNetworkModelSource;
      expect(source.uri, _manifest.downloadUri);
      expect(source.foreground, isTrue);
      expect(request.expectedSizeBytes, _manifest.sizeBytes);
      expect(request.expectedSha256, _manifest.sha256);
      expect(request.requiresIntegrityVerification, isTrue);
    });

    test('rejects non-network URIs as network sources', () {
      expect(
        () => OmnixNetworkModelSource(Uri.parse('file:///model.litertlm')),
        throwsArgumentError,
      );
    });

    test('rejects incomplete integrity requirements', () {
      expect(
        () => OmnixModelInstallRequest(
          template: OmnixModelTemplate.general,
          format: OmnixModelFormat.liteRtLm,
          source: OmnixAssetModelSource('model.litertlm'),
          expectedSizeBytes: 100,
        ),
        throwsArgumentError,
      );
    });
  });

  test('cancellation is emitted once and remains observable', () async {
    final token = OmnixCancellationToken();
    final cancellation = token.cancellations.first;

    token.cancel('not now');
    token.cancel('ignored');

    expect(await cancellation, 'not now');
    expect(token.isCancelled, isTrue);
    expect(token.reason, 'not now');
    expect(token.throwIfCancelled, throwsA(isA<OmnixOperationCancelled>()));
  });
}

final _manifest = OmnixModelManifest(
  source: Uri.parse('https://registry.example/models/gemma/manifest.json'),
  id: 'gemma-test',
  version: '1.0.0',
  displayName: 'Gemma Test',
  description: 'Test model',
  template: OmnixModelTemplate.gemma4,
  format: OmnixModelFormat.liteRtLm,
  preferredBackend: OmnixBackendPreference.cpu,
  downloadUri: Uri.parse(
    'https://huggingface.co/example/model/resolve/0123456789abcdef0123456789abcdef01234567/model.litertlm',
  ),
  sizeBytes: 1000,
  sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  license: 'Apache-2.0',
  capabilities: const OmnixModelCapabilities(supportsThinking: true),
  generationDefaults: const OmnixGenerationDefaults(
    temperature: 1,
    topK: 64,
    topP: 0.95,
    maxTokens: 4096,
  ),
);
