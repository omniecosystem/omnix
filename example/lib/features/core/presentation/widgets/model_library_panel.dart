// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:omnix_core/model_installation_types.dart';
import 'package:omnix_example/features/core/presentation/controllers/model_library_controller.dart';

class ModelLibraryPanel extends StatefulWidget {
  const ModelLibraryPanel({
    super.key,
    required this.controller,
    required this.onUse,
    this.canUse = true,
    this.roleFilter,
  });
  final ModelLibraryController controller;
  final ValueChanged<OmnixInstalledModel> onUse;
  final bool canUse;
  final String? roleFilter;
  @override
  State<ModelLibraryPanel> createState() => _ModelLibraryPanelState();
}

class _ModelLibraryPanelState extends State<ModelLibraryPanel> {
  final _url = TextEditingController();
  final _name = TextEditingController();
  final _hash = TextEditingController();
  final _size = TextEditingController();
  final _token = TextEditingController();
  String _role = 'chat';
  String? _error;
  @override
  void initState() {
    super.initState();
    if (widget.roleFilter == 'embedding') {
      _fillEmbedding();
    }
  }

  OmnixModelSpec _spec() => OmnixModelSpec(
    filename: _name.text.trim(),
    sha256: _hash.text.trim().toLowerCase(),
    bytes: int.parse(_size.text.trim()),
    role: _role,
  );
  Future<void> _start(bool network) async {
    setState(() => _error = null);
    try {
      final spec = _spec();
      final source = network
          ? _url.text.trim()
          : await widget.controller.backend.pickFile();
      if (!mounted || source == null) return;
      await widget.controller.install(
        spec,
        source,
        network: network,
        token: _token.text.trim().isEmpty ? null : _token.text.trim(),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _embeddingPreset() {
    setState(_fillEmbedding);
  }

  void _fillEmbedding() {
    _name.text = 'embeddinggemma-2-text-270m.litertlm';
    _hash.text =
        '2d079ee2f6f066b1f368e8d7c819f55214eaef1d0513b312321901f30ab286fb';
    _size.text = '164626432';
    _url.text =
        'https://huggingface.co/litert-community/embeddinggemma-2-text-270m-litert-lm/resolve/9be6e8b90982095dc05c2bd162e4b954ee4dbac7/embeddinggemma-2-text-270m.litertlm';
    _role = 'embedding';
  }

  void _chatPreset() {
    _name.text = 'gemma-4-E2B-it.litertlm';
    _hash.text =
        '181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c';
    _size.text = '2588147712';
    _url.text =
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1/gemma-4-E2B-it.litertlm';
    setState(() => _role = 'chat');
  }

  @override
  void dispose() {
    for (final c in [_url, _name, _hash, _size, _token]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final progress = controller.progress;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.roleFilter == 'embedding'
                    ? 'Embedding models'
                    : 'Model library',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'Downloads use OS background tasks where supported. Reopen the app to finish verification. Imports need the app open. Mobile data may be used.',
              ),
              for (final model in controller.models.where(
                (model) =>
                    widget.roleFilter == null ||
                    model.spec.role == widget.roleFilter,
              ))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.verified_outlined),
                  title: Text(model.spec.filename),
                  subtitle: Text(
                    '${model.spec.role} · ${(model.spec.bytes / 1000000).toStringAsFixed(1)} MB',
                  ),
                  trailing: TextButton(
                    onPressed: controller.busy || !widget.canUse
                        ? null
                        : () => widget.onUse(model),
                    child: const Text('Use'),
                  ),
                ),
              const Divider(),
              if (widget.roleFilter == null)
                TextButton(
                  onPressed: controller.busy ? null : _chatPreset,
                  child: const Text(
                    'Fill Gemma 4 E2B · 2.59 GB (or import existing file)',
                  ),
                ),
              TextButton(
                onPressed: controller.busy ? null : _embeddingPreset,
                child: const Text('Fill EmbeddingGemma 2 · 165 MB'),
              ),
              if (widget.roleFilter == null)
                DropdownButton<String>(
                  value: _role,
                  items: const [
                    DropdownMenuItem(value: 'chat', child: Text('Chat model')),
                    DropdownMenuItem(
                      value: 'embedding',
                      child: Text('Embedding model'),
                    ),
                  ],
                  onChanged: controller.busy
                      ? null
                      : (value) => setState(() => _role = value!),
                ),
              for (final (text, label) in [
                (_name, 'Model filename (.litertlm or .gguf)'),
                (_url, 'HTTPS download URL'),
                (_hash, 'Trusted SHA-256'),
                (_size, 'Exact file size in bytes'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: text,
                    enabled: !controller.busy,
                    decoration: InputDecoration(
                      labelText: label,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              TextField(
                controller: _token,
                obscureText: true,
                enabled: !controller.busy,
                decoration: const InputDecoration(
                  labelText: 'Access token (optional; not saved)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: controller.busy ? null : () => _start(true),
                    icon: const Icon(Icons.download),
                    label: const Text('Download'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.busy ? null : () => _start(false),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Import file'),
                  ),
                  if (controller.busy)
                    TextButton(
                      onPressed: controller.cancel,
                      child: const Text('Cancel'),
                    ),
                  if (controller.busy && controller.progress?.phase == 'paused')
                    TextButton(
                      onPressed: controller.resume,
                      child: const Text('Resume'),
                    ),
                ],
              ),
              if (progress != null) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: progress.total > 0
                      ? (progress.received / progress.total).clamp(0, 1)
                      : null,
                ),
                Text(
                  '${progress.phase} · ${(progress.received / 1000000).toStringAsFixed(1)} / ${(progress.total / 1000000).toStringAsFixed(1)} MB',
                ),
              ],
              if (_error ?? controller.error case final String error)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
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

class _PreviewBackend implements ModelLibraryBackend {
  @override
  Future<List<OmnixInstalledModel>> installed() async => [];
  @override
  Stream<OmnixInstallationProgress> install(
    OmnixModelSpec spec,
    String source, {
    required bool network,
    String? token,
  }) => const Stream.empty();
  @override
  Future<void> cancel() async {}
  @override
  Future<String?> pickFile() async => null;
}

void _previewUse(OmnixInstalledModel _) {}
@Preview(name: 'Model acquisition', size: Size(390, 844))
Widget modelLibraryPreview() => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: SingleChildScrollView(
      child: ModelLibraryPanel(
        controller: ModelLibraryController(_PreviewBackend()),
        onUse: _previewUse,
      ),
    ),
  ),
);

@Preview(name: 'Embedding model acquisition', size: Size(390, 844))
Widget embeddingLibraryPreview() => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: ModelLibraryPanel(
        controller: ModelLibraryController(_PreviewBackend()),
        roleFilter: 'embedding',
        onUse: _previewUse,
      ),
    ),
  ),
);
