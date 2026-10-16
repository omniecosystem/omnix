import 'package:test/test.dart';
import '../hook/runtime_selection.dart';

void main() {
  test('runtime libraries have one explicit owner', () {
    expect(includeLiteRtLmAssets(null), isTrue);
    expect(includeLiteRtLmAssets('self'), isTrue);
    expect(includeLiteRtLmAssets('external'), isFalse);
    expect(() => includeLiteRtLmAssets('unknown'), throwsArgumentError);
    expect(
      coreTargetDefines({
        'windows': {'litertlm_assets': 'external'},
      }, 'windows')['litertlm_assets'],
      'external',
    );
  });
  test('constraint library has one explicit owner', () {
    expect(includeAndroidConstraintProvider(null), isTrue);
    expect(includeAndroidConstraintProvider('self'), isTrue);
    expect(includeAndroidConstraintProvider('external'), isFalse);
    expect(
      () => includeAndroidConstraintProvider('unknown'),
      throwsArgumentError,
    );
    final defines = coreTargetDefines({
      'android': {'litertlm_constraint_assets': 'external'},
    }, 'android');
    expect(defines['litertlm_constraint_assets'], 'external');
  });
  group('runtime build selection', () {
    test('requires an explicit nonempty selection', () {
      expect(() => selectRuntimeFeatures({}), throwsArgumentError);
      expect(
        () => selectRuntimeFeatures({'llamacpp': true}),
        throwsArgumentError,
      );
      expect(
        () => selectRuntimeFeatures({'runtimes': <String>[]}),
        throwsArgumentError,
      );
    });
    test('supports either runtime or both without implicit additions', () {
      expect(
        selectRuntimeFeatures({
          'runtimes': ['llamacpp'],
        }),
        ['llamacpp'],
      );
      expect(
        selectRuntimeFeatures({
          'runtimes': ['litertlm'],
        }),
        ['litertlm'],
      );
      expect(
        selectRuntimeFeatures({
          'runtimes': ['llamacpp', 'litertlm'],
        }),
        ['litertlm', 'llamacpp'],
      );
    });
    test('rejects ambiguous or malformed selection', () {
      for (final defines in <Map<String, Object?>>[
        {'runtimes': 'llamacpp'},
        {
          'runtimes': ['llama_cpp'],
        },
        {
          'runtimes': ['llama-cpp'],
        },
        {
          'runtimes': [1],
        },
        {
          'runtimes': ['unknown'],
        },
        {
          'runtimes': ['litertlm', 'litertlm'],
        },
        {
          'runtimes': ['litertlm'],
          'llamacpp': false,
        },
        {'llamacpp': 'true'},
      ]) {
        expect(() => selectRuntimeFeatures(defines), throwsArgumentError);
      }
    });
  });
}
