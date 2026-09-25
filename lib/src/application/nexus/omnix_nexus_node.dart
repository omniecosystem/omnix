// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import '../../domain/knowledge/omnix_knowledge.dart';
import '../knowledge/omnix_knowledge_coordinator.dart';
import '../../rust/api/nexus.dart' as native;
import '../../rust/frb_generated.dart' show RustLib;

/// The text returned by a public Knowledge request to another node.
final class OmnixNodeKnowledgeReply {
  /// Creates a response from an A2A task or direct message.
  const OmnixNodeKnowledgeReply({required this.taskId, required this.texts});

  /// The completed A2A task identifier, if the peer returned a task.
  final String? taskId;

  /// The nonempty text artifacts supplied by the peer.
  final List<String> texts;
}

/// The local endpoint for a paired public-Knowledge listener.
final class OmnixNexusListener {
  OmnixNexusListener(this._stop, {required this.port});

  /// Local loopback port. A host may proxy this with its own HTTPS transport.
  final int port;

  final Future<void> Function() _stop;
  Future<void>? _stopping;

  /// Stops accepting requests; safe to call more than once.
  Future<void> stop() => _stopping ??= _stop();
}

/// Connects the Nexus application API to a native node implementation.
///
/// A host may provide a replacement for tests or for another platform.
abstract interface class OmnixNexusTransport {
  /// Starts a loopback A2A listener for verified public Knowledge requests.
  Future<OmnixNexusListener> startPublicKnowledgeListener(
    String nodeDirectory,
    String advertisedOrigin,
    int port,
    Future<String> Function(String verifiedCallerId, String question) answer,
  );

  /// Creates an identity without replacing an existing private key.
  Future<String> createIdentity(String nodeDirectory);

  /// Reads the public key of an existing identity.
  Future<String> publicKey(String nodeDirectory);

  /// Grants a peer access to public Knowledge only.
  Future<void> allowPublicPeer(String nodeDirectory, String publicKey);

  /// Revokes a peer's public Knowledge grant.
  Future<void> denyPublicPeer(String nodeDirectory, String publicKey);

  /// Sends one signed public Knowledge request to [remoteOrigin].
  Future<OmnixNodeKnowledgeReply> queryPublicKnowledge(
    String nodeDirectory,
    String remoteOrigin,
    String question,
  );
}

/// Exposes paired public Knowledge operations to an Omnix host.
///
/// This first slice is a caller and identity API, not a listener or remote
/// action gateway. The host chooses a private [nodeDirectory] outside its
/// source tree and handles pairing UX and secure network reachability.
final class OmnixNexusNode {
  /// Uses [transport] when supplied, or the bundled native bridge otherwise.
  OmnixNexusNode({required this.nodeDirectory, OmnixNexusTransport? transport})
    : _transport = transport ?? _NativeNexusTransport() {
    if (nodeDirectory.trim().isEmpty) {
      throw ArgumentError.value(nodeDirectory, 'nodeDirectory');
    }
  }

  /// The host-selected directory holding this node's local identity.
  final String nodeDirectory;

  final OmnixNexusTransport _transport;

  /// Serves public Knowledge to peers allowed by this node's local grant list.
  ///
  /// The listener binds to 127.0.0.1; the host must provide a reachable HTTPS
  /// [advertisedOrigin] separately. Only public chunks can enter a response.
  /// Peer grant changes take effect after stopping and restarting the listener.
  Future<OmnixNexusListener> startPublicKnowledgeListener({
    required String advertisedOrigin,
    required OmnixKnowledgeCoordinator knowledge,
    int port = 0,
  }) {
    if (port < 0 || port > 65535) {
      throw ArgumentError.value(port, 'port');
    }
    return _transport.startPublicKnowledgeListener(
      nodeDirectory,
      advertisedOrigin,
      port,
      (verifiedCallerId, question) async {
        if (verifiedCallerId.isEmpty ||
            question.trim().isEmpty ||
            question.length > 512) {
          return '';
        }
        try {
          final matches = await knowledge.retrieve(
            OmnixKnowledgeQuery(
              text: question,
              topK: 1,
              allowedAccess: {OmnixKnowledgeAccess.public},
            ),
          );
          if (matches.isEmpty) return '';
          final match = matches.first;
          return '${match.chunk.content}\nSource: ${match.chunk.source.title}';
        } catch (_) {
          return '';
        }
      },
    );
  }

  /// Creates a new local identity without replacing an existing one.
  Future<String> createIdentity() => _transport.createIdentity(nodeDirectory);

  /// Returns the existing public key, suitable for sharing with a peer.
  Future<String> publicKey() => _transport.publicKey(nodeDirectory);

  /// Allows [peerPublicKey] to request public Knowledge from this node.
  ///
  /// A running receiver must reload its grants to observe this change.
  Future<void> allowPublicPeer(String peerPublicKey) =>
      _transport.allowPublicPeer(nodeDirectory, peerPublicKey);

  /// Revokes [peerPublicKey]'s public Knowledge grant.
  ///
  /// A running receiver must reload its grants to observe this change.
  Future<void> denyPublicPeer(String peerPublicKey) =>
      _transport.denyPublicPeer(nodeDirectory, peerPublicKey);

  /// Sends a signed public Knowledge request to [remoteOrigin].
  Future<OmnixNodeKnowledgeReply> queryPublicKnowledge(
    String remoteOrigin,
    String question,
  ) => _transport.queryPublicKnowledge(nodeDirectory, remoteOrigin, question);
}

final class _NativeNexusTransport implements OmnixNexusTransport {
  static Future<void>? _initialization;

  Future<void> _ready() => _initialization ??=
      RustLib.instance.initialized ? Future<void>.value() : RustLib.init();

  @override
  Future<OmnixNexusListener> startPublicKnowledgeListener(
    String nodeDirectory,
    String advertisedOrigin,
    int port,
    Future<String> Function(String verifiedCallerId, String question) answer,
  ) async {
    await _ready();
    final info = await native.startPublicKnowledgeListener(
      nodeDir: nodeDirectory,
      advertisedOrigin: advertisedOrigin,
      port: port,
      answer: answer,
    );
    return OmnixNexusListener(
      () => native.stopPublicKnowledgeListener(id: info.id),
      port: info.port,
    );
  }

  @override
  Future<String> createIdentity(String nodeDirectory) async {
    await _ready();
    return native.createNodeIdentity(nodeDir: nodeDirectory);
  }

  @override
  Future<String> publicKey(String nodeDirectory) async {
    await _ready();
    return native.nodePublicKey(nodeDir: nodeDirectory);
  }

  @override
  Future<void> allowPublicPeer(String nodeDirectory, String publicKey) async {
    await _ready();
    await native.allowPublicPeer(nodeDir: nodeDirectory, publicKey: publicKey);
  }

  @override
  Future<void> denyPublicPeer(String nodeDirectory, String publicKey) async {
    await _ready();
    await native.denyPublicPeer(nodeDir: nodeDirectory, publicKey: publicKey);
  }

  @override
  Future<OmnixNodeKnowledgeReply> queryPublicKnowledge(
    String nodeDirectory,
    String remoteOrigin,
    String question,
  ) async {
    await _ready();
    final reply = await native.queryPeerPublicKnowledge(
      nodeDir: nodeDirectory,
      remoteOrigin: remoteOrigin,
      question: question,
    );
    return OmnixNodeKnowledgeReply(taskId: reply.taskId, texts: reply.texts);
  }
}
