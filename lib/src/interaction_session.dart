// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'rust/api/interaction.dart' as native;
import 'rust/api/agent.dart' as agent;
import 'dart:convert';
import 'sampling.dart';
import 'runtime_options.dart';
export 'runtime_options.dart';
import 'context_usage.dart';
export 'context_usage.dart';
import 'execution_admission.dart';
export 'execution_admission.dart';
import 'native_intent.dart';
import 'interaction_input.dart';
import 'agent_extensions.dart';
import 'workflow.dart';
import 'rust/api/agent_extensions.dart' as extensions;
import 'infrastructure/rust/rust_initialization.dart';
import 'rust/frb_generated.dart' show RustLib;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;

Future<void> initializeOmnixSessionLibrary(String trustedLibraryPath) =>
    RustLib.init(externalLibrary: ExternalLibrary.open(trustedLibraryPath));

abstract interface class OmnixSessionTransport {
  Future<BigInt> create(
    List<String> runtimes,
    String? libraryPath,
    int contextTokens,
  );
  Future<BigInt> open(
    BigInt engine,
    String modelPath,
    String? instructions,
    int outputTokens,
  );
  Stream<String> stream(BigInt session, String text);
  Future<String> history(BigInt session);
  Future<void> restore(BigInt session, String history);
  void cancel(BigInt session);
  Future<void> closeSession(BigInt session);
  Future<void> closeEngine(BigInt engine);
}

abstract interface class OmnixRuntimeConfigurationTransport {
  OmnixSessionTransport withRuntimeConfiguration(OmnixLiteRtLmOptions options);
}

abstract interface class OmnixSamplingSessionTransport
    implements OmnixSessionTransport {
  Future<BigInt> openSampled(
    BigInt engine,
    String path,
    String? instructions,
    int tokens,
    bool images,
    bool audio,
    String samplingJson,
  );
}

/// Optional transport support for explicit native reasoning configuration.
abstract interface class OmnixThinkingSessionTransport {
  Future<BigInt> openThinkingSession(
    BigInt engine,
    String path,
    String? instructions,
    int tokens,
    bool images,
    bool audio,
    String? samplingJson,
  );
  Future<BigInt> openThinkingAgent(
    BigInt engine,
    String path,
    String? instructions,
    int tokens,
    OmnixAgentExtensions extensions,
    String? samplingJson,
  );
}

/// Optional transport support for changing future reasoning without a model reload.
abstract interface class OmnixThinkingConfigurationTransport {
  Future<void> setSessionThinking(BigInt id, bool enabled);
  Future<void> setAgentThinking(BigInt id, bool enabled);
}

/// Optional support for validated restoration with an explicit future reasoning setting.
abstract interface class OmnixThinkingRestorationTransport {
  Future<void> restoreSessionThinking(BigInt id, String history, bool enabled);
  Future<String> restoreAgentThinking(
    BigInt id,
    String checkpoint,
    bool enabled,
  );
}

/// The runtime-reported output channel, never inferred from generated prose.
enum OmnixOutputKind { text, reasoning }

/// An owned output fragment from the native runtime.
final class OmnixOutputDelta {
  const OmnixOutputDelta(this.kind, this.text);
  final OmnixOutputKind kind;
  final String text;
  factory OmnixOutputDelta.fromJson(Map<String, dynamic> json) =>
      switch (json) {
        {'kind': 'text', 'text': final String text} => OmnixOutputDelta(
          OmnixOutputKind.text,
          text,
        ),
        {'kind': 'reasoning', 'text': final String text} => OmnixOutputDelta(
          OmnixOutputKind.reasoning,
          text,
        ),
        _ => throw const FormatException('Invalid output event.'),
      };
}

/// Optional transport support for separate reasoning and answer streams.
abstract interface class OmnixOutputSessionTransport {
  Stream<OmnixOutputDelta> messageEvents(
    BigInt session,
    List<OmnixInteractionInput> parts,
    OmnixKnowledgeUse knowledge,
  );
}

abstract interface class OmnixReconfigurationTransport {
  Future<void> reconfigureSession(BigInt id, int tokens, String? samplingJson);
  Future<void> reconfigureAgent(BigInt id, int tokens, String? samplingJson);
}

/// Optional transport support for native context policy and diagnostics.
abstract interface class OmnixContextTransport {
  Future<void> configureContext(
    BigInt id,
    bool isAgent,
    bool enabled,
    int safetyMargin,
  );
  Future<String> contextUsage(BigInt id, bool isAgent);
}

/// Optional bridge support for Rust-owned admission configuration and counters.
abstract interface class OmnixExecutionTransport {
  Future<BigInt> createWithExecution(
    List<String> runtimes,
    String? libraryPath,
    int contextTokens,
    OmnixExecutionOptions execution,
    OmnixLocalKnowledge? knowledge,
  );
  Future<String> executionSnapshot(BigInt engine);
}

abstract interface class OmnixAgentCapabilityTransport {
  /// Changes native declarations for future turns without granting authority.
  Future<void> setAgentToolsEnabled(BigInt id, bool enabled);

  /// Imports completed ordinary history into a fresh native agent session.
  Future<void> importAgentChatHistory(BigInt id, String history);
}

abstract interface class OmnixSamplingAgentTransport
    implements OmnixRegisteredAgentTransport {
  Future<BigInt> openSampledAgent(
    BigInt engine,
    String path,
    String? instructions,
    int tokens,
    OmnixAgentExtensions extensions,
    String samplingJson,
  );
}

abstract interface class OmnixMediaSessionTransport {
  Future<BigInt> openMedia(
    BigInt engine,
    String model,
    String? instructions,
    int tokens,
    bool images,
    bool audio,
  );
  Stream<String> messageStream(
    BigInt session,
    List<OmnixInteractionInput> parts,
    OmnixKnowledgeUse knowledge,
  );
}

abstract interface class OmnixAgentMediaTransport {
  Stream<OmnixAgentEvent> streamAgentMessage(
    BigInt id,
    List<OmnixInteractionInput> parts,
  );
}

/// Host-selected native Knowledge resources and retrieval limits.
///
/// Paths must be absolute. Other bindings must release the index before it is
/// opened here. The embedding model must match the index's persisted profile.
final class OmnixLocalKnowledge {
  const OmnixLocalKnowledge({
    required this.embeddingModel,
    required this.storePath,
    this.topK = 3,
    this.threshold = 0.7,
    this.publicOnly = true,
    this.createStore = false,
  });
  final String embeddingModel;
  final String storePath;
  final int topK;
  final double threshold;
  final bool publicOnly;

  /// Whether the trusted host explicitly allows creation of a new index.
  ///
  /// Existing indexes must still match the encoder's persisted profile.
  final bool createStore;
}

/// A document explicitly supplied by the host for native Knowledge ingestion.
final class OmnixKnowledgeDocument {
  const OmnixKnowledgeDocument({
    required this.id,
    required this.documentId,
    required this.title,
    required this.content,
    this.public = false,
  });
  final String id;
  final String documentId;
  final String title;
  final String content;
  final bool public;

  /// Encodes a bounded document for native validation.
  String encode() {
    if ([id, documentId, title, content].any((s) => s.trim().isEmpty)) {
      throw ArgumentError('Empty Knowledge document field.');
    }
    final encoded = jsonEncode({
      'id': id,
      'documentId': documentId,
      'title': title,
      'content': content,
      'public': public,
    });
    if (utf8.encode(encoded).length > 262144) {
      throw ArgumentError('Knowledge document exceeds bridge limit.');
    }
    return encoded;
  }
}

