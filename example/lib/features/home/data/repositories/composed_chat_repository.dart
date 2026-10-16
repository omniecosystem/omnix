import 'dart:convert';
import 'package:omnix_example/features/home/data/services/response_budget.dart';
import 'package:flutter/foundation.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/home/domain/agent_activity.dart';
import 'package:omnix_example/features/home/data/services/agent_extensions.dart';
import 'package:omnix_example/features/home/data/services/agent_chat_snapshot.dart';
import 'package:omnix_core/omnix_core.dart';
import 'package:omnix_storage/omnix_storage.dart';
import 'package:omnix_example/features/knowledge/presentation/controllers/knowledge_demo_controller.dart';

import 'package:omnix_example/features/home/data/repositories/chat_repository.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';

// UI compatibility only. Native inference and ownership belong to root Omnix.
// Media and configured retrieval stay inside root Rust.
class ComposedChatRepository
    implements
        PersistentCoreBackend,
        InstructionCoreBackend,
        ResponseBudgetBackend,
        GenerationSettingsBackend,
        LiveGenerationBackend,
        AgentIntentBackend,
        AgentAutonomyBackend,
        LiveAgentCoreBackend,
        MediaCoreBackend,
        PreparedCoreBackend,
        MixedInputCoreBackend {
  ComposedChatRepository(
    OmnixConversationSnapshotStore store, {
    OmnixSessionTransport? transport,
    OmnixLocalKnowledge? knowledge,
    bool? durableMedia,
    bool sharedToolAvailability = false,
    bool initialToolsEnabled = true,
    this.saveToolAvailability,
    int maxOutputTokens = homeResponseTokens,
  }) : _store = store,
       _sharedToolAvailability = sharedToolAvailability,
       _configuredOutputTokens = validateHomeResponseTokens(maxOutputTokens),
       _agentOutputTokens = validateHomeResponseTokens(maxOutputTokens) {
    _adapter = _SessionAdapter(transport, knowledge);
    _repository = NativeChatRepository(
      store,
      core: OmnixCore(transport: _adapter),
      nativeSources: () => _adapter.sources,
      durableMedia: durableMedia ?? transport == null,
      maxOutputTokens: maxOutputTokens,
    );
    if (sharedToolAvailability) {
      agentEnabled = initialToolsEnabled && agentAvailable;
      _sharedToolsEnabled = agentEnabled;
    }
  }

  late final NativeChatRepository _repository;
  final OmnixConversationSnapshotStore _store;
  final bool _sharedToolAvailability;
  final Future<void> Function(bool)? saveToolAvailability;
  bool _sharedToolsEnabled = false;
  int _configuredOutputTokens;
  int _agentOutputTokens;
  OmnixCoreSamplingOptions? _agentSampling;
  OmnixCoreSamplingOptions? _configuredSampling;
  int _agentContext = 4096;
  int _configuredContext = 4096;
  bool get _usesAgentSession =>
      agentEnabled || _agentCheckpoint != null || _agent != null;
  @override
  bool get supportsMixedInput => !_usesAgentSession
      ? _repository.supportsMixedInput
      : (_adapter.transport == null ||
            (_adapter.transport is OmnixAgentCheckpointTransport &&
                _adapter.transport is OmnixAgentMediaTransport));
  @override
  Future<void> prepare(String model) async {
    if (_usesAgentSession && _agentCheckpoint != null) {
      await _prepareAgent(model, _agentImages, _agentAudio);
    } else if (!agentEnabled && currentId != null) {
      await _repository.prepareSaved(model);
    } else {
      await _adapter.prepare(model, contextTokens);
    }
  }

  Future<void> _prepareAgent(
    String model,
    bool images,
    bool audio, {
    String? importHistory,
  }) async {
    if (_agent != null) return;
    if (_agentSaveFailed) throw StateError('Agent history could not be saved.');
    if (_agentModel != null && _agentModel != model) {
      throw StateError('Start a new chat before changing the agent model.');
    }
    try {
      if (_agentSampling != null &&
          _adapter.transport != null &&
          _adapter.transport is! OmnixSamplingAgentTransport) {
        throw UnsupportedError('Agent transport does not support sampling.');
      }
      _agentImages = images;
      _agentAudio = audio;
      if (images || audio) await _adapter.releasePreparation();
      _agentEngine = await _adapter.takePreparedEngine(model, _agentContext);
      _agent =
          _adapter.transport == null ||
              _adapter.transport is OmnixRegisteredAgentTransport
          ? await _agentEngine!.startAgent(
              modelPath: model,
              instructions: instructions,
              maxOutputTokens: _agentOutputTokens,
              sampling: _agentSampling == null
                  ? null
                  : OmnixSamplingOptions(
                      temperature: _agentSampling!.temperature,
                      topK: _agentSampling!.topK,
                      topP: _agentSampling!.topP,
                      seed: _agentSampling!.seed,
                    ),
              extensions: await exampleAgentExtensions(
                email: emailDraftsEnabled,
                knowledge: _adapter.knowledge != null,
                images: images,
                audio: audio,
                autonomy: autonomy,
              ),
            )
          : await _agentEngine!.startKnowledgeAgent(
              modelPath: model,
              instructions: instructions,
              maxOutputTokens: _agentOutputTokens,
              allowEmailDrafts: emailDraftsEnabled,
            );
      _agentModel = model;
      if (_agentCheckpoint != null) {
        await _agent!.restoreCheckpoint(_agentCheckpoint!);
      }
      if (importHistory != null) await _agent!.importChatHistory(importHistory);
      if (_adapter.transport == null ||
          _adapter.transport is OmnixAgentCapabilityTransport) {
        await _agent!.setToolsEnabled(agentEnabled);
      }
      await _adapter.releasePreparedSession();
    } catch (_) {
      final savedModel = _agentModel;
      try {
        await _releaseAgent();
      } finally {
        await _adapter.releasePreparation();
      }
      _agentModel = savedModel;
      rethrow;
    }
  }

  @override
  bool get canReconfigureLive => _usesAgentSession
      ? _agent != null && !_agentSaveFailed
      : _repository.canReconfigureLive;
  @override
  Future<void> applyGeneration(
    int tokens,
    OmnixCoreSamplingOptions? settings,
  ) async {
    if (!_usesAgentSession) {
      await _repository.applyGeneration(tokens, settings);
      return;
    }
    if (!canReconfigureLive) {
      throw StateError(
        'Prepare the saved agent chat before changing settings.',
      );
    }
    validateHomeResponseTokens(tokens);
    settings?.encode();
    if (tokens > _agentContext) {
      throw ArgumentError('Response budget exceeds context.');
    }
    OmnixSamplingOptions? convert(OmnixCoreSamplingOptions? value) =>
        value == null
        ? null
        : OmnixSamplingOptions(
            temperature: value.temperature,
            topK: value.topK,
            topP: value.topP,
            seed: value.seed,
          );
    await _agent!.reconfigure(
      maxOutputTokens: tokens,
      sampling: convert(settings),
    );
    try {
      final checkpoint = await _agent!.exportCheckpoint();
      if (_agentId != null) {
        await _store.writeSerializedSnapshot(
          AgentChatSnapshot(
            id: _agentId!,
            title: _agentTitle,
            model: _agentModel!,
            instructions: instructions,
            email: emailDraftsEnabled,
            autonomy: autonomy,
            checkpoint: checkpoint,
            entries: _agentMessages,
            maxOutputTokens: tokens,
            contextTokens: _agentContext,
            sampling: settings,
            images: _agentImages,
            audio: _agentAudio,
            toolsEnabled: agentEnabled,
          ).encode(),
        );
      }
      _agentCheckpoint = checkpoint;
    } catch (_) {
      try {
        await _agent!.reconfigure(
          maxOutputTokens: _agentOutputTokens,
          sampling: convert(_agentSampling),
        );
      } catch (_) {
        _agentSaveFailed = true;
        await _releaseAgent();
      }
      rethrow;
    }
    _agentOutputTokens = tokens;
    _agentSampling = settings;
  }

  @override
  OmnixCoreSamplingOptions? get sampling =>
      _usesAgentSession ? _agentSampling : _repository.sampling;
  @override
  int get contextTokens =>
      _usesAgentSession ? _agentContext : _repository.contextTokens;
  @override
  void configureGeneration(
    OmnixCoreSamplingOptions? sampling,
    int contextTokens,
  ) {
    if (_agent != null || messages.isNotEmpty || currentId != null) {
      throw StateError('Start a new chat before changing generation settings.');
    }
    _repository.configureGeneration(sampling, contextTokens);
    _agentSampling = _configuredSampling = sampling;
    _agentContext = _configuredContext = contextTokens;
  }

  @override
  int get maxOutputTokens =>
      _usesAgentSession ? _agentOutputTokens : _repository.maxOutputTokens;
  @override
  void configureResponseBudget(int tokens) {
    if (_agent != null || messages.isNotEmpty || currentId != null) {
      throw StateError('Start a new chat before changing response length.');
    }
    final validated = validateHomeResponseTokens(tokens);
    _repository.configureResponseBudget(validated);
    _configuredOutputTokens = validated;
    _agentOutputTokens = validated;
  }

  String? _agentId;
  String _agentTitle = '';
  String? _agentCheckpoint;
  bool _agentSaveFailed = false;
  late final _SessionAdapter _adapter;
  OmnixCognitiveEngine? _agentEngine;
  OmnixAgentSession? _agent;
  String? _agentModel;
  bool _agentImages = false;
  bool _agentAudio = false;
  List<ChatEntry> _agentMessages = [];
  bool _agentStopped = false;
  @override
  String agentText = '';
  @override
  String? agentStatus;
  List<AgentActivity> _activities = [];
  @override
  List<AgentActivity> get agentActivities => List.unmodifiable(_activities);

  void _finishActivities(AgentActivityState state) {
    _activities = [
      for (final activity in _activities)
        activity.state == AgentActivityState.running
            ? AgentActivity(activity.toolName, state)
            : activity,
    ];
  }

  @override
  bool agentEnabled = false;
  OmnixAutonomyMode _autonomy =
      const String.fromEnvironment('OMNIX_AUTONOMY') == 'reviewEveryCall'
      ? OmnixAutonomyMode.reviewEveryCall
      : OmnixAutonomyMode.scopedAssistance;
  @override
  OmnixAutonomyMode get autonomy => _autonomy;
  @override
  void configureAutonomy(OmnixAutonomyMode mode) {
    if (messages.isNotEmpty || currentId != null || _agent != null) {
      throw StateError('Start a new chat before changing autonomy.');
    }
    if (mode == OmnixAutonomyMode.delegatedScope) {
      throw ArgumentError(
        'This example exposes scoped assistance and review-every-call only.',
      );
    }
    _autonomy = mode;
  }

  @override
  bool emailDraftsEnabled = false;
  @override
  void configureEmailDrafts(bool enabled) {
    if (messages.isNotEmpty || currentId != null || _agent != null) {
      throw StateError(
        'Start a new chat before changing native intent permissions.',
      );
    }
    emailDraftsEnabled = enabled;
  }

  @override
  bool get agentAvailable =>
      _adapter.transport == null ||
      (_adapter.transport is OmnixAgentTransport &&
          _adapter.transport is OmnixRegisteredAgentTransport) ||
      (_adapter.knowledge != null && _adapter.transport is OmnixAgentTransport);
  @override
  void configureAgent(bool enabled) {
    if (messages.isNotEmpty || currentId != null || _agent != null) {
      throw StateError('Start a new chat before changing agent mode.');
    }
    if (enabled && !agentAvailable) {
      throw StateError('This transport does not support a host-tool agent.');
    }
    agentEnabled = enabled;
    if (_sharedToolAvailability) _sharedToolsEnabled = enabled;
  }

  @override
  bool get canSwitchAgent =>
      !_agentSaveFailed &&
      agentAvailable &&
      (_adapter.transport == null ||
          _adapter.transport is OmnixAgentCapabilityTransport &&
              _adapter.transport is OmnixAgentCheckpointTransport &&
              _adapter.transport is OmnixRegisteredAgentTransport);

  AgentChatSnapshot _snapshotForMode(String checkpoint, bool enabled) =>
      AgentChatSnapshot(
        id: _agentId!,
        title: _agentTitle,
        model: _agentModel!,
        instructions: instructions,
        email: emailDraftsEnabled,
        autonomy: autonomy,
        checkpoint: checkpoint,
        entries: _agentMessages,
        maxOutputTokens: _agentOutputTokens,
        sampling: _agentSampling,
        contextTokens: _agentContext,
        images: _agentImages,
        audio: _agentAudio,
        toolsEnabled: enabled,
      );

  @override
  Future<void> switchAgent(bool enabled, String model) async {
    final previous = agentEnabled;
    final previousShared = _sharedToolsEnabled;
    await _switchConversationTools(enabled, model);
    if (_sharedToolAvailability && previousShared != enabled) {
      try {
        await saveToolAvailability?.call(enabled);
      } catch (_) {
        try {
          await _switchConversationTools(previous, model);
        } finally {
          _sharedToolsEnabled = previousShared;
        }
        rethrow;
      }
      _sharedToolsEnabled = enabled;
    }
  }

  Future<void> _switchConversationTools(bool enabled, String model) async {
    if (!canSwitchAgent) throw StateError('Capability changes unavailable.');
    if (enabled == agentEnabled) return;
    if (!_usesAgentSession) {
      final id = _repository.currentId;
      if (id == null) {
        configureAgent(enabled);
        return;
      }
      final saved = await _store.readSerializedSnapshot(id);
      if (saved == null) throw StateError('Saved chat not found.');
      final value = jsonDecode(saved) as Map<String, dynamic>;
      final record = value['record'] as Map<String, dynamic>;
      if (record['modelPath'] != model) {
        throw StateError('Chat model mismatch.');
      }
      final history = await _repository.exportForAgent();
      final entries = List<ChatEntry>.of(_repository.messages);
      final oldTokens = _repository.maxOutputTokens;
      final oldSampling = _repository.sampling;
      final oldContext = _repository.contextTokens;
      await _repository.releaseForTransition();
      try {
        _agentId = id;
        _agentTitle = record['title'] as String;
        _agentMessages = entries;
        _agentOutputTokens = oldTokens;
        _agentSampling = oldSampling;
        _agentContext = oldContext;
        _agentImages = record['images'] as bool? ?? false;
        _agentAudio = record['audio'] as bool? ?? false;
        agentEnabled = enabled;
        await _prepareAgent(
          model,
          _agentImages,
          _agentAudio,
          importHistory: history,
        );
        final checkpoint = await _agent!.exportCheckpoint();
        await _store.writeSerializedSnapshot(
          _snapshotForMode(checkpoint, enabled).encode(),
        );
        _agentCheckpoint = checkpoint;
      } catch (_) {
        await _releaseAgent();
        agentEnabled = false;
        _agentCheckpoint = null;
        _agentId = null;
        _agentMessages = [];
        await _repository.select(id);
        rethrow;
      }
      return;
    }
    await _prepareAgent(model, _agentImages, _agentAudio);
    final previous = agentEnabled;
    await _agent!.setToolsEnabled(enabled);
    try {
      final checkpoint = await _agent!.exportCheckpoint();
      if (_agentId != null) {
        await _store.writeSerializedSnapshot(
          _snapshotForMode(checkpoint, enabled).encode(),
        );
      }
      _agentCheckpoint = checkpoint;
      agentEnabled = enabled;
    } catch (_) {
      try {
        await _agent!.setToolsEnabled(previous);
      } catch (_) {
        _agentSaveFailed = true;
        await _releaseAgent();
      }
      rethrow;
    }
  }

  Future<void> _releaseAgent() async {
    final agent = _agent;
    final engine = _agentEngine;
    _agent = null;
    _agentEngine = null;
    _agentModel = null;
    try {
      await cancelExampleDeviceTools();
    } finally {
      try {
        await agent?.close();
      } finally {
        await engine?.close();
      }
    }
  }

  void configureKnowledge(OmnixLocalKnowledge? knowledge) {
    if (_agentEngine != null ||
        _adapter._models.isNotEmpty ||
        _adapter._sessions.isNotEmpty) {
      throw StateError('Start a new chat before changing Knowledge ownership.');
    }
    _adapter.knowledge = knowledge;
    _adapter.sources = const [];
    if (knowledge == null && !_sharedToolAvailability) agentEnabled = false;
  }

  // Forward a host pressure signal; Rust decides whether an encoder is idle.
  Future<void> releaseIdleResources() async {
    final engines = <OmnixCognitiveEngine>{
      ?_agentEngine,
      ?_adapter._preparedEngine,
      ..._adapter._models.values.map((model) => model.engine),
    };
    for (final engine in engines) {
      final report = await engine.releaseIdleResources();
      debugPrint(
        '[Omnix][resources] knowledge=${report.knowledge.name} retainedChatModels=${report.retainedChatModels}',
      );
    }
  }

  // A host-level reference to the root engine, not a second inference scheduler.
  OmnixCognitiveEngine? knowledgeEngineFor(OmnixLocalKnowledge config) {
    final current = _adapter.knowledge;
    if (current == null ||
        current.embeddingModel != config.embeddingModel ||
        current.storePath != config.storePath ||
        current.publicOnly != config.publicOnly ||
        current.topK != config.topK ||
        current.threshold != config.threshold) {
      return null;
    }
    return _agentEngine ??
        (_adapter._models.isNotEmpty
            ? _adapter._models.values.first.engine
            : identical(_adapter._preparedKnowledge, current)
            ? _adapter._preparedEngine
            : null);
  }

  @override
  String? get currentId => _usesAgentSession ? _agentId : _repository.currentId;
  @override
  List<ChatEntry> get messages =>
      _usesAgentSession ? _agentMessages : _repository.messages;
  @override
  String get instructions => _repository.instructions;
  @override
  void configureInstructions(String value) =>
      _repository.configureInstructions(value);
  @override
  Future<List<ChatRecord>> records() => _repository.records();
  @override
  Future<void> select(String? id) async {
    final sharedTools = _sharedToolsEnabled;
    final saved = id == null ? null : await _store.readSerializedSnapshot(id);
    final isAgent =
        saved != null &&
        (jsonDecode(saved) as Map<String, dynamic>)['record']['kind'] ==
            'agent';
    // Parse before releasing the current chat. A corrupt record cannot replace it.
    final snapshot = isAgent ? AgentChatSnapshot.decode(saved) : null;
    if (snapshot != null && snapshot.id != id) {
      throw const FormatException('Agent conversation ID mismatch.');
    }
    await _releaseAgent();
    _agentMessages = [];
    _agentId = null;
    _agentTitle = '';
    _agentCheckpoint = null;
    _agentImages = false;
    _agentAudio = false;
    _agentSaveFailed = false;
    _agentOutputTokens = _configuredOutputTokens;
    _agentSampling = _configuredSampling;
    _agentContext = _configuredContext;
    agentText = '';
    agentStatus = null;
    _activities = [];
    if (snapshot != null) {
      await _repository.select(null);
      _repository.configureInstructions(snapshot.instructions);
      // A checkpoint describes past runtime state, not current host access.
      agentEnabled = _sharedToolAvailability
          ? sharedTools
          : snapshot.toolsEnabled;
      emailDraftsEnabled = snapshot.email;
      _autonomy = snapshot.autonomy;
      _agentMessages = snapshot.entries;
      _agentId = snapshot.id;
      _agentTitle = snapshot.title;
      _agentModel = snapshot.model;
      _agentCheckpoint = snapshot.checkpoint;
      _agentOutputTokens = snapshot.maxOutputTokens;
      _agentSampling = snapshot.sampling;
      _agentContext = snapshot.contextTokens;
      _agentImages = snapshot.images;
      _agentAudio = snapshot.audio;
      return;
    }
    if (id != null) agentEnabled = false;
    emailDraftsEnabled = false;
    await _repository.select(id);
    if (_sharedToolAvailability) {
      if (id != null && sharedTools) {
        final record =
            (jsonDecode(saved!) as Map<String, dynamic>)['record']
                as Map<String, dynamic>;
        await _switchConversationTools(true, record['modelPath'] as String);
      } else {
        agentEnabled = sharedTools;
      }
    }
  }

  @override
  Stream<String> generate(String model, String prompt) => _usesAgentSession
      ? _generateAgent(model, prompt)
      : _repository.generate(model, prompt);
  @override
  Stream<String> generateMessage(
    String model,
    String prompt,
    List<ChatAttachment> attachments,
  ) => _usesAgentSession
      ? _generateAgent(model, prompt, attachments: attachments)
      : _repository.generateMessage(model, prompt, attachments);
  Stream<String> _generateAgent(
    String model,
    String prompt, {
    List<ChatAttachment> attachments = const [],
  }) async* {
    if (_agentSaveFailed) {
      throw StateError(
        'Agent history could not be saved. Start a new chat before running more tools.',
      );
    }
    _agentStopped = false;
    _activities = [];
    if (_agentModel != null && _agentModel != model) {
      throw StateError('Start a new chat before changing the agent model.');
    }
    final images = attachments.any((a) => a.part.kind == OmnixInputKind.image);
    final audio = attachments.any((a) => a.part.kind == OmnixInputKind.audio);
    final desiredImages = images || _agentImages;
    final desiredAudio = audio || _agentAudio;
    var completed = false;
    try {
      if (_agent != null &&
          ((images && !_agentImages) || (audio && !_agentAudio))) {
        if (!supportsMixedInput) {
          throw StateError(
            'This transport cannot preserve mixed-input context.',
          );
        }
        // Completed context only: restoration never dispatches historical tools.
        _agentCheckpoint = await _agent!.exportCheckpoint();
        await _releaseAgent();
      }
      await _prepareAgent(model, desiredImages, desiredAudio);
      if (_agentStopped) return;
      OmnixAgentReply? reply;
      agentText = '';
      agentStatus = 'Thinking';
      final parts = attachments.isEmpty
          ? null
          : [
              if (prompt.isNotEmpty) OmnixInteractionInput.text(prompt),
              for (final attachment in attachments) _rootPart(attachment.part),
            ];
      await for (final event in _agent!.sendEvents(prompt, parts: parts)) {
        if (_agentStopped) return;
        if (event.kind == OmnixAgentEventKind.turnStarted) {
          agentText = '';
          agentStatus = 'Thinking';
        }
        if (event.kind == OmnixAgentEventKind.text) {
          if (!_activities.any(
            (a) => a.toolName == 'host_prepare_calendar_event',
          )) {
            agentText += event.text!;
          }
        }
        if (event.kind == OmnixAgentEventKind.toolStarted) {
          _activities.add(
            AgentActivity(event.toolName!, AgentActivityState.running),
          );
          agentText = '';
          agentStatus = 'Running ${event.toolName}';
        }
        if (event.kind == OmnixAgentEventKind.toolFinished) {
          if (kDebugMode && event.toolFailed) {
            // Do not log arguments, host results, or appointment content.
            debugPrint(
              '[Omnix][tool] ${event.toolName}: ${event.outcome?.status ?? "failed"}',
            );
            // This example's calendar validation reasons contain field/rule names only.
            // Other developer-supplied tools may include sensitive text in their reasons.
            if (event.toolName == 'host_prepare_calendar_event' &&
                event.outcome?.status == 'invalid_arguments') {
              debugPrint(
                '[Omnix][calendar-validation] ${event.outcome?.reason}',
              );
            }
            // This example's proposal adapter exposes only generated field/rule
            // feedback or a fixed service-unavailable message, never raw errors.
            if (event.toolName == 'host_propose_event_task' &&
                (event.outcome?.status == 'invalid_arguments' ||
                    event.outcome?.status == 'unavailable')) {
              debugPrint('[Omnix][task-proposal] ${event.outcome?.reason}');
            }
            // This no-argument example tool can only fail schema validation
            // before its Android callback; the generated reason contains no
            // supplied values. Do not apply this logging to arbitrary tools.
            if (event.toolName == 'host_battery_status' &&
                event.outcome?.status == 'invalid_arguments') {
              debugPrint(
                '[Omnix][battery-validation] ${event.outcome?.reason}',
              );
            }
          }
          // Current Rust execution is sequential. Do not infer parallel call IDs.
          final index = _activities.indexWhere(
            (activity) =>
                activity.toolName == event.toolName &&
                activity.state == AgentActivityState.running,
          );
          if (index >= 0) {
            _activities[index] = AgentActivity(
              event.toolName!,
              event.toolFailed
                  ? AgentActivityState.failed
                  : AgentActivityState.completed,
              outcomeStatus: event.outcome?.status,
              reason: event.outcome?.reason,
            );
          }
          agentStatus = 'Preparing answer';
        }
        if (event.kind == OmnixAgentEventKind.cancelled) {
          _finishActivities(AgentActivityState.cancelled);
          return;
        }
        if (event.kind == OmnixAgentEventKind.completed) {
          reply = event.reply;
          agentText = _verifiedAnswer(reply!);
          agentStatus = null;
        }
        yield event.kind == OmnixAgentEventKind.text &&
                _activities.any(
                  (a) => a.toolName == 'host_prepare_calendar_event',
                )
            ? ''
            : event.text ?? '';
      }
      if (_agentStopped) return;
      if (reply == null) throw StateError('Agent turn did not complete.');
      final sources = [
        for (final source in reply.sources)
          KnowledgePassage(source.title, source.content, null),
      ];
      final entries = <ChatEntry>[
        ..._agentMessages,
        ChatEntry('user', prompt, List.unmodifiable(attachments)),
        ChatEntry(
          'assistant',
          _verifiedAnswer(reply),
          const [],
          sources,
          agentActivities,
          reply.intents,
        ),
      ];
      // Legacy/custom transports may be intentionally ephemeral.
      if ((_adapter.transport == null ||
          _adapter.transport is OmnixAgentCheckpointTransport)) {
        try {
          final checkpoint = await _agent!.exportCheckpoint();
          final id =
              _agentId ?? 'agent-${DateTime.now().microsecondsSinceEpoch}';
          final title = _agentTitle.isEmpty
              ? (prompt.length > 60 ? '${prompt.substring(0, 60)}…' : prompt)
              : _agentTitle;
          await _store.writeSerializedSnapshot(
            AgentChatSnapshot(
              id: id,
              title: title,
              model: model,
              instructions: instructions,
              email: emailDraftsEnabled,
              autonomy: autonomy,
              checkpoint: checkpoint,
              maxOutputTokens: _agentOutputTokens,
              sampling: _agentSampling,
              contextTokens: _agentContext,
              images: _agentImages,
              audio: _agentAudio,
              toolsEnabled: agentEnabled,
              entries: entries,
            ).encode(),
          );
          _agentId = id;
          _agentTitle = title;
          _agentCheckpoint = checkpoint;
        } catch (_) {
          _agentSaveFailed = true;
          throw StateError(
            'The agent turn completed, but its history could not be saved. Tools may already have run. Start a new chat; do not blindly repeat the action.',
          );
        }
      }
      _agentMessages = entries;
      completed = true;
      _activities = [];
    } catch (_) {
      _finishActivities(
        _agentStopped
            ? AgentActivityState.cancelled
            : AgentActivityState.failed,
      );
      rethrow;
    } finally {
      agentStatus = null;
      if (!completed) {
        _finishActivities(AgentActivityState.cancelled);
        agentText = '';
        await _releaseAgent();
      }
    }
  }

  String _verifiedAnswer(OmnixAgentReply reply) {
    const calendar = 'host_prepare_calendar_event';
    if (!_activities.any((a) => a.toolName == calendar)) return reply.text;
    final outcomes = reply.toolOutcomes
        .where((o) => o.toolName == calendar)
        .toList();
    final status = outcomes.isEmpty ? null : outcomes.last.status;
    final reason = outcomes.isEmpty ? null : outcomes.last.reason;
    final summary = status == 'editor_opened'
        ? 'The calendar editor opened. Review and save there yourself; saving is not confirmed.'
        : 'No successful calendar handoff was confirmed (${status ?? 'unverified'}). '
              'The event was not confirmed as saved.';
    return reason == null || reason.isEmpty ? summary : '$summary\n$reason';
  }

  @override
  Future<void> stop() async {
    _agentStopped = true;
    _agent?.cancelGeneration();
    try {
      await cancelExampleDeviceTools();
    } finally {
      await _repository.stop();
    }
  }

  @override
  Future<void> close() async {
    try {
      await _releaseAgent();
    } finally {
      try {
        await _repository.close();
      } finally {
        await _adapter.releasePreparation();
      }
    }
  }
}

