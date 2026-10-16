// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_nexus/omnix_nexus.dart';
import 'package:omnix_example/features/nexus/presentation/pages/matter_example_screen.dart';

const _light = OmnixMatterDevice(nodeId: '42', name: 'Test light', endpoint: 1);
const _network = MethodChannel('xyz.omniecosystem.omnix/matter_network');

class _FakeTransport implements OmnixMatterTransport {
  int opens = 0;
  int closes = 0;
  final events = <String>[];
  final requests = <({String operation, Map<String, dynamic> arguments})>[];
  List<OmnixMatterDevice> devices = [_light];
  String? failOperation;
  Completer<BigInt>? opening;
  Completer<String>? reading;
  Completer<void>? closing;

  Future<OmnixMatterController> openController() => OmnixMatterController.open(
    directory: 'unused-fake-directory',
    transport: this,
  );

  @override
  Future<BigInt> open(String directory) async {
    opens++;
    events.add('open');
    return opening == null ? BigInt.one : await opening!.future;
  }

  @override
  Future<String> request(BigInt id, String operation, String arguments) async {
    expect(id, BigInt.one);
    requests.add((
      operation: operation,
      arguments: jsonDecode(arguments) as Map<String, dynamic>,
    ));
    events.add(operation);
    if (operation == failOperation) {
      throw StateError('simulated $operation failure');
    }
    switch (operation) {
      case 'list':
        return jsonEncode(devices.map((device) => device.toJson()).toList());
      case 'commission':
        return jsonEncode(_light.toJson());
      case 'read':
        return reading == null ? 'true' : await reading!.future;
      case 'set':
        return 'null';
      default:
        throw StateError('Unexpected operation: $operation');
    }
  }

  @override
  Future<void> close(BigInt id) async {
    expect(id, BigInt.one);
    closes++;
    events.add('close');
    await closing?.future;
  }
}

Finder _button(String label) => find.widgetWithText(OutlinedButton, label);

bool _enabled(WidgetTester tester, String label) =>
    tester.widget<OutlinedButton>(_button(label)).onPressed != null;

