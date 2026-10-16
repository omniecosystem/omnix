import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:omnix/omnix.dart' show OmnixAutonomyMode;
import 'agent_activity_timeline.dart';
import 'native_email_intent_card.dart';
import 'typing_dots.dart';
import 'package:omnix_core/omnix_core.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';
import 'package:omnix_example/features/home/domain/voice_capture.dart';
import 'package:omnix_example/features/knowledge/presentation/controllers/knowledge_demo_controller.dart';

class HomeChatPanel extends StatefulWidget {
  const HomeChatPanel({
    super.key,
    required this.controller,
    this.pickAttachment,
    this.voiceCapture,
  });
  final CoreController controller;
  final Future<ChatAttachment?> Function()? pickAttachment;
  final VoiceCapture? voiceCapture;
  @override
  State<HomeChatPanel> createState() => _HomeChatPanelState();
}

class _HomeChatPanelState extends State<HomeChatPanel>
    with WidgetsBindingObserver {
  final _prompt = TextEditingController();
  final List<ChatAttachment> _attachments = [];
  bool _picking = false;
  String? _attachmentError;
  bool _recording = false;
  bool _voiceWorking = false;
  int _voiceEpoch = 0;
  int _seconds = 0;
  Timer? _recordingTimer;
  String? _recordedModel;
  List<ChatEntry>? _recordedMessages;

  @override
  void initState() {
    super.initState();
    _prompt.addListener(_promptChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void _promptChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached ||
            state == AppLifecycleState.hidden) &&
        (_recording || _voiceWorking)) {
      unawaited(_cancelVoice());
    }
  }

  Future<void> _startVoice() async {
    final epoch = ++_voiceEpoch;
    _recordedModel = widget.controller.modelPath;
    _recordedMessages = widget.controller.messages;
    setState(() {
      _voiceWorking = true;
      _attachmentError = null;
    });
    try {
      await widget.voiceCapture!.start();
      if (!mounted || epoch != _voiceEpoch) return;
      setState(() {
        _recording = true;
        _seconds = 0;
      });
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _seconds++);
        if (_seconds >= 55) unawaited(_stopVoice());
      });
    } catch (e) {
      if (mounted && epoch == _voiceEpoch) {
        setState(() => _attachmentError = e.toString());
      }
      try {
        await widget.voiceCapture!.cancel();
      } catch (_) {
        /* Preserve the capture failure. */
      }
    } finally {
      if (mounted && epoch == _voiceEpoch) {
        setState(() => _voiceWorking = false);
      }
    }
  }

  Future<void> _stopVoice() async {
    if (_voiceWorking || !_recording) return;
    final epoch = _voiceEpoch;
    _recordingTimer?.cancel();
    setState(() => _voiceWorking = true);
    try {
      final attachment = await widget.voiceCapture!.stop();
      if (!mounted || epoch != _voiceEpoch) return;
      if (_recordedModel != widget.controller.modelPath ||
          !identical(_recordedMessages, widget.controller.messages)) {
        throw StateError(
          'The chat changed during recording. Please record again.',
        );
      }
      _addAttachment(attachment);
    } catch (e) {
      if (mounted && epoch == _voiceEpoch) {
        setState(() => _attachmentError = e.toString());
      }
    } finally {
      if (mounted && epoch == _voiceEpoch) {
        setState(() {
          _recording = false;
          _voiceWorking = false;
        });
      }
    }
  }

  Future<void> _cancelVoice() async {
    ++_voiceEpoch;
    _recordingTimer?.cancel();
    if (mounted) {
      setState(() {
        _recording = false;
        _voiceWorking = true;
      });
    }
    try {
      await widget.voiceCapture?.cancel();
    } catch (e) {
      if (mounted) setState(() => _attachmentError = e.toString());
    } finally {
      if (mounted) setState(() => _voiceWorking = false);
    }
  }

  Future<void> _pick() async {
    final model = widget.controller.modelPath;
    final messages = widget.controller.messages;
    setState(() {
      _picking = true;
      _attachmentError = null;
    });
    try {
      final attachment = await widget.pickAttachment!();
      if (!mounted || attachment == null) return;
      if (!widget.controller.canCompose ||
          model != widget.controller.modelPath ||
          !identical(messages, widget.controller.messages)) {
        return;
      }
      _addAttachment(attachment);
    } catch (e) {
      if (mounted) setState(() => _attachmentError = e.toString());
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _addAttachment(ChatAttachment attachment) {
    final proposed = [..._attachments, attachment];
    final images = proposed
        .where((a) => a.part.kind == OmnixInputKind.image)
        .length;
    final audio = proposed
        .where((a) => a.part.kind == OmnixInputKind.audio)
        .length;
    final bytes = proposed.fold<int>(0, (n, a) => n + a.part.bytes.length);
    if (images > 4 || audio > 1 || bytes > 16 * 1024 * 1024) {
      throw StateError(
        'Attach up to four images and one WAV, totaling at most 16 MiB.',
      );
    }
    final limit = attachment.part.kind == OmnixInputKind.audio
        ? 2 * 1024 * 1024
        : 8 * 1024 * 1024;
    if (attachment.part.bytes.length > limit) {
      throw StateError('Audio must be under 2 MiB and images under 8 MiB.');
    }
    setState(() => _attachments.add(attachment));
  }

  @override
  void dispose() {
    ++_voiceEpoch;
    _recordingTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.voiceCapture?.cancel().catchError((Object _) {}));
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.controller,
      if (widget.controller.knowledge != null) widget.controller.knowledge!,
    ]),
    builder: (context, _) => Column(
      children: [
        Expanded(
          child:
              widget.controller.messages.isEmpty &&
                  !widget.controller.sending &&
                  widget.controller.agentActivities.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      widget.controller.modelPath.isEmpty
                          ? 'Choose a local model in Core to start a conversation.'
                          : 'What would you like to explore?',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount:
                      widget.controller.messages.length +
                      (widget.controller.sending ||
                              widget.controller.agentActivities.isNotEmpty
                          ? 1
                          : 0),
                  itemBuilder: (context, i) {
                    final entry = i < widget.controller.messages.length
                        ? widget.controller.messages[i]
                        : ChatEntry(
                            'assistant',
                            widget.controller.answer,
                            const [],
                            const [],
                            widget.controller.agentActivities,
                          );
                    return Align(
                      alignment: entry.role == 'user'
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Card.outlined(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.role == 'user' ? 'You' : 'Omnix',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelMedium,
                                ),
                                const SizedBox(height: 8),
                                if (entry.activities.isNotEmpty)
                                  AgentActivityTimeline(
                                    activities: entry.activities,
                                  ),
                                if (i >= widget.controller.messages.length &&
                                    entry.text.isEmpty &&
                                    widget.controller.sending)
                                  const TypingDots()
                                else
                                  SelectableText(entry.text),
                                for (final intent in entry.intents)
                                  NativeEmailIntentCard(
                                    key: ValueKey(intent),
                                    intent: intent,
                                  ),
                                for (final attachment in entry.attachments)
                                  Chip(label: Text(attachment.name)),
                                if (entry.sources.isNotEmpty) ...[
                                  const Divider(),
                                  const Text('Sources'),
                                  for (final source in entry.sources)
                                    ExpansionTile(
                                      title: Text(source.title),
                                      subtitle: Text('Retrieved reference'),
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: SelectableText(source.content),
                                        ),
                                      ],
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (widget.controller.agentStatus != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(widget.controller.agentStatus!),
          ),
        if (_attachments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final attachment in _attachments)
                  InputChip(
                    label: Text(attachment.name),
                    deleteButtonTooltipMessage: 'Remove attachment',
                    onDeleted: !widget.controller.canCompose
                        ? null
                        : () => setState(() => _attachments.remove(attachment)),
                  ),
              ],
            ),
          ),
        if (_attachmentError != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_attachmentError!),
          ),
        if (widget.controller.error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              widget.controller.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_recording)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Recording · ${_seconds}s / 55s'),
              TextButton(
                onPressed: _voiceWorking ? null : _cancelVoice,
                child: const Text('Cancel recording'),
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.pickAttachment != null &&
                      widget.controller.supportsAttachments)
                    IconButton(
                      tooltip: 'Attach image or WAV',
                      onPressed:
                          _picking ||
                              widget.controller.useKnowledge ||
                              _recording ||
                              _voiceWorking ||
                              !widget.controller.canCompose ||
                              widget.controller.modelPath.isEmpty ||
                              !widget.controller.canAddAttachments
                          ? null
                          : _pick,
                      icon: const Icon(Icons.attach_file),
                    ),
                  Expanded(
                    child: TextField(
                      controller: _prompt,
                      minLines: 1,
                      maxLines: 4,
                      enabled:
                          widget.controller.canCompose &&
                          !_recording &&
                          !_voiceWorking,
                      decoration: const InputDecoration(
                        hintText: 'Message',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (widget.voiceCapture != null &&
                      widget.controller.supportsAttachments &&
                      !_recording &&
                      (_prompt.text.trim().isNotEmpty ||
                          _attachments.isNotEmpty))
                    IconButton(
                      tooltip: 'Record voice message',
                      onPressed:
                          !widget.controller.canCompose ||
                              _picking ||
                              _voiceWorking ||
                              widget.controller.modelPath.isEmpty ||
                              widget.controller.useKnowledge ||
                              !widget.controller.canAddAttachments ||
                              _attachments.any(
                                (a) => a.part.kind == OmnixInputKind.audio,
                              )
                          ? null
                          : () => unawaited(_startVoice()),
                      icon: const Icon(Icons.mic),
                    ),
                  FilledButton(
                    onPressed: widget.controller.sending
                        ? widget.controller.stop
                        : !widget.controller.canCompose ||
                              _picking ||
                              _voiceWorking ||
                              widget.controller.modelPath.isEmpty
                        ? null
                        : () {
                            if (_recording) {
                              unawaited(_stopVoice());
                              return;
                            }
                            if (_prompt.text.trim().isEmpty &&
                                _attachments.isEmpty &&
                                widget.voiceCapture != null &&
                                !widget.controller.useKnowledge &&
                                widget.controller.supportsAttachments) {
                              if (!widget.controller.canAddAttachments) {
                                setState(
                                  () => _attachmentError =
                                      'Start a new chat before recording audio.',
                                );
                                return;
                              }
                              unawaited(_startVoice());
                              return;
                            }
                            final text = _prompt.text;
                            if (text.trim().isEmpty && _attachments.isEmpty) {
                              return;
                            }
                            widget.controller.send(
                              widget.controller.modelPath,
                              text,
                              attachments: List.of(_attachments),
                            );
                            _prompt.clear();
                            setState(() => _attachments.clear());
                          },
                    child: widget.controller.sending
                        ? const Text('Stop')
                        : _recording
                        ? const Text('Stop recording')
                        : _prompt.text.trim().isEmpty &&
                              _attachments.isEmpty &&
                              widget.voiceCapture != null &&
                              !widget.controller.useKnowledge &&
                              widget.controller.supportsAttachments
                        ? const Tooltip(
                            message: 'Record voice message',
                            child: Icon(Icons.mic),
                          )
                        : const Text('Send'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _PreviewBackend implements MediaCoreBackend {
  @override
  Stream<String> generateMessage(
    String model,
    String prompt,
    List<ChatAttachment> attachments,
  ) => const Stream.empty();
  @override
  Stream<String> generate(String model, String prompt) => const Stream.empty();
  @override
  Future<void> stop() async {}
  @override
  Future<void> close() async {}
}

class _AgentPreviewBackend extends _PreviewBackend
    implements
        AgentProgressBackend,
        AgentAutonomyBackend,
        LiveAgentCoreBackend,
        MixedInputCoreBackend {
  @override
  bool get supportsMixedInput => agentEnabled;
  @override
  OmnixAutonomyMode autonomy = OmnixAutonomyMode.scopedAssistance;
  @override
  void configureAutonomy(OmnixAutonomyMode mode) {
    autonomy = mode;
  }

  @override
  bool agentEnabled = true;
  @override
  bool get agentAvailable => true;
  @override
  String get agentText => '';
  @override
  String? get agentStatus => 'Reading device information';
  @override
  void configureAgent(bool enabled) {
    agentEnabled = enabled;
  }

  @override
  bool get canSwitchAgent => true;
  @override
  Future<void> switchAgent(bool enabled, String model) async {
    agentEnabled = enabled;
  }
}

@Preview(
  name: 'Home with app-wide tools, without Knowledge',
  size: Size(600, 800),
)
Widget homeAgentPreview() => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: HomeChatPanel(
      controller: CoreController(_AgentPreviewBackend())
        ..modelPath = 'gemma.litertlm',
    ),
  ),
);

@Preview(name: 'Home conversation')
Widget homeConversationPreview() => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: HomeChatPanel(
      controller: CoreController(_PreviewBackend())
        ..modelPath = 'local-model'
        ..messages = [
          const ChatEntry('user', 'What can you remember?'),
          const ChatEntry(
            'assistant',
            'Our conversation remains on this device.',
          ),
        ],
    ),
  ),
);

@Preview(name: 'Home preparing model', size: Size(390, 700))
Widget homePreparingPreview() => MaterialApp(
  home: Scaffold(
    body: HomeChatPanel(
      controller: CoreController(_PreviewBackend())
        ..modelPath = 'local-model'
        ..busy = true
        ..readiness = ChatReadiness.preparing,
    ),
  ),
);

@Preview(name: 'Home media composer', size: Size(420, 700))
Widget homeMediaPreview() => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: HomeChatPanel(
      controller: CoreController(_PreviewBackend())..modelPath = 'local-model',
      pickAttachment: () async => null,
      voiceCapture: _PreviewVoiceCapture(),
    ),
  ),
);

