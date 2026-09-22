import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  group('OmnixNodeKnowledgeService', () {
    late _SemanticBackend backend;
    late _Authenticator authenticator;
    late _Authorizer authorizer;
    late OmnixNodeKnowledgeService service;

    setUp(() {
      backend = _SemanticBackend();
      authenticator = _Authenticator(_authenticated());
      authorizer = _Authorizer(
        OmnixNodeKnowledgeAllowed(
          OmnixNodeKnowledgeGrant(
            allowedAccess: const {OmnixKnowledgeAccess.public},
            maximumTopK: 2,
            minimumScoreFloor: 0.5,
          ),
        ),
      );
      service = OmnixNodeKnowledgeService(
        knowledge: OmnixKnowledgeCoordinator(backend),
        authenticator: authenticator,
        authorizer: authorizer,
      );
    });

    test(
      'constrains an authenticated query to its authorization grant',
      () async {
        backend.results = [
          _match('public:0', OmnixKnowledgeAccess.public, 0.9),
          _match('private:0', OmnixKnowledgeAccess.private, 0.8),
        ];

        final result = await service.retrieve(
          _request(
            topK: 8,
            minimumScore: 0.1,
            allowedAccess: const {
              OmnixKnowledgeAccess.private,
              OmnixKnowledgeAccess.public,
            },
          ),
        );

        expect(result, isA<OmnixNodeKnowledgeSuccess>());
        final success = result as OmnixNodeKnowledgeSuccess;
        expect(success.principal.nodeId, 'peer-a');
        expect(success.appliedQuery.topK, 2);
        expect(success.appliedQuery.minimumScore, 0.5);
        expect(success.appliedQuery.allowedAccess, {
          OmnixKnowledgeAccess.public,
        });
        expect(success.matches.map((match) => match.chunk.id), ['public:0']);
      },
    );

    test('does not authorize or retrieve rejected evidence', () async {
      authenticator.result = const OmnixNodeAuthenticationRejected(
        code: OmnixAuthenticationFailureCode.invalidEvidence,
      );

      final result = await service.retrieve(_request());

      expect(
        (result as OmnixNodeKnowledgeFailure).code,
        OmnixNodeKnowledgeFailureCode.authenticationRejected,
      );
      expect(authorizer.calls, 0);
      expect(backend.searchCalls, 0);
    });

    test('rejects an expired authenticated principal defensively', () async {
      authenticator.result = OmnixNodeAuthenticated(
        OmnixNodePrincipal(
          nodeId: 'peer-a',
          authenticationScheme: 'signed-challenge',
          authenticatedAt: DateTime.utc(2026, 1, 1),
          expiresAt: DateTime.utc(2026, 1, 2),
        ),
      );

      final result = await service.retrieve(_request());

      expect(
        (result as OmnixNodeKnowledgeFailure).code,
        OmnixNodeKnowledgeFailureCode.authenticationExpired,
      );
      expect(authorizer.calls, 0);
      expect(backend.searchCalls, 0);
    });

    test('returns policy denial without touching Knowledge', () async {
      authorizer.result = const OmnixNodeKnowledgeDenied(
        reason: 'not-shared',
        safeMessage: 'Knowledge access was denied.',
      );

      final result = await service.retrieve(_request());

      final failure = result as OmnixNodeKnowledgeFailure;
      expect(failure.code, OmnixNodeKnowledgeFailureCode.authorizationDenied);
      expect(failure.safeMessage, 'Knowledge access was denied.');
      expect(backend.searchCalls, 0);
    });

    test('rejects requests outside the granted access set', () async {
      final result = await service.retrieve(
        _request(allowedAccess: const {OmnixKnowledgeAccess.private}),
      );

      expect(
        (result as OmnixNodeKnowledgeFailure).code,
        OmnixNodeKnowledgeFailureCode.incompatibleAccess,
      );
      expect(backend.searchCalls, 0);
    });
  });
}

OmnixNodeKnowledgeRequest _request({
  int topK = 5,
  double minimumScore = 0,
  Set<OmnixKnowledgeAccess> allowedAccess = const {OmnixKnowledgeAccess.public},
}) => OmnixNodeKnowledgeRequest(
  context: OmnixNodeRequestContext(
    requestId: 'request-1',
    receivedAt: DateTime.utc(2026, 1, 3),
  ),
  evidence: OmnixNodeAuthenticationEvidence(
    scheme: 'opaque-test',
    payload: const [1, 2, 3],
  ),
  query: OmnixSemanticQuery(
    embedding: OmnixEmbedding(
      space: OmnixEmbeddingSpace(modelId: 'embedder', dimensions: 2),
      values: const [0.2, 0.8],
    ),
    topK: topK,
    minimumScore: minimumScore,
    allowedAccess: allowedAccess,
  ),
);

OmnixNodeAuthenticated _authenticated() => OmnixNodeAuthenticated(
  OmnixNodePrincipal(
    nodeId: 'peer-a',
    authenticationScheme: 'supabase',
    authenticatedAt: DateTime.utc(2026, 1, 3),
    expiresAt: DateTime.utc(2026, 1, 4),
  ),
);

OmnixKnowledgeMatch _match(
  String id,
  OmnixKnowledgeAccess access,
  double score,
) => OmnixKnowledgeMatch(
  chunk: OmnixKnowledgeChunk(
    id: id,
    documentId: id.split(':').first,
    content: '$id content',
    source: OmnixKnowledgeSource(id: id.split(':').first, title: '$id source'),
    access: access,
  ),
  score: score,
);

final class _Authenticator implements OmnixNodeAuthenticator {
  _Authenticator(this.result);

  OmnixNodeAuthenticationResult result;

  @override
  Future<OmnixNodeAuthenticationResult> authenticate({
    required OmnixNodeAuthenticationEvidence evidence,
    required OmnixNodeRequestContext context,
  }) async => result;
}

final class _Authorizer implements OmnixNodeKnowledgeAuthorizer {
  _Authorizer(this.result);

  OmnixNodeKnowledgeAuthorization result;
  int calls = 0;

  @override
  Future<OmnixNodeKnowledgeAuthorization> authorize({
    required OmnixNodePrincipal principal,
    required OmnixSemanticQuery query,
    required OmnixNodeRequestContext context,
  }) async {
    calls++;
    return result;
  }
}

final class _SemanticBackend implements OmnixSemanticKnowledgeBackend {
  @override
  final OmnixEmbeddingSpace embeddingSpace = OmnixEmbeddingSpace(
    modelId: 'embedder',
    dimensions: 2,
  );

  List<OmnixKnowledgeMatch> results = [];
  int searchCalls = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> index(OmnixKnowledgeChunk chunk) async {}

  @override
  Future<void> remove(String chunkId) async {}

  @override
  Future<List<OmnixKnowledgeMatch>> search(OmnixKnowledgeQuery query) async =>
      results;

  @override
  Future<void> flush() async {}

  @override
  Future<void> clear() async {}

  @override
  Future<OmnixEmbedding> embedQuery(String text) async =>
      OmnixEmbedding(space: embeddingSpace, values: const [0.2, 0.8]);

  @override
  Future<List<OmnixKnowledgeMatch>> searchSemantic(
    OmnixSemanticQuery query,
  ) async {
    searchCalls++;
    return results;
  }
}
