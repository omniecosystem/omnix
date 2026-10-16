// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_example/features/nexus/presentation/widgets/matter_host_panel.dart';

class FakeSession implements MatterDeviceSession {
  bool state = false;
  bool fail = false;
  bool closed = false;
  @override
  Future<void> setOnOff(bool on) async {
    if (fail) throw StateError('SDK unavailable');
    state = on;
  }

  @override
  Future<bool> readOnOff() async => state;
  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  testWidgets('consent, connection, commands and readback', (tester) async {
    final session = FakeSession();
    final model = MatterHostModel((_, _) async => session);
    addTearDown(model.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MatterHostPanel(
            model: model,
            backend: 'Windows · Matter.js',
            inputLabel: 'Bundle',
            android: false,
          ),
        ),
      ),
    );
    final connect = find.widgetWithText(FilledButton, 'Connect');
    expect(tester.widget<FilledButton>(connect).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(connect);
    await tester.pumpAndSettle();
    expect(find.text('Device state: Off'), findsOneWidget);
    await tester.ensureVisible(find.text('Turn on'));
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(find.text('Device state: On'), findsOneWidget);
    session.fail = true;
    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    expect(find.text('Device state: unknown'), findsOneWidget);
    expect(find.textContaining('SDK unavailable'), findsOneWidget);
    await tester.ensureVisible(find.text('Disconnect'));
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(session.closed, isTrue);
  });

  test('dispose during connect closes the arriving session', () async {
    final pending = Completer<MatterDeviceSession>();
    final session = FakeSession();
    final model = MatterHostModel((_, _) => pending.future);
    final connect = model.connect('', false);
    model.dispose();
    pending.complete(session);
    await connect;
    await Future<void>.delayed(Duration.zero);
    expect(session.closed, isTrue);
  });
}
