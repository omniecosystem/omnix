import 'package:flutter/material.dart';

import 'demo_controller.dart';

/// Demonstrates the standalone Core package without aggregate Omnix.
class CoreExampleApp extends StatefulWidget {
  const CoreExampleApp({super.key, required this.controller});

  final DemoController controller;

  @override
  State<CoreExampleApp> createState() => _CoreExampleAppState();
}

class _CoreExampleAppState extends State<CoreExampleApp> {
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Omnix Core',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF00E5FF),
        brightness: Brightness.dark,
        primary: const Color(0xFF00E5FF),
      ),
      scaffoldBackgroundColor: const Color(0xFF10171C),
      useMaterial3: true,
    ),
    home: Scaffold(
      appBar: AppBar(title: const Text('Omnix Core')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.memory_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Native inference. Standalone.',
                    style: TextStyle(fontSize: 24),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Stream, stop and recall with a trusted local GGUF or LiteRT-LM model. No storage or Nexus dependency is required.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Windows CPU/text only. Trusted artifact paths are supplied through environment variables.',
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: widget.controller.busy
                        ? null
                        : widget.controller.run,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      widget.controller.busy ? 'Running…' : 'Run local demo',
                    ),
                  ),
                  if (widget.controller.busy) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                  if (widget.controller.result != null ||
                      widget.controller.error != null) ...[
                    const SizedBox(height: 24),
                    Card.outlined(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: SelectableText(
                          widget.controller.error ?? widget.controller.result!,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