class _SessionAdapter
    implements
        OmnixCoreStreamingTransport,
        OmnixCoreRoutedTransport,
        OmnixCoreHistoryTransport,
        OmnixCoreSamplingTransport,
        OmnixCoreReconfigurationTransport,
        OmnixCoreMediaTransport {
  _SessionAdapter(this.transport, this.knowledge);
  final OmnixSessionTransport? transport;
  OmnixLocalKnowledge? knowledge;
  OmnixExecutionOptions? get execution => transport == null
      ? const OmnixExecutionOptions(maxWaiting: 2, wait: Duration(seconds: 30))
      : null;
  List<KnowledgePassage> sources = const [];
  final _models =
      <
        BigInt,
        ({OmnixCognitiveEngine engine, String path, bool images, bool audio})
      >{};
  final _sessions = <BigInt, OmnixInteractionSession>{};
  var _next = BigInt.zero;
  OmnixCognitiveEngine? _preparedEngine;
  OmnixInteractionSession? _preparedSession;
  String? _preparedPath;
  int? _preparedContext;
  OmnixLocalKnowledge? _preparedKnowledge;

  Future<void> releasePreparedSession() async {
    final session = _preparedSession;
    _preparedSession = null;
    await session?.close();
  }

  Future<void> releasePreparation() async {
    final engine = _preparedEngine;
    _preparedEngine = null;
    _preparedPath = null;
    _preparedContext = null;
    try {
      await releasePreparedSession();
    } finally {
      await engine?.close();
    }
  }

  Future<void> prepare(String model, int context) async {
    if (_preparedEngine != null &&
        _preparedPath == model &&
        _preparedContext == context &&
        identical(_preparedKnowledge, knowledge)) {
      return;
    }
    await releasePreparation();
    final engine = await OmnixCognitiveEngine.open(
      runtimes: ['litertlm'],
      contextTokens: context,
      transport: transport,
      knowledge: knowledge,
      execution: execution,
    );
    try {
      // An empty native session retains the Rust model lease. Never send a
      // dummy turn: preparation cannot invoke tools or append chat history.
      _preparedSession = await engine.startSession(
        modelPath: model,
        maxOutputTokens: 1,
      );
      _preparedEngine = engine;
      _preparedPath = model;
      _preparedContext = context;
      _preparedKnowledge = knowledge;
    } catch (_) {
      await engine.close();
      rethrow;
    }
  }

  Future<OmnixCognitiveEngine> takePreparedEngine(
    String model,
    int context,
  ) async {
    if (_preparedEngine != null &&
        _preparedPath == model &&
        _preparedContext == context &&
        identical(_preparedKnowledge, knowledge)) {
      final engine = _preparedEngine!;
      _preparedEngine = null;
      return engine;
    }
    await releasePreparation();
    return OmnixCognitiveEngine.open(
      runtimes: ['litertlm'],
      contextTokens: context,
      transport: transport,
      knowledge: knowledge,
      execution: execution,
    );
  }

  @override
  Future<List<String>> supportedPlatforms() async => ['windows', 'android'];
  @override
  Future<BigInt> loadTrustedModel(
    String libraryPath,
    String modelPath,
    int contextTokens,
  ) => loadRoutedModel(modelPath, libraryPath, contextTokens);
  @override
  Future<BigInt> loadRoutedModel(
    String modelPath,
    String? libraryPath,
    int contextTokens,
  ) => loadMediaModel(modelPath, libraryPath, contextTokens, false, false);
  @override
  Future<BigInt> loadMediaModel(
    String modelPath,
    String? libraryPath,
    int contextTokens,
    bool images,
    bool audio,
  ) async {
    // This qualification build explicitly bundles LiteRT-LM only. Header-based
    // model validation remains native; unsupported containers fail there.
    if (images || audio) await releasePreparation();
    final engine = libraryPath == null
        ? await takePreparedEngine(modelPath, contextTokens)
        : await OmnixCognitiveEngine.open(
            runtimes: ['litertlm'],
            libraryPath: libraryPath,
            contextTokens: contextTokens,
            transport: transport,
            knowledge: knowledge,
            execution: execution,
          );
    final id = _next += BigInt.one;
    _models[id] = (
      engine: engine,
      path: modelPath,
      images: images,
      audio: audio,
    );
    return id;
  }

  @override
  Future<BigInt> startConversation(
    BigInt modelId,
    String? systemPrompt,
    int maxOutputTokens,
  ) async {
    final model = _models[modelId];
    if (model == null) throw StateError('Unknown root model lease.');
    final session = await model.engine.startSession(
      modelPath: model.path,
      instructions: systemPrompt,
      maxOutputTokens: maxOutputTokens,
      enableImages: model.images,
      enableAudio: model.audio,
    );
    final id = _next += BigInt.one;
    _sessions[id] = session;
    await releasePreparedSession();
    return id;
  }

  @override
  Future<BigInt> startSampledConversation(
    BigInt modelId,
    String? systemPrompt,
    int maxOutputTokens,
    String samplingJson,
  ) async {
    final model = _models[modelId];
    if (model == null) throw StateError('Unknown root model lease.');
    final options = OmnixCoreSamplingOptions.fromJson(
      jsonDecode(samplingJson) as Map<String, dynamic>,
    );
    final session = await model.engine.startSession(
      modelPath: model.path,
      instructions: systemPrompt,
      maxOutputTokens: maxOutputTokens,
      enableImages: model.images,
      enableAudio: model.audio,
      sampling: OmnixSamplingOptions(
        temperature: options.temperature,
        topK: options.topK,
        topP: options.topP,
        seed: options.seed,
      ),
    );
    final id = _next += BigInt.one;
    _sessions[id] = session;
    await releasePreparedSession();
    return id;
  }

  OmnixInteractionSession _session(BigInt id) =>
      _sessions[id] ?? (throw StateError('Unknown root session.'));
  @override
  Future<void> reconfigureConversation(
    BigInt id,
    int tokens,
    String? samplingJson,
  ) {
    final settings = samplingJson == null
        ? null
        : OmnixCoreSamplingOptions.fromJson(
            jsonDecode(samplingJson) as Map<String, dynamic>,
          );
    return _session(id).reconfigure(
      maxOutputTokens: tokens,
      sampling: settings == null
          ? null
          : OmnixSamplingOptions(
              temperature: settings.temperature,
              topK: settings.topK,
              topP: settings.topP,
              seed: settings.seed,
            ),
    );
  }

  @override
  Stream<String> sendStream(BigInt conversationId, String text) async* {
    sources = const [];
    final session = _session(conversationId);
    yield* session.sendStream(text);
    sources = [
      for (final source in session.sources)
        KnowledgePassage(source.title, source.content, null),
    ];
  }

  @override
  Stream<String> sendMessageStream(
    BigInt conversationId,
    List<OmnixInputPart> parts,
  ) async* {
    sources = const [];
    final session = _session(conversationId);
    yield* session.sendMessageStream(parts.map(_rootPart).toList());
    sources = [
      for (final source in session.sources)
        KnowledgePassage(source.title, source.content, null),
    ];
  }

  @override
  Future<String> sendMessage(
    BigInt conversationId,
    List<OmnixInputPart> parts,
  ) => sendMessageStream(conversationId, parts).join();

  @override
  Future<String> send(BigInt conversationId, String text) =>
      _session(conversationId).send(text);
  @override
  Future<void> cancelGeneration(BigInt conversationId) async =>
      _session(conversationId).cancelGeneration();
  @override
  Future<String> conversationHistory(
    BigInt conversationId,
    String? snapshot,
  ) async {
    final session = _session(conversationId);
    if (snapshot != null) await session.restoreHistory(snapshot);
    return session.exportHistory();
  }

  @override
  Future<void> closeConversation(BigInt conversationId) async =>
      _sessions.remove(conversationId)?.close();
  @override
  Future<void> closeModel(BigInt modelId) async {
    try {
      await releasePreparedSession();
    } finally {
      await _models.remove(modelId)?.engine.close();
    }
  }
}

OmnixInteractionInput _rootPart(OmnixInputPart part) => switch (part.kind) {
  OmnixInputKind.text => OmnixInteractionInput.text(part.text!),
  OmnixInputKind.image => OmnixInteractionInput.image(part.bytes),
  OmnixInputKind.audio => OmnixInteractionInput.audio(part.bytes),
};
