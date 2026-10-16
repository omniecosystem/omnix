import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:omnix_core/omnix_core.dart';
import '../widgets/conversation_controls.dart';
import 'package:omnix_example/features/core/presentation/widgets/live_generation_panel.dart';
import 'package:omnix_example/app/feature_section.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';
import 'package:omnix_example/features/core/presentation/controllers/model_library_controller.dart';
import 'package:omnix_example/features/core/presentation/widgets/model_library_panel.dart';

class CoreScreen extends StatefulWidget {
  const CoreScreen({
    super.key,
    required this.controller,
    this.models,
    this.drafts,
  });
  final CoreController controller;
  final ModelLibraryController? models;
  final Widget? drafts;
  @override
  State<CoreScreen> createState() => _CoreScreenState();
}

class _CoreScreenState extends State<CoreScreen> {
  late final _path = TextEditingController(text: widget.controller.modelPath);
  late final _instructions = TextEditingController(
    text: widget.controller.instructions,
  );
  void _sampling({double? temperature, int? topK, double? topP, int? seed}) {
    final previous =
        widget.controller.sampling ?? const OmnixCoreSamplingOptions();
    widget.controller.configureGeneration(
      OmnixCoreSamplingOptions(
        temperature: temperature ?? previous.temperature,
        topK: topK ?? previous.topK,
        topP: topP ?? previous.topP,
        seed: seed ?? previous.seed,
      ),
      widget.controller.contextTokens,
    );
  }

