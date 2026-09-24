// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';

import 'package:omnix/omnix.dart';

/// A deliberately small, public-data-only backend for the cross-node demo.
/// It is keyword search, not embeddings or the production Knowledge backend.
final class PublicDemoKnowledgeBackend implements OmnixKnowledgeBackend {
  final List<OmnixKnowledgeChunk> _chunks = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> index(OmnixKnowledgeChunk chunk) async => _chunks.add(chunk);

  @override
  Future<void> remove(String chunkId) async =>
      _chunks.removeWhere((chunk) => chunk.id == chunkId);

  @override
  Future<void> flush() async {}

  @override
  Future<void> clear() async => _chunks.clear();

  @override
  Future<List<OmnixKnowledgeMatch>> search(OmnixKnowledgeQuery query) async {
    final terms = _terms(query.text);
    if (terms.isEmpty) return [];
    final matches = <OmnixKnowledgeMatch>[];
    for (final chunk in _chunks) {
      if (!query.allowedAccess.contains(chunk.access)) continue;
      final titleHits = terms.intersection(_terms(chunk.source.title)).length;
      final contentHits = terms.intersection(_terms(chunk.content)).length;
      if (titleHits + contentHits == 0) continue;
      matches.add(
        OmnixKnowledgeMatch(
          chunk: chunk,
          score: (2 * titleHits + contentHits) / (3 * terms.length),
        ),
      );
    }
    return matches;
  }

  Set<String> _terms(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((term) => term.length > 2)
      .toSet();
}

final class _DemoAuthenticator implements OmnixNodeAuthenticator {
  @override
  Future<OmnixNodeAuthenticationResult> authenticate({
    required OmnixNodeAuthenticationEvidence evidence,
    required OmnixNodeRequestContext context,
  }) async {
    if (evidence.scheme != 'a2a-demo-verified-caller' ||
        utf8.decode(evidence.payload) != 'paired-demo-client') {
      return const OmnixNodeAuthenticationRejected(
        code: OmnixAuthenticationFailureCode.invalidEvidence,
      );
    }
    return OmnixNodeAuthenticated(
      OmnixNodePrincipal(
        nodeId: 'paired-demo-client',
        authenticationScheme: evidence.scheme,
        authenticatedAt: context.receivedAt,
      ),
    );
  }
}

final class _PublicOnlyAuthorizer implements OmnixNodeKnowledgeAuthorizer {
  @override
  Future<OmnixNodeKnowledgeAuthorization> authorize({
    required OmnixNodePrincipal principal,
    required OmnixNodeKnowledgeQuery query,
    required OmnixNodeRequestContext context,
  }) async => principal.nodeId == 'paired-demo-client'
      ? OmnixNodeKnowledgeAllowed(
          OmnixNodeKnowledgeGrant(
            allowedAccess: {OmnixKnowledgeAccess.public},
            maximumTopK: 1,
          ),
        )
      : const OmnixNodeKnowledgeDenied(reason: 'unknown-caller');
}

/// Reads an explicit local fixture. No arbitrary remote file path is accepted.
Future<OmnixNodeKnowledgeService> publicDemoService(File fixture) async {
  final decoded = jsonDecode(await fixture.readAsString());
  if (decoded is! List) throw const FormatException('Expected document list');
  final coordinator = OmnixKnowledgeCoordinator(PublicDemoKnowledgeBackend());
  for (final entry in decoded) {
    if (entry is! Map<String, dynamic>) {
      throw const FormatException('Invalid document');
    }
    final id = entry['id'];
    final title = entry['title'];
    final content = entry['content'];
    final access = entry['access'];
    if (id is! String ||
        title is! String ||
        content is! String ||
        (access != 'public' && access != 'private')) {
      throw const FormatException('Invalid document fields');
    }
    final visibility = access == 'public'
        ? OmnixKnowledgeAccess.public
        : OmnixKnowledgeAccess.private;
    final source = OmnixKnowledgeSource(id: id, title: title);
    await coordinator.indexDocument(
      OmnixKnowledgeDocument(
        id: id,
        title: title,
        createdAt: DateTime.utc(2026, 1, 1),
        access: visibility,
      ),
      [
        OmnixKnowledgeChunk(
          id: '$id:0',
          documentId: id,
          content: content,
          source: source,
          access: visibility,
        ),
      ],
    );
  }
  return OmnixNodeKnowledgeService(
    knowledge: coordinator,
    authenticator: _DemoAuthenticator(),
    authorizer: _PublicOnlyAuthorizer(),
  );
}

Future<OmnixNodeKnowledgeResult> queryPublicDemo(
  OmnixNodeKnowledgeService service,
  String caller,
  String question,
) => service.retrieve(
  OmnixNodeKnowledgeRequest(
    context: OmnixNodeRequestContext(
      requestId: DateTime.now().microsecondsSinceEpoch.toString(),
      receivedAt: DateTime.now().toUtc(),
    ),
    evidence: OmnixNodeAuthenticationEvidence(
      scheme: 'a2a-demo-verified-caller',
      payload: utf8.encode(caller),
    ),
    query: OmnixNodeTextKnowledgeQuery(
      OmnixKnowledgeQuery(
        text: question,
        allowedAccess: {OmnixKnowledgeAccess.public},
        topK: 1,
      ),
    ),
  ),
);

/// Handles one line of the local, sequential Rust-to-Dart demo protocol.
/// The caller ID must have been established by the Rust A2A verifier; this
/// function is not an independent network authentication mechanism.
Future<String> handlePublicDemoRequest(
  OmnixNodeKnowledgeService service,
  String line,
) async {
  try {
    final request = jsonDecode(line);
    if (request is! Map<String, dynamic> ||
        request['id'] is! int ||
        request['caller'] is! String ||
        request['question'] is! String) {
      throw const FormatException('Invalid local request');
    }
    final id = request['id'] as int;
    final caller = request['caller'] as String;
    final question = request['question'] as String;
    if (question.trim().isEmpty || question.length > 512) {
      throw const FormatException('Invalid question');
    }
    final result = await queryPublicDemo(service, caller, question);
    if (result is! OmnixNodeKnowledgeSuccess || result.matches.isEmpty) {
      return jsonEncode({'id': id, 'status': 'denied'});
    }
    final match = result.matches.first;
    return jsonEncode({
      'id': id,
      'status': 'ok',
      'answer': '${match.chunk.content}\nSource: ${match.chunk.source.title}',
    });
  } catch (_) {
    return jsonEncode({'status': 'unavailable'});
  }
}
