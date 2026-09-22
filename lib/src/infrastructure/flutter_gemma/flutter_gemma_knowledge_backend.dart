// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';

import '../../domain/knowledge/omnix_knowledge.dart';
import '../../domain/knowledge/omnix_knowledge_backend.dart';

/// Minimal seam over Flutter Gemma's RAG facade.
///
/// Hosts normally use the default implementation. The interface keeps provider
/// API changes localized and lets adapter behavior be tested without opening a
/// native vector store.
abstract interface class FlutterGemmaRagGateway {
  Future<void> initialize(String databasePath);

  Future<void> addDocument({
    required String id,
    required String content,
    String? metadata,
  });

  Future<List<FlutterGemmaRagHit>> searchSimilar({
    required String query,
    required int topK,
    required double threshold,
  });

  Future<void> removeDocument(String id);

  Future<void> flush();

  Future<void> clear();
}

/// Provider result represented without exposing Flutter Gemma domain types.
final class FlutterGemmaRagHit {
  const FlutterGemmaRagHit({
    required this.id,
    required this.content,
    required this.similarity,
    this.metadata,
  });

  final String id;
  final String content;
  final double similarity;
  final String? metadata;
}

/// Adapts Flutter Gemma's configured RAG store to Omnix Knowledge contracts.
///
/// The host remains responsible for configuring Flutter Gemma with a vector
/// store, activating an embedding model, and supplying a writable database
/// path. Indexing uses `GemmaRag.addDocument`, which applies the provider's
/// retrieval-document embedding task rather than embedding document text as a
/// retrieval query.
final class FlutterGemmaKnowledgeBackend implements OmnixKnowledgeBackend {
  FlutterGemmaKnowledgeBackend({
    required String databasePath,
    FlutterGemmaRagGateway? gateway,
    this.candidateMultiplier = 4,
  }) : databasePath = databasePath.trim(),
       _gateway = gateway ?? const _DefaultFlutterGemmaRagGateway() {
    if (this.databasePath.isEmpty) {
      throw ArgumentError.value(
        databasePath,
        'databasePath',
        'must not be empty',
      );
    }
    if (candidateMultiplier <= 0) {
      throw ArgumentError.value(
        candidateMultiplier,
        'candidateMultiplier',
        'must be positive',
      );
    }
  }

  final String databasePath;
  final int candidateMultiplier;
  final FlutterGemmaRagGateway _gateway;

  @override
  Future<void> initialize() => _gateway.initialize(databasePath);

  @override
  Future<void> index(OmnixKnowledgeChunk chunk) => _gateway.addDocument(
    id: chunk.id,
    content: chunk.content,
    metadata: jsonEncode({
      'documentId': chunk.documentId,
      'sourceId': chunk.source.id,
      'sourceTitle': chunk.source.title,
      'sourceUri': chunk.source.uri?.toString(),
      'access': chunk.access.name,
      'metadata': chunk.metadata,
    }),
  );

  @override
  Future<void> remove(String chunkId) => _gateway.removeDocument(chunkId);

  @override
  Future<List<OmnixKnowledgeMatch>> search(OmnixKnowledgeQuery query) async {
    final hits = await _gateway.searchSimilar(
      query: query.text,
      topK: query.topK * candidateMultiplier,
      threshold: query.minimumScore,
    );

    return hits
        .map(_mapHit)
        .where((match) => query.allowedAccess.contains(match.chunk.access))
        .take(query.topK)
        .toList(growable: false);
  }

  @override
  Future<void> flush() => _gateway.flush();

  @override
  Future<void> clear() => _gateway.clear();

  OmnixKnowledgeMatch _mapHit(FlutterGemmaRagHit hit) {
    final metadata = _decodeMetadata(hit.metadata);
    final documentId = _string(metadata['documentId']) ?? _documentId(hit.id);
    final sourceId = _string(metadata['sourceId']) ?? documentId;
    final sourceTitle =
        _string(metadata['sourceTitle']) ??
        _string(metadata['source']) ??
        sourceId;
    final sourceUriText = _string(metadata['sourceUri']);
    final sourceUri = sourceUriText == null
        ? null
        : Uri.tryParse(sourceUriText);
    final access = OmnixKnowledgeAccess.values
        .where((value) => value.name == _string(metadata['access']))
        .firstOrNull;

    return OmnixKnowledgeMatch(
      chunk: OmnixKnowledgeChunk(
        id: hit.id,
        documentId: documentId,
        content: hit.content,
        source: OmnixKnowledgeSource(
          id: sourceId,
          title: sourceTitle,
          uri: sourceUri?.hasScheme == true ? sourceUri : null,
        ),
        // Missing or unrecognized metadata is private by default. This keeps
        // legacy entries visible locally without accidentally exporting them.
        access: access ?? OmnixKnowledgeAccess.private,
        metadata: _nestedMetadata(metadata['metadata']),
      ),
      score: hit.similarity,
    );
  }

  Map<String, Object?> _decodeMetadata(String? encoded) {
    if (encoded == null || encoded.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(encoded);
      return decoded is Map ? Map<String, Object?>.from(decoded) : const {};
    } on FormatException {
      return const {};
    } on TypeError {
      return const {};
    }
  }

  Map<String, Object?> _nestedMetadata(Object? value) {
    if (value is! Map) return const {};
    try {
      return Map<String, Object?>.from(value);
    } on TypeError {
      return const {};
    }
  }

  String? _string(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  String _documentId(String chunkId) {
    final separator = chunkId.indexOf(':');
    return separator > 0 ? chunkId.substring(0, separator) : chunkId;
  }
}

final class _DefaultFlutterGemmaRagGateway implements FlutterGemmaRagGateway {
  const _DefaultFlutterGemmaRagGateway();

  @override
  Future<void> initialize(String databasePath) =>
      FlutterGemma.rag.initialize(databasePath);

  @override
  Future<void> addDocument({
    required String id,
    required String content,
    String? metadata,
  }) => FlutterGemma.rag.addDocument(
    id: id,
    content: content,
    metadata: metadata,
  );

  @override
  Future<List<FlutterGemmaRagHit>> searchSimilar({
    required String query,
    required int topK,
    required double threshold,
  }) async {
    final hits = await FlutterGemma.rag.searchSimilar(
      query: query,
      topK: topK,
      threshold: threshold,
    );
    return hits
        .map(
          (hit) => FlutterGemmaRagHit(
            id: hit.id,
            content: hit.content,
            similarity: hit.similarity,
            metadata: hit.metadata,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> removeDocument(String id) =>
      FlutterGemma.rag.removeDocument(id: id);

  @override
  Future<void> flush() => FlutterGemma.rag.flush();

  @override
  Future<void> clear() => FlutterGemma.rag.clear();
}
