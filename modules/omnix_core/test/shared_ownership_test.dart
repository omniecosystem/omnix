import 'package:omnix_core/omnix_core.dart';
import 'package:test/test.dart';

class _Shared implements OmnixCoreSharedTransport {
  List<Object?>? settings;
  int independentLoads = 0;
  @override
  Future<BigInt> loadSharedModel(
    String model,
    String? library,
    int context,
    bool images,
    bool audio,
    String? cache,
  ) async {
    settings = [model, library, context, images, audio, cache];
    return BigInt.one;
  }

  @override
  Future<BigInt> loadRoutedModel(
    String model,
    String? library,
    int context,
  ) async {
    independentLoads++;
    return BigInt.two;
  }

  @override
  Future<int> sharedModelCount() async => 1;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Legacy implements OmnixCoreRoutedTransport {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'opt-in shared load forwards configuration without an independent load',
    () async {
      final transport = _Shared();
      final core = OmnixCore(transport: transport);
      await core.loadModel(
        modelPath: 'model',
        libraryPath: 'library',
        contextTokens: 4096,
        enableImages: true,
        enableAudio: true,
        cacheDirectory: 'cache',
        shareRuntime: true,
      );
      expect(transport.settings, [
        'model',
        'library',
        4096,
        true,
        true,
        'cache',
      ]);
      expect(transport.independentLoads, 0);
      expect(await core.sharedModelCount(), 1);
    },
  );
  test('existing callers keep independent ownership', () async {
    final transport = _Shared();
    await OmnixCore(transport: transport).loadModel(modelPath: 'model');
    expect(transport.independentLoads, 1);
    expect(transport.settings, isNull);
  });
  test('legacy transports reject explicit shared ownership', () async {
    final core = OmnixCore(transport: _Legacy());
    await expectLater(
      core.loadModel(modelPath: 'model', shareRuntime: true),
      throwsUnsupportedError,
    );
    await expectLater(core.sharedModelCount(), throwsUnsupportedError);
  });
}
