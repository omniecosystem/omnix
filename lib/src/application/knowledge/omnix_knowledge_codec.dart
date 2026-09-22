// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import '../../domain/knowledge/omnix_knowledge.dart';
import '../../domain/nodes/omnix_node_knowledge_authorization.dart';

/// Versioned JSON-compatible encoding for semantic queries and results.
final class OmnixKnowledgeCodec {
  const OmnixKnowledgeCodec();

  static const int schemaVersion = 1;

  Map<String, Object?> encodeNodeQuery(OmnixNodeKnowledgeQuery query) =>
      switch (query) {
        OmnixNodeTextKnowledgeQuery(:final query) => {
          'schemaVersion': schemaVersion,
          'kind': 'text',
          'text': query.text,
          'topK': query.topK,
          'minimumScore': query.minimumScore,
          'allowedAccess': _accessNames(query.allowedAccess),
        },
        OmnixNodeEmbeddingKnowledgeQuery(:final query) => {
          ...encodeSemanticQuery(query),
          'kind': 'embedding',
        },
      };

  OmnixNodeKnowledgeQuery decodeNodeQuery(Map<String, Object?> json) {
    try {
      _requireVersion(json);
      return switch (_nonEmptyString(json, 'kind')) {
        'text' => OmnixNodeTextKnowledgeQuery(
          OmnixKnowledgeQuery(
            text: _nonEmptyString(json, 'text'),
            topK: _integer(json, 'topK'),
            minimumScore: _number(json['minimumScore'], 'minimumScore'),
            allowedAccess: _accessSet(json['allowedAccess']),
          ),
        ),
        'embedding' => OmnixNodeEmbeddingKnowledgeQuery(
          decodeSemanticQuery(json),
        ),
        final kind => throw FormatException(
          'Invalid Knowledge node query kind: $kind.',
        ),
      };
    } on ArgumentError catch (error) {
      throw FormatException('Invalid Knowledge node query: $error');
    }
  }

  Map<String, Object?> encodeSemanticQuery(OmnixSemanticQuery query) => {
    'schemaVersion': schemaVersion,
    'embedding': {
      'space': {
        'modelId': query.embedding.space.modelId,
        'revision': query.embedding.space.revision,
        'dimensions': query.embedding.space.dimensions,
      },
      'values': query.embedding.values,
    },
    'topK': query.topK,
    'minimumScore': query.minimumScore,
    'allowedAccess': _accessNames(query.allowedAccess),
  };

  OmnixSemanticQuery decodeSemanticQuery(Map<String, Object?> json) {
    try {
      _requireVersion(json);
      final embedding = _map(json['embedding'], 'embedding');
      final space = _map(embedding['space'], 'embedding.space');
      final rawValues = embedding['values'];
      if (rawValues is! List) {
        throw const FormatException(
          'Knowledge embedding.values must be an array.',
        );
      }
      return OmnixSemanticQuery(
        embedding: OmnixEmbedding(
          space: OmnixEmbeddingSpace(
            modelId: _nonEmptyString(space, 'modelId'),
            revision: _nullableString(space, 'revision'),
            dimensions: _integer(space, 'dimensions'),
          ),
          values: rawValues
              .map((value) => _number(value, 'embedding.values'))
              .toList(growable: false),
        ),
        topK: _integer(json, 'topK'),
        minimumScore: _number(json['minimumScore'], 'minimumScore'),
        allowedAccess: _accessSet(json['allowedAccess']),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid Knowledge semantic query: $error');
    }
  }

  Map<String, Object?> encodeMatch(OmnixKnowledgeMatch match) {
    _validateJsonValue(match.chunk.metadata, 'chunk.metadata');
    return {
      'schemaVersion': schemaVersion,
      'score': match.score,
      'chunk': {
        'id': match.chunk.id,
        'documentId': match.chunk.documentId,
        'content': match.chunk.content,
        'access': match.chunk.access.name,
        'metadata': match.chunk.metadata,
        'source': {
          'id': match.chunk.source.id,
          'title': match.chunk.source.title,
          'uri': match.chunk.source.uri?.toString(),
        },
      },
    };
  }

  OmnixKnowledgeMatch decodeMatch(Map<String, Object?> json) {
    try {
      _requireVersion(json);
      final chunk = _map(json['chunk'], 'chunk');
      final source = _map(chunk['source'], 'chunk.source');
      final uriText = _nullableString(source, 'uri');
      final uri = uriText == null ? null : Uri.tryParse(uriText);
      if (uriText != null && (uri == null || !uri.hasScheme)) {
        throw const FormatException('Knowledge chunk.source.uri is invalid.');
      }
      return OmnixKnowledgeMatch(
        chunk: OmnixKnowledgeChunk(
          id: _nonEmptyString(chunk, 'id'),
          documentId: _nonEmptyString(chunk, 'documentId'),
          content: _nonEmptyString(chunk, 'content'),
          access: _enumValue(
            OmnixKnowledgeAccess.values,
            _nonEmptyString(chunk, 'access'),
            'chunk.access',
          ),
          metadata: _map(chunk['metadata'], 'chunk.metadata'),
          source: OmnixKnowledgeSource(
            id: _nonEmptyString(source, 'id'),
            title: _nonEmptyString(source, 'title'),
            uri: uri,
          ),
        ),
        score: _number(json['score'], 'score'),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Invalid Knowledge match: $error');
    }
  }

  List<String> _accessNames(Set<OmnixKnowledgeAccess> access) =>
      access.map((value) => value.name).toList(growable: false)..sort();

  Set<OmnixKnowledgeAccess> _accessSet(Object? value) {
    if (value is! List || value.isEmpty) {
      throw const FormatException(
        'Knowledge allowedAccess must be a non-empty array.',
      );
    }
    return value
        .map(
          (entry) => _enumValue(
            OmnixKnowledgeAccess.values,
            _requiredString(entry, 'allowedAccess'),
            'allowedAccess',
          ),
        )
        .toSet();
  }

  void _requireVersion(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != schemaVersion) {
      throw FormatException('Unsupported Knowledge schema version: $version.');
    }
  }

  Map<String, Object?> _map(Object? value, String field) {
    if (value is! Map) {
      throw FormatException('Knowledge $field must be an object.');
    }
    try {
      final result = Map<String, Object?>.from(value);
      _validateJsonValue(result, field);
      return result;
    } on TypeError {
      throw FormatException('Knowledge $field keys must be strings.');
    }
  }

  int _integer(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is int) return value;
    throw FormatException('Knowledge $field must be an integer.');
  }

  double _number(Object? value, String field) {
    if (value is num && value.isFinite) return value.toDouble();
    throw FormatException('Knowledge $field must be a finite number.');
  }

  String _requiredString(Object? value, String field) {
    if (value is String && value.trim().isNotEmpty) return value;
    throw FormatException('Knowledge $field must be non-empty text.');
  }

  String _nonEmptyString(Map<String, Object?> json, String field) =>
      _requiredString(json[field], field);

  String? _nullableString(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value == null || value is String) return value as String?;
    throw FormatException('Knowledge $field must be text or null.');
  }

  T _enumValue<T extends Enum>(List<T> values, String name, String field) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw FormatException('Invalid Knowledge $field: $name.');
  }

  void _validateJsonValue(Object? value, String field) {
    try {
      jsonEncode(value);
    } on JsonUnsupportedObjectError {
      throw FormatException('Knowledge $field must contain JSON-safe values.');
    }
  }
}
