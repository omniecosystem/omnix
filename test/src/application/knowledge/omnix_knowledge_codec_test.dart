import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  const codec = OmnixKnowledgeCodec();

  test('round-trips a semantic query without provider types', () {
    final query = OmnixSemanticQuery(
      embedding: OmnixEmbedding(
        space: OmnixEmbeddingSpace(
          modelId: 'embedding-gemma',
          revision: 'abc123',
          dimensions: 3,
        ),
        values: const [0.1, 0.2, 0.3],
      ),
      topK: 7,
      minimumScore: 0.42,
      allowedAccess: const {OmnixKnowledgeAccess.public},
    );

    final restored = codec.decodeSemanticQuery(
      codec.encodeSemanticQuery(query),
    );

    expect(
      restored.embedding.space.identifier,
      query.embedding.space.identifier,
    );
    expect(restored.embedding.values, query.embedding.values);
    expect(restored.topK, 7);
    expect(restored.minimumScore, 0.42);
    expect(restored.allowedAccess, {OmnixKnowledgeAccess.public});
  });

  test('round-trips text and embedding node query modalities', () {
    final text = codec.decodeNodeQuery(
      codec.encodeNodeQuery(
        OmnixNodeTextKnowledgeQuery(
          OmnixKnowledgeQuery(
            text: 'What is shared?',
            topK: 3,
            allowedAccess: const {OmnixKnowledgeAccess.public},
          ),
        ),
      ),
    );
    expect(text, isA<OmnixNodeTextKnowledgeQuery>());
    expect((text as OmnixNodeTextKnowledgeQuery).query.text, 'What is shared?');

    final embedding = codec.decodeNodeQuery(
      codec.encodeNodeQuery(
        OmnixNodeEmbeddingKnowledgeQuery(
          OmnixSemanticQuery(
            embedding: OmnixEmbedding(
              space: OmnixEmbeddingSpace(
                modelId: 'embedding-gemma',
                dimensions: 2,
              ),
              values: const [0.2, 0.8],
            ),
          ),
        ),
      ),
    );
    expect(embedding, isA<OmnixNodeEmbeddingKnowledgeQuery>());
  });

  test('round-trips an attributed retrieval match', () {
    final match = OmnixKnowledgeMatch(
      chunk: OmnixKnowledgeChunk(
        id: 'document:0',
        documentId: 'document',
        content: 'Local knowledge',
        source: OmnixKnowledgeSource(
          id: 'document',
          title: 'Notes',
          uri: Uri.parse('https://example.com/notes'),
        ),
        access: OmnixKnowledgeAccess.public,
        metadata: const {'language': 'en'},
      ),
      score: 0.91,
    );

    final restored = codec.decodeMatch(codec.encodeMatch(match));

    expect(restored.chunk.id, match.chunk.id);
    expect(restored.chunk.source.uri, match.chunk.source.uri);
    expect(restored.chunk.metadata, {'language': 'en'});
    expect(restored.score, 0.91);
  });

  test('rejects unknown schema versions and invalid vector dimensions', () {
    expect(
      () => codec.decodeSemanticQuery(const {'schemaVersion': 99}),
      throwsFormatException,
    );

    final malformed = codec.encodeSemanticQuery(
      OmnixSemanticQuery(
        embedding: OmnixEmbedding(
          space: OmnixEmbeddingSpace(modelId: 'embedder', dimensions: 2),
          values: const [0.2, 0.8],
        ),
      ),
    );
    final embedding = Map<String, Object?>.from(malformed['embedding']! as Map);
    embedding['values'] = [0.2];
    malformed['embedding'] = embedding;

    expect(() => codec.decodeSemanticQuery(malformed), throwsFormatException);
    expect(
      () => codec.decodeNodeQuery(const {'schemaVersion': 1, 'kind': 'audio'}),
      throwsFormatException,
    );
  });
}
