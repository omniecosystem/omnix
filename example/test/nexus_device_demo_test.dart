// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/nexus_device_demo.dart';
import 'package:omnix_example/public_knowledge_demo.dart';

void main() {
  group('two-device demo options', () {
    test('uses this node identity and remote origin independently', () {
      final options = parseNexusDeviceOptions(
        ['ask', '--question', 'blue notebook'],
        environment: {
          'OMNIXUS_NODE_DIR': 'private-node-b',
          'OMNIXUS_DEMO_URL': 'https://peer.example',
        },
      );
      expect(options.nodeDirectory, 'private-node-b');
      expect(options.origin, 'https://peer.example');
      expect(options.question, 'blue notebook');
    });

    test('rejects missing identity, origin, and question', () {
      expect(
        () => parseNexusDeviceOptions(['show'], environment: {}),
        throwsFormatException,
      );
      expect(
        () => parseNexusDeviceOptions([
          'serve',
          '--node-dir',
          'private-node-a',
        ], environment: {}),
        throwsFormatException,
      );
      expect(
        () => parseNexusDeviceOptions([
          'ask',
          '--node-dir',
          'private-node-a',
          '--origin',
          'https://peer.example',
        ], environment: {}),
        throwsFormatException,
      );
    });

    test('rejects invalid port and unexpected positional input', () {
      expect(
        () => parseNexusDeviceOptions([
          'serve',
          '--node-dir',
          'a',
          '--origin',
          'https://a.example',
          '--port',
          '70000',
        ], environment: {}),
        throwsFormatException,
      );
      expect(
        () => parseNexusDeviceOptions([
          'show',
          '--node-dir',
          'a',
          'extra',
        ], environment: {}),
        throwsFormatException,
      );
    });
  });

  test(
    'fixture indexes distinct public data but never retrieves private data',
    () async {
      final knowledge = await publicDemoKnowledge(
        File('public_knowledge_laptop_b.json'),
      );
      final publicMatches = await knowledge.retrieve(
        OmnixKnowledgeQuery(
          text: 'blue notebook',
          allowedAccess: {OmnixKnowledgeAccess.public},
        ),
      );
      expect(publicMatches, hasLength(1));
      expect(publicMatches.first.chunk.content, contains('Laptop B indexes'));

      final privateMatches = await knowledge.retrieve(
        OmnixKnowledgeQuery(
          text: 'private note',
          allowedAccess: {OmnixKnowledgeAccess.public},
        ),
      );
      expect(privateMatches, isEmpty);
      final localPrivateMatches = await knowledge.retrieve(
        OmnixKnowledgeQuery(
          text: 'private note',
          allowedAccess: {OmnixKnowledgeAccess.private},
        ),
      );
      expect(localPrivateMatches, hasLength(1));
    },
  );
}
