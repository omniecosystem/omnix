// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'package:omnix_nexus/omnix_nexus.dart';
import 'package:test/test.dart';

class FakeMatterTransport implements OmnixMatterTransport {
  final calls = <String>[];
  Completer<void>? pending;
  int closes = 0;
  @override
  Future<BigInt> open(String directory) async => BigInt.one;
  @override
  Future<void> close(BigInt id) async {
    closes++;
  }

  @override
  Future<String> request(BigInt id, String operation, String arguments) async {
    calls.add(operation);
    if (operation == 'read') {
      await pending?.future;
      return 'true';
    }
    if (operation == 'list') {
      return jsonEncode([
        const OmnixMatterDevice(
          nodeId: '112234',
          name: 'Light',
          endpoint: 1,
        ).toJson(),
      ]);
    }
    return 'null';
  }
}

void main() {
  test('device serialization preserves pending status', () {
    const record = OmnixMatterDevice(
      nodeId: '112234',
      name: 'Light',
      endpoint: 1,
      operational: false,
    );
    expect(OmnixMatterDevice.fromJson(record.toJson()).operational, isFalse);
    expect(
      () => OmnixMatterDevice.fromJson({'node_id': 'oops'}),
      throwsFormatException,
    );
  });
  test('consent and pending checks do not invoke native commands', () async {
    final transport = FakeMatterTransport();
    final controller = await OmnixMatterController.open(
      directory: 'private',
      transport: transport,
    );
    await expectLater(
      controller.commissionSimulator(
        address: '::1',
        passcode: 20202021,
        name: 'Light',
      ),
      throwsStateError,
    );
    await expectLater(
      controller.readOnOff(
        const OmnixMatterDevice(
          nodeId: '112234',
          name: 'Light',
          endpoint: 1,
          operational: false,
        ),
      ),
      throwsStateError,
    );
    expect(transport.calls, isEmpty);
    await controller.close();
  });
  test(
    'close drains accepted work, rejects new work and is idempotent',
    () async {
      final transport = FakeMatterTransport()..pending = Completer<void>();
      final controller = await OmnixMatterController.open(
        directory: 'private',
        transport: transport,
      );
      final read = controller.readOnOff(
        const OmnixMatterDevice(nodeId: '112234', name: 'Light', endpoint: 1),
      );
      final close = controller.close();
      await expectLater(controller.devices(), throwsStateError);
      expect(transport.closes, 0);
      transport.pending!.complete();
      expect(await read, isTrue);
      await close;
      await controller.close();
      expect(transport.closes, 1);
    },
  );
  test('lists immutable native records', () async {
    final controller = await OmnixMatterController.open(
      directory: 'private',
      transport: FakeMatterTransport(),
    );
    final devices = await controller.devices();
    expect(devices.single.nodeId, '112234');
    expect(() => devices.clear(), throwsUnsupportedError);
    await controller.close();
  });
}
