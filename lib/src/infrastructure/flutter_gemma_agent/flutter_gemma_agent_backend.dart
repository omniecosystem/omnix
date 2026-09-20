// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:flutter_gemma/flutter_gemma.dart' show InferenceChat;
import 'package:flutter_gemma_agent/flutter_gemma_agent.dart' as agent;

import '../../domain/agents/omnix_agent.dart';
import '../../domain/capabilities/omnix_capability_registry_snapshot.dart';
import '../flutter_gemma/flutter_gemma_model_loader.dart';
import 'flutter_gemma_agent_skill_adapter.dart';

/// Flutter Gemma Agent implementation of the neutral Omnix agent contract.
final class FlutterGemmaAgentBackend implements OmnixAgentBackend {
  /// Creates a backend using the imported [skills] and provider executors.
  const FlutterGemmaAgentBackend({
    required this.skills,
    this.executors,
    this.secretStore,
  });

  /// Skill catalog used to materialize each provider registry.
  final FlutterGemmaAgentSkillAdapter skills;

  /// Explicit provider executors, or `null` to use globally registered ones.
  final List<agent.SkillExecutor>? executors;

  /// Optional provider secret store shared by opened sessions.
  final agent.SecretStore? secretStore;

  @override
  Future<OmnixAgentSession> openAgent(
    OmnixAgentConfiguration configuration,
    OmnixCapabilityRegistrySnapshot capabilities,
  ) async {
    final model = await getActiveFlutterGemmaModel(
      maxTokens: configuration.maxTokens,
      preferredBackend: configuration.preferredBackend,
    );
    final providerRegistry = skills.buildProviderRegistry(capabilities);
    final session = await agent.AgentSession.fromModel(
      model,
      registry: providerRegistry,
      executors: executors,
      secretStore: secretStore,
      maxIterations: configuration.maxSteps,
      modelType: flutterGemmaModelType(configuration.modelTemplate),
      supportsFunctionCalls: configuration.supportsFunctionCalls,
      supportImage: configuration.supportsImages,
      supportAudio: configuration.supportsAudio,
      temperature: configuration.temperature,
      randomSeed: configuration.randomSeed,
      topK: configuration.topK,
      topP: configuration.topP,
      maxOutputTokens: configuration.maxOutputTokens,
      systemPromptTemplate:
          configuration.systemPromptTemplate ?? agent.defaultAgentSystemPrompt,
    );
    return FlutterGemmaAgentSession(session);
  }
}

/// Agent-session wrapper used by [FlutterGemmaAgentBackend].
final class FlutterGemmaAgentSession implements OmnixAgentSession {
  /// Wraps an already-created provider [session].
  FlutterGemmaAgentSession(this._session);

  final agent.AgentSession _session;
  bool _closed = false;
  bool _running = false;
  bool _cancelled = false;

  /// Temporary bridge for hosts whose history or voice integrations still
  /// require the Flutter Gemma chat directly.
  ///
  /// New Omnix consumers should use [ask], [stop], and [close] instead.
  InferenceChat get nativeChat => _session.chat;

  @override
  Stream<OmnixAgentEvent> ask(String prompt, {Uint8List? imageBytes}) async* {
    if (_closed) throw StateError('Agent session is closed.');
    if (_running) throw StateError('An agent turn is already in progress.');
    final text = prompt.trim();
    if (text.isEmpty) throw ArgumentError.value(prompt, 'prompt', 'is empty');

    _running = true;
    _cancelled = false;
    try {
      await for (final event in _session.ask(
        text,
        imageBytes: imageBytes,
        isCancelled: () => _cancelled,
      )) {
        yield mapFlutterGemmaAgentEvent(event);
      }
    } finally {
      _running = false;
    }
  }

  @override
  Future<void> stop() async {
    if (_closed || !_running) return;
    _cancelled = true;
    await _session.chat.stopGeneration();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    if (_running) await stop();
    await _session.close();
    _closed = true;
  }
}

/// Maps one Flutter Gemma Agent event without exposing provider types.
OmnixAgentEvent mapFlutterGemmaAgentEvent(agent.AgentEvent event) =>
    switch (event) {
      agent.SkillLoadEvent(:final skillName, :final found) =>
        OmnixAgentSkillLoad(skillId: skillName, found: found),
      agent.ToolCallEvent(:final toolName, :final args, :final skill) =>
        OmnixAgentToolCall(
          name: toolName,
          arguments: Map<String, Object?>.from(args),
          skillId: skill?.name,
        ),
      agent.ToolResultEvent(:final toolName, :final result) =>
        OmnixAgentToolResult(
          name: toolName,
          output: mapFlutterGemmaSkillResult(result),
        ),
      agent.TextChunkEvent(:final text) => OmnixAgentTextDelta(text),
      agent.DoneEvent(:final text) => OmnixAgentCompleted(text),
      agent.MaxIterationsEvent(:final iterations) => OmnixAgentStepLimitReached(
        iterations,
      ),
      agent.AgentErrorEvent(:final message, :final toolName) =>
        OmnixAgentFailure(message, toolName: toolName),
    };

/// Maps one Flutter Gemma skill result into a headless Omnix value.
OmnixAgentToolOutput mapFlutterGemmaSkillResult(agent.SkillResult result) =>
    switch (result) {
      agent.TextResult(:final text) => OmnixAgentTextOutput(text),
      agent.ImageResult(:final bytes) => OmnixAgentImageOutput(bytes),
      agent.WebviewResult(:final url, :final iframe) => _mapWebOutput(
        url,
        iframe: iframe,
      ),
      agent.ErrorResult(:final message) => OmnixAgentErrorOutput(message),
      agent.WidgetResult(:final widget) => OmnixAgentUnavailableOutput(
        kind: 'native-view',
        description: widget.runtimeType.toString(),
      ),
    };

OmnixAgentToolOutput _mapWebOutput(String url, {required bool iframe}) {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) {
    return OmnixAgentErrorOutput('Invalid web resource URI: $url');
  }
  return OmnixAgentWebOutput(uri, embed: iframe);
}
