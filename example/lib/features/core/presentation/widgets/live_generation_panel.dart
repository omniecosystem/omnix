import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:omnix_core/omnix_core.dart';
import 'package:omnix_example/app/feature_section.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';

class LiveGenerationPanel extends StatefulWidget {
  const LiveGenerationPanel({super.key, required this.controller});
  final CoreController controller;
  @override
  State<LiveGenerationPanel> createState() => _LiveGenerationPanelState();
}

class _LiveGenerationPanelState extends State<LiveGenerationPanel> {
  late int _tokens = widget.controller.maxOutputTokens;
  late OmnixCoreSamplingOptions? _settings = widget.controller.sampling;
  void _change({double? temperature, double? topP, int? topK, int? seed}) {
    final old = _settings ?? const OmnixCoreSamplingOptions();
    setState(
      () => _settings = OmnixCoreSamplingOptions(
        temperature: temperature ?? old.temperature,
        topP: topP ?? old.topP,
        topK: topK ?? old.topK,
        seed: seed ?? old.seed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.controller.canApplyLiveSettings;
    return FeatureSection(
      title: 'Update this conversation',
      icon: Icons.tune,
      children: [
        Text('$_tokens output tokens'),
        Slider(
          key: const Key('live-output-tokens'),
          value: _tokens.toDouble(),
          min: 1,
          max: widget.controller.contextTokens.clamp(1, 4096).toDouble(),
          onChanged: enabled
              ? (value) => setState(() => _tokens = value.round())
              : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Custom sampling'),
          value: _settings != null,
          onChanged: enabled
              ? (value) => setState(
                  () => _settings = value
                      ? const OmnixCoreSamplingOptions()
                      : null,
                )
              : null,
        ),
        if (_settings case final OmnixCoreSamplingOptions settings) ...[
          Text('Temperature: ${settings.temperature.toStringAsFixed(2)}'),
          Slider(
            value: settings.temperature,
            min: 0,
            max: 2,
            onChanged: enabled ? (value) => _change(temperature: value) : null,
          ),
          Text('Top-P: ${settings.topP.toStringAsFixed(2)}'),
          Slider(
            value: settings.topP,
            min: 0.01,
            max: 1,
            onChanged: enabled ? (value) => _change(topP: value) : null,
          ),
          TextFormField(
            key: const Key('live-top-k'),
            initialValue: '${settings.topK}',
            enabled: enabled,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Top-K (1–10000)'),
            onChanged: (text) {
              final value = int.tryParse(text);
              if (value != null) _change(topK: value);
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('live-seed'),
            initialValue: '${settings.seed}',
            enabled: enabled,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Seed (0–2147483647)'),
            onChanged: (text) {
              final value = int.tryParse(text);
              if (value != null) _change(seed: value);
            },
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('apply-live-settings'),
          onPressed: enabled
              ? () => widget.controller.applyGeneration(_tokens, _settings)
              : null,
          child: const Text('Apply to this conversation'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Applies between turns without running past tools again. Context size and system instructions still require a new chat. Saved chats are prepared when opened; retry preparation in Home if loading fails.',
        ),
      ],
    );
  }
}

@Preview(name: 'Live generation controls', size: Size(390, 650))
Widget liveGenerationPreview() => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: LiveGenerationPanel(
        controller: CoreController(_PreviewBackend())
          ..messages.add(const ChatEntry('assistant', 'Existing conversation')),
      ),
    ),
  ),
);

class _PreviewBackend implements LiveGenerationBackend {
  @override
  bool get canReconfigureLive => true;
  @override
  int contextTokens = 4096;
  @override
  OmnixCoreSamplingOptions? sampling;
  @override
  Future<void> applyGeneration(
    int tokens,
    OmnixCoreSamplingOptions? options,
  ) async {
    sampling = options;
  }

  @override
  void configureGeneration(OmnixCoreSamplingOptions? options, int tokens) {}
  @override
  Stream<String> generate(String model, String prompt) => const Stream.empty();
  @override
  Future<void> stop() async {}
  @override
  Future<void> close() async {}
}
