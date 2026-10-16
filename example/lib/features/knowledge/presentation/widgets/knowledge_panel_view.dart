import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:omnix_example/features/knowledge/data/services/text_document_import.dart';
import 'package:omnix_example/app/feature_section.dart';
import 'package:omnix_example/features/knowledge/presentation/controllers/knowledge_demo_controller.dart';
import 'package:omnix_example/features/core/presentation/controllers/model_library_controller.dart';
import 'package:omnix_example/features/core/presentation/widgets/model_library_panel.dart';

/// The native-free presentation of the Knowledge example.
class KnowledgePanelView extends StatefulWidget {
  const KnowledgePanelView({
    super.key,
    required this.controller,
    this.initialEncoderPath = '',
    this.initialTokenizerPath = '',
    this.initialGenerationPath = '',
    this.initialLegacyGecko = false,
    this.models,
    this.pickText = pickKnowledgeText,
    this.onIndexed,
  });
  final KnowledgeDemoController controller;
  final String initialEncoderPath;
  final String initialTokenizerPath;
  final String initialGenerationPath;
  final bool initialLegacyGecko;
  final ModelLibraryController? models;
  final Future<ImportedKnowledgeText?> Function() pickText;
  final Future<void> Function()? onIndexed;
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
  bool _importing = false;
  String? _importError;
  Future<void> _importText() async {
    setState(() {
      _importing = true;
      _importError = null;
    });
    try {
      final document = await widget.pickText();
      if (!mounted || document == null) return;
      setState(() {
        _title.text = document.name;
        _content.text = document.text;
      });
    } catch (error) {
      if (mounted) setState(() => _importError = error.toString());
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

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
          enabled: !state.busy && !_importing,
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
                'Import or paste text, review it, then index locally. Text files are supported now; PDF, DOCX and media ingestion are not yet supported.',
              ),
              const SizedBox(height: 16),
              FeatureSection(
                title: 'Embedding model',
                icon: Icons.memory_outlined,
                children: [
                  field(
                    _legacy
                        ? 'Embedding model (.tflite)'
                        : 'EmbeddingGemma 2 text model (.litertlm)',
                    _encoder,
                  ),
                  if (widget.models case final ModelLibraryController models)
                    ExpansionTile(
                      title: const Text('Import or download embedding model'),
                      children: [
                        ModelLibraryPanel(
                          controller: models,
                          roleFilter: 'embedding',
                          canUse: !state.busy,
                          onUse: (model) => setState(() {
                            _encoder.text = model.path;
                            _legacy = false;
                          }),
                        ),
                      ],
                    ),
                  if (_legacy)
                    field('SentencePiece tokenizer (.model)', _tokenizer),
                  SwitchListTile(
                    title: const Text('Legacy Gecko compatibility profile'),
                    subtitle: const Text(
                      'Off selects EmbeddingGemma 2 with its bundled tokenizer. Each model uses a separate index.',
                    ),
                    value: _legacy,
                    onChanged: state.busy
                        ? null
                        : (value) => setState(() => _legacy = value),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FeatureSection(
                title: 'Add knowledge',
                icon: Icons.note_add_outlined,
                children: [
                  OutlinedButton.icon(
                    onPressed: state.busy || _importing ? null : _importText,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(
                      _importing ? 'Importing…' : 'Import text document',
                    ),
                  ),
                  const Text(
                    'UTF-8 TXT, MD, CSV or JSON · up to 32 KiB. Importing alone does not index or retain the file.',
                  ),
                  if (_importError != null)
                    Text(
                      _importError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  field('Source title', _title),
                  field(
                    _legacy
                        ? 'Passage (up to 300 characters)'
                        : 'Document text (up to 32 KiB)',
                    _content,
                    lines: 5,
                  ),
                  if (widget.onIndexed != null)
                    const Text(
                      'Indexing adds text to Knowledge and starts a new Home chat. Existing chat history is kept.',
                    ),
                  FilledButton.icon(
                    onPressed: state.busy || _importing
                        ? null
                        : () async {
                            await state.index(
                              encoder: _encoder.text.trim(),
                              tokenizer: _tokenizer.text.trim(),
                              legacyGecko: _legacy,
                              title: _title.text,
                              content: _content.text,
                            );
                            if (state.indexed && widget.onIndexed != null) {
                              await state.handoff(widget.onIndexed!);
                            }
                          },
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      widget.onIndexed == null
                          ? 'Index and reopen'
                          : 'Index and make available to Home',
                    ),
                  ),
                ],
              ),
              if (widget.onIndexed == null) const SizedBox(height: 20),
              if (widget.onIndexed == null)
                FeatureSection(
                  title: 'Search and answer',
                  icon: Icons.manage_search,
                  children: [
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
                  ],
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
                          '${passage.title} · similarity ${passage.score?.toStringAsFixed(3) ?? 'unavailable'}',
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
      pickText: () async => const ImportedKnowledgeText(
        'router-guide.txt',
        'Hold the reset button for ten seconds.',
      ),
    ),
  ),
);
