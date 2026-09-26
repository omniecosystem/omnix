// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:omnix/omnix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'nexus_panel_view.dart';
import 'public_knowledge_demo.dart';

/// Replaceable boundary so widget tests never open a native socket or key.
abstract interface class NexusExampleGateway {
  Future<String?> existingPublicKey();
  Future<String> createIdentity();
  Future<void> allowPeer(String key);
  Future<void> denyPeer(String key);
  Future<OmnixNexusListener> startSharing(
    String origin,
    NexusDemoFixture fixture,
  );
  Future<OmnixNodeKnowledgeReply> ask(String origin, String question);
}

/// Omnix-backed implementation for this example, with an app-owned identity.
final class NativeNexusExampleGateway implements NexusExampleGateway {
  late final Future<OmnixNexusNode> _node = _openNode();

  Future<OmnixNexusNode> _openNode() async {
    final support = await getApplicationSupportDirectory();
    return OmnixNexusNode(
      nodeDirectory: p.join(support.path, 'omnix-nexus-demo'),
    );
  }

  @override
  Future<String?> existingPublicKey() async {
    final node = await _node;
    if (!await File(p.join(node.nodeDirectory, 'identity.key')).exists()) {
      return null;
    }
    return node.publicKey();
  }

  @override
  Future<String> createIdentity() async => (await _node).createIdentity();

  @override
  Future<void> allowPeer(String key) async =>
      (await _node).allowPublicPeer(key);

  @override
  Future<void> denyPeer(String key) async => (await _node).denyPublicPeer(key);

  @override
  Future<OmnixNexusListener> startSharing(
    String origin,
    NexusDemoFixture fixture,
  ) async {
    final json = await rootBundle.loadString(fixture.asset);
    final knowledge = await publicDemoKnowledgeFromJson(json);
    return (await _node).startPublicKnowledgeListener(
      advertisedOrigin: origin,
      knowledge: knowledge,
      port: 46137,
    );
  }

  @override
  Future<OmnixNodeKnowledgeReply> ask(String origin, String question) async =>
      (await _node).queryPublicKnowledge(origin, question);
}

class NexusExampleScreen extends StatefulWidget {
  const NexusExampleScreen({super.key, this.gateway, this.supported});

  final NexusExampleGateway? gateway;
  final bool? supported;

  @override
  State<NexusExampleScreen> createState() => _NexusExampleScreenState();
}

class _NexusExampleScreenState extends State<NexusExampleScreen> {
  late final NexusExampleGateway _gateway =
      widget.gateway ?? NativeNexusExampleGateway();
  OmnixNexusListener? _listener;
  String? _publicKey;
  String? _answer;
  String? _status;
  String? _error;
  bool _busy = false;

  bool get _supported =>
      widget.supported ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows);

  @override
  void initState() {
    super.initState();
    if (_supported) unawaited(_loadIdentity());
  }

  Future<void> _loadIdentity() async {
    await _run(() async {
      final key = await _gateway.existingPublicKey();
      if (!mounted) return;
      setState(() {
        _publicKey = key;
        _status = key == null
            ? 'Create a local identity to begin.'
            : 'Identity loaded.';
      });
    });
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy || !_supported) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createIdentity() => _run(() async {
    final key = await _gateway.createIdentity();
    if (mounted) {
      setState(() {
        _publicKey = key;
        _status = 'Identity created. Share only its public key.';
      });
    }
  });

  Future<void> _changeGrant(String key, {required bool allow}) => _run(
    () async {
      if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key)) {
        throw const FormatException('Enter a 64-character peer public key.');
      }
      if (allow) {
        await _gateway.allowPeer(key);
      } else {
        await _gateway.denyPeer(key);
      }
      if (mounted) {
        setState(() {
          _status = allow
              ? 'Peer allowed for public Knowledge. Restart sharing if active.'
              : 'Peer revoked. Restart sharing if active.';
        });
      }
    },
  );

  String _httpsOrigin(String input) {
    final uri = Uri.tryParse(input);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty && uri.path != '/' ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        'Enter a plain HTTPS origin, with no path or Markdown link.',
      );
    }
    return uri.origin;
  }

  Future<void> _start(String input, NexusDemoFixture fixture) => _run(() async {
    final origin = _httpsOrigin(input);
    final listener = await _gateway.startSharing(origin, fixture);
    if (!mounted) {
      await listener.stop();
      return;
    }
    setState(() {
      _listener = listener;
      _status =
          'Sharing ${fixture.label} on 127.0.0.1:${listener.port} via $origin';
    });
  });

  Future<void> _stop() => _run(() async {
    final listener = _listener;
    if (listener == null) return;
    await listener.stop();
    if (mounted) {
      setState(() {
        _listener = null;
        _status = 'Sharing stopped.';
      });
    }
  });

  Future<void> _ask(String input, String question) => _run(() async {
    final origin = _httpsOrigin(input);
    if (question.isEmpty) {
      throw const FormatException('Enter a public Knowledge query.');
    }
    if (mounted) setState(() => _answer = null);
    final reply = await _gateway.ask(origin, question);
    if (mounted) {
      setState(() {
        _answer = reply.texts.join('\n\n');
        _status = 'Peer reply received.';
      });
    }
  });

  @override
  void dispose() {
    final listener = _listener;
    if (listener != null) unawaited(listener.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NexusPanelView(
    supported: _supported,
    busy: _busy,
    sharing: _listener != null,
    publicKey: _publicKey,
    answer: _answer,
    error: _error,
    status: _status,
    onCreateIdentity: _createIdentity,
    onAllowPeer: (key) => _changeGrant(key, allow: true),
    onDenyPeer: (key) => _changeGrant(key, allow: false),
    onStart: _start,
    onStop: _stop,
    onAsk: _ask,
  );
}
