import 'package:omnix_core/omnix_core.dart';
import 'package:test/test.dart';

class _Routing implements OmnixCoreRoutedTransport {
  String? path;
  String? library;
  @override
  Future<BigInt> loadRoutedModel(
    String modelPath,
    String? libraryPath,
    int contextTokens,
  ) async {
    path = modelPath;
    library = libraryPath;
    return BigInt.one;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('routing delegates artifacts without guessing the extension', () async {
    final transport = _Routing();
    final core = OmnixCore(transport: transport);
    await core.loadModel(modelPath: 'artifact.no-extension');
    expect(transport.path, 'artifact.no-extension');
    expect(transport.library, isNull);
    await core.loadModel(modelPath: 'artifact', libraryPath: 'trusted-runtime');
    expect(transport.library, 'trusted-runtime');
  });
  test('invalid requests fail before native artifact loading', () async {
    final transport = _Routing();
    final core = OmnixCore(transport: transport);
    await expectLater(core.loadModel(modelPath: ''), throwsArgumentError);
    await expectLater(
      core.loadModel(modelPath: 'artifact', contextTokens: 32769),
      throwsArgumentError,
    );
    expect(transport.path, isNull);
  });
}