/// Optional transport capability for root-owned indexing and retrieval.
abstract interface class OmnixKnowledgeIndexTransport {
  Future<void> indexKnowledge(BigInt engine, String documentJson);
  Future<List<OmnixInteractionSource>> searchKnowledge(
    BigInt engine,
    String query,
  );
}

/// Optional capability for releasing idle native resources.
abstract interface class OmnixResourceTransport {
  Future<String> releaseIdleResources(BigInt engine);
}

/// The observed release outcome for the configured Knowledge provider.
enum OmnixIdleRelease {
  released,
  alreadyReleased,
  busy,
  unsupported,
  notRegistered,
}

/// Native resource ownership observations, not estimates of memory savings.
final class OmnixIdleResourceReport {
  const OmnixIdleResourceReport({
    required this.knowledge,
    required this.retainedChatModels,
  });
  final OmnixIdleRelease knowledge;
  final int retainedChatModels;
  factory OmnixIdleResourceReport.decode(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> ||
        value['retainedChatModels'] is! int ||
        (value['retainedChatModels'] as int) < 0) {
      throw const FormatException('Invalid native resource report.');
    }
    final outcomes = <String, OmnixIdleRelease>{
      'Released': OmnixIdleRelease.released,
      'AlreadyReleased': OmnixIdleRelease.alreadyReleased,
      'Busy': OmnixIdleRelease.busy,
      'Unsupported': OmnixIdleRelease.unsupported,
      'NotRegistered': OmnixIdleRelease.notRegistered,
    };
    final outcome = outcomes[value['knowledge']];
    if (outcome == null) {
      throw const FormatException('Invalid native release outcome.');
    }
    return OmnixIdleResourceReport(
      knowledge: outcome,
      retainedChatModels: value['retainedChatModels'] as int,
    );
  }
}

/// The native retrieval policy for one interaction.
enum OmnixKnowledgeUse { disabled, ifAvailable, required }

/// Retrieved reference material, not a claim that every answer is supported.
final class OmnixInteractionSource {
  const OmnixInteractionSource({required this.title, required this.content});
  final String title;
  final String content;
}

/// Optional transport capability for Rust-owned retrieval.
abstract interface class OmnixKnowledgeSessionTransport {
  Future<BigInt> createWithKnowledge(
    List<String> runtimes,
    String? libraryPath,
    int contextTokens,
    OmnixLocalKnowledge knowledge,
  );
  Stream<String> groundedStream(
    BigInt session,
    String text,
    OmnixKnowledgeUse knowledge,
  );
  Future<List<OmnixInteractionSource>> sources(BigInt session);
}