Future<void> _show(
  WidgetTester tester,
  _FakeTransport transport, {
  Future<OmnixMatterController> Function()? opener,
}) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        body: MatterExampleScreen(
          openController: opener ?? transport.openController,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(
  WidgetTester tester,
  String label, {
  bool settle = true,
}) async {
  await tester.ensureVisible(_button(label));
  await tester.tap(_button(label));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _startAndLoad(
  WidgetTester tester,
  _FakeTransport transport,
) async {
  await _show(tester, transport);
  await _tap(tester, 'Start Controller');
  await _tap(tester, 'Reload devices');
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('does not open automatically and disables controls until start', (
    tester,
  ) async {
    final transport = _FakeTransport();
    await _show(tester, transport);
    expect(transport.opens, 0);
    expect(transport.requests, isEmpty);
    expect(_enabled(tester, 'Start Controller'), isTrue);
    expect(_enabled(tester, 'Reload devices'), isFalse);
    expect(_enabled(tester, 'Stop Controller'), isFalse);
    expect(_enabled(tester, 'Pair software light'), isFalse);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField).first).enabled,
      isFalse,
    );
    await _tap(tester, 'Start Controller');
    expect(transport.opens, 1);
    expect(transport.requests, isEmpty);
    expect(_enabled(tester, 'Reload devices'), isTrue);
    await _unmount(tester);
    expect(transport.closes, 1);
  });

  for (final address in ['::1', '[::1]:5541']) {
    testWidgets(
      'pairing $address requires consent and sends explicit consent JSON',
      (tester) async {
        final transport = _FakeTransport();
        await _show(tester, transport);
        await _tap(tester, 'Start Controller');
        await tester.enterText(find.byType(TextFormField).at(0), address);
        expect(_enabled(tester, 'Pair software light'), isFalse);
        await _tap(tester, 'Pair software light');
        expect(transport.requests, isEmpty);
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        expect(_enabled(tester, 'Pair software light'), isTrue);
        await _tap(tester, 'Pair software light');
        expect(transport.requests.single.operation, 'commission');
        expect(transport.requests.single.arguments, {
          'address': address == '::1' ? '[::1]:5540' : address,
          'passcode': 20202021,
          'name': 'Software light',
          'simulatorConsent': true,
        });
        expect(find.textContaining('On/off: unknown'), findsOneWidget);
        await _unmount(tester);
      },
    );
  }

  testWidgets('reads actual state and sends explicit on/off commands', (
    tester,
  ) async {
    final transport = _FakeTransport();
    await _startAndLoad(tester, transport);
    expect(find.textContaining('On/off: unknown'), findsOneWidget);
    await _tap(tester, 'Read on/off');
    expect(find.text('Last read: on'), findsOneWidget);
    await _tap(tester, 'Turn off');
    expect(find.text('Last read: off'), findsNothing);
    expect(find.textContaining('On/off: unknown'), findsOneWidget);
    await _tap(tester, 'Turn on');
    expect(transport.requests.map((request) => request.operation), [
      'list',
      'read',
      'set',
      'set',
    ]);
    expect(transport.requests[1].arguments, {'nodeId': '42'});
    expect(transport.requests[2].arguments, {'nodeId': '42', 'on': false});
    expect(transport.requests[3].arguments, {'nodeId': '42', 'on': true});
    await _unmount(tester);
  });

  testWidgets('incomplete pairing disables all device commands', (
    tester,
  ) async {
    final transport = _FakeTransport()
      ..devices = [
        const OmnixMatterDevice(
          nodeId: '42',
          name: 'Pending light',
          endpoint: 1,
          operational: false,
        ),
      ];
    await _startAndLoad(tester, transport);
    expect(find.textContaining('Incomplete pairing'), findsOneWidget);
    for (final label in ['Read on/off', 'Turn on', 'Turn off']) {
      expect(_enabled(tester, label), isFalse);
      await _tap(tester, label);
    }
    expect(transport.requests.single.operation, 'list');
    await _unmount(tester);
  });

  testWidgets('stop disables commands immediately and drains an active read', (
    tester,
  ) async {
    final transport = _FakeTransport()..reading = Completer<String>();
    await _startAndLoad(tester, transport);
    await _tap(tester, 'Read on/off', settle: false);
    expect(_enabled(tester, 'Turn on'), isFalse);
    expect(_enabled(tester, 'Reload devices'), isFalse);
    await _tap(tester, 'Stop Controller', settle: false);
    expect(find.text('Stopping controller…'), findsOneWidget);
    expect(transport.closes, 0);
    expect(_enabled(tester, 'Stop Controller'), isFalse);
    await _tap(tester, 'Turn on', settle: false);
    transport.reading!.complete('true');
    await tester.pumpAndSettle();
    expect(transport.closes, 1);
    expect(transport.requests.map((request) => request.operation), [
      'list',
      'read',
    ]);
    expect(find.text('Last read: on'), findsNothing);
    expect(_enabled(tester, 'Reload devices'), isFalse);
    expect(_enabled(tester, 'Start Controller'), isTrue);
    await _unmount(tester);
    expect(transport.closes, 1);
  });

  testWidgets('command errors are visible and controls recover', (
    tester,
  ) async {
    final transport = _FakeTransport()..failOperation = 'read';
    await _startAndLoad(tester, transport);
    await _tap(tester, 'Read on/off');
    expect(find.textContaining('simulated read failure'), findsOneWidget);
    expect(find.textContaining('On/off: unknown'), findsOneWidget);
    expect(_enabled(tester, 'Read on/off'), isTrue);
    transport.failOperation = null;
    await _tap(tester, 'Read on/off');
    expect(find.textContaining('simulated read failure'), findsNothing);
    expect(find.text('Last read: on'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('pause closes and resume requires an explicit restart', (
    tester,
  ) async {
    final transport = _FakeTransport();
    await _startAndLoad(tester, transport);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    // Paused applications no longer schedule frames; drain shutdown separately.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pumpAndSettle();
    expect(transport.closes, 1);
    expect(_enabled(tester, 'Start Controller'), isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(transport.opens, 1);
    expect(_enabled(tester, 'Start Controller'), isTrue);
    expect(_enabled(tester, 'Reload devices'), isFalse);
    await _unmount(tester);
  });

  testWidgets(
    'dispose during open closes the late controller without UI errors',
    (tester) async {
      final transport = _FakeTransport()..opening = Completer<BigInt>();
      await _show(tester, transport);
      await _tap(tester, 'Start Controller', settle: false);
      await tester.pumpWidget(const SizedBox.shrink());
      transport.opening!.complete(BigInt.one);
      await tester.pumpAndSettle();
      expect(transport.closes, 1);
      expect(transport.requests, isEmpty);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'Android acquire precedes open; overlapping stop/dispose releases once',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final transport = _FakeTransport()..closing = Completer<void>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_network, (
        call,
      ) async {
        transport.events.add(call.method);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _network,
          null,
        ),
      );
      await _show(tester, transport);
      expect(transport.events, isEmpty);
      await _tap(tester, 'Start Controller');
      expect(transport.events, ['acquire', 'open']);
      await _tap(tester, 'Stop Controller', settle: false);
      expect(_enabled(tester, 'Reload devices'), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      transport.closing!.complete();
      await tester.pumpAndSettle();
      expect(transport.events, ['acquire', 'open', 'close', 'release']);
      expect(transport.closes, 1);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('Android open failure releases the lock and renders its error', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final transport = _FakeTransport();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_network, (
      call,
    ) async {
      transport.events.add(call.method);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _network,
        null,
      ),
    );
    await _show(
      tester,
      transport,
      opener: () async {
        transport.events.add('failed-open');
        throw StateError('simulated open failure');
      },
    );
    await _tap(tester, 'Start Controller');
    expect(transport.events, ['acquire', 'failed-open', 'release']);
    expect(find.textContaining('simulated open failure'), findsOneWidget);
    expect(_enabled(tester, 'Start Controller'), isTrue);
    expect(_enabled(tester, 'Reload devices'), isFalse);
    await _unmount(tester);
    expect(transport.events.where((event) => event == 'release'), hasLength(1));
  });
}
