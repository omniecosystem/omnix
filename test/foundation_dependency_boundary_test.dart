import 'dart:io';
import 'package:test/test.dart';

void main() {
  test('retired Flutter host and driver stay outside the headless root', () {
    expect(Directory('reference_example').existsSync(), isFalse);
    expect(Directory('test_driver').existsSync(), isFalse);
    expect(
      File('example/test_driver/integration_test.dart').existsSync(),
      isTrue,
    );
  });
  test('root manifest remains framework-free and companion-neutral', () {
    final manifest = File('pubspec.yaml').readAsStringSync();
    expect(manifest, isNot(matches(RegExp(r'^\s+flutter:', multiLine: true))));
    expect(manifest, isNot(contains('flutter_gemma:')));
    expect(manifest, isNot(contains('flutter_edge_ai:')));
    for (final companion in ['core', 'nexus', 'knowledge', 'storage']) {
      expect(manifest, isNot(contains('omnix_$companion:')));
    }
  });
  test('root libraries do not import archived or companion Dart APIs', () {
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('package:omnix_legacy/')),
        reason: file.path,
      );
      expect(source, isNot(contains('package:flutter/')), reason: file.path);
      for (final companion in ['core', 'nexus', 'knowledge', 'storage']) {
        expect(
          source,
          isNot(contains('package:omnix_$companion/')),
          reason: file.path,
        );
      }
    }
  });
}
