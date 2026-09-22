// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import '../knowledge/omnix_knowledge.dart';
import 'omnix_node_authentication.dart';

/// Limits granted to one authenticated node for one semantic query.
final class OmnixNodeKnowledgeGrant {
  OmnixNodeKnowledgeGrant({
    Set<OmnixKnowledgeAccess> allowedAccess = const {
      OmnixKnowledgeAccess.public,
    },
    this.maximumTopK = 5,
    this.minimumScoreFloor = 0,
  }) : allowedAccess = Set.unmodifiable(allowedAccess) {
    if (this.allowedAccess.isEmpty) {
      throw ArgumentError.value(
        allowedAccess,
        'allowedAccess',
        'must not be empty',
      );
    }
    if (maximumTopK <= 0) {
      throw ArgumentError.value(maximumTopK, 'maximumTopK', 'must be positive');
    }
    if (!minimumScoreFloor.isFinite ||
        minimumScoreFloor < -1 ||
        minimumScoreFloor > 1) {
      throw ArgumentError.value(
        minimumScoreFloor,
        'minimumScoreFloor',
        'must be between -1 and 1',
      );
    }
  }

  final Set<OmnixKnowledgeAccess> allowedAccess;
  final int maximumTopK;
  final double minimumScoreFloor;
}

/// Result of applying product-specific policy to an authenticated node.
sealed class OmnixNodeKnowledgeAuthorization {
  const OmnixNodeKnowledgeAuthorization();
}

final class OmnixNodeKnowledgeAllowed extends OmnixNodeKnowledgeAuthorization {
  const OmnixNodeKnowledgeAllowed(this.grant);

  final OmnixNodeKnowledgeGrant grant;
}

final class OmnixNodeKnowledgeDenied extends OmnixNodeKnowledgeAuthorization {
  const OmnixNodeKnowledgeDenied({required this.reason, this.safeMessage});

  final String reason;
  final String? safeMessage;
}

/// Decides which knowledge an authenticated node may retrieve.
abstract interface class OmnixNodeKnowledgeAuthorizer {
  Future<OmnixNodeKnowledgeAuthorization> authorize({
    required OmnixNodePrincipal principal,
    required OmnixSemanticQuery query,
    required OmnixNodeRequestContext context,
  });
}
