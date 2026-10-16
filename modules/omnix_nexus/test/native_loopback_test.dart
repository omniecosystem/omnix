// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:omnix_nexus/omnix_nexus.dart';
import 'package:omnix_nexus/src/rust/frb_generated.dart' show RustLib;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  setUpAll(() async {
    // Dart's test runner does not place code assets beside its executable.
    // Open the DLL registered by this package's hook, never a global DLL.
    final outputs =
        Directory(p.join('.dart_tool', 'hooks_runner', 'omnix_nexus'))
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => p.basename(file.path) == 'output.json')
            .toList()
          ..sort(
            (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
          );
    for (final output in outputs) {
      final data =
          jsonDecode(output.readAsStringSync()) as Map<String, dynamic>;
      for (final asset in data['assets'] as List<dynamic>? ?? []) {
        final encoding = asset['encoding'] as Map<String, dynamic>?;
        final file = encoding?['file'];
        if (encoding?['id'] ==
                'package:omnix_nexus/src/rust/frb_generated.io.dart' &&
            file is String &&
            p.extension(file) == '.dll' &&
            File(file).existsSync()) {
          await RustLib.init(externalLibrary: ExternalLibrary.open(file));
          return;
        }
      }
    }
    throw StateError('The Nexus build hook did not register a Windows DLL.');
  });

  test(
    'native signed requests, denial, restart and revocation',
    () async {
      final keeperDirectory = await Directory.systemTemp.createTemp(
        'omnix-nexus-keeper-',
      );
      final callerDirectory = await Directory.systemTemp.createTemp(
        'omnix-nexus-caller-',
      );
      final strangerDirectory = await Directory.systemTemp.createTemp(
        'omnix-nexus-stranger-',
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
        expect(await keeper.listAllowedPublicPeers(), [callerKey]);

        // Reserve a loopback port before constructing the advertised origin.
        final reservation = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final port = reservation.port;
        await reservation.close();
        final origin = 'http://127.0.0.1:$port';
        var callbacks = 0;
        Future<String> answer(String verifiedCaller, String question) async {
          callbacks++;
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
        final beforeStranger = callbacks;
        await expectLater(
          stranger.queryPublicKnowledge(origin, 'public'),
          throwsA(anything),
        );
        expect(
          callbacks,
          beforeStranger,
          reason: 'Unpaired callers must not reach the host',
        );
        await listener.stop();
        listener = null;

        final restartedKeeper = OmnixNexusNode(
          nodeDirectory: keeperDirectory.path,
        );
        expect(await restartedKeeper.publicKey(), keeperKey);
        expect(await restartedKeeper.listAllowedPublicPeers(), [callerKey]);
        await restartedKeeper.denyPublicPeer(callerKey);
        listener = await restartedKeeper.startPublicKnowledgeListener(
          advertisedOrigin: origin,
          port: port,
          answer: answer,
        );
        final beforeRevoked = callbacks;
        await expectLater(
          caller.queryPublicKnowledge(origin, 'public'),
          throwsA(anything),
        );
        expect(
          callbacks,
          beforeRevoked,
          reason: 'Revoked callers must not reach the host',
        );
      } finally {
        await listener?.stop();
        await keeperDirectory.delete(recursive: true);
        await callerDirectory.delete(recursive: true);
        await strangerDirectory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
