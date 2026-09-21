// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

/// Public API for the Omnix on-device intelligence engine.
library;

export 'src/application/omnix.dart';
export 'src/application/omnix_runtime.dart';
export 'src/application/capabilities/omnix_capability_registry.dart';
export 'src/application/capabilities/omnix_tool_input_validator.dart';
export 'src/application/models/omnix_model_manifest_parser.dart';
export 'src/application/scheduling/inference_scheduler.dart';
export 'src/application/workflow/omnix_workflow_runtime.dart';
export 'src/application/workflow/omnix_workflow_codec.dart';
export 'src/domain/agents/omnix_agent.dart';
export 'src/domain/capabilities/omnix_capability.dart';
export 'src/domain/capabilities/omnix_capability_registry_snapshot.dart';
export 'src/domain/engine/omnix_engine.dart';
export 'src/domain/engine/omnix_engine_event.dart';
export 'src/domain/engine/omnix_engine_state.dart';
export 'src/domain/engine/omnix_runtime_info.dart';
export 'src/domain/inference/omnix_conversation.dart';
export 'src/domain/inference/omnix_inference_provider_capabilities.dart';
export 'src/domain/inference/omnix_message.dart';
export 'src/domain/models/omnix_model_manifest.dart';
export 'src/domain/models/omnix_model_capabilities.dart';
export 'src/domain/models/omnix_model_manager.dart';
export 'src/domain/scheduling/inference_scheduler_snapshot.dart';
export 'src/domain/workflow/omnix_workflow_event.dart';
export 'src/domain/workflow/omnix_workflow_executor.dart';
export 'src/domain/workflow/omnix_workflow_store.dart';
export 'src/domain/workflow/omnix_workflow_task.dart';
