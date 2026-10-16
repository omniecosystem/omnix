import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

Future<List<String>> checkPackagedController({
  String? applicationExecutable,
}) async {
  if (!Platform.isWindows) {
    throw UnsupportedError('This qualification targets native Windows.');
  }
  final bundle = p.join(
    p.dirname(applicationExecutable ?? Platform.resolvedExecutable),
    'matterjs',
  );
  final node = p.join(bundle, 'node.exe');
  final script = p.join(bundle, 'controller.mjs');
  if (!File(node).existsSync() || !File(script).existsSync()) {
    throw StateError(
      'Packaged Matter.js runtime is missing; no global fallback.',
    );
  }
  final child = await Process.start(
    node,
    [script, '--control'],
    workingDirectory: bundle,
    runInShell: false,
    includeParentEnvironment: false,
    environment: {
      for (final name in ['SystemRoot', 'WINDIR', 'TEMP', 'TMP'])
        if (Platform.environment[name] case final String value) name: value,
      'PATH': '',
    },
  );
  final milestones = <String>[];
  final diagnostics = <String>[];
  final output = child.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        if (line.startsWith('PASS:')) milestones.add(line);
      });
  final outputDone = output.asFuture<void>();
  final errors = child.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        diagnostics.add(line);
        if (diagnostics.length > 10) diagnostics.removeAt(0);
      });
  final errorsDone = errors.asFuture<void>();
  try {
    final status = await child.exitCode.timeout(const Duration(seconds: 210));
    await outputDone;
    await errorsDone;
    if (status != 0 || milestones.length != 4) {
      throw StateError(
        'Packaged controller failed ($status): ${diagnostics.join('\n')}',
      );
    }
    return List.unmodifiable(milestones);
  } finally {
    child.kill();
    await output.cancel();
    await errors.cancel();
  }
}
