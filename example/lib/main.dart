import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix/omnix_flutter_gemma.dart';

const _modelUri =
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/'
    'resolve/main/gemma-4-E2B-it.litertlm';
const _modelArtifact = 'gemma-4-E2B-it.litertlm';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(OmnixExample(runtime: FlutterGemmaOmnix.createRuntime()));
}

class OmnixExample extends StatefulWidget {
  const OmnixExample({super.key, required this.runtime});

  final OmnixRuntime runtime;

  @override
  State<OmnixExample> createState() => _OmnixExampleState();
}

class _OmnixExampleState extends State<OmnixExample> {
  final TextEditingController _promptController = TextEditingController();
  OmnixConversation? _conversation;
  OmnixRuntimeInfo? _runtimeInfo;
  String _answer = '';
  String _thinking = '';
  String? _error;
  int _installProgress = 0;
  bool _initializing = true;
  bool _installed = false;
  bool _installing = false;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final info = await widget.runtime.initialize();
      final installed = await widget.runtime.models.isInstalled(_modelArtifact);
      if (!mounted) return;
      setState(() {
        _runtimeInfo = info;
        _installed = installed;
        _initializing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _initializing = false;
      });
    }
  }

  Future<void> _install() async {
    setState(() {
      _error = null;
      _installing = true;
      _installProgress = 0;
    });
    try {
      await widget.runtime.models.install(
        OmnixModelInstallRequest(
          template: OmnixModelTemplate.gemma4,
          format: OmnixModelFormat.liteRtLm,
          source: OmnixNetworkModelSource(
            Uri.parse(_modelUri),
            foreground: defaultTargetPlatform == TargetPlatform.android,
          ),
        ),
        onProgress: (progress) {
          if (mounted) setState(() => _installProgress = progress);
        },
      );
      if (!mounted) return;
      setState(() => _installed = true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  Future<void> _send() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _generating) return;
    setState(() {
      _error = null;
      _answer = '';
      _thinking = '';
      _generating = true;
    });
    try {
      _conversation ??= await widget.runtime.openConversation(
        const OmnixConversationConfiguration(
          modelTemplate: OmnixModelTemplate.gemma4,
          preferredBackend: OmnixBackendPreference.cpu,
          maxTokens: 4096,
          maxOutputTokens: 512,
          temperature: 1,
          topK: 64,
          topP: 0.95,
          thinking: true,
        ),
      );
      await for (final event in _conversation!.send(prompt)) {
        if (!mounted) return;
        setState(() {
          switch (event) {
            case OmnixTextDelta(:final text):
              _answer += text;
            case OmnixThinkingDelta(:final text):
              _thinking += text;
            case OmnixToolCall():
              break;
          }
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _stop() => _conversation?.stop() ?? Future.value();

  @override
  void dispose() {
    _promptController.dispose();
    unawaited(_conversation?.close());
    unawaited(widget.runtime.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Omnix example')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    _runtimeInfo == null
                        ? 'Initializing Omnix…'
                        : '${_runtimeInfo!.engineName} '
                              '${_runtimeInfo!.engineVersion} · '
                              'Native API ${_runtimeInfo!.apiVersion}',
                  ),
                  const SizedBox(height: 24),
                  if (_initializing)
                    const LinearProgressIndicator()
                  else if (!_installed) ...[
                    const Text(
                      'Install Gemma 4 E2B to run a local conversation. '
                      'The download is approximately 2.6 GB.',
                    ),
                    const SizedBox(height: 12),
                    if (_installing) ...[
                      LinearProgressIndicator(value: _installProgress / 100),
                      const SizedBox(height: 8),
                      Text('$_installProgress%'),
                    ] else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _install,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Install model'),
                        ),
                      ),
                  ] else ...[
                    TextField(
                      controller: _promptController,
                      enabled: !_generating,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Prompt',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _generating ? null : _send,
                          icon: const Icon(Icons.send_outlined),
                          label: const Text('Send'),
                        ),
                        const SizedBox(width: 12),
                        if (_generating)
                          OutlinedButton.icon(
                            onPressed: _stop,
                            icon: const Icon(Icons.stop_outlined),
                            label: const Text('Stop'),
                          ),
                      ],
                    ),
                    if (_thinking.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Thinking',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SelectableText(_thinking),
                    ],
                    if (_answer.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Response',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SelectableText(_answer),
                    ],
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 24),
                    SelectableText(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
