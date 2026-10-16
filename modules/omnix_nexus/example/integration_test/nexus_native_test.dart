import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix_nexus/omnix_nexus.dart';
import 'package:omnix_nexus_example/local_demo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('minimal example sends real signed requests', (tester) async {
    await tester.runAsync(() async {
      final result = await runLocalDemo();
      expect(result, contains('Nexus connects approved peers through A2A.'));
      expect(result, contains('Private request refused.'));
    });
  });

  testWidgets('packaged Nexus verifies peers and preserves grants', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: Text('Nexus native validation')),
      ),
    );
    await tester.runAsync(() async {
      final keeperDirectory = await Directory.systemTemp.createTemp(
        'nexus-keeper-test-',
      );
      final callerDirectory = await Directory.systemTemp.createTemp(
        'nexus-caller-test-',
      );
      final strangerDirectory = await Directory.systemTemp.createTemp(
        'nexus-stranger-test-',
      );
      OmnixNexusListener? listener;
      try {
        final keeper = OmnixNexusNode(nodeDirectory: keeperDirectory.path);
        final caller = OmnixNexusNode(nodeDirectory: callerDirectory.path);
        final stranger = OmnixNexusNode(nodeDirectory: strangerDirectory.path);
        final keeperKey = await keeper.createIdentity();
        final callerKey = await caller.createIdentity();
        await stranger.createIdentity();
        await keeper.allowPublicPeer(callerKey);
        final reserved = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final port = reserved.port;
        await reserved.close();
        final origin = 'http://127.0.0.1:$port';
        var calls = 0;
        Future<String> answer(String verifiedCaller, String question) async {
          calls++;
          expect(verifiedCaller, 'ed25519:$callerKey');
          return question == 'public' ? 'Public answer\nSource: Test' : '';
        }

        listener = await keeper.startPublicKnowledgeListener(
          advertisedOrigin: origin,
          port: port,
          answer: answer,
        );
        expect(
          (await caller.queryPublicKnowledge(origin, 'public')).texts.join(),
          contains('Public answer'),
        );
        await expectLater(
          caller.queryPublicKnowledge(origin, 'private'),
          throwsA(anything),
        );
        final callsBeforeStranger = calls;
        await expectLater(
          stranger.queryPublicKnowledge(origin, 'public'),
          throwsA(anything),
        );
        expect(calls, callsBeforeStranger);
        await listener.stop();
        listener = null;
        final restarted = OmnixNexusNode(nodeDirectory: keeperDirectory.path);
        expect(await restarted.publicKey(), keeperKey);
        expect(await restarted.listAllowedPublicPeers(), [callerKey]);
        await restarted.denyPublicPeer(callerKey);
        listener = await restarted.startPublicKnowledgeListener(
          advertisedOrigin: origin,
          port: port,
          answer: answer,
        );
        final callsBeforeRevoked = calls;
        await expectLater(
          caller.queryPublicKnowledge(origin, 'public'),
          throwsA(anything),
        );
        expect(calls, callsBeforeRevoked);
      } finally {
        await listener?.stop();
        await keeperDirectory.delete(recursive: true);
        await callerDirectory.delete(recursive: true);
        await strangerDirectory.delete(recursive: true);
      }
    });
  });
}
