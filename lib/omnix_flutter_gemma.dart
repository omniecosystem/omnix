// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

/// Flutter Gemma infrastructure adapters for Omnix.
library;

import 'src/application/omnix.dart';
import 'src/application/omnix_runtime.dart';
import 'src/application/capabilities/omnix_capability_registry.dart';
import 'src/domain/agents/omnix_agent.dart';
import 'src/infrastructure/flutter_gemma/flutter_gemma_inference_backend.dart';
import 'src/infrastructure/flutter_gemma/flutter_gemma_model_manager.dart';

export 'src/infrastructure/flutter_gemma/flutter_gemma_inference_backend.dart'
    show FlutterGemmaConversation, FlutterGemmaInferenceBackend;
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
    );
  }
}
