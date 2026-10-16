import 'package:flutter/foundation.dart';
import 'package:omnix_example/features/home/domain/agent_activity.dart';
import 'package:omnix_core/omnix_core.dart';
import 'package:omnix/omnix.dart' show OmnixEmailIntent, OmnixAutonomyMode;
import 'package:omnix_example/features/knowledge/presentation/controllers/knowledge_demo_controller.dart';

abstract interface class GroundedCoreBackend implements CoreDemoBackend {
  bool get hasGrounding;
  Stream<String> generateGrounded(
    String model,
    String question,
    List<KnowledgePassage> sources,
  );
}

class ChatAttachment {
  const ChatAttachment(this.name, this.part);
  final String name;
  final OmnixInputPart part;
}

abstract interface class MediaCoreBackend implements CoreDemoBackend {
  Stream<String> generateMessage(
    String model,
    String prompt,
    List<ChatAttachment> attachments,
  );
}

abstract interface class CoreDemoBackend {
  Stream<String> generate(String model, String prompt);
  Future<void> stop();
  Future<void> close();
}

abstract interface class PreparedCoreBackend implements CoreDemoBackend {
  Future<void> prepare(String model);
}

abstract interface class MixedInputCoreBackend implements MediaCoreBackend {
  bool get supportsMixedInput;
}

enum ChatReadiness { idle, preparing, ready, failed }

abstract interface class AgentCoreBackend implements CoreDemoBackend {
  bool get agentEnabled;
  bool get agentAvailable;
  void configureAgent(bool enabled);
}

abstract interface class LiveAgentCoreBackend implements AgentCoreBackend {
  bool get canSwitchAgent;
  Future<void> switchAgent(bool enabled, String model);
}

abstract interface class AgentProgressBackend implements AgentCoreBackend {
  String get agentText;
  String? get agentStatus;
}

abstract interface class AgentAutonomyBackend implements AgentCoreBackend {
  OmnixAutonomyMode get autonomy;
  void configureAutonomy(OmnixAutonomyMode mode);
}

abstract interface class AgentTimelineBackend implements AgentProgressBackend {
  List<AgentActivity> get agentActivities;
}

abstract interface class AgentIntentBackend implements AgentTimelineBackend {
  bool get emailDraftsEnabled;
  void configureEmailDrafts(bool enabled);
}

abstract interface class InstructionCoreBackend implements CoreDemoBackend {
  String get instructions;
  void configureInstructions(String value);
}

abstract interface class ResponseBudgetBackend implements CoreDemoBackend {
  int get maxOutputTokens;
  void configureResponseBudget(int tokens);
}

abstract interface class GenerationSettingsBackend implements CoreDemoBackend {
  OmnixCoreSamplingOptions? get sampling;
  int get contextTokens;
  void configureGeneration(
    OmnixCoreSamplingOptions? sampling,
    int contextTokens,
  );
}

abstract interface class LiveGenerationBackend
    implements GenerationSettingsBackend {
  bool get canReconfigureLive;
  Future<void> applyGeneration(int tokens, OmnixCoreSamplingOptions? sampling);
}

class ChatEntry {
  const ChatEntry(
    this.role,
    this.text, [
    this.attachments = const [],
    this.sources = const [],
    this.activities = const [],
    this.intents = const [],
  ]);
  final String role;
  final String text;
  final List<ChatAttachment> attachments;
  final List<KnowledgePassage> sources;
  final List<AgentActivity> activities;
  final List<OmnixEmailIntent> intents;
}

class ChatRecord {
  const ChatRecord(this.id, this.title, this.model);
  final String id;
  final String title;
  final String model;
}

abstract interface class PersistentCoreBackend implements CoreDemoBackend {
  String? get currentId;
  List<ChatEntry> get messages;
  Future<List<ChatRecord>> records();
  Future<void> select(String? id);
}

