// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:omnix/omnix.dart';
import 'package:omnix_example/public_knowledge_demo.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2 || args[1].trim().isEmpty) {
    stderr.writeln(
      'Usage: dart run bin/public_knowledge_node.dart <caller> <question>',
    );
    exitCode = 2;
    return;
  }
  try {
    final service = await publicDemoService(File('public_knowledge.json'));
    final result = await queryPublicDemo(service, args[0], args[1]);
    if (result is! OmnixNodeKnowledgeSuccess || result.matches.isEmpty) {
      stderr.writeln('resource not available to this caller');
      exitCode = 2;
      return;
    }
    final match = result.matches.first;
    // dart run may write build-hook chatter to stdout before this point.
    // The Rust demo adapter only accepts text following this marker.
    stdout.write(
      '\nOMNIXUS_DEMO_ANSWER_V1\n'
      '${match.chunk.content}\nSource: ${match.chunk.source.title}',
    );
  } catch (_) {
    stderr.writeln('public knowledge unavailable');
    exitCode = 2;
  }
}
