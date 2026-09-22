// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'omnix_knowledge.dart';

/// Provider-neutral indexing and text-retrieval boundary.
abstract interface class OmnixKnowledgeBackend {
  Future<void> initialize();

  Future<void> index(OmnixKnowledgeChunk chunk);

  Future<void> remove(String chunkId);

  Future<List<OmnixKnowledgeMatch>> search(OmnixKnowledgeQuery query);

  /// Makes preceding writes durable when the backend buffers them.
  Future<void> flush();

  Future<void> clear();
}

/// Optional direct-vector extension used by compatible local or remote nodes.
abstract interface class OmnixSemanticKnowledgeBackend
    implements OmnixKnowledgeBackend {
  OmnixEmbeddingSpace get embeddingSpace;

  Future<OmnixEmbedding> embedQuery(String text);

  Future<List<OmnixKnowledgeMatch>> searchSemantic(OmnixSemanticQuery query);
}
