import 'package:flutter/material.dart';

import 'demo_controller.dart';

/// Demonstrates the standalone Storage package without aggregate Omnix.
class StorageExampleApp extends StatefulWidget {
  const StorageExampleApp({super.key, required this.controller});

  final DemoController controller;

  @override
  State<StorageExampleApp> createState() => _StorageExampleAppState();
}

class _StorageExampleAppState extends State<StorageExampleApp> {
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Omnix Storage',
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
      appBar: AppBar(title: const Text('Omnix Storage')),
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
                    Icons.storage_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Native persistence. Standalone.',
                    style: TextStyle(fontSize: 24),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Write a conversation snapshot to a temporary SQLite database, close it, and read it through a fresh connection.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Only temporary example data. No model downloads or network.',
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
