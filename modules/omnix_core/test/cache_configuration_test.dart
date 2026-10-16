import 'package:omnix_core/omnix_core.dart';
import 'package:test/test.dart';

class _Routed implements OmnixCoreRoutedTransport {
  int loads = 0;
  @override
  Future<BigInt> loadRoutedModel(
    String model,
    String? library,
    int context,
  ) async {
    loads++;
    return BigInt.one;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Configured extends _Routed implements OmnixCoreConfiguredTransport {
  List<Object?>? configuration;
  @override
  Future<BigInt> loadConfiguredModel(
    String model,
    String? library,
    int context,
    bool images,
    bool audio,
    String cache,
  ) async {
    configuration = [model, library, context, images, audio, cache];
    return BigInt.one;
  }
}

void main() {
  test('configured media preserves both encoder options', () async {
    final transport = _MediaConfigured();
    await OmnixCore(transport: transport).loadModel(
      modelPath: 'model',
      cacheDirectory: 'cache',
      enableImages: true,
      enableAudio: true,
    );
    expect(transport.configuration, ['model', null, 2048, true, true, 'cache']);
  });
  test('omitted cache preserves the existing routed transport', () async {
    final transport = _Routed();
    await OmnixCore(transport: transport).loadModel(modelPath: 'model');
    expect(transport.loads, 1);
  });

  test(
    'explicit cache and load settings reach the configured transport',
    () async {
      final transport = _Configured();
      await OmnixCore(transport: transport).loadModel(
        modelPath: 'model',
        libraryPath: 'runtime',
        contextTokens: 4096,
        cacheDirectory: 'host-owned-cache',
      );
      expect(transport.configuration, [
        'model',
        'runtime',
        4096,
        false,
        false,
        'host-owned-cache',
      ]);
      expect(transport.loads, 0);
    },
  );

  test('unsupported configuration fails without loading', () async {
    final transport = _Routed();
    await expectLater(
      OmnixCore(
        transport: transport,
      ).loadModel(modelPath: 'model', cacheDirectory: 'cache'),
      throwsUnsupportedError,
    );
    expect(transport.loads, 0);
  });

  test('blank cache fails before invoking native code', () async {
    final transport = _Configured();
    await expectLater(
      OmnixCore(
        transport: transport,
      ).loadModel(modelPath: 'model', cacheDirectory: '  '),
      throwsArgumentError,
    );
    expect(transport.configuration, isNull);
  });
}

class _MediaConfigured extends _Configured implements OmnixCoreMediaTransport {}
