// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

/// Flutter Gemma infrastructure adapters for Omnix.
library;

import 'src/application/omnix.dart';
import 'src/application/omnix_runtime.dart';
import 'src/application/capabilities/omnix_capability_registry.dart';
import 'src/application/knowledge/omnix_knowledge_coordinator.dart';
import 'src/application/scheduling/inference_scheduler.dart';
import 'src/domain/agents/omnix_agent.dart';
import 'src/infrastructure/flutter_gemma/flutter_gemma_inference_backend.dart';
import 'src/infrastructure/flutter_gemma/flutter_gemma_knowledge_backend.dart';
import 'src/infrastructure/flutter_gemma/flutter_gemma_model_manager.dart';

export 'src/infrastructure/flutter_gemma/flutter_gemma_inference_backend.dart'
    show FlutterGemmaConversation, FlutterGemmaInferenceBackend;
export 'src/infrastructure/flutter_gemma/flutter_gemma_knowledge_backend.dart'
    show
        FlutterGemmaKnowledgeBackend,
        FlutterGemmaRagGateway,
        FlutterGemmaRagHit;
export 'src/infrastructure/flutter_gemma/flutter_gemma_model_manager.dart'
    show FlutterGemmaModelManager;

/// Recommended LiteRT-LM composition for applications using Omnix.
abstract final class FlutterGemmaOmnix {
  /// Creates an uninitialized runtime with model installation and inference.
  static OmnixRuntime createRuntime({
    String? huggingFaceToken,
    int maxDownloadRetries = 10,
    OmnixCapabilityRegistry? capabilityRegistry,
    OmnixAgentBackend? agentBackend,
    InferenceScheduler? inferenceScheduler,
  }) {
    final modelManager = FlutterGemmaModelManager(
      huggingFaceToken: huggingFaceToken,
      maxDownloadRetries: maxDownloadRetries,
    );
    return Omnix.createRuntime(
      inferenceBackend: const FlutterGemmaInferenceBackend(),
      modelManager: modelManager,
      capabilityRegistry: capabilityRegistry,
      agentBackend: agentBackend,
      inferenceScheduler: inferenceScheduler,
    );
  }

  /// Creates a Knowledge coordinator over Flutter Gemma's configured RAG
  /// facade.
  ///
  /// Before using the coordinator, the host must configure Flutter Gemma with
  /// a vector store and activate an embedding model. [databasePath] must point
  /// to writable application storage on native platforms.
  static OmnixKnowledgeCoordinator createKnowledgeCoordinator({
    required String databasePath,
    int candidateMultiplier = 4,
  }) => OmnixKnowledgeCoordinator(
    FlutterGemmaKnowledgeBackend(
      databasePath: databasePath,
      candidateMultiplier: candidateMultiplier,
    ),
  );
}
