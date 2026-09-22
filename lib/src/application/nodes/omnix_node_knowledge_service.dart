// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import '../../domain/knowledge/omnix_knowledge.dart';
import '../../domain/nodes/omnix_node_authentication.dart';
import '../../domain/nodes/omnix_node_knowledge_authorization.dart';
import '../knowledge/omnix_knowledge_coordinator.dart';

/// One authenticated retrieval request at a node boundary.
final class OmnixNodeKnowledgeRequest {
  const OmnixNodeKnowledgeRequest({
    required this.context,
    required this.evidence,
    required this.query,
  });

  final OmnixNodeRequestContext context;
  final OmnixNodeAuthenticationEvidence evidence;
  final OmnixNodeKnowledgeQuery query;
}

enum OmnixNodeKnowledgeFailureCode {
  authenticationRejected,
  authenticationExpired,
  authorizationDenied,
  incompatibleAccess,
}

/// Result safe for a transport adapter to map into its own protocol.
sealed class OmnixNodeKnowledgeResult {
  const OmnixNodeKnowledgeResult();
}

final class OmnixNodeKnowledgeSuccess extends OmnixNodeKnowledgeResult {
  OmnixNodeKnowledgeSuccess({
    required this.principal,
    required this.appliedQuery,
    required List<OmnixKnowledgeMatch> matches,
  }) : matches = List.unmodifiable(matches);

  final OmnixNodePrincipal principal;
  final OmnixNodeKnowledgeQuery appliedQuery;
  final List<OmnixKnowledgeMatch> matches;
}

final class OmnixNodeKnowledgeFailure extends OmnixNodeKnowledgeResult {
  const OmnixNodeKnowledgeFailure({required this.code, this.safeMessage});

  final OmnixNodeKnowledgeFailureCode code;
  final String? safeMessage;
}

/// Authenticates, authorizes, constrains, and executes node retrieval.
///
/// Authentication mechanism and transport are deliberately injected. The same
/// service therefore supports a server-issued identity or direct peer proof.
final class OmnixNodeKnowledgeService {
  factory OmnixNodeKnowledgeService({
    required OmnixKnowledgeCoordinator knowledge,
    required OmnixNodeAuthenticator authenticator,
    required OmnixNodeKnowledgeAuthorizer authorizer,
  }) => OmnixNodeKnowledgeService._(knowledge, authenticator, authorizer);

  const OmnixNodeKnowledgeService._(
    this._knowledge,
    this._authenticator,
    this._authorizer,
  );

  final OmnixKnowledgeCoordinator _knowledge;
  final OmnixNodeAuthenticator _authenticator;
  final OmnixNodeKnowledgeAuthorizer _authorizer;

  Future<OmnixNodeKnowledgeResult> retrieve(
    OmnixNodeKnowledgeRequest request,
  ) async {
    final authentication = await _authenticator.authenticate(
      evidence: request.evidence,
      context: request.context,
    );
    if (authentication case OmnixNodeAuthenticationRejected(
      :final safeMessage,
    )) {
      return OmnixNodeKnowledgeFailure(
        code: OmnixNodeKnowledgeFailureCode.authenticationRejected,
        safeMessage: safeMessage,
      );
    }

    final principal = (authentication as OmnixNodeAuthenticated).principal;
    if (principal.isExpiredAt(request.context.receivedAt)) {
      return const OmnixNodeKnowledgeFailure(
        code: OmnixNodeKnowledgeFailureCode.authenticationExpired,
      );
    }

    final authorization = await _authorizer.authorize(
      principal: principal,
      query: request.query,
      context: request.context,
    );
    if (authorization case OmnixNodeKnowledgeDenied(:final safeMessage)) {
      return OmnixNodeKnowledgeFailure(
        code: OmnixNodeKnowledgeFailureCode.authorizationDenied,
        safeMessage: safeMessage,
      );
    }

    final grant = (authorization as OmnixNodeKnowledgeAllowed).grant;
    final access = request.query.allowedAccess.intersection(
      grant.allowedAccess,
    );
    if (access.isEmpty) {
      return const OmnixNodeKnowledgeFailure(
        code: OmnixNodeKnowledgeFailureCode.incompatibleAccess,
      );
    }

    final topK = request.query.topK < grant.maximumTopK
        ? request.query.topK
        : grant.maximumTopK;
    final minimumScore = request.query.minimumScore > grant.minimumScoreFloor
        ? request.query.minimumScore
        : grant.minimumScoreFloor;
    final (constrained, matches) = switch (request.query) {
      OmnixNodeTextKnowledgeQuery(:final query) => await _retrieveText(
        query,
        topK: topK,
        minimumScore: minimumScore,
        allowedAccess: access,
      ),
      OmnixNodeEmbeddingKnowledgeQuery(:final query) =>
        await _retrieveEmbedding(
          query,
          topK: topK,
          minimumScore: minimumScore,
          allowedAccess: access,
        ),
    };
    return OmnixNodeKnowledgeSuccess(
      principal: principal,
      appliedQuery: constrained,
      matches: matches,
    );
  }

  Future<(OmnixNodeKnowledgeQuery, List<OmnixKnowledgeMatch>)> _retrieveText(
    OmnixKnowledgeQuery query, {
    required int topK,
    required double minimumScore,
    required Set<OmnixKnowledgeAccess> allowedAccess,
  }) async {
    final constrained = OmnixKnowledgeQuery(
      text: query.text,
      topK: topK,
      minimumScore: minimumScore,
      allowedAccess: allowedAccess,
    );
    return (
      OmnixNodeTextKnowledgeQuery(constrained),
      await _knowledge.retrieve(constrained),
    );
  }

  Future<(OmnixNodeKnowledgeQuery, List<OmnixKnowledgeMatch>)>
  _retrieveEmbedding(
    OmnixSemanticQuery query, {
    required int topK,
    required double minimumScore,
    required Set<OmnixKnowledgeAccess> allowedAccess,
  }) async {
    final constrained = OmnixSemanticQuery(
      embedding: query.embedding,
      topK: topK,
      minimumScore: minimumScore,
      allowedAccess: allowedAccess,
    );
    return (
      OmnixNodeEmbeddingKnowledgeQuery(constrained),
      await _knowledge.retrieveSemantic(constrained),
    );
  }
}
