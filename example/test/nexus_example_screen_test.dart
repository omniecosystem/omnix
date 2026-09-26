// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/nexus_example_screen.dart';
import 'package:omnix_example/nexus_panel_view.dart';

class _FakeGateway implements NexusExampleGateway {
  String? identity;
  String? allowedKey;
  String? deniedKey;
  String? sharedOrigin;
  NexusDemoFixture? fixture;
  String? askedOrigin;
  String? askedQuestion;
  bool stopped = false;

  @override
  Future<String?> existingPublicKey() async => identity;

  @override
  Future<String> createIdentity() async => identity = 'a' * 64;

  @override
  Future<void> allowPeer(String key) async => allowedKey = key;

  @override
  Future<void> denyPeer(String key) async => deniedKey = key;

  @override
  Future<OmnixNexusListener> startSharing(
    String origin,
    NexusDemoFixture selectedFixture,
  ) async {
    sharedOrigin = origin;
    fixture = selectedFixture;
    return OmnixNexusListener(() async => stopped = true, port: 46137);
  }

  @override
  Future<OmnixNodeKnowledgeReply> ask(String origin, String question) async {
    askedOrigin = origin;
    askedQuestion = question;
    return const OmnixNodeKnowledgeReply(
      taskId: 'demo-task',
      texts: ['A public answer.'],
    );
  }
}

Future<void> _show(WidgetTester tester, _FakeGateway gateway) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NexusExampleScreen(gateway: gateway, supported: true),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _visible(WidgetTester tester, String key) async {
  final target = find.byKey(Key(key));
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      280,
      scrollable: find.descendant(
        of: find.byType(NexusPanelView),
        matching: find.byType(Scrollable),
      ).first,
    );
  } else {
    await tester.ensureVisible(target);
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sharing requires an explicit start and can be stopped', (
    tester,
  ) async {
    final gateway = _FakeGateway();
    await _show(tester, gateway);
    expect(gateway.sharedOrigin, isNull);

    await tester.tap(find.byKey(const Key('nexus-create-identity')));
    await tester.pumpAndSettle();
    expect(gateway.identity, hasLength(64));
    await _visible(tester, 'nexus-own-origin');
    await tester.enterText(
      find.byKey(const Key('nexus-own-origin')),
      'https://local.example',
    );
    await _visible(tester, 'nexus-toggle-sharing');
    await tester.tap(find.byKey(const Key('nexus-toggle-sharing')));
    await tester.pumpAndSettle();
    expect(gateway.sharedOrigin, 'https://local.example');
    expect(gateway.fixture, NexusDemoFixture.laptopA);

    await tester.tap(find.byKey(const Key('nexus-toggle-sharing')));
    await tester.pumpAndSettle();
    expect(gateway.stopped, isTrue);
  });

  testWidgets('grant, revoke, and remote query pass through the gateway', (
    tester,
  ) async {
    final gateway = _FakeGateway()..identity = 'a' * 64;
    await _show(tester, gateway);

    await _visible(tester, 'nexus-peer-key');
    await tester.enterText(find.byKey(const Key('nexus-peer-key')), 'b' * 64);
    await _visible(tester, 'nexus-allow');
    await tester.tap(find.byKey(const Key('nexus-allow')));
    await tester.pumpAndSettle();
    expect(gateway.allowedKey, 'b' * 64);

    await _visible(tester, 'nexus-deny');
    await tester.tap(find.byKey(const Key('nexus-deny')));
    await tester.pumpAndSettle();
    expect(gateway.deniedKey, 'b' * 64);

    await _visible(tester, 'nexus-remote-origin');
    await tester.enterText(
      find.byKey(const Key('nexus-remote-origin')),
      'https://peer.example',
    );
    await _visible(tester, 'nexus-question');
    await tester.enterText(find.byKey(const Key('nexus-question')), 'Omnixus');
    await _visible(tester, 'nexus-ask');
    await tester.tap(find.byKey(const Key('nexus-ask')));
    await tester.pumpAndSettle();
    expect(gateway.askedOrigin, 'https://peer.example');
    expect(gateway.askedQuestion, 'Omnixus');
    expect(find.text('A public answer.'), findsOneWidget);
  });

  testWidgets('rejects non-HTTPS origins before network access', (
    tester,
  ) async {
    final gateway = _FakeGateway()..identity = 'a' * 64;
    await _show(tester, gateway);
    await _visible(tester, 'nexus-remote-origin');
    await tester.enterText(
      find.byKey(const Key('nexus-remote-origin')),
      'http://peer.example',
    );
    await _visible(tester, 'nexus-question');
    await tester.enterText(find.byKey(const Key('nexus-question')), 'hello');
    await _visible(tester, 'nexus-ask');
    await tester.tap(find.byKey(const Key('nexus-ask')));
    await tester.pumpAndSettle();
    expect(gateway.askedOrigin, isNull);
    expect(find.textContaining('plain HTTPS origin'), findsOneWidget);
  });
}
