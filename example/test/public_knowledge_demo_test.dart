import 'dart:convert';
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

    test('multiple requests share one public Knowledge service', () async {
      Future<Map<String, dynamic>> ask(int id, String question) async =>
          jsonDecode(
                await handlePublicDemoRequest(
                  service,
                  jsonEncode({
                    'id': id,
                    'caller': 'paired-demo-client',
                    'question': question,
                  }),
                ),
              )
              as Map<String, dynamic>;

      final first = await ask(1, 'What is Omnixus?');
      final second = await ask(2, 'What is A2A?');
      final denied = await ask(3, 'private note');
      expect(first['status'], 'ok');
      expect(first['id'], 1);
      expect(second['status'], 'ok');
      expect(second['id'], 2);
      expect(second['answer'], contains('Agent2Agent'));
      expect(denied['status'], 'denied');
      expect(denied['id'], 3);
    });

    test('malformed local requests do not expose knowledge', () async {
      final reply = jsonDecode(await handlePublicDemoRequest(service, '{}'));
      expect(reply['status'], 'unavailable');
    });
  });
}
