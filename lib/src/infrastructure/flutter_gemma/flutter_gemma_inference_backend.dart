// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import '../../domain/inference/omnix_conversation.dart';
import '../../domain/models/omnix_model_manifest.dart';

/// Thin Omnix adapter over an already initialized Flutter Gemma runtime.
///
/// Runtime and engine registration remain with the host during the incremental
/// adoption phase. This adapter owns only the active model conversation it
/// creates and closes that conversation deterministically.
final class FlutterGemmaInferenceBackend implements OmnixInferenceBackend {
  const FlutterGemmaInferenceBackend();

  @override
  Future<OmnixConversation> openConversation(
    OmnixConversationConfiguration configuration,
  ) async {
    final model = await _getActiveModel(configuration);
    final chat = await model.createChat(
      temperature: configuration.temperature,
      topK: configuration.topK,
      topP: configuration.topP,
      maxOutputTokens: configuration.maxOutputTokens,
      isThinking: configuration.thinking,
      modelType: _modelType(configuration.modelTemplate),
      systemInstruction: configuration.systemInstruction,
    );
    return FlutterGemmaConversation(chat);
  }
}

Future<InferenceModel> _getActiveModel(
  OmnixConversationConfiguration configuration,
) async {
  final attempts = <String>[];
  for (final backend in _backendOrder(configuration.preferredBackend)) {
    try {
      return await FlutterGemma.getActiveModel(
        maxTokens: configuration.maxTokens,
        preferredBackend: backend,
      );
    } catch (error) {
      attempts.add('${backend.name}: $error');
    }
  }
  throw StateError(
    'No inference backend could load the active model. '
    'Attempts: ${attempts.join(' | ')}',
  );
}

List<PreferredBackend> _backendOrder(OmnixBackendPreference preferred) {
  if (kIsWeb) return const [PreferredBackend.gpu];
  final candidates = switch (preferred) {
    OmnixBackendPreference.cpu => const [
      PreferredBackend.cpu,
      PreferredBackend.gpu,
    ],
    OmnixBackendPreference.gpu => const [
      PreferredBackend.gpu,
      PreferredBackend.cpu,
    ],
    OmnixBackendPreference.npu => const [
      PreferredBackend.npu,
      PreferredBackend.gpu,
      PreferredBackend.cpu,
    ],
  };
  if (defaultTargetPlatform == TargetPlatform.android) return candidates;
  return candidates
      .where((backend) => backend != PreferredBackend.npu)
      .toList(growable: false);
}

/// Conversation wrapper used by [FlutterGemmaInferenceBackend].
final class FlutterGemmaConversation implements OmnixConversation {
  FlutterGemmaConversation(this._chat);

  final InferenceChat _chat;
  bool _closed = false;
  bool _generating = false;

  /// Temporary bridge for hosts whose remaining integrations still require the
  /// Flutter Gemma chat directly, such as plugin-specific voice orchestration.
  ///
  /// New Omnix consumers should use [send], [stop], and [close] instead.
  InferenceChat get nativeChat => _chat;

  @override
  Stream<OmnixConversationEvent> send(String prompt) async* {
    if (_closed) throw StateError('Conversation is closed.');
    if (_generating) throw StateError('Generation is already in progress.');
    final text = prompt.trim();
    if (text.isEmpty) throw ArgumentError.value(prompt, 'prompt', 'is empty');

    _generating = true;
    try {
      await _chat.addQuery(Message.text(text: text, isUser: true));
      await for (final response in _chat.generateChatResponseAsync()) {
        for (final event in mapFlutterGemmaResponse(response)) {
          yield event;
        }
      }
    } finally {
      _generating = false;
    }
  }

  @override
  Future<void> stop() => _chat.stopGeneration();

  @override
  Future<void> close() async {
    if (_closed) return;
    if (_generating) await stop();
    await _chat.close();
    _closed = true;
  }
}

/// Internal response mapping kept visible for adapter contract tests.
Iterable<OmnixConversationEvent> mapFlutterGemmaResponse(
  ModelResponse response,
) sync* {
  switch (response) {
    case TextResponse(:final token):
      yield OmnixTextDelta(token);
    case ThinkingResponse(:final content):
      yield OmnixThinkingDelta(content);
    case FunctionCallResponse(:final name, :final args):
      yield OmnixToolCall(
        name: name,
        arguments: Map<String, Object?>.from(args),
      );
    case ParallelFunctionCallResponse(:final calls):
      for (final call in calls) {
        yield OmnixToolCall(
          name: call.name,
          arguments: Map<String, Object?>.from(call.args),
        );
      }
  }
}

ModelType _modelType(OmnixModelTemplate template) => switch (template) {
  OmnixModelTemplate.general => ModelType.general,
  OmnixModelTemplate.gemma4 => ModelType.gemma4,
  OmnixModelTemplate.qwen3 => ModelType.qwen3,
  OmnixModelTemplate.phi => ModelType.phi,
};