final class NativeOmnixSessionTransport
    implements
        OmnixResourceTransport,
        OmnixRuntimeConfigurationTransport,
        OmnixExecutionTransport,
        OmnixContextTransport,
        OmnixReconfigurationTransport,
        OmnixSamplingSessionTransport,
        OmnixThinkingSessionTransport,
        OmnixThinkingConfigurationTransport,
        OmnixThinkingRestorationTransport,
        OmnixOutputSessionTransport,
        OmnixSamplingAgentTransport,
        OmnixSessionTransport,
        OmnixKnowledgeSessionTransport,
        OmnixKnowledgeIndexTransport,
        OmnixAgentTransport,
        OmnixEmailIntentTransport,
        OmnixRegisteredAgentTransport,
        OmnixAgentStreamingTransport,
        OmnixMediaSessionTransport,
        OmnixAgentMediaTransport,
        OmnixAgentCheckpointTransport,
        OmnixAgentCapabilityTransport {
  NativeOmnixSessionTransport({this.litertlm});
  @override
  Future<void> setSessionThinking(BigInt id, bool enabled) =>
      native.interactionSetThinking(sessionId: id, enabled: enabled);
  @override
  Future<void> setAgentThinking(BigInt id, bool enabled) =>
      agent.agentSetThinking(agentId: id, enabled: enabled);
  @override
  Future<void> restoreSessionThinking(
    BigInt id,
    String history,
    bool enabled,
  ) => native.interactionRestore(
    sessionId: id,
    history: history,
    thinking: enabled,
  );
  @override
  Future<String> restoreAgentThinking(
    BigInt id,
    String checkpoint,
    bool enabled,
  ) => agent.agentCheckpoint(
    agentId: id,
    checkpoint: checkpoint,
    thinking: enabled,
  );
  final OmnixLiteRtLmOptions? litertlm;
  @override
  OmnixSessionTransport withRuntimeConfiguration(
    OmnixLiteRtLmOptions options,
  ) => NativeOmnixSessionTransport(litertlm: options);
  @override
  Future<String> releaseIdleResources(BigInt engine) =>
      native.interactionReleaseIdleResources(engineId: engine);
  @override
  Future<BigInt> createWithExecution(
    List<String> runtimes,
    String? libraryPath,
    int contextTokens,
    OmnixExecutionOptions execution,
    OmnixLocalKnowledge? knowledge,
  ) async {
    final encoded = execution.encode();
    await ensureRustInitialized();
    if (knowledge != null) {
      return native.interactionCreateWithKnowledge(
        runtimes: runtimes,
        libraryPath: libraryPath,
        contextTokens: contextTokens,
        embeddingModel: knowledge.embeddingModel,
        storePath: knowledge.storePath,
        topK: knowledge.topK,
        threshold: knowledge.threshold,
        publicOnly: knowledge.publicOnly,
        executionJson: encoded,
        runtimeJson: litertlm?.encode(),
        createStore: knowledge.createStore,
      );
    }
    return native.interactionCreate(
      runtimes: runtimes,
      libraryPath: libraryPath,
      contextTokens: contextTokens,
      executionJson: encoded,
      runtimeJson: litertlm?.encode(),
    );
  }

  @override
  Future<String> executionSnapshot(BigInt engine) =>
      native.interactionExecutionSnapshot(engineId: engine);
  @override
  Future<void> configureContext(
    BigInt id,
    bool isAgent,
    bool enabled,
    int safetyMargin,
  ) => isAgent
      ? agent.agentConfigureContext(
          agentId: id,
          enabled: enabled,
          safetyMargin: safetyMargin,
        )
      : native.interactionConfigureContext(
          sessionId: id,
          enabled: enabled,
          safetyMargin: safetyMargin,
        );
  @override
  Future<String> contextUsage(BigInt id, bool isAgent) => isAgent
      ? agent.agentContextUsage(agentId: id)
      : native.interactionContextUsage(sessionId: id);
  @override
  Future<void> setAgentToolsEnabled(BigInt id, bool enabled) =>
      agent.agentSetToolsEnabled(agentId: id, enabled: enabled);
  @override
  Future<void> importAgentChatHistory(BigInt id, String history) =>
      agent.agentImportChatHistory(agentId: id, history: history);
  @override
  Future<void> reconfigureSession(
    BigInt id,
    int tokens,
    String? samplingJson,
  ) => native.interactionReconfigure(
    sessionId: id,
    maxOutputTokens: tokens,
    samplingJson: samplingJson,
  );
  @override
  Future<void> reconfigureAgent(BigInt id, int tokens, String? samplingJson) =>
      agent.agentReconfigure(
        agentId: id,
        maxOutputTokens: tokens,
        samplingJson: samplingJson,
      );
  @override
  Future<String> agentCheckpoint(BigInt id, String? checkpoint) =>
      agent.agentCheckpoint(agentId: id, checkpoint: checkpoint);
  @override
  Future<BigInt> openMedia(
    BigInt engine,
    String model,
    String? instructions,
    int tokens,
    bool images,
    bool audio,
  ) => native.interactionOpenMedia(
    engineId: engine,
    modelPath: model,
    systemPrompt: instructions,
    maxOutputTokens: tokens,
    images: images,
    audio: audio,
  );
  @override
  Stream<String> messageStream(
    BigInt session,
    List<OmnixInteractionInput> parts,
    OmnixKnowledgeUse knowledge,
  ) async* {
    await for (final event in messageEvents(session, parts, knowledge)) {
      if (event.kind == OmnixOutputKind.text) yield event.text;
    }
  }

  @override
  Stream<OmnixOutputDelta> messageEvents(
    BigInt session,
    List<OmnixInteractionInput> parts,
    OmnixKnowledgeUse knowledge,
  ) async* {
    native.interactionPrepare(sessionId: session);
    var terminal = false;
    await for (final raw in native.interactionMessageStream(
      sessionId: session,
      parts: nativeInteractionParts(parts),
      knowledge: knowledge.name,
    )) {
      final event = jsonDecode(raw) as Map<String, dynamic>;
      if (terminal) throw StateError('Invalid interaction stream lifecycle.');
      switch (event['kind']) {
        case 'text':
        case 'reasoning':
          yield OmnixOutputDelta.fromJson(event);
        case 'completed':
          terminal = true;
        case 'cancelled':
          throw const OmnixExecutionException(OmnixExecutionFailure.cancelled);
        case 'failed':
          final failure = OmnixExecutionException.fromNative(
            event['text'] as String,
          );
          if (failure != null) {
            throw failure;
          }
          throw StateError('Native interaction failed: ${event['text']}');
        default:
          throw StateError('Invalid interaction event.');
      }
    }
    if (!terminal) {
      throw StateError('Interaction stream ended without completion.');
    }
  }

  @override
  Stream<OmnixAgentEvent> streamAgentMessage(
    BigInt id,
    List<OmnixInteractionInput> parts,
  ) async* {
    agent.agentPrepare(agentId: id);
    await for (final raw in agent.agentMessageStream(
      agentId: id,
      parts: nativeInteractionParts(parts),
    )) {
      yield OmnixAgentEvent.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    }
  }

  @override
  Future<BigInt> openAgent(
    BigInt engine,
    String model,
    String? instructions,
    int tokens,
  ) => agent.agentOpen(
    engineId: engine,
    modelPath: model,
    instructions: instructions,
    maxOutputTokens: tokens,
  );
  @override
  Future<BigInt> openSampled(
    BigInt engine,
    String path,
    String? instructions,
    int tokens,
    bool images,
    bool audio,
    String samplingJson,
  ) => native.interactionOpenSampled(
    engineId: engine,
    modelPath: path,
    systemPrompt: instructions,
    maxOutputTokens: tokens,
    images: images,
    audio: audio,
    samplingJson: samplingJson,
    thinking: false,
  );
  @override
  Future<BigInt> openSampledAgent(
    BigInt engine,
    String path,
    String? instructions,
    int tokens,
    OmnixAgentExtensions registration,
    String samplingJson,
  ) => extensions.agentOpenSampledRegistered(
    engineId: engine,
    modelPath: path,
    instructions: instructions,
    maxOutputTokens: tokens,
    samplingJson: samplingJson,
    thinking: false,
    registrationJson: registration.encodeRegistration(),
    execute: registration.executeRequest,
  );
  @override
  Future<BigInt> openRegisteredAgent(
    BigInt engine,
    String model,
    String? instructions,
    int tokens,
    OmnixAgentExtensions registration,
  ) => extensions.agentOpenRegistered(
    engineId: engine,
    modelPath: model,
    instructions: instructions,
    maxOutputTokens: tokens,
    registrationJson: registration.encodeRegistration(),
    execute: registration.executeRequest,
  );
  @override
  Future<BigInt> openThinkingSession(
    BigInt engine,
    String path,
    String? instructions,
    int tokens,
    bool images,
    bool audio,
    String? samplingJson,
  ) => native.interactionOpenSampled(
    engineId: engine,
    modelPath: path,
    systemPrompt: instructions,
    maxOutputTokens: tokens,
    images: images,
    audio: audio,
    samplingJson: samplingJson,
    thinking: true,
  );
  @override
  Future<BigInt> openThinkingAgent(
    BigInt engine,
    String path,
    String? instructions,
    int tokens,
    OmnixAgentExtensions registration,
    String? samplingJson,
  ) => extensions.agentOpenSampledRegistered(
    engineId: engine,
    modelPath: path,
    instructions: instructions,
    maxOutputTokens: tokens,
    samplingJson: samplingJson,
    thinking: true,
    registrationJson: registration.encodeRegistration(),
    execute: registration.executeRequest,
  );
  @override
  Future<OmnixAgentReply> runAgent(BigInt id, String text) async {
    agent.agentPrepare(agentId: id);
    return OmnixAgentReply.fromJson(
      jsonDecode(await agent.agentRun(agentId: id, text: text))
          as Map<String, dynamic>,
    );
  }

  @override
  Future<BigInt> openAgentWithEmailDrafts(
    BigInt engine,
    String model,
    String? instructions,
    int tokens,
  ) => agent.agentOpenWithEmailDrafts(
    engineId: engine,
    modelPath: model,
    instructions: instructions,
    maxOutputTokens: tokens,
  );

  @override
  void cancelAgent(BigInt id) => agent.agentCancel(agentId: id);
  @override
  Stream<OmnixAgentEvent> streamAgent(BigInt id, String text) async* {
    agent.agentPrepare(agentId: id);
    await for (final event in agent.agentStream(agentId: id, text: text)) {
      yield OmnixAgentEvent.fromJson(jsonDecode(event) as Map<String, dynamic>);
    }
  }

  @override
  Future<void> closeAgent(BigInt id) => agent.agentClose(agentId: id);
  @override
  Future<BigInt> createWithKnowledge(
    List<String> runtimes,
    String? libraryPath,
    int contextTokens,
    OmnixLocalKnowledge knowledge,
  ) async {
    await ensureRustInitialized();
    return native.interactionCreateWithKnowledge(
      runtimes: runtimes,
      libraryPath: libraryPath,
      contextTokens: contextTokens,
      embeddingModel: knowledge.embeddingModel,
      storePath: knowledge.storePath,
      topK: knowledge.topK,
      threshold: knowledge.threshold,
      publicOnly: knowledge.publicOnly,
      createStore: knowledge.createStore,
      runtimeJson: litertlm?.encode(),
    );
  }

  @override
  Future<void> indexKnowledge(BigInt engine, String documentJson) => native
      .interactionKnowledgeIndex(engineId: engine, recordJson: documentJson);
  @override
  Future<List<OmnixInteractionSource>> searchKnowledge(
    BigInt engine,
    String query,
  ) async {
    final decoded =
        jsonDecode(
              await native.interactionKnowledgeSearch(
                engineId: engine,
                query: query,
              ),
            )
            as List<dynamic>;
    return decoded
        .map(
          (entry) => OmnixInteractionSource(
            title: entry['title'] as String,
            content: entry['content'] as String,
          ),
        )
        .toList();
  }

  @override
  Stream<String> groundedStream(
    BigInt session,
    String text,
    OmnixKnowledgeUse knowledge,
  ) async* {
    yield* messageStream(session, [
      OmnixInteractionInput.text(text),
    ], knowledge);
  }

  @override
  Future<List<OmnixInteractionSource>> sources(BigInt session) async {
    final decoded =
        jsonDecode(await native.interactionSources(sessionId: session))
            as List<dynamic>;
    return List.unmodifiable(
      decoded.map((item) {
        final value = item as Map<String, dynamic>;
        return OmnixInteractionSource(
          title: value['title'] as String,
          content: value['content'] as String,
        );
      }),
    );
  }

  @override
  Future<BigInt> create(
    List<String> runtimes,
    String? libraryPath,
    int contextTokens,
  ) async {
    await ensureRustInitialized();
    return native.interactionCreate(
      runtimes: runtimes,
      libraryPath: libraryPath,
      contextTokens: contextTokens,
      runtimeJson: litertlm?.encode(),
    );
  }

  @override
  Future<BigInt> open(
    BigInt engine,
    String modelPath,
    String? instructions,
    int outputTokens,
  ) => native.interactionOpen(
    engineId: engine,
    modelPath: modelPath,
    systemPrompt: instructions,
    maxOutputTokens: outputTokens,
  );
  @override
  Stream<String> stream(BigInt session, String text) async* {
    yield* messageStream(session, [
      OmnixInteractionInput.text(text),
    ], OmnixKnowledgeUse.disabled);
  }

  @override
  Future<String> history(BigInt session) =>
      native.interactionHistory(sessionId: session);
  @override
  Future<void> restore(BigInt session, String history) =>
      native.interactionRestore(sessionId: session, history: history);
  @override
  void cancel(BigInt session) => native.interactionCancel(sessionId: session);
  @override
  Future<void> closeSession(BigInt session) =>
      native.interactionCloseSession(sessionId: session);
  @override
  Future<void> closeEngine(BigInt engine) =>
      native.interactionCloseEngine(engineId: engine);
}

