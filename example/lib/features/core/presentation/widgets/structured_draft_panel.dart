import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:omnix_core/omnix_core.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';
import 'package:omnix_example/features/core/domain/structured_draft.dart';

class StructuredDraftPanel extends StatefulWidget {
  const StructuredDraftPanel({
    super.key,
    required this.core,
    required this.backend,
    this.chooseAudio,
  });
  final CoreController core;
  final StructuredDraftBackend backend;
  final Future<ChatAttachment?> Function()? chooseAudio;
  @override
  State<StructuredDraftPanel> createState() => _StructuredDraftPanelState();
}

class _StructuredDraftPanelState extends State<StructuredDraftPanel> {
  final _instruction = TextEditingController();
  final _title = TextEditingController();
  final _details = TextEditingController();
  bool _busy = false;
  bool _cancelled = false;
  bool _review = false;
  String? _error;
  bool get _available =>
      !widget.core.busy &&
      widget.core.messages.isEmpty &&
      widget.core.modelPath.isNotEmpty;

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy || !_available) return;
    setState(() {
      _busy = true;
      _cancelled = false;
      _error = null;
      _review = false;
    });
    try {
      await operation();
    } on FormatException {
      if (mounted && !_cancelled) {
        setState(
          () => _error =
              'The model did not return a valid note, even after one correction. Try again with a clearer request.',
        );
      }
    } catch (e) {
      if (mounted && !_cancelled) {
        setState(() => _error = 'Draft unavailable: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generate() => _run(() async {
    final result = await widget.backend.draft(
      widget.core.modelPath,
      _instruction.text.trim(),
    );
    if (!mounted || _cancelled) return;
    setState(() {
      _title.text = result.title;
      _details.text = result.details;
      _review = true;
    });
  });
  Future<void> _transcribe() => _run(() async {
    final model = widget.core.modelPath;
    final audio = await widget.chooseAudio!();
    if (!mounted || _cancelled || audio == null) return;
    if (!_available || widget.core.modelPath != model) {
      throw StateError('The selected model changed.');
    }
    final text = await widget.backend.transcribe(model, audio.part);
    if (mounted && !_cancelled) setState(() => _instruction.text = text);
  });
  Future<void> _stop() async {
    _cancelled = true;
    try {
      await widget.backend.cancel();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not stop drafting: $e');
    }
  }

  Future<void> _copy() async {
    try {
      final reviewed = StructuredNote.fromJson({
        'title': _title.text,
        'details': _details.text,
      });
      await Clipboard.setData(
        ClipboardData(text: jsonEncode(reviewed.toJson())),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reviewed note copied. No action was executed.'),
          ),
        );
      }
    } on FormatException {
      setState(
        () => _error = 'Complete the title and details within their limits.',
      );
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    unawaited(widget.backend.close().catchError((Object _) {}));
    _instruction.dispose();
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.core,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Turn a request into a note',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Local inference → validated fields → your review. Nothing is scheduled, sent or executed. Prompted JSON is not guaranteed structured decoding.',
        ),
        const SizedBox(height: 12),
        if (!_available)
          const Text(
            'Choose a model in Core and start a new Home chat before drafting. This releases the previous chat runtime.',
          ),
        TextField(
          controller: _instruction,
          enabled: !_busy && _available,
          maxLength: 1600,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Request',
            border: OutlineInputBorder(),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: !_busy && _available ? _generate : null,
              child: const Text('Generate note'),
            ),
            if (widget.chooseAudio != null)
              OutlinedButton(
                onPressed: !_busy && _available ? _transcribe : null,
                child: const Text('Transcribe WAV'),
              ),
            if (_busy)
              TextButton(onPressed: _stop, child: const Text('Stop drafting')),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'WAV input requires a compatible audio model. Review and correct the transcript, especially names and numbers, before generating.',
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_review) ...[
          const SizedBox(height: 24),
          Text(
            'Review your note',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'The model can invent or omit details. Edit both fields before copying.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
          ),
          TextField(
            controller: _details,
            maxLength: 800,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Details',
              border: OutlineInputBorder(),
            ),
          ),
          OutlinedButton(
            onPressed: _copy,
            child: const Text('Copy reviewed JSON'),
          ),
        ],
      ],
    ),
  );
}

class PreviewDraftBackend implements StructuredDraftBackend {
  @override
  Future<StructuredNote> draft(String model, String instruction) async =>
      StructuredNote('Research note', instruction);
  @override
  Future<String> transcribe(String model, OmnixInputPart audio) async =>
      'Compare two local runtime engines.';
  @override
  Future<void> cancel() async {}
  @override
  Future<void> close() async {}
}

class PreviewDraftCore implements CoreDemoBackend {
  @override
  Stream<String> generate(String model, String prompt) => const Stream.empty();
  @override
  Future<void> stop() async {}
  @override
  Future<void> close() async {}
}

@Preview(name: 'Structured note drafting', size: Size(420, 760))
Widget structuredDraftPreview() => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: StructuredDraftPanel(
      core: CoreController(PreviewDraftCore())..configureModel('trusted-model'),
      backend: PreviewDraftBackend(),
    ),
  ),
);
