import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_matterjs_app/packaged_controller_check.dart';

void main() {
  test(
    'missing packaged runtime fails rather than invoking global Node',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'omnix-package-check-',
      );
      try {
        await expectLater(
          checkPackagedController(
            applicationExecutable: p.join(directory.path, 'app.exe'),
          ),
          throwsStateError,
        );
      } finally {
        await directory.delete();
      }
    },
    skip: !Platform.isWindows,
  );
}