final class OmnixCognitiveEngine {
  OmnixCognitiveEngine._(this._id, this._transport);
  final BigInt _id;
  final OmnixSessionTransport _transport;
  Future<void> _tail = Future.value();
  Future<void>? _closing;
  static Future<OmnixCognitiveEngine> open({
    required List<String> runtimes,
    String? libraryPath,
    int contextTokens = 4096,
    OmnixSessionTransport? transport,
    OmnixLocalKnowledge? knowledge,
    OmnixExecutionOptions? execution,
    OmnixLiteRtLmOptions? litertlm,
  }) async {
    if (runtimes.isEmpty ||
        runtimes.toSet().length != runtimes.length ||
        runtimes.any((r) => r != 'litertlm' && r != 'llamacpp')) {
      throw ArgumentError('Select distinct litertlm and/or llamacpp runtimes.');
    }
    if (contextTokens < 128 || contextTokens > 32768) {
      throw ArgumentError('Invalid context limit.');
    }
    var selected = transport ?? NativeOmnixSessionTransport();
    if (litertlm != null) {
      litertlm.encode();
      if (!runtimes.contains('litertlm')) {
        throw ArgumentError('LiteRT-LM options require the litertlm runtime.');
      }
      if (selected is! OmnixRuntimeConfigurationTransport) {
        throw UnsupportedError(
          'Transport does not support runtime configuration.',
        );
      }
      selected = (selected as OmnixRuntimeConfigurationTransport)
          .withRuntimeConfiguration(litertlm);
    }
    if (execution != null) {
      execution.encode();
      if (selected is! OmnixExecutionTransport) {
        throw UnsupportedError(
          'Transport does not support native execution admission.',
        );
      }
    }
    if (knowledge != null) {
      if (knowledge.embeddingModel.trim().isEmpty ||
          knowledge.storePath.trim().isEmpty ||
          knowledge.topK < 1 ||
          knowledge.topK > 16 ||
          !knowledge.threshold.isFinite ||
          knowledge.threshold < -1 ||
          knowledge.threshold > 1) {
        throw ArgumentError('Invalid Knowledge configuration.');
      }
      if (selected is! OmnixKnowledgeSessionTransport) {
        throw UnsupportedError('Transport does not support native Knowledge.');
      }
      if (knowledge.createStore && selected is! OmnixKnowledgeIndexTransport) {
        throw UnsupportedError(
          'Transport does not support native Knowledge creation.',
        );
      }
      if (execution == null) {
        return OmnixCognitiveEngine._(
          await (selected as OmnixKnowledgeSessionTransport)
              .createWithKnowledge(
                List.unmodifiable(runtimes),
                libraryPath,
                contextTokens,
                knowledge,
              ),
          selected,
        );
      }
    }
    if (execution != null) {
      return OmnixCognitiveEngine._(
        await (selected as OmnixExecutionTransport).createWithExecution(
          List.unmodifiable(runtimes),
          libraryPath,
          contextTokens,
          execution,
          knowledge,
        ),
        selected,
      );
    }
    return OmnixCognitiveEngine._(
      await selected.create(
        List.unmodifiable(runtimes),
        libraryPath,
        contextTokens,
      ),
      selected,
    );
  }

  /// Embeds, indexes and flushes a document through this engine's native provider.
  ///
  /// No model-generated visibility or automatic retry is applied.
  Future<void> indexDocument(OmnixKnowledgeDocument document) {
    final encoded = document.encode();
    return _knowledgeCall(
      (transport) => transport.indexKnowledge(_id, encoded),
    );
  }

  /// Retrieves authorized sources through this engine without generating an answer.
  Future<List<OmnixInteractionSource>> retrieveSources(String query) {
    if (query.trim().isEmpty) {
      return Future.error(ArgumentError('Empty Knowledge query.'));
    }
    return _knowledgeCall((transport) => transport.searchKnowledge(_id, query));
  }

  Future<T> _knowledgeCall<T>(
    Future<T> Function(OmnixKnowledgeIndexTransport) action,
  ) {
    if (_closing != null) {
      return Future.error(StateError('Engine closed.'));
    }
    final transport = _transport;
    if (transport is! OmnixKnowledgeIndexTransport) {
      return Future.error(
        UnsupportedError('Transport does not support native indexing.'),
      );
    }
    final pending = _tail.then((_) async {
      try {
        return await action(transport as OmnixKnowledgeIndexTransport);
      } catch (error, stack) {
        final failure = OmnixExecutionException.fromNative(error);
        if (failure != null) {
          Error.throwWithStackTrace(failure, stack);
        }
        rethrow;
      }
    });
    _tail = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return pending;
  }

  Future<OmnixInteractionSession> startSession({
    required String modelPath,
    String? instructions,
    int maxOutputTokens = 256,
    bool enableImages = false,
    bool enableAudio = false,
    OmnixSamplingOptions? sampling,
    bool thinking = false,
  }) {
    if (_closing != null) return Future.error(StateError('Engine closed.'));
    if (modelPath.trim().isEmpty || maxOutputTokens <= 0) {
      return Future.error(ArgumentError('Invalid session settings.'));
    }
    final pending = _tail.then(
      (_) async => OmnixInteractionSession._(
        await (thinking
            ? (_transport is OmnixThinkingSessionTransport
                  ? (_transport as OmnixThinkingSessionTransport)
                        .openThinkingSession(
                          _id,
                          modelPath,
                          instructions,
                          maxOutputTokens,
                          enableImages,
                          enableAudio,
                          sampling?.encode(),
                        )
                  : throw UnsupportedError(
                      'Transport does not support thinking.',
                    ))
            : sampling != null
            ? (_transport is OmnixSamplingSessionTransport
                  ? _transport.openSampled(
                      _id,
                      modelPath,
                      instructions,
                      maxOutputTokens,
                      enableImages,
                      enableAudio,
                      sampling.encode(),
                    )
                  : throw UnsupportedError(
                      'Transport does not support sampling settings.',
                    ))
            : enableImages || enableAudio
            ? (_transport is OmnixMediaSessionTransport
                  ? (_transport as OmnixMediaSessionTransport).openMedia(
                      _id,
                      modelPath,
                      instructions,
                      maxOutputTokens,
                      enableImages,
                      enableAudio,
                    )
                  : throw UnsupportedError('Transport does not support media.'))
            : _transport.open(_id, modelPath, instructions, maxOutputTokens)),
        _transport,
      ),
    );
    _tail = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return pending;
  }

