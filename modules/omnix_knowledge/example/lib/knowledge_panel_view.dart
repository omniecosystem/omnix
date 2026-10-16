import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'knowledge_demo_controller.dart';

/// The native-free presentation of the Knowledge example.
class KnowledgePanelView extends StatefulWidget {
  const KnowledgePanelView({
    super.key,
    required this.controller,
    this.initialEncoderPath = '',
    this.initialTokenizerPath = '',
    this.initialGenerationPath = '',
    this.initialLegacyGecko = false,
  });
  final KnowledgeDemoController controller;
  final String initialEncoderPath;
  final String initialTokenizerPath;
  final String initialGenerationPath;
  final bool initialLegacyGecko;
  @override
  State<KnowledgePanelView> createState() => _KnowledgePanelViewState();
}

class _KnowledgePanelViewState extends State<KnowledgePanelView> {
  late final TextEditingController _encoder;
  late final TextEditingController _tokenizer;
  late final TextEditingController _generation;
  final _title = TextEditingController(text: 'Router guide');
  final _content = TextEditingController(
    text:
        'To reset the router, hold its reset button for ten seconds. Wait for the indicator to turn blue before reconnecting.',
  );
  final _question = TextEditingController(text: 'How do I reset the router?');
  late bool _legacy;
  @override
  void initState() {
    super.initState();
    _encoder = TextEditingController(text: widget.initialEncoderPath);
    _tokenizer = TextEditingController(text: widget.initialTokenizerPath);
    _generation = TextEditingController(text: widget.initialGenerationPath);
    _legacy = widget.initialLegacyGecko;
  }

  @override
  void dispose() {
    for (final controller in [
      _encoder,
      _tokenizer,
      _generation,
      _title,
      _content,
      _question,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final state = widget.controller;
      Widget field(
        String label,
        TextEditingController controller, {
        int lines = 1,
      }) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          enabled: !state.busy,
          controller: controller,
          maxLines: lines,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
      );
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Knowledge',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const Text(
                'Native Core embeddings → durable Qdrant retrieval → Core answer. Windows CPU qualification; trusted local files only. This demo indexes the passage as public in its own local store; it starts no network listener.',
              ),
              const SizedBox(height: 16),
              field('Embedding model (.tflite)', _encoder),
              field('SentencePiece tokenizer (.model)', _tokenizer),
              SwitchListTile(
                title: const Text('Legacy Gecko compatibility profile'),
                subtitle: const Text(
                  'Off selects Gemma; its real-model qualification is pending.',
                ),
                value: _legacy,
                onChanged: state.busy
                    ? null
                    : (value) => setState(() => _legacy = value),
              ),
              field('Source title', _title),
              field('Passage (up to 300 characters)', _content, lines: 3),
              FilledButton.icon(
                onPressed: state.busy
                    ? null
                    : () => state.index(
                        encoder: _encoder.text.trim(),
                        tokenizer: _tokenizer.text.trim(),
                        legacyGecko: _legacy,
                        title: _title.text,
                        content: _content.text,
                      ),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Index and reopen'),
              ),
              const SizedBox(height: 20),
              field('Generation model (.gguf or .litertlm)', _generation),
              field('Question', _question),
              FilledButton.icon(
                onPressed: state.busy || !state.indexed
                    ? null
                    : () => state.ask(
                        model: _generation.text.trim(),
                        question: _question.text,
                      ),
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Retrieve and answer'),
              ),
              const SizedBox(height: 16),
              if (state.busy) const LinearProgressIndicator(),
              Text(state.stage),
              if (state.error != null)
                SelectableText(
                  state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              for (final passage in state.passages)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${passage.title} · similarity ${passage.score.toStringAsFixed(3)}',
                        ),
                        const SizedBox(height: 8),
                        SelectableText(passage.content),
                      ],
                    ),
                  ),
                ),
              if (state.answer != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Generated answer'),
                        const SizedBox(height: 8),
                        SelectableText(state.answer!),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _PreviewBackend implements KnowledgeDemoBackend {
  @override
  Future<void> indexAndReopen({
    required String encoder,
    required String tokenizer,
    required bool legacyGecko,
    required String title,
    required String content,
  }) async {}
  @override
  Future<List<KnowledgePassage>> retrieve(String question) async => [
    const KnowledgePassage(
      'Router guide',
      'Hold the reset button for ten seconds.',
      0.85,
    ),
  ];
  @override
  Future<String> answer(String model, String prompt) async =>
      'Hold the reset button for ten seconds, then wait for the blue indicator.';
  @override
  Future<void> close() async {}
}

@Preview(name: 'Knowledge retrieval', group: 'Omnix')
Widget knowledgePreview() => MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.cyan,
      brightness: Brightness.dark,
    ),
  ),
  home: Scaffold(
    body: KnowledgePanelView(
      controller: KnowledgeDemoController(_PreviewBackend()),
    ),
  ),
);
