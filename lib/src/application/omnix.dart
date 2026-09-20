// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import '../domain/engine/omnix_engine.dart';
import '../domain/inference/omnix_conversation.dart';
import '../domain/models/omnix_model_manager.dart';
import '../infrastructure/rust/rust_omnix_engine.dart';
import 'capabilities/omnix_capability_registry.dart';
import 'omnix_runtime.dart';

/// Composition root for creating Omnix runtime instances.
abstract final class Omnix {
  /// Creates the default engine without initializing native resources.
  static OmnixEngine createEngine() => RustOmnixEngine();

  /// Creates the application runtime around the default native engine.
  ///
  /// The inference backend is explicit so Flutter Gemma remains a replaceable
  /// infrastructure adapter rather than leaking into the core Omnix API.
  static OmnixRuntime createRuntime({
    required OmnixInferenceBackend inferenceBackend,
    OmnixModelManager? modelManager,
    OmnixCapabilityRegistry? capabilityRegistry,
  }) => OmnixRuntime(
    engine: createEngine(),
    inferenceBackend: inferenceBackend,
    modelManager: modelManager,
    capabilityRegistry: capabilityRegistry,
  );
}
