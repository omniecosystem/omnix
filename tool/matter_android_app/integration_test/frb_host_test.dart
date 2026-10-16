// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix_nexus/omnix_nexus.dart';
import 'package:omnix_matter_android_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Registered SDK owner accepts Dart FRB command and readback',
    (tester) async {
      app.main();
      await tester.pumpAndSettle();
      const channel = MethodChannel('omnix/matter-qualification');
      final before = await channel.invokeMapMethod<String, dynamic>(
        'qualifyLifecycle',
      );
      expect(await channel.invokeMethod<bool>('registerRustHost'), isTrue);
      final host = await OmnixMatterHost.openAndroid(
        nodeId: BigInt.from(0x12344321),
        endpoint: 1,
      );
      await expectLater(
        OmnixMatterHost.openAndroid(
          nodeId: BigInt.from(0x12344321),
          endpoint: 1,
        ),
        throwsA(anything),
      );
      try {
        for (final on in [true, false]) {
          await host.setOnOff(on: on);
          expect(await host.readOnOff(), on);
        }
      } finally {
        await host.close();
      }
      await host.close();
      await expectLater(host.readOnOff(), throwsStateError);
      final reopened = await OmnixMatterHost.openAndroid(
        nodeId: BigInt.from(0x12344321),
        endpoint: 1,
      );
      try {
        expect(await reopened.readOnOff(), isFalse);
      } finally {
        await reopened.close();
      }
      final after = await channel.invokeMapMethod<String, dynamic>(
        'qualifyLifecycle',
      );
      expect(after?['ownerId'], before?['ownerId']);
      expect(after?['fabricIndex'], before?['fabricIndex']);
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
