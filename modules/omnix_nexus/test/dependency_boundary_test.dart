// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('standalone Nexus has no inference or root Omnix dependency', () {
    final configFile = File(
      p.join('.dart_tool', 'package_config.json'),
    ).absolute;
    final config =
        jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    final module = (config['packages'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .singleWhere((package) => package['name'] == 'omnix_nexus');
    final moduleDirectory = p.fromUri(
      configFile.uri.resolve(module['rootUri'] as String),
    );
    final manifest = File(
      p.join(moduleDirectory, 'pubspec.yaml'),
    ).readAsStringSync();
    expect(manifest, isNot(matches(RegExp(r'^\s+omnix:', multiLine: true))));
    expect(manifest, isNot(contains('flutter_gemma')));
    expect(manifest, isNot(contains('flutter_edge_ai')));
    expect(manifest, isNot(contains('llamadart')));
    for (final file in Directory(
      p.join(moduleDirectory, 'lib'),
    ).listSync(recursive: true).whereType<File>()) {
      if (p.extension(file.path) != '.dart') continue;
      final source = file.readAsStringSync();
      expect(source, isNot(contains('package:omnix/')), reason: file.path);
      expect(
        source,
        isNot(contains('package:flutter_gemma')),
        reason: file.path,
      );
      expect(
        source,
        isNot(contains('package:flutter_edge_ai')),
        reason: file.path,
      );
    }
  });
}
