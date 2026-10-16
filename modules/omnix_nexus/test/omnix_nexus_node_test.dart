// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:omnix_nexus/omnix_nexus.dart';
import 'package:test/test.dart';

final class FakeTransport implements OmnixNexusTransport {
  Future<String> Function(String, String)? answer;
  int stops = 0;
  final grants = <String>[];

  @override
  Future<OmnixNexusListener> startPublicKnowledgeListener(
    String directory,
    String origin,
    int port,
    Future<String> Function(String, String) answer,
  ) async {
    this.answer = answer;
    return OmnixNexusListener(() async {
      stops++;
    }, port: 46137);
  }

  @override
  Future<String> createIdentity(String directory) async => 'key';
  @override
  Future<String> publicKey(String directory) async => 'key';
  @override
  Future<void> allowPublicPeer(String directory, String key) async {
    grants.add(key);
  }

  @override
  Future<void> denyPublicPeer(String directory, String key) async {
    grants.remove(key);
  }

  @override
  Future<List<String>> listAllowedPublicPeers(String directory) async =>
      List.of(grants);
  @override
  Future<OmnixNodeKnowledgeReply> queryPublicKnowledge(
    String directory,
    String origin,
    String question,
  ) async => OmnixNodeKnowledgeReply(taskId: 'task', texts: [question]);
}

void main() {
  late FakeTransport transport;
  late OmnixNexusNode node;
  setUp(() {
    transport = FakeTransport();
    node = OmnixNexusNode(nodeDirectory: 'node', transport: transport);
  });

  test('rejects an empty identity directory', () {
    expect(
      () => OmnixNexusNode(nodeDirectory: ' ', transport: transport),
      throwsArgumentError,
    );
  });

  test('delegates identity, grants and requests', () async {
    expect(await node.createIdentity(), 'key');
    expect(await node.publicKey(), 'key');
    await node.allowPublicPeer('peer');
    expect(await node.listAllowedPublicPeers(), ['peer']);
    expect(
      (await node.queryPublicKnowledge(
        'https://peer.example',
        'question',
      )).texts,
      ['question'],
    );
    await node.denyPublicPeer('peer');
    expect(await node.listAllowedPublicPeers(), isEmpty);
  });

  test('host callback owns the answer and stop is idempotent', () async {
    final listener = await node.startPublicKnowledgeListener(
      advertisedOrigin: 'https://peer.example',
      answer: (caller, question) async => '$caller:$question',
    );
    expect(
      await transport.answer!('ed25519:peer', 'question'),
      'ed25519:peer:question',
    );
    await listener.stop();
    await listener.stop();
    expect(transport.stops, 1);
  });

  test('invalid requests never reach the host', () async {
    var calls = 0;
    await node.startPublicKnowledgeListener(
      advertisedOrigin: 'https://peer.example',
      answer: (_, _) async {
        calls++;
        return 'answer';
      },
    );
    expect(await transport.answer!('', 'question'), isEmpty);
    expect(await transport.answer!('peer', ' '), isEmpty);
    expect(await transport.answer!('peer', 'x' * 513), isEmpty);
    expect(calls, 0);
  });

  test('host errors deny rather than escape across the bridge', () async {
    await node.startPublicKnowledgeListener(
      advertisedOrigin: 'https://peer.example',
      answer: (_, _) async => throw StateError('private detail'),
    );
    expect(await transport.answer!('peer', 'question'), isEmpty);
  });

  test('rejects invalid listener ports', () {
    expect(
      () => node.startPublicKnowledgeListener(
        advertisedOrigin: 'https://peer.example',
        port: 65536,
        answer: (_, _) async => '',
      ),
      throwsArgumentError,
    );
  });
}
