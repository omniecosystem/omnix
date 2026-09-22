// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

/// Transport-neutral context for one request received by an Omnix node.
final class OmnixNodeRequestContext {
  OmnixNodeRequestContext({
    required this.requestId,
    required this.receivedAt,
    Map<String, Object?> attributes = const {},
  }) : attributes = Map.unmodifiable(attributes) {
    _requireText(requestId, 'requestId');
  }

  final String requestId;
  final DateTime receivedAt;

  /// Non-secret transport facts such as a relay identifier or connection ID.
  final Map<String, Object?> attributes;
}

/// Opaque proof presented to an application-selected authenticator.
///
/// A server adapter may carry a bearer token while a peer-to-peer adapter may
/// carry a signed challenge. Omnix neither interprets nor persists [payload].
final class OmnixNodeAuthenticationEvidence {
  OmnixNodeAuthenticationEvidence({
    required this.scheme,
    required List<int> payload,
    Map<String, Object?> attributes = const {},
  }) : payload = List.unmodifiable(payload),
       attributes = Map.unmodifiable(attributes) {
    _requireText(scheme, 'scheme');
    if (payload.isEmpty) {
      throw ArgumentError.value(payload, 'payload', 'must not be empty');
    }
    if (payload.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError.value(payload, 'payload', 'must contain bytes');
    }
  }

  final String scheme;
  final List<int> payload;
  final Map<String, Object?> attributes;
}

/// Identity established by an [OmnixNodeAuthenticator].
final class OmnixNodePrincipal {
  OmnixNodePrincipal({
    required this.nodeId,
    required this.authenticationScheme,
    required this.authenticatedAt,
    this.expiresAt,
    Map<String, Object?> claims = const {},
  }) : claims = Map.unmodifiable(claims) {
    _requireText(nodeId, 'nodeId');
    _requireText(authenticationScheme, 'authenticationScheme');
    if (expiresAt != null && !expiresAt!.isAfter(authenticatedAt)) {
      throw ArgumentError.value(
        expiresAt,
        'expiresAt',
        'must be after authenticatedAt',
      );
    }
  }

  final String nodeId;
  final String authenticationScheme;
  final DateTime authenticatedAt;
  final DateTime? expiresAt;
  final Map<String, Object?> claims;

  bool isExpiredAt(DateTime instant) =>
      expiresAt != null && !expiresAt!.isAfter(instant);
}

enum OmnixAuthenticationFailureCode {
  invalidEvidence,
  expiredEvidence,
  unsupportedScheme,
  unavailable,
}

/// Result returned by an application-selected authentication adapter.
sealed class OmnixNodeAuthenticationResult {
  const OmnixNodeAuthenticationResult();
}

final class OmnixNodeAuthenticated extends OmnixNodeAuthenticationResult {
  const OmnixNodeAuthenticated(this.principal);

  final OmnixNodePrincipal principal;
}

final class OmnixNodeAuthenticationRejected
    extends OmnixNodeAuthenticationResult {
  const OmnixNodeAuthenticationRejected({required this.code, this.safeMessage});

  final OmnixAuthenticationFailureCode code;

  /// Optional message safe to return to an untrusted caller.
  final String? safeMessage;
}

/// Authenticates server-issued credentials, peer proofs, or other evidence.
abstract interface class OmnixNodeAuthenticator {
  Future<OmnixNodeAuthenticationResult> authenticate({
    required OmnixNodeAuthenticationEvidence evidence,
    required OmnixNodeRequestContext context,
  });
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}