  @override
  void dispose() {
    _path.dispose();
    _instructions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.drafts == null
      ? _configuration(context)
      : DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: 'Model & settings'),
                  Tab(text: 'Structured draft'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [_configuration(context), widget.drafts!],
                ),
              ),
            ],
          ),
        );

  Widget _configuration(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (widget.controller.error != null) ...[
              Text(
                widget.controller.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
            ],
            if (widget.models case final ModelLibraryController models)
              ExpansionTile(
                title: const Text('Model library'),
                subtitle: const Text(
                  'Import, download or select an installed model',
                ),
                leading: const Icon(Icons.download_outlined),
                children: [
                  ModelLibraryPanel(
                    controller: models,
                    canUse:
                        !widget.controller.busy &&
                        widget.controller.messages.isEmpty,
                    onUse: (model) {
                      if (model.spec.role == 'chat') {
                        _path.text = model.path;
                        widget.controller.configureModel(model.path);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Embedding model installed. Open Knowledge to use it.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            const SizedBox(height: 20),
            if (widget.controller.supportsAgent ||
                widget.controller.supportsKnowledge ||
                widget.controller.temporaryMediaChat) ...[
              FeatureSection(
                title: 'Conversation options',
                icon: Icons.chat_bubble_outline,
                children: [ConversationControls(controller: widget.controller)],
              ),
              const SizedBox(height: 16),
            ],
            FeatureSection(
              title: 'Active model',
              icon: Icons.memory_outlined,
              children: [
                const Text(
                  'Local inference with the appropriate bundled runtime.',
                ),
                if (widget.controller.backend is PreparedCoreBackend) ...[
                  const SizedBox(height: 12),
                  if (widget.controller.readiness == ChatReadiness.preparing)
                    const LinearProgressIndicator()
                  else
                    TextButton.icon(
                      onPressed:
                          widget.controller.busy ||
                              widget.controller.modelPath.isEmpty
                          ? null
                          : widget.controller.prepare,
                      icon: Icon(
                        widget.controller.readiness == ChatReadiness.ready
                            ? Icons.check_circle_outline
                            : Icons.refresh,
                      ),
                      label: Text(
                        widget.controller.readiness == ChatReadiness.ready
                            ? 'Model ready'
                            : 'Prepare model',
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _path,
                  enabled:
                      !widget.controller.busy &&
                      widget.controller.messages.isEmpty,
                  decoration: const InputDecoration(
                    labelText: 'Trusted local model path',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (widget.controller.backend is LiveGenerationBackend &&
                (widget.controller.messages.isNotEmpty ||
                    widget.controller.selectedId != null)) ...[
              LiveGenerationPanel(
                key: ValueKey(widget.controller.selectedId),
                controller: widget.controller,
              ),
              const SizedBox(height: 16),
            ],
            if (widget.controller.supportsGenerationSettings &&
                !(widget.controller.backend is LiveGenerationBackend &&
                    widget.controller.messages.isNotEmpty)) ...[
              FeatureSection(
                title: 'Generation settings',
                icon: Icons.tune,
                children: [
                  DropdownButtonFormField<int>(
                    key: ValueKey('context-${widget.controller.contextTokens}'),
                    initialValue: widget.controller.contextTokens,
                    decoration: const InputDecoration(
                      labelText: 'Context window (tokens)',
                    ),
                    items: [
                      for (final value in [
                        1024,
                        2048,
                        4096,
                        8192,
                        16384,
                        32768,
                      ])
                        DropdownMenuItem(value: value, child: Text('$value')),
                    ],
                    onChanged: widget.controller.canConfigureResponseBudget
                        ? (value) {
                            if (value != null) {
                              widget.controller.configureGeneration(
                                widget.controller.sampling,
                                value,
                              );
                            }
                          }
                        : null,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Custom sampling'),
                    subtitle: const Text('Otherwise retain runtime defaults'),
                    value: widget.controller.sampling != null,
                    onChanged: widget.controller.canConfigureResponseBudget
                        ? (enabled) => widget.controller.configureGeneration(
                            enabled ? const OmnixCoreSamplingOptions() : null,
                            widget.controller.contextTokens,
                          )
                        : null,
                  ),
                  if (widget.controller.sampling
                      case final OmnixCoreSamplingOptions settings) ...[
                    Text(
                      'Temperature: ${settings.temperature.toStringAsFixed(2)}',
                    ),
                    Slider(
                      key: const Key('core-temperature'),
                      value: settings.temperature,
                      min: 0,
                      max: 2,
                      onChanged: widget.controller.canConfigureResponseBudget
                          ? (value) => _sampling(temperature: value)
                          : null,
                    ),
                    Text('Top-P: ${settings.topP.toStringAsFixed(2)}'),
                    Slider(
                      value: settings.topP,
                      min: 0.01,
                      max: 1,
                      onChanged: widget.controller.canConfigureResponseBudget
                          ? (value) => _sampling(topP: value)
                          : null,
                    ),
                    TextFormField(
                      key: ValueKey('top-k-${settings.topK}'),
                      initialValue: '${settings.topK}',
                      enabled: widget.controller.canConfigureResponseBudget,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Top-K (1–10000)',
                      ),
                      onFieldSubmitted: (value) {
                        final parsed = int.tryParse(value);
                        if (parsed != null) _sampling(topK: parsed);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: ValueKey('seed-${settings.seed}'),
                      initialValue: '${settings.seed}',
                      enabled: widget.controller.canConfigureResponseBudget,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Seed (0–2147483647)',
                      ),
                      onFieldSubmitted: (value) {
                        final parsed = int.tryParse(value);
                        if (parsed != null) _sampling(seed: parsed);
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'These settings reach the native runtime. Start a new chat to change context or sampling; saved chats retain their settings.',
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (widget.controller.supportsResponseBudget &&
                !(widget.controller.backend is LiveGenerationBackend &&
                    widget.controller.messages.isNotEmpty)) ...[
              FeatureSection(
                title: 'Response length',
                icon: Icons.tune,
                children: [
                  Text(
                    '${widget.controller.maxOutputTokens} output tokens',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Slider(
                    key: const Key('core-response-budget'),
                    value: widget.controller.maxOutputTokens.toDouble(),
                    min: 1,
                    max: 4096,
                    label: '${widget.controller.maxOutputTokens} tokens',
                    onChanged: widget.controller.canConfigureResponseBudget
                        ? (value) => widget.controller.configureResponseBudget(
                            value.round(),
                          )
                        : null,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tokens in [256, 1024, 2048, 4096])
                        ChoiceChip(
                          label: Text('$tokens'),
                          selected: widget.controller.maxOutputTokens == tokens,
                          onSelected:
                              widget.controller.canConfigureResponseBudget
                              ? (_) => widget.controller
                                    .configureResponseBudget(tokens)
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.controller.canConfigureResponseBudget
                        ? 'Maximum generated tokens per model turn. Larger limits allow longer replies, but can take more time. The context window remains 4096 tokens.'
                        : 'Start a new chat to change response length. Saved text chats keep their original budget.',
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (widget.controller.supportsInstructions) ...[
              FeatureSection(
                title: 'Conversation',
                icon: Icons.chat_bubble_outline,
                children: [
                  TextField(
                    controller: _instructions,
                    enabled:
                        !widget.controller.busy &&
                        widget.controller.messages.isEmpty &&
                        widget.controller.selectedId == null,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Instructions for this chat',
                      helperText:
                          'Saved with text chats. Start a new chat to change them.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            FilledButton(
              onPressed:
                  widget.controller.busy ||
                      widget.controller.messages.isNotEmpty
                  ? null
                  : () {
                      widget.controller.configureModel(_path.text);
                      widget.controller.configureInstructions(
                        _instructions.text,
                      );
                      Navigator.of(context).maybePop();
                    },
              child: const Text('Use this model'),
            ),
            if (widget.controller.messages.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  'Start a new chat from history before changing the model.',
                ),
              ),
            const SizedBox(height: 20),
            const ExpansionTile(
              title: Text('Runtime details'),
              leading: Icon(Icons.info_outline),
              children: [
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'GGUF and LiteRT-LM models use their respective bundled runtimes. Image and audio support depends on the model and platform. A larger response budget does not expand the context window.',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _PreviewBackend
    implements
        InstructionCoreBackend,
        ResponseBudgetBackend,
        GenerationSettingsBackend,
        AgentCoreBackend {
  @override
  bool agentEnabled = true;
  @override
  bool get agentAvailable => true;
  @override
  void configureAgent(bool enabled) => agentEnabled = enabled;
  @override
  OmnixCoreSamplingOptions? sampling;
  @override
  int contextTokens = 4096;
  @override
  void configureGeneration(OmnixCoreSamplingOptions? options, int context) {
    sampling = options;
    contextTokens = context;
  }

  @override
  int maxOutputTokens = 1024;
  @override
  void configureResponseBudget(int tokens) => maxOutputTokens = tokens;
  @override
  String instructions = '';
  @override
  void configureInstructions(String value) => instructions = value;
  @override
  Stream<String> generate(String model, String prompt) => const Stream.empty();
  @override
  Future<void> stop() async {}
  @override
  Future<void> close() async {}
}

@Preview(name: 'Core model configuration')
@Preview(name: 'Compact Core configuration', size: Size(390, 650))
Widget coreConfigurationPreview() => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: CoreScreen(controller: CoreController(_PreviewBackend())),
  ),
);