  Future<void> close() =>
      _closing ??= _tail.then((_) => _transport.closeEngine(_id));

  /// Requests idle resource release without closing live conversations.
  ///
  /// A busy provider reports deferral; this method does not wait for generation
  /// or retry automatically. The next Knowledge operation reloads its encoder.
  Future<OmnixIdleResourceReport> releaseIdleResources() {
    if (_closing != null) return Future.error(StateError('Engine closed.'));
    final transport = _transport;
    if (transport is! OmnixResourceTransport) {
      return Future.error(
        UnsupportedError('Transport does not support idle release.'),
      );
    }
    // Start immediately: pressure handling must not queue behind indexing. Track
    // completion only so close cannot release the native handle underneath it.
    final pending = (transport as OmnixResourceTransport)
        .releaseIdleResources(_id)
        .then(OmnixIdleResourceReport.decode);
    final previous = _tail;
    _tail = Future.wait<void>([
      previous,
      pending.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    ]).then((_) {});
    return pending;
  }

  /// Reads native admission counters without waiting for inference completion.
  Future<OmnixExecutionSnapshot> executionSnapshot() async {
    if (_closing != null) throw StateError('Engine closed.');
    final transport = _transport;
    if (transport is! OmnixExecutionTransport) {
      throw UnsupportedError('Transport does not support execution counters.');
    }
    return OmnixExecutionSnapshot.decode(
      await (transport as OmnixExecutionTransport).executionSnapshot(_id),
    );
  }

  /// Opens durable work using this engine's native tools and fresh host grants.
  ///
  /// This does not execute or recover steps. Close the returned owner separately.
  Future<OmnixWorkflow> startWorkflow({
    required String databasePath,
    required OmnixWorkflowDefinition definition,
    required OmnixAgentExtensions extensions,
    OmnixWorkflowTransport? workflowTransport,
  }) {
    if (_closing != null) return Future.error(StateError('Engine closed.'));
    if (_transport is! NativeOmnixSessionTransport &&
        workflowTransport == null) {
      return Future.error(
        UnsupportedError(
          'Supply a Workflow transport for this custom engine transport.',
        ),
      );
    }
    final pending = _tail.then(
      (_) => OmnixWorkflow.open(
        databasePath: databasePath,
        definition: definition,
        extensions: extensions,
        engineId: _id,
        transport: workflowTransport,
      ),
    );
    _tail = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return pending;
  }

  /// Opens a Rust-owned agent with access only to explicitly granted tools.
  ///
  /// Registered agents can request supported image/audio input through their
  /// extensions. Checkpoints preserve completed exchanges and owned media when
  /// supported by the runtime. The current native agent bridge accepts LiteRT-LM
  /// models on Android and Windows; other runtimes and targets report unsupported.
  Future<OmnixAgentSession> startAgent({
    required String modelPath,
    required OmnixAgentExtensions extensions,
    String? instructions,
    int maxOutputTokens = 256,
    OmnixSamplingOptions? sampling,
    bool thinking = false,
  }) {
    if (_closing != null) return Future.error(StateError('Engine closed.'));
    final transport = _transport;
    if (transport is! OmnixAgentTransport ||
        transport is! OmnixRegisteredAgentTransport) {
      return Future.error(
        UnsupportedError(
          'Transport does not support registered native agents.',
        ),
      );
    }
    if (modelPath.trim().isEmpty || maxOutputTokens <= 0) {
      return Future.error(ArgumentError('Invalid agent settings.'));
    }
    final pending = _tail.then(
      (_) async => OmnixAgentSession._(
        await (thinking
            ? (transport is OmnixThinkingSessionTransport
                  ? (transport as OmnixThinkingSessionTransport)
                        .openThinkingAgent(
                          _id,
                          modelPath,
                          instructions,
                          maxOutputTokens,
                          extensions,
                          sampling?.encode(),
                        )
                  : throw UnsupportedError(
                      'Transport does not support agent thinking.',
                    ))
            : sampling != null
            ? (transport is OmnixSamplingAgentTransport
                  ? (transport as OmnixSamplingAgentTransport).openSampledAgent(
                      _id,
                      modelPath,
                      instructions,
                      maxOutputTokens,
                      extensions,
                      sampling.encode(),
                    )
                  : throw UnsupportedError(
                      'Transport does not support agent sampling settings.',
                    ))
            : (transport as OmnixRegisteredAgentTransport).openRegisteredAgent(
                _id,
                modelPath,
                instructions,
                maxOutputTokens,
                extensions,
              )),
        transport as OmnixAgentTransport,
      ),
    );
    _tail = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return pending;
  }

  Future<OmnixAgentSession> startKnowledgeAgent({
    required String modelPath,
    String? instructions,
    int maxOutputTokens = 256,
    bool allowEmailDrafts = false,
  }) {
    if (_closing != null) return Future.error(StateError('Engine closed.'));
    final transport = _transport;
    if (transport is! OmnixAgentTransport) {
      return Future.error(
        UnsupportedError('Transport does not support native agents.'),
      );
    }
    if (modelPath.trim().isEmpty || maxOutputTokens <= 0) {
      return Future.error(ArgumentError('Invalid agent settings.'));
    }
    if (allowEmailDrafts && transport is! OmnixEmailIntentTransport) {
      return Future.error(
        UnsupportedError('Transport does not support native email proposals.'),
      );
    }
    final pending = _tail.then(
      (_) async => OmnixAgentSession._(
        await (allowEmailDrafts
            ? (transport as OmnixEmailIntentTransport).openAgentWithEmailDrafts(
                _id,
                modelPath,
                instructions,
                maxOutputTokens,
              )
            : (transport as OmnixAgentTransport).openAgent(
                _id,
                modelPath,
                instructions,
                maxOutputTokens,
              )),
        transport as OmnixAgentTransport,
      ),
    );
    _tail = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return pending;
  }
}

/// The optional transport for native agent execution, never a Dart tool loop.
abstract interface class OmnixAgentTransport {
  Future<BigInt> openAgent(
    BigInt engine,
    String model,
    String? instructions,
    int tokens,
  );
  Future<OmnixAgentReply> runAgent(BigInt id, String text);
  void cancelAgent(BigInt id);
  Future<void> closeAgent(BigInt id);
}

abstract interface class OmnixRegisteredAgentTransport {
  Future<BigInt> openRegisteredAgent(
    BigInt engine,
    String model,
    String? instructions,
    int tokens,
    OmnixAgentExtensions extensions,
  );
}

/// The optional transport for Rust-owned completed agent context.
abstract interface class OmnixAgentCheckpointTransport {
  Future<String> agentCheckpoint(BigInt id, String? checkpoint);
}

