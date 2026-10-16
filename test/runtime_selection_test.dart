import 'package:test/test.dart';
import '../hook/runtime_selection.dart';

void main() {
  test(
    'external native assets require explicit ownership; Android stays qualified',
    () {
      expect(selectLiteRtLmAssetOwner(null, android: false), 'self');
      expect(selectLiteRtLmAssetOwner('external', android: false), 'external');
      expect(
        selectLiteRtLmAssetOwner('omnix_core', android: true),
        'omnix_core',
      );
      expect(selectLiteRtLmAssetOwner('external', android: true), 'external');
      expect(
        () => selectLiteRtLmAssetOwner('other', android: false),
        throwsArgumentError,
      );
    },
  );
  test('Android external loader accepts basenames, not paths', () {
    expect(selectAndroidLiteRtLmLibrary(null), 'liblitert-lm.so');
    expect(selectAndroidLiteRtLmLibrary('libLiteRtLm.so'), 'libLiteRtLm.so');
    for (final value in <Object>[
      '../lib.so',
      '/lib.so',
      r'C:\lib.so',
      '',
      42,
    ]) {
      expect(() => selectAndroidLiteRtLmLibrary(value), throwsArgumentError);
    }
    expect(selectLiteRtLmAssetOwner('self', android: true), 'self');
  });
  test('Android constraint provider ownership is explicit', () {
    expect(includeAndroidConstraintProvider(null), isTrue);
    expect(includeAndroidConstraintProvider('self'), isTrue);
    expect(includeAndroidConstraintProvider('external'), isFalse);
    expect(
      () => includeAndroidConstraintProvider('other'),
      throwsArgumentError,
    );
  });
  test('root remains lean unless explicitly configured', () {
    expect(selectRootRuntimes(null, null), isEmpty);
    expect(selectRootRuntimes([], null), isEmpty);
    expect(selectRootRuntimes(['litertlm', 'llamacpp'], null), [
      'litertlm',
      'llamacpp',
    ]);
  });
  test('target override replaces rather than merges runtime selection', () {
    expect(
      selectRootRuntimes(
        ['litertlm'],
        {
          'runtimes': ['llamacpp'],
        },
      ),
      ['llamacpp'],
    );
    expect(selectRootRuntimes(['litertlm'], {'runtimes': []}), isEmpty);
  });
  test('invalid selection fails before native work begins', () {
    for (final value in <Object>[
      'litertlm',
      ['other'],
      ['litertlm', 'litertlm'],
    ]) {
      expect(() => selectRootRuntimes(value, null), throwsArgumentError);
    }
    expect(() => selectRootRuntimes(null, 'windows'), throwsArgumentError);
  });
}
