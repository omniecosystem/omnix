import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

final class _FakeTransport implements OmnixNexusTransport {
  final calls = <String>[];

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
  });
}
