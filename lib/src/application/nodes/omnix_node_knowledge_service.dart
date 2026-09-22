// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import '../../domain/knowledge/omnix_knowledge.dart';
import '../../domain/nodes/omnix_node_authentication.dart';
import '../../domain/nodes/omnix_node_knowledge_authorization.dart';
import '../knowledge/omnix_knowledge_coordinator.dart';

/// One authenticated semantic retrieval request at a node boundary.
final class OmnixNodeKnowledgeRequest {
  const OmnixNodeKnowledgeRequest({
    required this.context,
    required this.evidence,
    required this.query,
  });

  final OmnixNodeRequestContext context;
  final OmnixNodeAuthenticationEvidence evidence;
  final OmnixSemanticQuery query;
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
  final OmnixSemanticQuery appliedQuery;
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

    final constrained = OmnixSemanticQuery(
      embedding: request.query.embedding,
      topK: request.query.topK < grant.maximumTopK
          ? request.query.topK
          : grant.maximumTopK,
      minimumScore: request.query.minimumScore > grant.minimumScoreFloor
          ? request.query.minimumScore
          : grant.minimumScoreFloor,
      allowedAccess: access,
    );
    final matches = await _knowledge.retrieveSemantic(constrained);
    return OmnixNodeKnowledgeSuccess(
      principal: principal,
      appliedQuery: constrained,
      matches: matches,
    );
  }
}
