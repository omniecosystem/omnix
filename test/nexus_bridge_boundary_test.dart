import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('aggregate bridge leaves Nexus handles to the standalone module', () {
    final exports = File('rust/src/api/mod.rs').readAsStringSync();
    expect(exports, isNot(contains('pub mod nexus;')));
    expect(exports, isNot(contains('pub mod matter;')));
    final generated = File(
      'lib/src/rust/frb_generated.dart',
    ).readAsStringSync();
    expect(generated, isNot(contains("import 'api/nexus.dart'")));
    expect(generated, isNot(contains("import 'api/matter.dart'")));
  });
}
