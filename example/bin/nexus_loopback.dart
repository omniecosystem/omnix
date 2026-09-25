// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:omnix/omnix.dart';
import 'package:omnix/src/rust/frb_generated.dart' show RustLib;
import 'package:omnix_example/public_knowledge_demo.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:path/path.dart' as p;

/// Exercises the real Rust A2A listener and Dart Knowledge callback locally.
Future<void> main() async {
  final nativeLibrary = Platform.environment['OMNIX_NATIVE_DLL'];
  if (nativeLibrary != null) {
    await RustLib.init(externalLibrary: ExternalLibrary.open(nativeLibrary));
  }
  final directory = await Directory.systemTemp.createTemp('omnix-nexus-demo-');
  OmnixNexusListener? listener;
  try {
    final keeper = OmnixNexusNode(nodeDirectory: p.join(directory.path, 'keeper'));
    final requester = OmnixNexusNode(
      nodeDirectory: p.join(directory.path, 'requester'),
    );
    await keeper.createIdentity();
    final requesterKey = await requester.createIdentity();
    await keeper.allowPublicPeer(requesterKey);

    final knowledge = OmnixKnowledgeCoordinator(PublicDemoKnowledgeBackend());
    Future<void> add(String id, String content, OmnixKnowledgeAccess access) =>
        knowledge.indexDocument(
          OmnixKnowledgeDocument(
            id: id,
            title: id,
            createdAt: DateTime.utc(2026, 1, 1),
            access: access,
          ),
          [
            OmnixKnowledgeChunk(
              id: '$id:0',
              documentId: id,
              content: content,
              source: OmnixKnowledgeSource(id: id, title: id),
              access: access,
            ),
          ],
        );
    await add(
      'Omnixus',
      'Omnixus links independent AI nodes using A2A.',
      OmnixKnowledgeAccess.public,
    );
    await add(
      'private',
      'This must never cross the node boundary.',
      OmnixKnowledgeAccess.private,
    );

    const port = 46138;
    const origin = 'http://127.0.0.1:$port';
    listener = await keeper.startPublicKnowledgeListener(
      advertisedOrigin: origin,
      knowledge: knowledge,
      port: port,
    );
    final reply = await requester.queryPublicKnowledge(origin, 'Omnixus');
    if (!reply.texts.join().contains('Omnixus links independent AI nodes') ||
        reply.texts.join().contains('This must never cross')) {
      throw StateError('Public Knowledge boundary failed');
    }
    var privateDenied = false;
    try {
      await requester.queryPublicKnowledge(origin, 'private');
    } catch (_) {
      privateDenied = true;
    }
    if (!privateDenied) {
      throw StateError('Private Knowledge crossed the node boundary');
    }
    stdout.writeln('A2A public Knowledge: ${reply.texts.first}');
    stdout.writeln('Private Knowledge request: denied');
    stdout.writeln('Loopback listener port: ${listener.port}');
  } finally {
    stdout.writeln('Stopping loopback listener...');
    await listener?.stop();
    stdout.writeln('Removing temporary identities...');
    await directory.delete(recursive: true);
    RustLib.dispose();
  }
}