/// The optional capability for Rust-validated, host-reviewed email proposals.
abstract interface class OmnixEmailIntentTransport {
  Future<BigInt> openAgentWithEmailDrafts(
    BigInt engine,
    String model,
    String? instructions,
    int tokens,
  );
}

/// The optional transport for genuine native agent events.
abstract interface class OmnixAgentStreamingTransport {
  Stream<OmnixAgentEvent> streamAgent(BigInt id, String text);
}

/// The native agent's model-turn and authorized tool-progress boundaries.
enum OmnixAgentEventKind {
  failed,
  turnStarted,
  text,
  reasoning,
  toolStarted,
  toolFinished,
  completed,
  cancelled,
}

/// A native event whose text remains provisional until turn completion.
final class OmnixAgentEvent {
  const OmnixAgentEvent({
    required this.kind,
    this.text,
    this.toolName,
    this.reply,
    this.toolFailed = false,
    this.recoverable = false,
    this.interruptionRetained = false,
    this.outcome,
  });
  factory OmnixAgentEvent.fromJson(Map<String, dynamic> json) {
    final kind = OmnixAgentEventKind.values.firstWhere(
      (value) => value.name == json['kind'],
      orElse: () => throw const FormatException('Unknown agent event.'),
    );
    final text = json['text'] as String?;
    final tool = json['toolName'] as String?;
    final reply = json['reply'] == null
        ? null
        : OmnixAgentReply.fromJson(json['reply'] as Map<String, dynamic>);
    if (((kind == OmnixAgentEventKind.text ||
                kind == OmnixAgentEventKind.reasoning ||
                kind == OmnixAgentEventKind.failed) &&
            text == null) ||
        ((kind == OmnixAgentEventKind.toolStarted ||
                kind == OmnixAgentEventKind.toolFinished) &&
            tool == null) ||
        (kind == OmnixAgentEventKind.completed && reply == null)) {
      throw const FormatException('Incomplete agent event.');
    }
    return OmnixAgentEvent(
      kind: kind,
      text: text,
      toolName: tool,
      reply: reply,
      toolFailed: json['toolFailed'] as bool? ?? false,
      recoverable: json['recoverable'] as bool? ?? false,
      interruptionRetained: json['interruptionRetained'] as bool? ?? false,
      outcome: json['outcome'] == null
          ? null
          : OmnixToolOutcome.fromJson(json['outcome'] as Map<String, dynamic>),
    );
  }
  final OmnixAgentEventKind kind;
  final String? text;
  final String? toolName;
  final OmnixAgentReply? reply;
  final bool toolFailed;
  final bool recoverable;

  /// Whether native recovery retained the request and partial answer in context.
  final bool interruptionRetained;
  final OmnixToolOutcome? outcome;
  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    if (text != null) 'text': text,
    if (toolName != null) 'toolName': toolName,
    if (reply != null) 'reply': reply!.toJson(),
    if (toolFailed) 'toolFailed': true,
    if (recoverable) 'recoverable': true,
    if (interruptionRetained) 'interruptionRetained': true,
    if (outcome != null) 'outcome': outcome!.toJson(),
  };
}

final class OmnixToolOutcome {
  const OmnixToolOutcome({
    required this.callId,
    required this.toolName,
    required this.status,
    this.reason,
  });
  factory OmnixToolOutcome.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as String;
    final reason = json['reason'] as String?;
    if (status.isEmpty ||
        status.length > 64 ||
        !RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(status) ||
        (reason?.length ?? 0) > 1024) {
      throw const FormatException('Invalid tool outcome.');
    }
    return OmnixToolOutcome(
      callId: json['callId'] as String,
      toolName: json['toolName'] as String,
      status: status,
      reason: reason,
    );
  }
  final String callId;
  final String toolName;
  final String status;
  final String? reason;
  Map<String, Object?> toJson() => {
    'callId': callId,
    'toolName': toolName,
    'status': status,
    'reason': reason,
  };
}

/// A completed model answer with separate authorized retrieval evidence.
final class OmnixAgentReply {
  OmnixAgentReply({
    required this.text,
    required this.toolCalls,
    required List<OmnixInteractionSource> sources,
    List<OmnixEmailIntent> intents = const [],
    List<OmnixToolOutcome> toolOutcomes = const [],
  }) : sources = List.unmodifiable(sources),
       toolOutcomes = List.unmodifiable(toolOutcomes),
       intents = List.unmodifiable(intents);
  factory OmnixAgentReply.fromJson(Map<String, dynamic> json) {
    final text = json['text'] as String;
    final calls = json['toolCalls'] as int;
    if (calls < 0 || calls > 32) {
      throw const FormatException('Invalid tool count.');
    }
    final intents = json['intents'] as List? ?? const [];
    if (intents.length > 32) {
      throw const FormatException('Too many native proposals.');
    }
    return OmnixAgentReply(
      text: text,
      toolCalls: calls,
      intents: [
        for (final item in intents)
          OmnixEmailIntent.fromJson(item as Map<String, dynamic>),
      ],
      toolOutcomes: [
        for (final item in json['toolOutcomes'] as List? ?? const [])
          OmnixToolOutcome.fromJson(item as Map<String, dynamic>),
      ],
      sources: [
        for (final item in json['sources'] as List)
          OmnixInteractionSource(
            title: (item as Map<String, dynamic>)['title'] as String,
            content: item['content'] as String,
          ),
      ],
    );
  }
  final String text;
  final int toolCalls;
  final List<OmnixInteractionSource> sources;
  final List<OmnixEmailIntent> intents;
  final List<OmnixToolOutcome> toolOutcomes;
  Map<String, dynamic> toJson() => {
    'text': text,
    'toolCalls': toolCalls,
    'intents': [for (final intent in intents) intent.toJson()],
    'toolOutcomes': [for (final outcome in toolOutcomes) outcome.toJson()],
    'sources': [
      for (final source in sources)
        {'title': source.title, 'content': source.content},
    ],
  };
}

/// A live native agent session with runtime-confirmed interruption recovery.
final class OmnixAgentSession {
  /// Changes future native reasoning between completed turns without erasing context.
  Future<void> setThinking(bool enabled) async {
    if (_closed || _busy) throw StateError('Agent closed or busy.');
    final transport = _transport;
    if (transport is! OmnixThinkingConfigurationTransport) {
      throw UnsupportedError('Live thinking settings unsupported.');
    }
    _busy = true;
    try {
      await (transport as OmnixThinkingConfigurationTransport).setAgentThinking(
        _id,
        enabled,
      );
    } finally {
      _busy = false;
    }
  }

  /// Configures recent-turn selection when the runtime supports accounting.
  ///
  /// LiteRT-LM rejects enabling this capability explicitly. Full checkpoints
  /// remain intact. This does not enable summarization.
  Future<void> configureContext({
    bool enabled = true,
    int safetyMargin = 128,
  }) async {
    if (safetyMargin < 0 || safetyMargin > 32768) {
      throw ArgumentError('Invalid safety margin.');
    }
    if (_closed || _busy) throw StateError('Agent closed or busy.');
    final transport = _transport;
    if (transport is! OmnixContextTransport) {
      throw UnsupportedError('Context policy unsupported.');
    }
    _busy = true;
    try {
      await (transport as OmnixContextTransport).configureContext(
        _id,
        true,
        enabled,
        safetyMargin,
      );
    } finally {
      _busy = false;
    }
  }