class CoreController extends ChangeNotifier {
  CoreController(this.backend, {this.knowledge});
  final CoreDemoBackend backend;
  final KnowledgeDemoController? knowledge;
  bool get canApplyLiveSettings =>
      !busy &&
      !_disposed &&
      backend is LiveGenerationBackend &&
      (backend as LiveGenerationBackend).canReconfigureLive &&
      (messages.isNotEmpty || selectedId != null);
  Future<void> applyGeneration(
    int tokens,
    OmnixCoreSamplingOptions? settings,
  ) async {
    if (!canApplyLiveSettings) return;
    busy = true;
    notifyListeners();
    try {
      await (backend as LiveGenerationBackend).applyGeneration(
        tokens,
        settings,
      );
      error = null;
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  bool get supportsGenerationSettings => backend is GenerationSettingsBackend;
  OmnixCoreSamplingOptions? get sampling => backend is GenerationSettingsBackend
      ? (backend as GenerationSettingsBackend).sampling
      : null;
  int get contextTokens => backend is GenerationSettingsBackend
      ? (backend as GenerationSettingsBackend).contextTokens
      : 4096;
  void configureGeneration(
    OmnixCoreSamplingOptions? sampling,
    int contextTokens,
  ) {
    if (!canConfigureResponseBudget || !supportsGenerationSettings) return;
    try {
      (backend as GenerationSettingsBackend).configureGeneration(
        sampling,
        contextTokens,
      );
      error = null;
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  bool get supportsResponseBudget => backend is ResponseBudgetBackend;
  int get maxOutputTokens => backend is ResponseBudgetBackend
      ? (backend as ResponseBudgetBackend).maxOutputTokens
      : 1024;
  bool get canConfigureResponseBudget =>
      supportsResponseBudget &&
      !busy &&
      !_disposed &&
      messages.isEmpty &&
      selectedId == null;
  void configureResponseBudget(int tokens) {
    if (!canConfigureResponseBudget) return;
    try {
      (backend as ResponseBudgetBackend).configureResponseBudget(tokens);
      error = null;
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  bool useKnowledge = false;
  bool _stopped = false;
  bool get supportsAgent => backend is AgentCoreBackend;
  bool get supportsAutonomy => backend is AgentAutonomyBackend;
  OmnixAutonomyMode get autonomy => backend is AgentAutonomyBackend
      ? (backend as AgentAutonomyBackend).autonomy
      : OmnixAutonomyMode.scopedAssistance;
  void configureAutonomy(OmnixAutonomyMode mode) {
    if (busy ||
        _disposed ||
        messages.isNotEmpty ||
        selectedId != null ||
        backend is! AgentAutonomyBackend) {
      return;
    }
    try {
      (backend as AgentAutonomyBackend).configureAutonomy(mode);
      error = null;
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  bool get agentEnabled =>
      backend is AgentCoreBackend && (backend as AgentCoreBackend).agentEnabled;
  bool get agentAvailable =>
      backend is AgentCoreBackend &&
      (backend as AgentCoreBackend).agentAvailable;
  String? get agentStatus => agentEnabled && backend is AgentProgressBackend
      ? (backend as AgentProgressBackend).agentStatus
      : null;
  List<AgentActivity> get agentActivities =>
      agentEnabled && backend is AgentTimelineBackend
      ? (backend as AgentTimelineBackend).agentActivities
      : const [];
  bool get supportsEmailDrafts => backend is AgentIntentBackend;
  bool get emailDraftsEnabled =>
      backend is AgentIntentBackend &&
      (backend as AgentIntentBackend).emailDraftsEnabled;
  void configureEmailDrafts(bool enabled) {
    if (busy ||
        _disposed ||
        messages.isNotEmpty ||
        selectedId != null ||
        backend is! AgentIntentBackend) {
      return;
    }
    try {
      (backend as AgentIntentBackend).configureEmailDrafts(enabled);
      error = null;
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  void configureAgent(bool enabled) {
    if (busy ||
        _disposed ||
        messages.isNotEmpty ||
        selectedId != null ||
        backend is! AgentCoreBackend) {
      return;
    }
    try {
      (backend as AgentCoreBackend).configureAgent(enabled);
      error = null;
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  bool get canSwitchAgent =>
      !busy &&
      !_disposed &&
      (messages.isEmpty && selectedId == null ||
          backend is LiveAgentCoreBackend &&
              (backend as LiveAgentCoreBackend).canSwitchAgent);

  Future<void> switchAgent(bool enabled) {
    if (!canSwitchAgent) return Future.value();
    if (messages.isEmpty &&
        selectedId == null &&
        backend is! LiveAgentCoreBackend) {
      configureAgent(enabled);
      return Future.value();
    }
    busy = true;
    notifyListeners();
    return _pending = _switchAgent(enabled);
  }

  Future<void> _switchAgent(bool enabled) async {
    try {
      await (backend as LiveAgentCoreBackend).switchAgent(enabled, modelPath);
      final persistent = backend;
      if (persistent is PersistentCoreBackend) {
        selectedId = persistent.currentId;
        messages = List.of(persistent.messages);
      }
      error = null;
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  bool get supportsKnowledge =>
      knowledge != null && backend is GroundedCoreBackend;
  void configureKnowledge(bool enabled) {
    if (busy ||
        _disposed ||
        messages.isNotEmpty ||
        selectedId != null ||
        !supportsKnowledge) {
      return;
    }
    useKnowledge = enabled;
    notifyListeners();
  }

  String answer = '';
  List<ChatEntry> messages = [];
  List<ChatRecord> history = [];
  String? selectedId;
  String? selectedModel;
  String modelPath = '';
  ChatReadiness readiness = ChatReadiness.idle;

  Future<void> prepare() {
    if (busy || _disposed || modelPath.isEmpty) return Future.value();
    busy = true;
    readiness = ChatReadiness.preparing;
    notifyListeners();
    return _pending = _prepare();
  }

  Future<void> _prepare() async {
    try {
      final target = backend;
      if (target is PreparedCoreBackend) await target.prepare(modelPath);
      readiness = ChatReadiness.ready;
      error = null;
    } catch (e) {
      readiness = ChatReadiness.failed;
      error = 'Could not prepare the model: $e';
    } finally {
      busy = sending;
      if (!_disposed) notifyListeners();
    }
  }

  String instructions = '';
  bool get supportsInstructions => backend is InstructionCoreBackend;
  String? error;
  bool busy = false;
  bool sending = false;
  bool get canCompose =>
      !busy || (readiness == ChatReadiness.preparing && !sending);
  bool temporaryMediaChat = false;
  bool get supportsAttachments => backend is MediaCoreBackend;
  bool get supportsMixedInput =>
      backend is MixedInputCoreBackend &&
      (backend as MixedInputCoreBackend).supportsMixedInput;
  bool get canAddAttachments =>
      supportsAttachments &&
      (messages.isEmpty || temporaryMediaChat || supportsMixedInput);
  bool _disposed = false;
  Future<void>? _pending;

  void configureModel(String path) {
    if (busy || _disposed || messages.isNotEmpty) return;
    modelPath = path.trim();
    readiness = ChatReadiness.idle;
    notifyListeners();
  }

  void configureInstructions(String value) {
    if (busy || _disposed || messages.isNotEmpty || selectedId != null) return;
    final configurable = backend;
    if (configurable is! InstructionCoreBackend) return;
    try {
      configurable.configureInstructions(value);
      instructions = configurable.instructions;
      error = null;
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  Future<void> initialize() {
    busy = true;
    return _pending = _initialize();
  }

  Future<void> _initialize() async {
    await _refresh();
    busy = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> _refresh() async {
    final persistent = backend;
    if (persistent is! PersistentCoreBackend) return;
    try {
      history = await persistent.records();
    } catch (e) {
      error = 'Could not read saved chats: $e';
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> select(ChatRecord? record) {
    if (busy || _disposed) return Future.value();
    busy = true;
    notifyListeners();
    return _pending = _select(record);
  }

  Future<void> _select(ChatRecord? record) async {
    try {
      final persistent = backend;
      if (persistent is PersistentCoreBackend) {
        await persistent.select(record?.id);
        messages = List.of(persistent.messages);
      } else {
        messages = [];
      }
      selectedId = record?.id;
      final configurable = backend;
      instructions = configurable is InstructionCoreBackend
          ? configurable.instructions
          : '';
      selectedModel = record?.model;
      if (record != null) modelPath = record.model;
      answer = '';
      error = null;
      readiness = ChatReadiness.idle;
      temporaryMediaChat = false;
      useKnowledge =
          backend is GroundedCoreBackend &&
          (backend as GroundedCoreBackend).hasGrounding;
      if (record != null && backend is PreparedCoreBackend) {
        readiness = ChatReadiness.preparing;
        notifyListeners();
        await (backend as PreparedCoreBackend).prepare(modelPath);
        readiness = ChatReadiness.ready;
      }
    } catch (e) {
      readiness = ChatReadiness.failed;
      error = e.toString();
    } finally {
      busy = sending;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> send(
    String model,
    String prompt, {
    List<ChatAttachment> attachments = const [],
  }) {
    if (!canCompose ||
        _disposed ||
        model.trim().isEmpty ||
        (prompt.trim().isEmpty && attachments.isEmpty)) {
      return Future.value();
    }
    if (attachments.isNotEmpty && !canAddAttachments) {
      error = supportsAttachments
          ? 'Start a new chat before adding images or audio.'
          : 'This backend does not support attachments.';
      notifyListeners();
      return Future.value();
    }
    if (useKnowledge &&
        (attachments.isNotEmpty ||
            temporaryMediaChat ||
            prompt.length > 200 ||
            knowledge?.indexed != true ||
            knowledge?.busy == true)) {
      error =
          'Knowledge answers require an indexed passage and a text question up to 200 characters. Open Knowledge first.';
      notifyListeners();
      return Future.value();
    }
    _stopped = false;
    final preparation = busy ? _pending : null;
    final selected = List<ChatAttachment>.unmodifiable(attachments);
    temporaryMediaChat =
        temporaryMediaChat || (selected.isNotEmpty && !supportsMixedInput);
    busy = true;
    sending = true;
    answer = '';
    modelPath = model.trim();
    error = null;
    messages = [...messages, ChatEntry('user', prompt.trim(), selected)];
    notifyListeners();
    return _pending = _sendWhenPrepared(
      preparation,
      model.trim(),
      prompt.trim(),
      selected,
    );
  }

  Future<void> _sendWhenPrepared(
    Future<void>? preparation,
    String model,
    String prompt,
    List<ChatAttachment> attachments,
  ) async {
    if (preparation != null) {
      await preparation;
      if (_stopped || _disposed || readiness == ChatReadiness.failed) {
        sending = false;
        busy = false;
        if (!_disposed) notifyListeners();
        return;
      }
    }
    await _generate(model, prompt, attachments);
  }

  Future<void> _generate(
    String model,
    String prompt,
    List<ChatAttachment> attachments,
  ) async {
    List<KnowledgePassage> sources = const [];
    try {
      if (useKnowledge) {
        sources = await knowledge!.backend.retrieve(prompt);
        if (_stopped || _disposed) return;
        if (sources.isEmpty) {
          error = 'No matching Knowledge passage. No answer was generated.';
          return;
        }
      }
      final stream = useKnowledge
          ? (backend as GroundedCoreBackend).generateGrounded(
              model,
              prompt,
              sources,
            )
          : temporaryMediaChat || attachments.isNotEmpty
          ? (backend as MediaCoreBackend).generateMessage(
              model,
              prompt,
              attachments,
            )
          : backend.generate(model, prompt);
      await for (final delta in stream) {
        if (agentEnabled && backend is AgentProgressBackend) {
          answer = (backend as AgentProgressBackend).agentText;
        } else {
          answer += delta;
        }
        if (!_disposed) notifyListeners();
      }
    } catch (e) {
      error = e.toString();
    } finally {
      final persistent = backend;
      if (persistent is PersistentCoreBackend) {
        selectedId = persistent.currentId;
        messages = List.of(persistent.messages);
        answer = '';
        await _refresh();
      } else if (answer.isNotEmpty) {
        messages = [
          ...messages,
          ChatEntry('assistant', answer, const [], sources),
        ];
      }
      sending = false;
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> stop() async {
    _stopped = true;
    try {
      await backend.stop();
    } catch (e) {
      error = e.toString();
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> close() async {
    _stopped = true;
    try {
      await backend.stop();
      await _pending;
    } finally {
      await backend.close();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
