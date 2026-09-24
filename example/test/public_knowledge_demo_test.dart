import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/public_knowledge_demo.dart';

void main() {
  group('public node demo', () {
    late OmnixNodeKnowledgeService service;

    setUp(() async {
      service = await publicDemoService(File('public_knowledge.json'));
    });

    test('answers an allowed public query through Omnix', () async {
      final result = await queryPublicDemo(
        service,
        'paired-demo-client',
        'What is Omnixus?',
      );
      expect(result, isA<OmnixNodeKnowledgeSuccess>());
      final success = result as OmnixNodeKnowledgeSuccess;
      expect(success.matches.single.chunk.documentId, 'omnixus');
    });

    test('private content is never returned', () async {
      final result = await queryPublicDemo(
        service,
        'paired-demo-client',
        'private note',
      );
      expect((result as OmnixNodeKnowledgeSuccess).matches, isEmpty);
    });

    test('an unknown caller is rejected before retrieval', () async {
      final result = await queryPublicDemo(service, 'unknown', 'Omnixus');
      expect(result, isA<OmnixNodeKnowledgeFailure>());
    });
  });
}
