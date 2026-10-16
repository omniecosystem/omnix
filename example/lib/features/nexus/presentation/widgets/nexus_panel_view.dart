// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

enum NexusDemoFixture {
  laptopA('Laptop A · Omnixus', 'public_knowledge.json'),
  laptopB('Laptop B · blue notebook', 'public_knowledge_laptop_b.json');

  const NexusDemoFixture(this.label, this.asset);
  final String label;
  final String asset;
}

/// A previewable, native-free presentation of the experimental Nexus controls.
class NexusPanelView extends StatefulWidget {
  const NexusPanelView({
    super.key,
    required this.supported,
    required this.busy,
    required this.sharing,
    required this.publicKey,
    required this.onCreateIdentity,
    required this.onAllowPeer,
    required this.onDenyPeer,
    required this.onStart,
    required this.onStop,
    required this.onAsk,
    this.answer,
    this.error,
    this.status,
  });

  final bool supported;
  final bool busy;
  final bool sharing;
  final String? publicKey;
  final String? answer;
  final String? error;
  final String? status;
  final VoidCallback onCreateIdentity;
  final ValueChanged<String> onAllowPeer;
  final ValueChanged<String> onDenyPeer;
  final void Function(String origin, NexusDemoFixture fixture) onStart;
  final VoidCallback onStop;
  final void Function(String origin, String question) onAsk;

  @override
  State<NexusPanelView> createState() => _NexusPanelViewState();
}

class _NexusPanelViewState extends State<NexusPanelView> {
  final _peerKey = TextEditingController();
  final _ownOrigin = TextEditingController();
  final _remoteOrigin = TextEditingController();
  final _question = TextEditingController();
  NexusDemoFixture _fixture = NexusDemoFixture.laptopA;

  @override
  void dispose() {
    _peerKey.dispose();
    _ownOrigin.dispose();
    _remoteOrigin.dispose();
    _question.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.supported && !widget.busy;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Nexus · public Knowledge',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Experimental peer-to-peer A2A. Sharing is off until you start it. '
                'Only the selected demo fixture’s public entries can be returned.',
              ),
              if (!widget.supported) ...[
                const SizedBox(height: 12),
                const Text(
                  'This example’s Nexus controls are currently enabled on Windows only.',
                ),
              ],
              const SizedBox(height: 18),
              _section(
                context,
                icon: Icons.fingerprint_outlined,
                title: 'This node',
                children: [
                  if (widget.publicKey == null)
                    const Text(
                      'No identity loaded. Create one to exchange public keys.',
                    )
                  else ...[
                    const Text('Public key · safe to share with a peer'),
                    const SizedBox(height: 8),
                    SelectableText(
                      widget.publicKey!,
                      key: const Key('nexus-public-key'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('nexus-create-identity'),
                    onPressed: enabled && widget.publicKey == null
                        ? widget.onCreateIdentity
                        : null,
                    icon: const Icon(Icons.key_outlined),
                    label: const Text('Create identity'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _section(
                context,
                icon: Icons.verified_user_outlined,
                title: 'Peer access',
                children: [
                  const Text(
                    'Paste the other node’s public key. Grants apply after sharing is restarted.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('nexus-peer-key'),
                    controller: _peerKey,
                    enabled: enabled && widget.publicKey != null,
                    decoration: const InputDecoration(
                      labelText: 'Peer public key',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('nexus-allow'),
                        onPressed: enabled && widget.publicKey != null
                            ? () => widget.onAllowPeer(_peerKey.text.trim())
                            : null,
                        icon: const Icon(Icons.person_add_alt_outlined),
                        label: const Text('Allow public Knowledge'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('nexus-deny'),
                        onPressed: enabled && widget.publicKey != null
                            ? () => widget.onDenyPeer(_peerKey.text.trim())
                            : null,
                        icon: const Icon(Icons.person_remove_outlined),
                        label: const Text('Revoke'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _section(
                context,
                icon: Icons.sensors_outlined,
                title: 'Share from this node',
                children: [
                  Text(
                    widget.sharing
                        ? 'Status · sharing public demo Knowledge'
                        : 'Status · off',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('nexus-own-origin'),
                    controller: _ownOrigin,
                    enabled: enabled && !widget.sharing,
                    decoration: const InputDecoration(
                      labelText: 'This node’s HTTPS origin',
                      hintText: 'https://this-node.example',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<NexusDemoFixture>(
                    key: const Key('nexus-fixture'),
                    initialValue: _fixture,
                    decoration: const InputDecoration(
                      labelText: 'Demo Knowledge fixture',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final fixture in NexusDemoFixture.values)
                        DropdownMenuItem(
                          value: fixture,
                          child: Text(fixture.label),
                        ),
                    ],
                    onChanged: enabled && !widget.sharing
                        ? (value) {
                            if (value != null) setState(() => _fixture = value);
                          }
                        : null,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('nexus-toggle-sharing'),
                    onPressed: enabled && widget.publicKey != null
                        ? widget.sharing
                              ? widget.onStop
                              : () => widget.onStart(
                                  _ownOrigin.text.trim(),
                                  _fixture,
                                )
                        : null,
                    icon: Icon(
                      widget.sharing
                          ? Icons.stop_circle_outlined
                          : Icons.play_circle_outline,
                    ),
                    label: Text(
                      widget.sharing ? 'Stop sharing' : 'Start sharing',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The listener binds only to 127.0.0.1:46137. Configure your own '
                    'HTTPS route, such as the private Tailscale Serve route used in the demo.',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _section(
                context,
                icon: Icons.travel_explore_outlined,
                title: 'Ask another node',
                children: [
                  TextField(
                    key: const Key('nexus-remote-origin'),
                    controller: _remoteOrigin,
                    enabled: enabled,
                    decoration: const InputDecoration(
                      labelText: 'Peer HTTPS origin',
                      hintText: 'https://other-node.example',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('nexus-question'),
                    controller: _question,
                    enabled: enabled,
                    decoration: const InputDecoration(
                      labelText: 'Public Knowledge query',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('nexus-ask'),
                    onPressed: enabled && widget.publicKey != null
                        ? () => widget.onAsk(
                            _remoteOrigin.text.trim(),
                            _question.text.trim(),
                          )
                        : null,
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Ask peer'),
                  ),
                  if (widget.answer != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      widget.answer!,
                      key: const Key('nexus-answer'),
                    ),
                  ],
                ],
              ),
              if (widget.busy) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (widget.status != null) ...[
                const SizedBox(height: 16),
                SelectableText(widget.status!, key: const Key('nexus-status')),
              ],
              if (widget.error != null) ...[
                const SizedBox(height: 16),
                SelectableText(
                  widget.error!,
                  key: const Key('nexus-error'),
                  style: TextStyle(color: scheme.error),
                ),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    ),
  );
}

@Preview(name: 'Nexus · public Knowledge', size: Size(430, 850))
Widget nexusPanelPreview() => MaterialApp(
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.cyan,
      brightness: Brightness.dark,
    ),
  ),
  home: Scaffold(
    body: NexusPanelView(
      supported: true,
      busy: false,
      sharing: false,
      publicKey:
          '85d8709a97ca38e63a60cc3ca04a0a7adfcf74ad3d114c2c8fd3d156bcaac03d',
      onCreateIdentity: () {},
      onAllowPeer: (_) {},
      onDenyPeer: (_) {},
      onStart: (_, _) {},
      onStop: () {},
      onAsk: (_, _) {},
    ),
  ),
);
