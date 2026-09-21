import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  const parser = OmnixModelManifestParser(
    trustedMarketplaceHost: 'omnies.omniecosystem.xyz',
  );
  final source = Uri.parse(
    'https://omnies.omniecosystem.xyz/models/test-model/manifest.json',
  );

  Map<String, dynamic> validManifest() => {
    'schema_version': 1,
    'id': 'test-model',
    'version': '1.0.0',
    'display_name': 'Test Model',
    'description': 'A reviewed model used for validation.',
    'model_type': 'general',
    'file_type': 'litertlm',
    'preferred_backend': 'cpu',
    'url':
        'https://huggingface.co/developer/test-model/resolve/0123456789abcdef0123456789abcdef01234567/test-model.litertlm',
    'size_bytes': 2000000,
    'sha256': 'a' * 64,
    'license': 'Apache-2.0',
    'thinking': false,
    'thinking_mandatory': false,
    'function_calls': true,
    'input_modalities': ['text', 'image', 'audio'],
    'platforms': ['android', 'windows'],
    'temperature': 0.7,
    'top_k': 40,
    'top_p': 0.95,
    'max_tokens': 4096,
  };

  group('OmnixModelManifestParser', () {
    test('accepts a pinned public LiteRT-LM manifest', () {
      final model = parser.parse(source: source, manifest: validManifest());

      expect(model.template, OmnixModelTemplate.general);
      expect(model.format, OmnixModelFormat.liteRtLm);
      expect(model.preferredBackend, OmnixBackendPreference.cpu);
      expect(model.sizeBytes, 2000000);
      expect(model.generationDefaults.maxTokens, 4096);
      expect(model.capabilities.supportsImages, isTrue);
      expect(model.capabilities.supportsAudio, isTrue);
      expect(model.capabilities.supportsFunctionCalls, isTrue);
      expect(model.capabilities.targetPlatforms, {
        OmnixTargetPlatform.android,
        OmnixTargetPlatform.windows,
      });
    });

    test('rejects unpinned download URLs', () {
      final manifest = validManifest()
        ..['url'] =
            'https://huggingface.co/developer/test-model/resolve/main/test-model.litertlm';

      expect(
        () => parser.parse(source: source, manifest: manifest),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects untrusted marketplace sources', () {
      expect(
        () => parser.parse(
          source: Uri.parse('https://example.com/models/test/manifest.json'),
          manifest: validManifest(),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects unsupported model formats', () {
      final manifest = validManifest()..['file_type'] = 'onnx';

      expect(
        () => parser.parse(source: source, manifest: manifest),
        throwsA(isA<StateError>()),
      );
    });

    test('defaults omitted capabilities conservatively', () {
      final manifest = validManifest()
        ..remove('function_calls')
        ..remove('input_modalities')
        ..remove('platforms');

      final model = parser.parse(source: source, manifest: manifest);

      expect(model.capabilities.inputModalities, {OmnixInputModality.text});
      expect(model.capabilities.supportsFunctionCalls, isFalse);
      expect(model.capabilities.targetPlatforms, isEmpty);
    });

    test('rejects a multimodal declaration without text input', () {
      final manifest = validManifest()..['input_modalities'] = ['image'];

      expect(
        () => parser.parse(source: source, manifest: manifest),
        throwsFormatException,
      );
    });
  });
}
