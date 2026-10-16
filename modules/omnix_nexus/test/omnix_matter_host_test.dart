// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'package:omnix_nexus/omnix_nexus.dart';
import 'package:test/test.dart';
import '../hook/component_selection.dart';

class Host implements OmnixMatterHostTransport {
  bool on = false;
  int closes = 0;
  Completer<void>? pending;
  bool failClose = false;
  @override
  Future<void> setOnOff(bool value) async {
    await pending?.future;
    on = value;
  }

  @override
  Future<bool> readOnOff() async => on;
  @override
  Future<void> close() async {
    closes++;
    if (failClose) throw StateError('Shutdown failed');
  }
}

void main() {
  test('platform overrides select hosts without changing independent A2A', () {
    final defines = <String, Object?>{
      'protocols': ['a2a', 'matter'],
      'android': <String, Object?>{'matter_backend': 'android_host'},
      'windows': <String, Object?>{'matter_backend': 'windows_qualification'},
    };
    expect(selectNexusFeatures(defines, android: true), [
      'a2a',
      'matter-android',
    ]);
    expect(selectNexusFeatures(defines, windows: true), [
      'a2a',
      'matter-process',
    ]);
    expect(selectNexusFeatures(defines), ['a2a', 'matter']);
  });
  test('Android host selection is explicit and platform bounded', () {
    expect(
      selectNexusFeatures({
        'protocols': ['matter'],
        'matter_backend': 'android_host',
      }, android: true),
      ['matter-android'],
    );
    expect(
      () => selectNexusFeatures({
        'protocols': ['matter'],
        'matter_backend': 'android_host',
      }, windows: true),
      throwsArgumentError,
    );
    expect(
      selectNexusFeatures({
        'protocols': ['a2a', 'matter'],
        'matter_backend': 'android_host',
      }, android: true),
      ['a2a', 'matter-android'],
    );
  });
  test(
    'explicit Windows host selection does not enable experimental Matter',
    () {
      final defines = <String, Object?>{
        'protocols': ['matter'],
        'matter_backend': 'windows_qualification',
      };
      expect(selectNexusFeatures(defines, windows: true), ['matter-process']);
      expect(() => selectNexusFeatures(defines), throwsArgumentError);
      expect(
        () => selectNexusFeatures({
          'protocols': ['a2a'],
          'matter_backend': 'windows_qualification',
        }, windows: true),
        throwsArgumentError,
      );
      expect(
        selectNexusFeatures({
          'protocols': ['matter'],
        }),
        ['matter'],
      );
    },
  );
  test('commands, readback, and idempotent close', () async {
    final transport = Host();
    final host = OmnixMatterHost.fromTransport(transport);
    await host.setOnOff(on: true);
    expect(await host.readOnOff(), isTrue);
    await host.close();
    await host.close();
    expect(transport.closes, 1);
    await expectLater(host.readOnOff(), throwsStateError);
  });
  test(
    'busy calls and close are rejected without abandoning active command',
    () async {
      final transport = Host()..pending = Completer<void>();
      final host = OmnixMatterHost.fromTransport(transport);
      final command = host.setOnOff(on: true);
      await expectLater(host.readOnOff(), throwsStateError);
      await expectLater(host.close(), throwsStateError);
      expect(transport.closes, 0);
      transport.pending!.complete();
      await command;
      await host.close();
    },
  );
  test('failed shutdown is reported and prevents further commands', () async {
    final transport = Host()..failClose = true;
    final host = OmnixMatterHost.fromTransport(transport);
    await expectLater(host.close(), throwsStateError);
    await expectLater(host.readOnOff(), throwsStateError);
    await expectLater(host.close(), throwsStateError);
    expect(transport.closes, 1);
  });
}
