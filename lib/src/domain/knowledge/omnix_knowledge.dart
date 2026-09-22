// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

/// Visibility attached to knowledge before product-specific authorization.
enum OmnixKnowledgeAccess { private, public }

/// A durable source whose content may be split into searchable chunks.
final class OmnixKnowledgeDocument {
  OmnixKnowledgeDocument({
    required this.id,
    required this.title,
    required this.createdAt,
    this.access = OmnixKnowledgeAccess.private,
    this.uri,
    Map<String, Object?> metadata = const {},
  }) : metadata = Map.unmodifiable(metadata) {
    _requireText(id, 'id');
    _requireText(title, 'title');
  }

  final String id;
  final String title;
  final DateTime createdAt;
  final OmnixKnowledgeAccess access;
  final Uri? uri;
  final Map<String, Object?> metadata;
}

/// One independently retrievable portion of a knowledge document.
final class OmnixKnowledgeChunk {
  OmnixKnowledgeChunk({
    required this.id,
    required this.documentId,
    required this.content,
    required this.source,
    this.access = OmnixKnowledgeAccess.private,
    Map<String, Object?> metadata = const {},
  }) : metadata = Map.unmodifiable(metadata) {
    _requireText(id, 'id');
    _requireText(documentId, 'documentId');
    _requireText(content, 'content');
  }

  final String id;
  final String documentId;
  final String content;
  final OmnixKnowledgeSource source;
  final OmnixKnowledgeAccess access;
  final Map<String, Object?> metadata;
}

/// Human-readable provenance retained with a retrieved chunk.
final class OmnixKnowledgeSource {
  OmnixKnowledgeSource({required this.id, required this.title, this.uri}) {
    _requireText(id, 'id');
    _requireText(title, 'title');
  }

  final String id;
  final String title;
  final Uri? uri;
}

/// Identity of the embedding space in which vectors can be compared.
final class OmnixEmbeddingSpace {
  OmnixEmbeddingSpace({
    required this.modelId,
    required this.dimensions,
    this.revision,
  }) {
    _requireText(modelId, 'modelId');
    if (dimensions <= 0) {
      throw ArgumentError.value(dimensions, 'dimensions', 'must be positive');
    }
  }

  final String modelId;
  final int dimensions;
  final String? revision;

  String get identifier => [modelId, ?revision, dimensions].join(':');

  bool isCompatibleWith(OmnixEmbeddingSpace other) =>
      modelId == other.modelId &&
      revision == other.revision &&
      dimensions == other.dimensions;
}

/// A validated immutable vector and the embedding space that produced it.
final class OmnixEmbedding {
  OmnixEmbedding({required this.space, required List<double> values})
    : values = List.unmodifiable(values) {
    if (values.length != space.dimensions) {
      throw ArgumentError.value(
        values.length,
        'values',
        'must match the ${space.dimensions}-dimension embedding space',
      );
    }
    if (values.any((value) => !value.isFinite)) {
      throw ArgumentError.value(values, 'values', 'must all be finite');
    }
  }

  final OmnixEmbeddingSpace space;
  final List<double> values;
}

/// A local natural-language retrieval request.
final class OmnixKnowledgeQuery {
  OmnixKnowledgeQuery({
    required this.text,
    this.topK = 5,
    this.minimumScore = 0,
    Set<OmnixKnowledgeAccess> allowedAccess = const {
      OmnixKnowledgeAccess.private,
      OmnixKnowledgeAccess.public,
    },
  }) : allowedAccess = Set.unmodifiable(allowedAccess) {
    _requireText(text, 'text');
    _validateSearch(topK, minimumScore, this.allowedAccess);
  }

  final String text;
  final int topK;
  final double minimumScore;
  final Set<OmnixKnowledgeAccess> allowedAccess;
}

/// A transport-ready semantic request suitable for an Omnixus node boundary.
final class OmnixSemanticQuery {
  OmnixSemanticQuery({
    required this.embedding,
    this.topK = 5,
    this.minimumScore = 0,
    Set<OmnixKnowledgeAccess> allowedAccess = const {
      OmnixKnowledgeAccess.public,
    },
  }) : allowedAccess = Set.unmodifiable(allowedAccess) {
    _validateSearch(topK, minimumScore, this.allowedAccess);
  }

  final OmnixEmbedding embedding;
  final int topK;
  final double minimumScore;
  final Set<OmnixKnowledgeAccess> allowedAccess;
}

/// A scored retrieval hit with sufficient provenance for attribution.
final class OmnixKnowledgeMatch {
  OmnixKnowledgeMatch({required this.chunk, required this.score}) {
    if (!score.isFinite || score < -1 || score > 1) {
      throw ArgumentError.value(score, 'score', 'must be between -1 and 1');
    }
  }

  final OmnixKnowledgeChunk chunk;
  final double score;

  OmnixKnowledgeCitation get citation => OmnixKnowledgeCitation(
    chunkId: chunk.id,
    documentId: chunk.documentId,
    source: chunk.source,
    score: score,
  );
}

/// Source attribution detached from the retrieved content itself.
final class OmnixKnowledgeCitation {
  const OmnixKnowledgeCitation({
    required this.chunkId,
    required this.documentId,
    required this.source,
    required this.score,
  });

  final String chunkId;
  final String documentId;
  final OmnixKnowledgeSource source;
  final double score;
}

/// RAG-ready context accompanied by its ordered citations.
final class OmnixKnowledgeContext {
  OmnixKnowledgeContext({
    required this.text,
    required List<OmnixKnowledgeCitation> citations,
    required this.omittedMatchCount,
  }) : citations = List.unmodifiable(citations);

  final String text;
  final List<OmnixKnowledgeCitation> citations;
  final int omittedMatchCount;
}

void _validateSearch(
  int topK,
  double minimumScore,
  Set<OmnixKnowledgeAccess> allowedAccess,
) {
  if (topK <= 0) {
    throw ArgumentError.value(topK, 'topK', 'must be positive');
  }
  if (!minimumScore.isFinite || minimumScore < -1 || minimumScore > 1) {
    throw ArgumentError.value(
      minimumScore,
      'minimumScore',
      'must be between -1 and 1',
    );
  }
  if (allowedAccess.isEmpty) {
    throw ArgumentError.value(
      allowedAccess,
      'allowedAccess',
      'must not be empty',
    );
  }
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'must not be empty');
  }
}
