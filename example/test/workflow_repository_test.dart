import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_example/features/workflow/data/repositories/workflow_repository.dart';
import 'package:path/path.dart' as p;

void main() {
  test('missing saved journal fails before native execution', () async {
    final root = await Directory.systemTemp.createTemp(
      'workflow-pointer-test-',
    );
    try {
      await File(
        p.join(root.path, 'current-job'),
      ).writeAsString('demo-missing');
      final repository = WorkflowRepository(directory: root);
      await expectLater(repository.open(), throwsStateError);
      expect(
        await Directory(p.join(root.path, 'demo-missing')).exists(),
        isFalse,
      );
    } finally {
      // Only this freshly created test directory is removed.
      await root.delete(recursive: true);
    }
  });
}