@Preview(name: 'Home agent with media', size: Size(420, 700))
@Preview(name: 'Compact agent Home', size: Size(390, 700))
@Preview(name: 'Wide agent Home', size: Size(1000, 700))
Widget homeAgentMediaPreview() => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: HomeChatPanel(
      controller: CoreController(_AgentPreviewBackend())
        ..modelPath = 'local-model',
      pickAttachment: () async => ChatAttachment(
        'scene.jpg',
        OmnixInputPart.image(Uint8List.fromList([1, 2])),
      ),
      voiceCapture: _PreviewVoiceCapture(),
    ),
  ),
);

class _PreviewVoiceCapture implements VoiceCapture {
  @override
  Future<void> start() async {}
  @override
  Future<ChatAttachment> stop() async => ChatAttachment(
    'Voice message.wav',
    OmnixInputPart.audio(Uint8List.fromList([0, 0])),
  );
  @override
  Future<void> cancel() async {}
  @override
  Future<void> close() async {}
}

@Preview(name: 'Home retrieved evidence', size: Size(600, 800))
Widget homeKnowledgeEvidencePreview() => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: HomeChatPanel(
      controller: CoreController(_PreviewBackend())
        ..modelPath = 'local-model'
        ..messages = [
          const ChatEntry('user', 'How do I reset the router?'),
          const ChatEntry(
            'assistant',
            'Hold reset for ten seconds and wait for blue.',
            [],
            [
              KnowledgePassage(
                'Router guide',
                'Hold the reset button for ten seconds. Wait for the indicator to turn blue.',
                0.95,
              ),
            ],
          ),
        ],
    ),
  ),
);
