// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'package:test/test.dart';
import '../hook/android_litertlm_bundle.dart';
import '../hook/runtime_selection.dart';

void main() {
  test('Android acceleration packaging is explicit and symmetric', () {
    expect(androidLiteRtLmBundleLibraries(null), androidLiteRtLmLibraries);
    expect(androidLiteRtLmBundleLibraries(['cpu']), androidLiteRtLmLibraries);
    expect(
      androidLiteRtLmBundleLibraries(['gpu']),
      androidLiteRtLmGpuLibraries,
    );
    expect(
      androidLiteRtLmBundleLibraries(['cpu', 'gpu']),
      androidLiteRtLmGpuLibraries,
    );
    for (final invalid in [
      [],
      ['cpu', 'cpu'],
      ['unknown'],
      'gpu',
    ]) {
      expect(
        () => androidLiteRtLmBundleLibraries(invalid),
        throwsArgumentError,
      );
    }
    expect(
      () => androidLiteRtLmBundleLibraries(['npu']),
      throwsUnsupportedError,
    );
  });

  final gpuArchive = Platform.environment['OMNIX_TEST_ANDROID_GPU_ARCHIVE'];
  test(
    'verified GPU archive contains all eight native libraries',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'omnix-android-gpu-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final libraries = await prepareAndroidLiteRtLmBundle(
        directory.uri,
        sourceArchive: File(gpuArchive!),
        backends: ['cpu', 'gpu'],
      );
      expect(
        libraries.map((library) => library.name),
        androidLiteRtLmGpuLibraries,
      );
      for (final library in libraries) {
        expect((await File.fromUri(library.file).readAsBytes()).take(4), [
          0x7f,
          0x45,
          0x4c,
          0x46,
        ]);
      }
    },
    skip: gpuArchive == null,
  );

  final archiveOverride = Platform.environment['OMNIX_TEST_ANDROID_ARCHIVE'];
  final candidate = archiveOverride != null
      ? File(archiveOverride)
      : File.fromUri(
          Directory.current.uri.resolve(
            '.local-native/litertlm-android-0.18.0.tar.gz',
          ),
        );
  test(
    'CPU archive cannot masquerade as a GPU distribution',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'omnix-android-profile-',
      );
      addTearDown(() => directory.delete(recursive: true));
      await expectLater(
        prepareAndroidLiteRtLmBundle(
          directory.uri,
          sourceArchive: candidate,
          backends: ['gpu'],
        ),
        throwsStateError,
      );
      expect(directory.listSync(), isEmpty);
    },
    skip: !candidate.existsSync(),
  );
  test(
    'pinned candidate extracts exactly its two runtime libraries',
    () async {
      final directory = await Directory.systemTemp.createTemp('omnix-bundle-');
      addTearDown(() => directory.delete(recursive: true));
      final libraries = await prepareAndroidLiteRtLmBundle(
        directory.uri,
        sourceArchive: candidate,
      );
      expect(
        libraries.map((library) => library.name),
        androidLiteRtLmLibraries,
      );
      for (final library in libraries) {
        final bytes = await File.fromUri(library.file).readAsBytes();
        expect(bytes.take(4), [0x7f, 0x45, 0x4c, 0x46]);
      }
    },
    skip: !candidate.existsSync()
        ? 'Pinned local qualification archive absent'
        : false,
  );
  test('rejects an untrusted Android runtime before extraction', () async {
    final directory = await Directory.systemTemp.createTemp('omnix-archive-');
    addTearDown(() => directory.delete(recursive: true));
    final archive = File.fromUri(directory.uri.resolve('invalid.tar.gz'));
    await archive.writeAsBytes([1, 2, 3]);
    await expectLater(
      prepareAndroidLiteRtLmBundle(directory.uri, sourceArchive: archive),
      throwsStateError,
    );
    expect(
      await Directory.fromUri(
        directory.uri.resolve('android-runtime/'),
      ).exists(),
      isFalse,
    );
  });
  test(
    'external constraint owner bundles only the pinned engine',
    () async {
      final directory = await Directory.systemTemp.createTemp('omnix-engine-');
      addTearDown(() => directory.delete(recursive: true));
      final libraries = await prepareAndroidLiteRtLmBundle(
        directory.uri,
        sourceArchive: candidate,
        includeConstraintProvider: false,
      );
      expect(libraries.map((library) => library.name), ['liblitert-lm.so']);
      expect(
        File.fromUri(
          directory.uri.resolve(
            'android-runtime/libGemmaModelConstraintProvider.so',
          ),
        ).existsSync(),
        isFalse,
      );
    },
    skip: !candidate.existsSync()
        ? 'Pinned local qualification archive absent'
        : false,
  );
  test('platform selection is explicit and leaves Windows unchanged', () {
    final defines = <String, Object?>{
      'runtimes': ['litertlm', 'llamacpp'],
      'embeddings': true,
      'android': {
        'runtimes': ['litertlm'],
        'embeddings': false,
      },
    };
    expect(coreTargetDefines(defines, 'windows')['runtimes'], [
      'litertlm',
      'llamacpp',
    ]);
    final android = coreTargetDefines(defines, 'android');
    expect(selectRuntimeFeatures(android), ['litertlm']);
    expect(android['embeddings'], false);
    expect(defines['embeddings'], true);
  });
  test('rejects malformed platform configuration', () {
    expect(
      () => coreTargetDefines({'android': true}, 'android'),
      throwsArgumentError,
    );
    expect(
      () => coreTargetDefines({
        'android': {'unknown': true},
      }, 'android'),
      throwsArgumentError,
    );
  });
}
