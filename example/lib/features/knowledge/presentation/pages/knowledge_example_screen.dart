import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:omnix_core/omnix_core.dart';
import 'package:omnix_example/features/knowledge/presentation/controllers/knowledge_demo_controller.dart';
import 'package:omnix_example/features/knowledge/data/services/knowledge_native_backend.dart';
import 'package:omnix_example/features/knowledge/presentation/widgets/knowledge_panel_view.dart';
import 'package:omnix_example/features/core/presentation/controllers/model_library_controller.dart';

/// The isolated example store owner, independent of any consumer app.
class KnowledgeExampleScreen extends StatefulWidget {
  const KnowledgeExampleScreen({
    super.key,
    this.controller,
    this.models,
    this.onUseInHome,
  });
  final KnowledgeDemoController? controller;
  final ModelLibraryController? models;
  final Future<void> Function()? onUseInHome;
  @override
  State<KnowledgeExampleScreen> createState() => _KnowledgeExampleScreenState();
}

class _KnowledgeExampleScreenState extends State<KnowledgeExampleScreen> {
  KnowledgeDemoController? _controller;
  String? _error;
  String _encoder = '';
  String _tokenizer = '';
  String _generation = '';
  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final installed = await OmnixModelInstaller(
        root: p.join(directory.path, 'models-v1'),
      ).installed();
      final embeddings = installed.where(
        (model) => model.spec.role == 'embedding',
      );
      final chat = installed.where((model) => model.spec.role == 'chat');
      if (embeddings.isNotEmpty) _encoder = embeddings.first.path;
      if (chat.isNotEmpty) _generation = chat.first.path;
      final local = Platform.isWindows
          ? Platform.environment['LOCALAPPDATA']
          : null;
      if (local != null && local.isNotEmpty) {
        Future<String> existing(String name) async {
          final candidate = p.join(local, 'flutter_gemma', name);
          return await File(candidate).exists() ? candidate : '';
        }

        final candidate = p.join(
          local,
          'Omnix',
          'qualification',
          'embeddinggemma-2',
          'embeddinggemma-2-text-270m.litertlm',
        );
        if (_encoder.isEmpty) {
          _encoder = await File(candidate).exists() ? candidate : '';
        }
        _tokenizer = await existing('Gecko_512_quant__sentencepiece.model');
        if (_generation.isEmpty) {
          _generation = await existing('gemma-4-E2B-it.litertlm');
        }
      }
      if (!mounted) return;
      setState(
        () => _controller =
            widget.controller ??
            KnowledgeDemoController(
              NativeKnowledgeDemoBackend(
                p.join(directory.path, 'knowledge-rag-example-v1'),
              ),
            ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    if (widget.controller == null) controller?.dispose();
    if (controller != null && widget.controller == null) {
      unawaited(
        controller.close().catchError((Object e) {
          debugPrint('Knowledge close failed: $e');
        }),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Center(child: Text(_error!));
    final controller = _controller;
    return controller == null
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Expanded(
                child: KnowledgePanelView(
                  controller: controller,
                  onIndexed: widget.onUseInHome,
                  models: widget.models,
                  initialEncoderPath: _encoder,
                  initialTokenizerPath: _tokenizer,
                  initialGenerationPath: _generation,
                  initialLegacyGecko: false,
                ),
              ),
            ],
          );
  }
}
