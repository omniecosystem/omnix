// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import '../hook/litertlm_bundle.dart';

void main() {
  final verifiedArchive = Platform.environment['OMNIX_CORE_LITERTLM_ARCHIVE'];
  test(
    'accelerator packaging is explicit and never silently substitutes CPU',
    () {
      expect(liteRtLmBundleLibraries(null), liteRtLmCpuLibraries);
      expect(liteRtLmBundleLibraries(['gpu']), liteRtLmGpuLibraries);
      expect(liteRtLmBundleLibraries(['cpu', 'gpu']), liteRtLmGpuLibraries);
      expect(() => liteRtLmBundleLibraries(['npu']), throwsUnsupportedError);
      for (final value in [
        [],
        ['gpu', 'gpu'],
        ['other'],
        'gpu',
      ]) {
        expect(() => liteRtLmBundleLibraries(value), throwsArgumentError);
      }
    },
  );
  test(
    'verified GPU bundle contains the explicit dependency closure',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'omnix-gpu-assets-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final libraries = await prepareLiteRtLmBundle(
        directory.uri,
        sourceArchive: File(verifiedArchive!),
        backends: ['gpu'],
      );
      expect(libraries.map((item) => item.name).toSet(), liteRtLmGpuLibraries);
      expect(libraries.length, 8);
      expect(libraries.any((item) => item.name.contains('openvino')), isFalse);
    },
    skip: verifiedArchive == null,
  );
  test(
    'verified archive produces only the three CPU code assets',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'omnix-cpu-assets-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final libraries = await prepareLiteRtLmBundle(
        directory.uri,
        sourceArchive: File(verifiedArchive!),
      );
      expect(
        libraries.map((library) => library.name).toSet(),
        liteRtLmCpuLibraries,
      );
      expect(libraries.length, 3);
      for (final library in libraries) {
        expect(await File.fromUri(library.file).length(), greaterThan(0));
      }
    },
    skip: verifiedArchive == null
        ? 'Set the verified local archive to qualify extraction'
        : false,
  );
  test('Dart and Rust ship the same CPU-only dependency closure', () async {
    final library = await Isolate.resolvePackageUri(
      Uri.parse('package:omnix_core/omnix_core.dart'),
    );
    final manifest = await File(
      p.join(
        p.dirname(p.fromUri(library!)),
        '..',
        'rust',
        'backend',
        'build_support',
        'litertlm_windows_cpu.txt',
      ),
    ).readAsLines();
    expect(
      manifest.where((name) => name.isNotEmpty).toSet(),
      liteRtLmCpuLibraries,
    );
    expect(liteRtLmCpuLibraries.length, 3);
    expect(liteRtLmCpuLibraries, contains('libLiteRt.dll'));
    expect(
      liteRtLmCpuLibraries,
      contains('libGemmaModelConstraintProvider.dll'),
    );
  });
  test('rejects an untrusted archive before extraction or execution', () async {
    final directory = await Directory.systemTemp.createTemp('omnix-checksum-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File.fromUri(directory.uri.resolve('untrusted.tar.gz'));
    await file.writeAsString('not a trusted native runtime');
    await expectLater(verifyLiteRtLmArchive(file), throwsStateError);
    await expectLater(
      prepareLiteRtLmBundle(
        directory.uri.resolve('output/'),
        sourceArchive: file,
      ),
      throwsStateError,
    );
    expect(
      Directory.fromUri(directory.uri.resolve('output/litertlm/')).existsSync(),
      isFalse,
    );
  });
}
