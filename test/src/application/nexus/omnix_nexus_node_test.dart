import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

final class _FakeTransport implements OmnixNexusTransport {
  final calls = <String>[];
  Future<String> Function(String, String)? answer;

  @override
  Future<OmnixNexusListener> startPublicKnowledgeListener(
    String nodeDirectory,
    String advertisedOrigin,
    int port,
    Future<String> Function(String, String) answer,
  ) async {
    calls.add('listen:$nodeDirectory:$advertisedOrigin:$port');
    this.answer = answer;
    return OmnixNexusListener(() async {
      calls.add('stop');
    }, port: 46137);
  }

  @override
  Future<String> createIdentity(String nodeDirectory) async {
    calls.add('create:$nodeDirectory');
    return 'local-public-key';
  }

  @override
  Future<String> publicKey(String nodeDirectory) async {
    calls.add('show:$nodeDirectory');
    return 'local-public-key';
  }

  @override
  Future<void> allowPublicPeer(String nodeDirectory, String publicKey) async {
    calls.add('allow:$nodeDirectory:$publicKey');
  }

  @override
  Future<void> denyPublicPeer(String nodeDirectory, String publicKey) async {
    calls.add('deny:$nodeDirectory:$publicKey');
  }

  @override
  Future<OmnixNodeKnowledgeReply> queryPublicKnowledge(
    String nodeDirectory,
    String remoteOrigin,
    String question,
  ) async {
    calls.add('query:$nodeDirectory:$remoteOrigin:$question');
    return const OmnixNodeKnowledgeReply(
      taskId: 'task-1',
      texts: ['Public answer'],
    );
  }
}

final class _MixedKnowledgeBackend implements OmnixKnowledgeBackend {
  @override
  Future<void> initialize() async {}
  @override
  Future<void> index(OmnixKnowledgeChunk chunk) async {}
  @override
  Future<void> remove(String chunkId) async {}
  @override
  Future<void> flush() async {}
  @override
  Future<void> clear() async {}
  @override
  Future<List<OmnixKnowledgeMatch>> search(OmnixKnowledgeQuery query) async {
    OmnixKnowledgeMatch match(String title, OmnixKnowledgeAccess access) =>
        OmnixKnowledgeMatch(
          chunk: OmnixKnowledgeChunk(
            id: title,
            documentId: title,
            content: title,
            source: OmnixKnowledgeSource(id: title, title: title),
            access: access,
          ),
          score: 0.9,
        );
    return [
      match('private secret', OmnixKnowledgeAccess.private),
      match('public fact', OmnixKnowledgeAccess.public),
    ];
  }
}

void main() {
  group('OmnixNexusNode', () {
    test('requires a node directory', () {
      expect(
        () => OmnixNexusNode(nodeDirectory: ' ', transport: _FakeTransport()),
        throwsArgumentError,
      );
    });

    test(
      'delegates identity, grants, and public query to its transport',
      () async {
        final fake = _FakeTransport();
        final node = OmnixNexusNode(nodeDirectory: 'node-a', transport: fake);

        expect(await node.createIdentity(), 'local-public-key');
        expect(await node.publicKey(), 'local-public-key');
        await node.allowPublicPeer('peer-b');
        final reply = await node.queryPublicKnowledge(
          'https://peer.example',
          'What is Omnixus?',
        );
        await node.denyPublicPeer('peer-b');

        expect(reply.taskId, 'task-1');
        expect(reply.texts, ['Public answer']);
        expect(fake.calls, [
          'create:node-a',
          'show:node-a',
          'allow:node-a:peer-b',
          'query:node-a:https://peer.example:What is Omnixus?',
          'deny:node-a:peer-b',
        ]);
      },
    );

    test('listener returns public Knowledge only and stops once', () async {
      final fake = _FakeTransport();
      final node = OmnixNexusNode(nodeDirectory: 'node-a', transport: fake);
      final listener = await node.startPublicKnowledgeListener(
        advertisedOrigin: 'https://peer.example',
        knowledge: OmnixKnowledgeCoordinator(_MixedKnowledgeBackend()),
      );
      expect(listener.port, 46137);
      expect(fake.calls, ['listen:node-a:https://peer.example:0']);
      expect(
        await fake.answer!('ed25519:peer', 'public fact'),
        'public fact\nSource: public fact',
      );
      expect(await fake.answer!('', 'public fact'), isEmpty);
      expect(await fake.answer!('ed25519:peer', ' '), isEmpty);
      await listener.stop();
      await listener.stop();
      expect(fake.calls.last, 'stop');
      expect(fake.calls.where((call) => call == 'stop').length, 1);
    });
  });
}
