// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import '../models/omnix_model_manifest.dart';
import 'omnix_message.dart';

/// Settings for one local multi-turn conversation.
final class OmnixConversationConfiguration {
  const OmnixConversationConfiguration({
    required this.modelTemplate,
    this.preferredBackend = OmnixBackendPreference.cpu,
    this.maxTokens = 4096,
    this.maxOutputTokens,
    this.temperature = 0.7,
    this.topK = 40,
    this.topP = 0.95,
    this.systemInstruction,
    this.thinking = false,
  });

  final OmnixModelTemplate modelTemplate;
  final OmnixBackendPreference preferredBackend;
  final int maxTokens;
  final int? maxOutputTokens;
  final double temperature;
  final int topK;
  final double topP;
  final String? systemInstruction;
  final bool thinking;
}

/// A response fragment emitted while a conversation turn is generated.
sealed class OmnixConversationEvent {
  const OmnixConversationEvent();
}

/// Visible assistant text.
final class OmnixTextDelta extends OmnixConversationEvent {
  const OmnixTextDelta(this.text);

  final String text;
}

/// Model reasoning separated from its visible answer.
final class OmnixThinkingDelta extends OmnixConversationEvent {
  const OmnixThinkingDelta(this.text);

  final String text;
}

/// A function requested by the model.
final class OmnixToolCall extends OmnixConversationEvent {
  const OmnixToolCall({required this.name, required this.arguments});

  final String name;
  final Map<String, Object?> arguments;
}

/// A stateful local conversation owned by an inference backend.
abstract interface class OmnixConversation {
  /// A provider-neutral snapshot of the currently replayable history.
  List<OmnixMessage> get history;

  /// Replaces native session history with [messages].
  ///
  /// Durable persistence remains the responsibility of a host or storage
  /// adapter. This method only restores the active model session.
  Future<void> replaceHistory(List<OmnixMessage> messages);

  /// Adds a user turn and streams the model response.
  Stream<OmnixConversationEvent> send(String prompt);

  /// Requests cancellation of the active generation.
  Future<void> stop();

  /// Releases the native session owned by this conversation.
  Future<void> close();
}

/// Backend capable of opening local model conversations.
abstract interface class OmnixInferenceBackend {
  Future<OmnixConversation> openConversation(
    OmnixConversationConfiguration configuration,
  );
}
