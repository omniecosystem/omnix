import 'dart:io';

import 'package:omnix_nexus/omnix_nexus.dart';
import 'package:path/path.dart' as p;

/// Sends a real signed A2A request using disposable example identities.
///
/// Reads no consumer app data and downloads no models. Stops its listener and
/// removes only the temporary directory created by this invocation.
Future<String> runLocalDemo() async {
  final temporary = await Directory.systemTemp.createTemp(
    'omnix-nexus-example-',
  );
  OmnixNexusListener? listener;
  try {
    final keeper = OmnixNexusNode(
      nodeDirectory: p.join(temporary.path, 'keeper'),
    );
    final caller = OmnixNexusNode(
      nodeDirectory: p.join(temporary.path, 'caller'),
    );
    await keeper.createIdentity();
    final callerKey = await caller.createIdentity();
    await keeper.allowPublicPeer(callerKey);

    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    final origin = 'http://127.0.0.1:$port';
    var privateRequestReachedHost = false;
    listener = await keeper.startPublicKnowledgeListener(
      advertisedOrigin: origin,
      port: port,
      answer: (verifiedCaller, question) async {
        if (verifiedCaller != 'ed25519:$callerKey') return '';
        if (question == 'private note') {
          privateRequestReachedHost = true;
          return '';
        }
        return question == 'What is Nexus?'
            ? 'Nexus connects approved peers through A2A.\nSource: Example'
            : '';
      },
    );
    final reply = await caller.queryPublicKnowledge(origin, 'What is Nexus?');
    if (reply.texts.isEmpty) throw StateError('No public answer was returned.');

    var refused = false;
    try {
      await caller.queryPublicKnowledge(origin, 'private note');
    } catch (_) {
      if (!privateRequestReachedHost) rethrow;
      refused = true;
    }
    if (!refused) throw StateError('Private-answer denial failed.');
    return '${reply.texts.join('\n')}\n\nPrivate request refused.';
  } finally {
    try {
      await listener?.stop();
    } finally {
      await temporary.delete(recursive: true);
    }
  }
}
