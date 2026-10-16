// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_core/model_installation_types.dart';
import 'package:omnix_example/features/core/presentation/controllers/model_library_controller.dart';
import 'package:omnix_example/features/core/presentation/widgets/model_library_panel.dart';

class FakeLibrary implements ModelLibraryBackend {
  final events = StreamController<OmnixInstallationProgress>.broadcast();
  List<OmnixInstalledModel> records = [];
  bool cancelled = false;
  OmnixModelSpec? requested;
  @override
  Future<List<OmnixInstalledModel>> installed() async => records;
  @override
  Stream<OmnixInstallationProgress> install(
    OmnixModelSpec spec,
    String source, {
    required bool network,
    String? token,
  }) {
    requested = spec;
    return events.stream;
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
  }

  @override
  Future<String?> pickFile() async => null;
}

class RecoverableLibrary extends FakeLibrary
    implements RecoverableModelLibraryBackend {
  int recoveries = 0;
  int backgrounds = 0;
  bool detached = false;
  @override
  Future<Stream<OmnixInstallationProgress>?> recover() async {
    recoveries++;
    return events.stream;
  }

  @override
  Future<void> background() async {
    backgrounds++;
  }

  @override
  Future<void> detach() async {
    detached = true;
    await events.close();
  }

  @override
  Future<void> resume() async => throw StateError('Cannot resume this task');
}

void main() {
  test(
    'concurrent recovery attaches once and close detaches without cancel',
    () async {
      final backend = RecoverableLibrary();
      final controller = ModelLibraryController(backend);
      await Future.wait([controller.initialize(), controller.initialize()]);
      expect(backend.recoveries, 1);
      expect(controller.busy, isTrue);
      await controller.background();
      expect(backend.backgrounds, 1);
      expect(backend.cancelled, isFalse);
      await controller.resume();
      expect(controller.error, contains('Cannot resume'));
      await controller.close();
      expect(backend.detached, isTrue);
      expect(backend.cancelled, isFalse);
      expect(controller.busy, isFalse);
      controller.dispose();
    },
  );
  test('model specification round trips without an authentication token', () {
    const spec = OmnixModelSpec(
      filename: 'model.litertlm',
      sha256: 'trusted',
      bytes: 123,
      role: 'chat',
    );
    final copy = OmnixModelSpec.fromJson(spec.toJson());
    expect(copy.filename, spec.filename);
    expect(copy.bytes, 123);
    expect(spec.toJson().containsKey('token'), isFalse);
  });
  test('failed installation does not become ready and busy recovers', () async {
    final backend = FakeLibrary();
    final controller = ModelLibraryController(backend);
    const spec = OmnixModelSpec(
      filename: 'model.litertlm',
      sha256: 'trusted',
      bytes: 123,
      role: 'chat',
    );
    final pending = controller.install(
      spec,
      'https://example.invalid/model',
      network: true,
    );
    expect(controller.busy, isTrue);
    backend.events.add(
      const OmnixInstallationProgress(
        phase: 'failed',
        received: 50,
        total: 123,
        error: 'SHA-256 mismatch',
      ),
    );
    await backend.events.close();
    await pending;
    expect(controller.busy, isFalse);
    expect(controller.models, isEmpty);
    expect(controller.error, 'SHA-256 mismatch');
    controller.dispose();
  });
  test('installation completes then reloads the durable catalog', () async {
    final backend = FakeLibrary();
    final controller = ModelLibraryController(backend);
    const spec = OmnixModelSpec(
      filename: 'model.litertlm',
      sha256: 'trusted',
      bytes: 123,
      role: 'chat',
    );
    final pending = controller.install(spec, '/host/file', network: false);
    backend.records = [
      const OmnixInstalledModel(spec: spec, path: '/private/model'),
    ];
    backend.events.add(
      const OmnixInstallationProgress(
        phase: 'installed',
        received: 123,
        total: 123,
        path: '/private/model',
        error: 'Installed; download-record cleanup needs attention.',
      ),
    );
    await backend.events.close();
    await pending;
    expect(controller.models.single.path, '/private/model');
    expect(controller.error, contains('cleanup needs attention'));
    expect(controller.busy, isFalse);
    controller.dispose();
  });
  testWidgets('preset fills trusted embedding metadata without downloading', (
    tester,
  ) async {
    final backend = FakeLibrary();
    final controller = ModelLibraryController(backend);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ModelLibraryPanel(controller: controller, onUse: (_) {}),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Fill EmbeddingGemma 2 · 165 MB'));
    await tester.pump();
    expect(find.text('embeddinggemma-2-text-270m.litertlm'), findsOneWidget);
    expect(find.text('164626432'), findsOneWidget);
    expect(backend.requested, isNull);
    expect(controller.busy, isFalse);
    await tester.pumpWidget(const SizedBox());
    await backend.events.close();
    controller.dispose();
  });
  testWidgets('shows a verified installation and selects its path', (
    tester,
  ) async {
    final backend = FakeLibrary();
    final controller = ModelLibraryController(backend);
    const spec = OmnixModelSpec(
      filename: 'test.litertlm',
      sha256: 'trusted',
      bytes: 100,
      role: 'chat',
    );
    controller.models = [
      const OmnixInstalledModel(spec: spec, path: '/private/test'),
    ];
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ModelLibraryPanel(
              controller: controller,
              onUse: (model) => selected = model.path,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Use'));
    expect(selected, '/private/test');
    await tester.pumpWidget(const SizedBox());
    await backend.events.close();
    controller.dispose();
  });
}
