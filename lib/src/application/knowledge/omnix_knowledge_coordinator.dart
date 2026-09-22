// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import '../../domain/context/omnix_context.dart';
import '../../domain/knowledge/omnix_knowledge.dart';
import '../../domain/knowledge/omnix_knowledge_backend.dart';
import '../context/omnix_recent_context_policy.dart';

/// Coordinates indexing, retrieval, access filtering, and RAG context assembly.
final class OmnixKnowledgeCoordinator {
  factory OmnixKnowledgeCoordinator(
    OmnixKnowledgeBackend backend, {
    OmnixTokenEstimator estimator = const OmnixApproximateTokenEstimator(),
  }) => OmnixKnowledgeCoordinator._(backend, estimator);

  OmnixKnowledgeCoordinator._(this._backend, this._estimator);

  final OmnixKnowledgeBackend _backend;
  final OmnixTokenEstimator _estimator;
  Future<void>? _initialization;

  Future<void> initialize() {
    final pending = _initialization;
    if (pending != null) return pending;
    final initialization = _initializeOnce();
    _initialization = initialization;
    return initialization;
  }

  Future<void> _initializeOnce() async {
    try {
      await _backend.initialize();
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  Future<void> indexDocument(
    OmnixKnowledgeDocument document,
    Iterable<OmnixKnowledgeChunk> chunks,
  ) async {
    await initialize();
    final materialized = chunks.toList(growable: false);
    for (final chunk in materialized) {
      if (chunk.documentId != document.id) {
        throw ArgumentError.value(
          chunk.documentId,
          'chunks',
          'must belong to document ${document.id}',
        );
      }
      if (chunk.access != document.access) {
        throw ArgumentError.value(
          chunk.access,
          'chunks',
          'must use the document access policy',
        );
      }
    }
    for (final chunk in materialized) {
      await _backend.index(chunk);
    }
    await _backend.flush();
  }

  Future<void> removeChunks(Iterable<String> chunkIds) async {
    await initialize();
    for (final chunkId in chunkIds) {
      if (chunkId.trim().isEmpty) {
        throw ArgumentError.value(chunkId, 'chunkIds', 'must not be empty');
      }
      await _backend.remove(chunkId);
    }
    await _backend.flush();
  }

  Future<List<OmnixKnowledgeMatch>> retrieve(OmnixKnowledgeQuery query) async {
    await initialize();
    return _normalize(await _backend.search(query), query);
  }

  Future<OmnixSemanticQuery> createSemanticQuery(
    OmnixKnowledgeQuery query,
  ) async {
    await initialize();
    final backend = _backend;
    if (backend is! OmnixSemanticKnowledgeBackend) {
      throw UnsupportedError('This knowledge backend cannot export queries.');
    }
    return OmnixSemanticQuery(
      embedding: await backend.embedQuery(query.text),
      topK: query.topK,
      minimumScore: query.minimumScore,
      allowedAccess: query.allowedAccess,
    );
  }

  Future<List<OmnixKnowledgeMatch>> retrieveSemantic(
    OmnixSemanticQuery query,
  ) async {
    await initialize();
    final backend = _backend;
    if (backend is! OmnixSemanticKnowledgeBackend) {
      throw UnsupportedError('This knowledge backend cannot search vectors.');
    }
    if (!backend.embeddingSpace.isCompatibleWith(query.embedding.space)) {
      throw ArgumentError.value(
        query.embedding.space.identifier,
        'query',
        'is incompatible with ${backend.embeddingSpace.identifier}',
      );
    }
    return _normalizeSemantic(await backend.searchSemantic(query), query);
  }

  Future<OmnixKnowledgeContext> buildContext(
    OmnixKnowledgeQuery query, {
    required int maxTokens,
  }) async {
    if (maxTokens <= 0) {
      throw ArgumentError.value(maxTokens, 'maxTokens', 'must be positive');
    }
    final matches = await retrieve(query);
    final sections = <String>[];
    final citations = <OmnixKnowledgeCitation>[];
    var used = 0;
    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      final section =
          'Context ${index + 1} (${match.chunk.source.title}):\n'
          '${match.chunk.content}';
      final cost = _estimator.estimateText(section);
      if (used + cost > maxTokens) break;
      sections.add(section);
      citations.add(match.citation);
      used += cost;
    }
    return OmnixKnowledgeContext(
      text: sections.join('\n\n'),
      citations: citations,
      omittedMatchCount: matches.length - sections.length,
    );
  }

  Future<void> clear() async {
    await initialize();
    await _backend.clear();
    await _backend.flush();
  }

  List<OmnixKnowledgeMatch> _normalize(
    List<OmnixKnowledgeMatch> matches,
    OmnixKnowledgeQuery query,
  ) => _normalized(
    matches,
    topK: query.topK,
    minimumScore: query.minimumScore,
    allowedAccess: query.allowedAccess,
  );

  List<OmnixKnowledgeMatch> _normalizeSemantic(
    List<OmnixKnowledgeMatch> matches,
    OmnixSemanticQuery query,
  ) => _normalized(
    matches,
    topK: query.topK,
    minimumScore: query.minimumScore,
    allowedAccess: query.allowedAccess,
  );

  List<OmnixKnowledgeMatch> _normalized(
    List<OmnixKnowledgeMatch> matches, {
    required int topK,
    required double minimumScore,
    required Set<OmnixKnowledgeAccess> allowedAccess,
  }) {
    final bestByChunk = <String, OmnixKnowledgeMatch>{};
    for (final match in matches) {
      if (match.score < minimumScore ||
          !allowedAccess.contains(match.chunk.access)) {
        continue;
      }
      final previous = bestByChunk[match.chunk.id];
      if (previous == null || match.score > previous.score) {
        bestByChunk[match.chunk.id] = match;
      }
    }
    final normalized = bestByChunk.values.toList(growable: false)
      ..sort((left, right) => right.score.compareTo(left.score));
    return List.unmodifiable(normalized.take(topK));
  }
}
