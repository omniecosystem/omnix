import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  group('OmnixKnowledgeCoordinator', () {
    late _FakeKnowledgeBackend backend;
    late OmnixKnowledgeCoordinator coordinator;

    setUp(() {
      backend = _FakeKnowledgeBackend();
      coordinator = OmnixKnowledgeCoordinator(
        backend,
        estimator: const _WordEstimator(),
      );
    });

    test('initializes once and flushes a validated document index', () async {
      await coordinator.indexDocument(_privateDocument, [_privateChunk]);
      await coordinator.initialize();

      expect(backend.initializeCalls, 1);
      expect(backend.indexed, [_privateChunk]);
      expect(backend.flushCalls, 1);
    });

    test('rejects chunks from another document before writing', () async {
      final wrongChunk = _chunk(
        id: 'other:0',
        documentId: 'other',
        access: OmnixKnowledgeAccess.private,
      );

      await expectLater(
        coordinator.indexDocument(_privateDocument, [wrongChunk]),
        throwsArgumentError,
      );
      expect(backend.indexed, isEmpty);
      expect(backend.flushCalls, 0);
    });

    test('normalizes scores, access, duplicates, and top-k', () async {
      backend.textResults = [
        OmnixKnowledgeMatch(chunk: _privateChunk, score: 0.6),
        OmnixKnowledgeMatch(chunk: _privateChunk, score: 0.9),
        OmnixKnowledgeMatch(chunk: _publicChunk, score: 0.8),
        OmnixKnowledgeMatch(chunk: _lowChunk, score: 0.2),
      ];

      final results = await coordinator.retrieve(
        OmnixKnowledgeQuery(
          text: 'query',
          topK: 1,
          minimumScore: 0.5,
          allowedAccess: const {OmnixKnowledgeAccess.private},
        ),
      );

      expect(results, hasLength(1));
      expect(results.single.chunk.id, _privateChunk.id);
      expect(results.single.score, 0.9);
    });

    test('builds bounded context with matching ordered citations', () async {
      backend.textResults = [
        OmnixKnowledgeMatch(chunk: _privateChunk, score: 0.9),
        OmnixKnowledgeMatch(chunk: _secondPrivateChunk, score: 0.8),
      ];

      final context = await coordinator.buildContext(
        OmnixKnowledgeQuery(text: 'query'),
        maxTokens: 6,
      );

      expect(context.text, contains(_privateChunk.content));
      expect(context.text, isNot(contains(_secondPrivateChunk.content)));
      expect(context.citations.single.chunkId, _privateChunk.id);
      expect(context.omittedMatchCount, 1);
    });

    test('creates a transport-ready semantic query', () async {
      final query = OmnixKnowledgeQuery(
        text: 'private query',
        topK: 3,
        minimumScore: 0.4,
        allowedAccess: const {OmnixKnowledgeAccess.public},
      );

      final semantic = await coordinator.createSemanticQuery(query);

      expect(
        semantic.embedding.space.identifier,
        backend.embeddingSpace.identifier,
      );
      expect(semantic.topK, 3);
      expect(semantic.minimumScore, 0.4);
      expect(semantic.allowedAccess, {OmnixKnowledgeAccess.public});
    });

    test('rejects vectors from an incompatible embedding space', () async {
      final query = OmnixSemanticQuery(
        embedding: OmnixEmbedding(
          space: OmnixEmbeddingSpace(modelId: 'other', dimensions: 2),
          values: const [0.5, 0.5],
        ),
      );

      await expectLater(
        coordinator.retrieveSemantic(query),
        throwsArgumentError,
      );
      expect(backend.semanticSearchCalls, 0);
    });
  });
}

final _privateDocument = OmnixKnowledgeDocument(
  id: 'private',
  title: 'Private notes',
  createdAt: DateTime.utc(2026),
);

final _privateChunk = _chunk(
  id: 'private:0',
  documentId: 'private',
  content: 'alpha beta',
  access: OmnixKnowledgeAccess.private,
);

final _secondPrivateChunk = _chunk(
  id: 'private:1',
  documentId: 'private',
  content: 'gamma delta epsilon',
  access: OmnixKnowledgeAccess.private,
);

final _publicChunk = _chunk(
  id: 'public:0',
  documentId: 'public',
  access: OmnixKnowledgeAccess.public,
);

final _lowChunk = _chunk(
  id: 'private:2',
  documentId: 'private',
  access: OmnixKnowledgeAccess.private,
);

OmnixKnowledgeChunk _chunk({
  required String id,
  required String documentId,
  String content = 'content',
  required OmnixKnowledgeAccess access,
}) => OmnixKnowledgeChunk(
  id: id,
  documentId: documentId,
  content: content,
  source: OmnixKnowledgeSource(id: documentId, title: '$documentId source'),
  access: access,
);

final class _WordEstimator implements OmnixTokenEstimator {
  const _WordEstimator();

  @override
  int estimateMessage(OmnixMessage message) => estimateText(message.text);

  @override
  int estimateText(String text) => text.split(RegExp(r'\s+')).length;
}

final class _FakeKnowledgeBackend implements OmnixSemanticKnowledgeBackend {
  @override
  final OmnixEmbeddingSpace embeddingSpace = OmnixEmbeddingSpace(
    modelId: 'embedding-gemma',
    revision: 'test',
    dimensions: 2,
  );

  int initializeCalls = 0;
  int flushCalls = 0;
  int semanticSearchCalls = 0;
  final List<OmnixKnowledgeChunk> indexed = [];
  List<OmnixKnowledgeMatch> textResults = [];
  List<OmnixKnowledgeMatch> semanticResults = [];

  @override
  Future<void> initialize() async => initializeCalls++;

  @override
  Future<void> index(OmnixKnowledgeChunk chunk) async => indexed.add(chunk);

  @override
  Future<void> remove(String chunkId) async {}

  @override
  Future<List<OmnixKnowledgeMatch>> search(OmnixKnowledgeQuery query) async =>
      textResults;

  @override
  Future<void> flush() async => flushCalls++;

  @override
  Future<void> clear() async {}

  @override
  Future<OmnixEmbedding> embedQuery(String text) async =>
      OmnixEmbedding(space: embeddingSpace, values: const [0.25, 0.75]);

  @override
  Future<List<OmnixKnowledgeMatch>> searchSemantic(
    OmnixSemanticQuery query,
  ) async {
    semanticSearchCalls++;
    return semanticResults;
  }
}
