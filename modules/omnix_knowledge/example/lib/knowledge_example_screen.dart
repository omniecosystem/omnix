import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'knowledge_demo_controller.dart';
import 'knowledge_native_backend.dart';
import 'knowledge_panel_view.dart';

/// The isolated example store owner, independent of any consumer app.
class KnowledgeExampleScreen extends StatefulWidget {
  const KnowledgeExampleScreen({super.key});
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
      final local = Platform.isWindows
          ? Platform.environment['LOCALAPPDATA']
          : null;
      if (local != null && local.isNotEmpty) {
        Future<String> existing(String name) async {
          final candidate = p.join(local, 'flutter_gemma', name);
          return await File(candidate).exists() ? candidate : '';
        }

        _encoder = await existing('Gecko_512_quant.tflite');
        _tokenizer = await existing('Gecko_512_quant__sentencepiece.model');
        _generation = await existing('gemma-4-E2B-it.litertlm');
      }
      if (!mounted) return;
      setState(
        () => _controller = KnowledgeDemoController(
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
    controller?.dispose();
    if (controller != null) {
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
        : KnowledgePanelView(
            controller: controller,
            initialEncoderPath: _encoder,
            initialTokenizerPath: _tokenizer,
            initialGenerationPath: _generation,
            initialLegacyGecko: _encoder.isNotEmpty && _tokenizer.isNotEmpty,
          );
  }
}
