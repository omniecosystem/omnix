import 'package:flutter/material.dart';

import 'demo_controller.dart';

/// Demonstrates Nexus without a model, database or consumer app dependency.
class NexusExampleApp extends StatefulWidget {
  const NexusExampleApp({super.key, required this.controller});

  final DemoController controller;

  @override
  State<NexusExampleApp> createState() => _NexusExampleAppState();
}

class _NexusExampleAppState extends State<NexusExampleApp> {
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Omnix Nexus',
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
      appBar: AppBar(title: const Text('Omnix Nexus')),
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
                    Icons.hub_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Two nodes. One device.',
                    style: TextStyle(fontSize: 24),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Create temporary identities, approve a peer, and send a '
                    'signed A2A request over loopback. A public answer succeeds; '
                    'a private request is refused.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No model downloads, account or Tailscale required.',
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
