import 'dart:convert';
import 'package:omnix/omnix.dart';
import 'package:test/test.dart';
import 'interaction_session_test.dart' show Transport;

class ConfiguredTransport extends Transport
    implements OmnixRuntimeConfigurationTransport {
  OmnixLiteRtLmOptions? options;
  @override
  OmnixSessionTransport withRuntimeConfiguration(OmnixLiteRtLmOptions options) {
    this.options = options;
    return this;
  }
}

void main() {
  test('all backends are explicit, with no automatic fallback', () async {
    for (final backend in OmnixLiteRtLmBackend.values) {
      final transport = ConfiguredTransport();
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: transport,
        litertlm: OmnixLiteRtLmOptions(backend: backend),
      );
      expect(jsonDecode(transport.options!.encode())['backend'], backend.name);
      await engine.close();
    }
  });
  test('incompatible configuration fails before opening a transport', () async {
    expect(
      () => const OmnixLiteRtLmOptions(
        backend: OmnixLiteRtLmBackend.gpu,
        dispatchDirectory: 'unused',
      ).encode(),
      throwsArgumentError,
    );
    await expectLater(
      OmnixCognitiveEngine.open(
        runtimes: ['llamacpp'],
        transport: ConfiguredTransport(),
        litertlm: const OmnixLiteRtLmOptions(),
      ),
      throwsArgumentError,
    );
    await expectLater(
      OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: Transport(),
        litertlm: const OmnixLiteRtLmOptions(backend: OmnixLiteRtLmBackend.gpu),
      ),
      throwsUnsupportedError,
    );
  });
}
