import 'dart:convert';

import 'package:omnix/omnix.dart';
import 'package:omnix/omnix_flutter_gemma.dart';
import 'package:test/test.dart';

void main() {
  group('FlutterGemmaKnowledgeBackend', () {
    late _FakeRagGateway gateway;
    late FlutterGemmaKnowledgeBackend backend;

    setUp(() {
      gateway = _FakeRagGateway();
      backend = FlutterGemmaKnowledgeBackend(
        databasePath: 'knowledge.db',
        gateway: gateway,
      );
    });

    test('initializes the configured database path', () async {
      await backend.initialize();

      expect(gateway.databasePath, 'knowledge.db');
    });

    test('indexes content with provenance and access metadata', () async {
      await backend.index(_chunk(access: OmnixKnowledgeAccess.public));

      expect(gateway.addedId, 'document:0');
      expect(gateway.addedContent, 'Omnix knowledge');
      final metadata = jsonDecode(gateway.addedMetadata!) as Map;
      expect(metadata['documentId'], 'document');
      expect(metadata['sourceTitle'], 'Architecture');
      expect(metadata['sourceUri'], 'https://example.com/architecture');
      expect(metadata['access'], 'public');
      expect(metadata['metadata'], {'language': 'en'});
    });

    test(
      'over-fetches then enforces access without provider filters',
      () async {
        gateway.hits = [
          _hit('private:0', access: 'private', score: 0.99),
          _hit('public:0', access: 'public', score: 0.9),
          _hit('public:1', access: 'public', score: 0.8),
        ];

        final matches = await backend.search(
          OmnixKnowledgeQuery(
            text: 'query',
            topK: 2,
            minimumScore: 0.4,
            allowedAccess: const {OmnixKnowledgeAccess.public},
          ),
        );

        expect(gateway.searchedTopK, 8);
        expect(gateway.searchedThreshold, 0.4);
        expect(matches.map((match) => match.chunk.id), [
          'public:0',
          'public:1',
        ]);
      },
    );

    test('maps legacy metadata and fails closed to private access', () async {
      gateway.hits = const [
        FlutterGemmaRagHit(
          id: 'legacy:3',
          content: 'Legacy content',
          similarity: 0.7,
          metadata: '{"source":"Old notes","documentId":"legacy"}',
        ),
      ];

      final matches = await backend.search(OmnixKnowledgeQuery(text: 'legacy'));

      expect(matches.single.chunk.documentId, 'legacy');
      expect(matches.single.chunk.source.title, 'Old notes');
      expect(matches.single.chunk.access, OmnixKnowledgeAccess.private);
    });

    test('delegates removal, flush, and clear', () async {
      await backend.remove('document:0');
      await backend.flush();
      await backend.clear();

      expect(gateway.removed, ['document:0']);
      expect(gateway.flushCount, 1);
      expect(gateway.clearCount, 1);
    });
  });
}

OmnixKnowledgeChunk _chunk({required OmnixKnowledgeAccess access}) =>
    OmnixKnowledgeChunk(
      id: 'document:0',
      documentId: 'document',
      content: 'Omnix knowledge',
      source: OmnixKnowledgeSource(
        id: 'document',
        title: 'Architecture',
        uri: Uri.parse('https://example.com/architecture'),
      ),
      access: access,
      metadata: const {'language': 'en'},
    );

FlutterGemmaRagHit _hit(
  String id, {
  required String access,
  required double score,
}) => FlutterGemmaRagHit(
  id: id,
  content: '$id content',
  similarity: score,
  metadata: jsonEncode({
    'documentId': id.split(':').first,
    'sourceId': id.split(':').first,
    'sourceTitle': '$id source',
    'access': access,
  }),
);

final class _FakeRagGateway implements FlutterGemmaRagGateway {
  String? databasePath;
  String? addedId;
  String? addedContent;
  String? addedMetadata;
  int? searchedTopK;
  double? searchedThreshold;
  List<FlutterGemmaRagHit> hits = [];
  final List<String> removed = [];
  int flushCount = 0;
  int clearCount = 0;

  @override
  Future<void> initialize(String databasePath) async {
    this.databasePath = databasePath;
  }

  @override
  Future<void> addDocument({
    required String id,
    required String content,
    String? metadata,
  }) async {
    addedId = id;
    addedContent = content;
    addedMetadata = metadata;
  }

  @override
  Future<List<FlutterGemmaRagHit>> searchSimilar({
    required String query,
    required int topK,
    required double threshold,
  }) async {
    searchedTopK = topK;
    searchedThreshold = threshold;
    return hits;
  }

  @override
  Future<void> removeDocument(String id) async => removed.add(id);

  @override
  Future<void> flush() async {
    flushCount++;
  }

  @override
  Future<void> clear() async {
    clearCount++;
  }
}