  /// Reads context diagnostics when supported, without executing tools.
  ///
  /// LiteRT-LM reports unsupported rather than estimating token counts.
  Future<OmnixContextUsage?> contextUsage() async {
    if (_closed || _busy) throw StateError('Agent closed or busy.');
    final transport = _transport;
    if (transport is! OmnixContextTransport) {
      throw UnsupportedError('Context diagnostics unsupported.');
    }
    _busy = true;
    try {
      return OmnixContextUsage.decode(
        await (transport as OmnixContextTransport).contextUsage(_id, true),
      );
    } finally {
      _busy = false;
    }
  }

  /// Enables or disables the supplied tools between completed turns.
  ///
  /// Disabling removes native declarations but retains historical context.
  /// Enabling keeps the host's existing policy and does not grant approval.
  /// Throws [StateError] when closed or busy, and [UnsupportedError] for
  /// transports without capability switching.
  Future<void> setToolsEnabled(bool enabled) => _capabilityOperation(
    (transport) => transport.setAgentToolsEnabled(_id, enabled),
  );

  /// Imports completed ordinary context into a fresh tool-capable session.
  ///
  /// [history] is the opaque ordinary history envelope, not display text.
  /// The host must supply the same model and the required media encoders.
  /// Rust validates text or native context and rejects tool-bearing history.
  /// No inference, tool execution, or approval occurs during import.
  Future<void> importChatHistory(String history) => _capabilityOperation(
    (transport) => transport.importAgentChatHistory(_id, history),
  );
  Future<void> _capabilityOperation(
    Future<void> Function(OmnixAgentCapabilityTransport) operation,
  ) async {
    if (_closed || _busy) throw StateError('Agent closed or busy.');
    final transport = _transport;
    if (transport is! OmnixAgentCapabilityTransport) {
      throw UnsupportedError('Transport does not support capability changes.');
    }
    _busy = true;
    try {
      await operation(transport as OmnixAgentCapabilityTransport);
      if (_closed) throw StateError('Agent closed during capability change.');
    } finally {
      _busy = false;
    }
  }

  Future<void> reconfigure({
    required int maxOutputTokens,
    OmnixSamplingOptions? sampling,
  }) async {
    if (_closed || _busy) throw StateError('Agent closed or busy.');
    final transport = _transport;
    if (transport is! OmnixReconfigurationTransport) {
      throw UnsupportedError('Live settings unsupported.');
    }
    final encoded = sampling?.encode();
    if (maxOutputTokens < 1) throw ArgumentError('Invalid response budget.');
    _busy = true;
    try {
      await (transport as OmnixReconfigurationTransport).reconfigureAgent(
        _id,
        maxOutputTokens,
        encoded,
      );
    } finally {
      _busy = false;
    }
  }

  OmnixAgentSession._(this._id, this._transport);
  final BigInt _id;
  final OmnixAgentTransport _transport;
  bool _busy = false;
  bool _closed = false;
  Future<void>? _closing;

  /// Exports completed context without executing host tools.
  ///
  /// Store the opaque checkpoint privately; it can contain tool arguments and
  /// results and owned media. Runtime-specific bounds are validated natively.
  Future<String> exportCheckpoint() => _checkpoint(null);

  /// Restores context into a fresh agent with newly supplied host authority.
  ///
  /// The native implementation rejects mismatched model metadata, settings,
  /// tool declarations and incomplete exchanges. It never executes saved calls.
  Future<void> restoreCheckpoint(String checkpoint, {bool? thinking}) async {
    await _checkpoint(checkpoint, thinking: thinking);
  }

  Future<String> _checkpoint(String? checkpoint, {bool? thinking}) async {
    if (_closed || _busy) throw StateError('Agent closed or busy.');
    final transport = _transport;
    if (transport is! OmnixAgentCheckpointTransport) {
      throw UnsupportedError('Transport does not support agent checkpoints.');
    }
    if (thinking != null && transport is! OmnixThinkingRestorationTransport) {
      throw UnsupportedError('Thinking checkpoint transition unsupported.');
    }
    _busy = true;
    try {
      final result = thinking != null
          ? await (transport as OmnixThinkingRestorationTransport)
                .restoreAgentThinking(_id, checkpoint!, thinking)
          : await (transport as OmnixAgentCheckpointTransport).agentCheckpoint(
              _id,
              checkpoint,
            );
      if (_closed) {
        throw StateError('Agent closed during checkpoint operation.');
      }
      return result;
    } finally {
      _busy = false;
    }
  }

  Future<OmnixAgentReply> send(String text) async {
    if (_transport is OmnixAgentStreamingTransport) {
      OmnixAgentReply? reply;
      await for (final event in sendEvents(text)) {
        if (event.kind == OmnixAgentEventKind.completed) reply = event.reply;
      }
      return reply ?? (throw StateError('Agent turn did not complete.'));
    }
    if (_closed || _busy) throw StateError('Agent closed or busy.');
    if (text.trim().isEmpty) throw ArgumentError('Empty request.');
    _busy = true;
    try {
      final reply = await _transport.runAgent(_id, text);
      if (_closed) throw StateError('Agent closed during generation.');
      return reply;
    } catch (_) {
      await close();
      rethrow;
    } finally {
      _busy = false;
    }
  }

  /// Streams provisional model text, tool progress and the authoritative reply.
  ///
  /// Reset displayed text on `turnStarted`; `toolStarted` marks the preceding
  /// text as preamble. Only `completed` supplies a completed answer. Hosts may
  /// also save partial text; `interruptionRetained` reports whether native
  /// recovery retained the interrupted request and answer in model context.
  /// Native-confirmed recovery retains the loaded model and session.
  /// Otherwise, failure or abandoning the stream invalidates the session.
  Stream<OmnixAgentEvent> sendEvents(
    String text, {
    List<OmnixInteractionInput>? parts,
  }) async* {
    if (_closed || _busy) throw StateError('Agent closed or busy.');
    if (text.trim().isEmpty && (parts == null || parts.isEmpty)) {
      throw ArgumentError('Empty request.');
    }
    final transport = _transport;
    if (transport is! OmnixAgentStreamingTransport) {
      throw UnsupportedError(
        'Transport does not support native agent streaming.',
      );
    }
    if (parts != null && transport is! OmnixAgentMediaTransport) {
      throw UnsupportedError('Transport does not support agent media.');
    }
    _busy = true;
    var completed = false;
    var terminal = false;
    var recovered = false;
    try {
      await for (final event
          in (parts != null
              ? (transport as OmnixAgentMediaTransport).streamAgentMessage(
                  _id,
                  parts,
                )
              : (transport as OmnixAgentStreamingTransport).streamAgent(
                  _id,
                  text,
                ))) {
        if (_closed || terminal) {
          throw StateError('Invalid agent stream lifecycle.');
        }
        if (event.kind == OmnixAgentEventKind.failed) {
          final admission = OmnixExecutionException.fromNative(
            event.text ?? '',
          );
          if (admission != null) throw admission;
          throw StateError('Native agent failed: ${event.text}');
        }
        if (event.kind == OmnixAgentEventKind.completed) {
          completed = true;
          terminal = true;
        }
        if (event.kind == OmnixAgentEventKind.cancelled) {
          terminal = true;
          recovered = event.recoverable;
        }
        yield event;
      }
      if (!terminal) throw StateError('Agent stream ended without completion.');
    } catch (_) {
      completed = false;
      recovered = false;
      rethrow;
    } finally {
      try {
        if (!completed && !recovered) await close();
      } finally {
        _busy = false;
      }
    }
  }

