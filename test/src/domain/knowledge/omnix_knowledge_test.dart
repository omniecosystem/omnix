import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  group('Omnix knowledge contracts', () {
    test('embedding vectors must match their declared space', () {
      final space = OmnixEmbeddingSpace(modelId: 'embedder', dimensions: 3);

      expect(
        () => OmnixEmbedding(space: space, values: const [1, 2]),
        throwsArgumentError,
      );
      expect(
        () => OmnixEmbedding(space: space, values: const [1, double.nan, 2]),
        throwsArgumentError,
      );
    });

    test(
      'embedding compatibility includes model, revision, and dimensions',
      () {
        final first = OmnixEmbeddingSpace(
          modelId: 'embedding-gemma',
          revision: 'v1',
          dimensions: 768,
        );
        final same = OmnixEmbeddingSpace(
          modelId: 'embedding-gemma',
          revision: 'v1',
          dimensions: 768,
        );
        final different = OmnixEmbeddingSpace(
          modelId: 'embedding-gemma',
          revision: 'v2',
          dimensions: 768,
        );

        expect(first.isCompatibleWith(same), isTrue);
        expect(first.isCompatibleWith(different), isFalse);
      },
    );

    test('semantic queries expose public knowledge by default', () {
      final query = OmnixSemanticQuery(
        embedding: OmnixEmbedding(
          space: OmnixEmbeddingSpace(modelId: 'embedder', dimensions: 2),
          values: const [0.2, 0.8],
        ),
      );

      expect(query.allowedAccess, {OmnixKnowledgeAccess.public});
    });
  });
}
