import 'dart:convert';
import 'package:omnix/omnix.dart';
import 'package:test/test.dart';
import 'interaction_session_test.dart' show Transport;

class SamplingTransport extends Transport
    implements OmnixSamplingSessionTransport, OmnixReconfigurationTransport {
  String? received;
  int? updatedTokens;
  @override
  Future<void> reconfigureSession(
    BigInt id,
    int tokens,
    String? samplingJson,
  ) async {
    updatedTokens = tokens;
    received = samplingJson;
  }

  @override
  Future<void> reconfigureAgent(
    BigInt id,
    int tokens,
    String? samplingJson,
  ) async {}
  @override
  Future<BigInt> openSampled(
    BigInt engine,
    String path,
    String? instructions,
    int tokens,
    bool images,
    bool audio,
    String samplingJson,
  ) async {
    received = samplingJson;
    return BigInt.two;
  }
}

void main() {
  test('live settings update without reopening or clearing context', () async {
    final transport = SamplingTransport();
    final engine = await OmnixCognitiveEngine.open(
      runtimes: ['litertlm'],
      transport: transport,
    );
    final session = await engine.startSession(modelPath: 'model');
    await session.reconfigure(
      maxOutputTokens: 512,
      sampling: const OmnixSamplingOptions(seed: 42),
    );
    expect(transport.updatedTokens, 512);
    expect(jsonDecode(transport.received!)['seed'], 42);
    expect(transport.sessionCloses, 0);
    expect(transport.restored, isNull);
    await session.close();
    await engine.close();
    await expectLater(
      session.reconfigure(maxOutputTokens: 512),
      throwsStateError,
    );
  });
  test('sampler values reach the native transport unchanged', () async {
    final transport = SamplingTransport();
    final engine = await OmnixCognitiveEngine.open(
      runtimes: ['litertlm'],
      transport: transport,
    );
    final session = await engine.startSession(
      modelPath: 'model.litertlm',
      sampling: const OmnixSamplingOptions(
        temperature: 0.4,
        topK: 30,
        topP: 0.9,
        seed: 123,
      ),
    );
    expect(jsonDecode(transport.received!), {
      'temperature': 0.4,
      'top_k': 30,
      'top_p': 0.9,
      'seed': 123,
    });
    await session.close();
    await engine.close();
  });
  test(
    'unsupported transports do not silently ignore requested sampling',
    () async {
      final engine = await OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        transport: Transport(),
      );
      await expectLater(
        engine.startSession(
          modelPath: 'model.litertlm',
          sampling: const OmnixSamplingOptions(),
        ),
        throwsUnsupportedError,
      );
      await engine.close();
    },
  );
  test('reject invalid sampler settings before crossing the bridge', () {
    for (final options in [
      OmnixSamplingOptions(temperature: double.nan),
      const OmnixSamplingOptions(topK: 0),
      const OmnixSamplingOptions(topP: 0),
      const OmnixSamplingOptions(seed: -1),
      const OmnixSamplingOptions(seed: 2147483648),
    ]) {
      expect(options.encode, throwsArgumentError);
    }
    expect(const OmnixSamplingOptions(temperature: 0).encode(), isNotEmpty);
  });
}