  /// Requests native streaming cancellation and prevents subsequent tool steps.
  void cancelGeneration() {
    if (!_closed) _transport.cancelAgent(_id);
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _transport.cancelAgent(_id);
    return _closing = _transport.closeAgent(_id);
  }
}

final class OmnixInteractionSession {
  /// Changes future native reasoning without reloading the model or erasing history.
  Future<void> setThinking(bool enabled) {
    final transport = _transport;
    if (transport is! OmnixThinkingConfigurationTransport) {
      return Future.error(
        UnsupportedError('Live thinking settings unsupported.'),
      );
    }
    return _exclusive(
      () => (transport as OmnixThinkingConfigurationTransport)
          .setSessionThinking(_id, enabled),
    );
  }

  /// Configures recent-turn selection when the runtime supports accounting.
  ///
  /// LiteRT-LM rejects enabling this capability without changing stored history.
  Future<void> configureContext({bool enabled = true, int safetyMargin = 128}) {
    if (safetyMargin < 0 || safetyMargin > 32768) {
      throw ArgumentError('Invalid safety margin.');
    }
    final transport = _transport;
    if (transport is! OmnixContextTransport) {
      return Future.error(UnsupportedError('Context policy unsupported.'));
    }
    return _exclusive(
      () => (transport as OmnixContextTransport).configureContext(
        _id,
        false,
        enabled,
        safetyMargin,
      ),
    );
  }

  /// Reads native context diagnostics when supported.
  ///
  /// LiteRT-LM reports unsupported rather than estimating token counts.
  Future<OmnixContextUsage?> contextUsage() async {
    final transport = _transport;
    if (transport is! OmnixContextTransport) {
      throw UnsupportedError('Context diagnostics unsupported.');
    }
    String? encoded;
    await _exclusive(() async {
      encoded = await (transport as OmnixContextTransport).contextUsage(
        _id,
        false,
      );
    });
    return OmnixContextUsage.decode(encoded!);
  }

  Future<void> reconfigure({
    required int maxOutputTokens,
    OmnixSamplingOptions? sampling,
  }) {
    final transport = _transport;
    if (transport is! OmnixReconfigurationTransport) {
      return Future.error(UnsupportedError('Live settings unsupported.'));
    }
    if (maxOutputTokens < 1) {
      return Future.error(ArgumentError('Invalid response budget.'));
    }
    final encoded = sampling?.encode();
    return _exclusive(
      () => (transport as OmnixReconfigurationTransport).reconfigureSession(
        _id,
        maxOutputTokens,
        encoded,
      ),
    );
  }

  OmnixInteractionSession._(this._id, this._transport);
  final BigInt _id;
  final OmnixSessionTransport _transport;
  bool _busy = false;
  bool _closed = false;
  Future<void>? _closing;
  List<OmnixInteractionSource> _sources = const [];

  /// The references from the last completed turn, cleared when a new turn starts.
  List<OmnixInteractionSource> get sources => _sources;
  Stream<String> sendMessageStream(
    List<OmnixInteractionInput> parts, {
    OmnixKnowledgeUse knowledge = OmnixKnowledgeUse.ifAvailable,
  }) async* {
    await for (final event in sendMessageEvents(parts, knowledge: knowledge)) {
      if (event.kind == OmnixOutputKind.text) yield event.text;
    }
  }

  /// Streams native reasoning separately from visible answer text.
  Stream<OmnixOutputDelta> sendMessageEvents(
    List<OmnixInteractionInput> parts, {
    OmnixKnowledgeUse knowledge = OmnixKnowledgeUse.ifAvailable,
  }) async* {
    if (_closed || _busy) throw StateError('Session closed or busy.');
    if (parts.isEmpty) throw ArgumentError('Empty request.');
    final transport = _transport;
    if (transport is! OmnixMediaSessionTransport) {
      throw UnsupportedError('Transport does not support media.');
    }
    _busy = true;
    _sources = const [];
    var completed = false;
    try {
      final updates = transport is OmnixOutputSessionTransport
          ? (transport as OmnixOutputSessionTransport).messageEvents(
              _id,
              parts,
              knowledge,
            )
          : (transport as OmnixMediaSessionTransport)
                .messageStream(_id, parts, knowledge)
                .map((text) => OmnixOutputDelta(OmnixOutputKind.text, text));
      await for (final delta in updates) {
        yield delta;
      }
      if (transport is OmnixKnowledgeSessionTransport) {
        _sources = List.unmodifiable(
          await (transport as OmnixKnowledgeSessionTransport).sources(_id),
        );
      }
      completed = true;
    } catch (error, stack) {
      final admission = OmnixExecutionException.fromNative(error);
      if (admission != null) Error.throwWithStackTrace(admission, stack);
      rethrow;
    } finally {
      _busy = false;
      if (!completed) await close();
    }
  }

  Stream<String> sendStream(
    String text, {
    OmnixKnowledgeUse knowledge = OmnixKnowledgeUse.ifAvailable,
  }) async* {
    if (_closed || _busy) throw StateError('Session closed or busy.');
    if (text.trim().isEmpty) throw ArgumentError('Empty request.');
    final transport = _transport;
    if (knowledge == OmnixKnowledgeUse.required &&
        transport is! OmnixKnowledgeSessionTransport) {
      throw UnsupportedError('Transport does not support native Knowledge.');
    }
    _busy = true;
    _sources = const [];
    var completed = false;
    try {
      if (transport is OmnixKnowledgeSessionTransport) {
        final grounded = transport as OmnixKnowledgeSessionTransport;
        await for (final delta in grounded.groundedStream(
          _id,
          text,
          knowledge,
        )) {
          yield delta;
        }
        _sources = List.unmodifiable(await grounded.sources(_id));
      } else {
        await for (final delta in transport.stream(_id, text)) {
          yield delta;
        }
      }
      completed = true;
    } catch (error, stack) {
      final admission = OmnixExecutionException.fromNative(error);
      if (admission != null) Error.throwWithStackTrace(admission, stack);
      rethrow;
    } finally {
      _busy = false;
      if (!completed) await close();
    }
  }

  Future<String> send(
    String text, {
    OmnixKnowledgeUse knowledge = OmnixKnowledgeUse.ifAvailable,
  }) => sendStream(text, knowledge: knowledge).join();
  Future<T> _exclusive<T>(Future<T> Function() operation) async {
    if (_closed || _busy) {
      throw StateError('Session closed or busy.');
    }
    _busy = true;
    try {
      return await operation();
    } finally {
      _busy = false;
    }
  }

  /// Exports completed native context, including owned media when supported.
  ///
  /// Snapshots can contain private recordings and images. Version-2 media
  /// context is opaque; a host display transcript is not a replacement.
  Future<String> exportHistory() => _exclusive(() => _transport.history(_id));

  /// Restores [history] into a fresh, compatibly configured native session.
  ///
  /// Use the same model, instructions, sampling, response budget, and required
  /// input encoders. Restoration does not generate a new inference turn.
  Future<void> restoreHistory(String history, {bool? thinking}) =>
      _exclusive(() {
        final transport = _transport;
        if (thinking == null) return transport.restore(_id, history);
        if (transport is! OmnixThinkingRestorationTransport) {
          throw UnsupportedError('Thinking history transition unsupported.');
        }
        return (transport as OmnixThinkingRestorationTransport)
            .restoreSessionThinking(_id, history, thinking);
      });

  void cancelGeneration() {
    if (!_closed) _transport.cancel(_id);
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _transport.cancel(_id);
    return _closing = _transport.closeSession(_id);
  }
}
