// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const liteRtLmWindowsSha256 =
    'e505e247b07313c05bbc957b7c33c82f6adb6c6c78eecae03a590319c7d049e2';
const _archiveUrl =
    'https://github.com/DenisovAV/flutter_gemma/releases/download/native-v0.17.1-a/litertlm-windows_x86_64.tar.gz';
// Keep in sync with backend/build_support/litertlm_windows_cpu.txt.
// Checked by the bundle manifest regression test.
const liteRtLmCpuLibraries = {
  'LiteRtLm.dll',
  'libLiteRt.dll',
  'libGemmaModelConstraintProvider.dll',
};

const liteRtLmGpuLibraries = {
  ...liteRtLmCpuLibraries,
  'libLiteRtWebGpuAccelerator.dll',
  'libLiteRtTopKWebGpuSampler.dll',
  'libwebgpu_dawn.dll',
  'dxcompiler.dll',
  'dxil.dll',
};

Set<String> liteRtLmBundleLibraries(Object? backends) {
  final selected = backends ?? const ['cpu'];
  if (selected is! List ||
      selected.isEmpty ||
      selected.toSet().length != selected.length ||
      selected.any((item) => item != 'cpu' && item != 'gpu' && item != 'npu')) {
    throw ArgumentError(
      'litertlm_backends must select unique cpu, gpu or npu backends.',
    );
  }
  if (selected.contains('npu')) {
    throw UnsupportedError(
      'Automatic Windows NPU packaging is not qualified. Supply a compatible vendor distribution externally.',
    );
  }
  return selected.contains('gpu') ? liteRtLmGpuLibraries : liteRtLmCpuLibraries;
}

// A pinned native distribution, not a dependency on its publisher's Dart API.
// See THIRD_PARTY_NOTICES.md for provenance and licenses.
Future<List<({String name, Uri file})>> prepareLiteRtLmBundle(
  Uri output, {
  File? sourceArchive,
  Object? backends,
}) async {
  final requiredNames = liteRtLmBundleLibraries(backends);
  final archiveFile = File.fromUri(output.resolve('litertlm-0.17.1-a.tar.gz'));
  await archiveFile.parent.create(recursive: true);
  if (sourceArchive != null) {
    await verifyLiteRtLmArchive(sourceArchive);
    await sourceArchive.copy(archiveFile.path);
  }
  if (!await archiveFile.exists()) {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    final temporary = File('${archiveFile.path}.download');
    try {
      final request = await client
          .getUrl(Uri.parse(_archiveUrl))
          .timeout(const Duration(seconds: 30));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw StateError(
          'LiteRT-LM download failed: HTTP ${response.statusCode}',
        );
      }
      final sink = temporary.openWrite();
      try {
        await sink
            .addStream(response.timeout(const Duration(seconds: 30)))
            .timeout(
              const Duration(minutes: 5),
              onTimeout: () {
                client.close(force: true);
                throw const HttpException(
                  'LiteRT-LM download exceeded five minutes',
                );
              },
            );
      } finally {
        await sink.close();
      }
      await verifyLiteRtLmArchive(temporary);
      await temporary.rename(archiveFile.path);
    } finally {
      client.close(force: true);
      if (await temporary.exists()) await temporary.delete();
    }
  }
  await verifyLiteRtLmArchive(archiveFile);
  final archive = TarDecoder().decodeBytes(
    GZipDecoder().decodeBytes(await archiveFile.readAsBytes()),
  );
  final destination = Directory.fromUri(output.resolve('litertlm/'));
  await destination.create(recursive: true);
  final libraries = <({String name, Uri file})>[];
  final names = <String>{};
  for (final entry in archive.files) {
    if (!entry.isFile || p.posix.extension(entry.name) != '.dll') continue;
    final name = p.posix.basename(entry.name);
    if (entry.isSymbolicLink || !names.add(name)) {
      throw StateError('Invalid LiteRT-LM archive entry: ${entry.name}');
    }
    if (!requiredNames.contains(name)) continue;
    // Flatten into the owned hook directory; no archive path is executed or
    // used as a destination. Siblings keep their upstream loader names.
    final file = File(p.join(destination.path, name));
    await file.writeAsBytes(entry.content);
    libraries.add((name: name, file: file.uri));
  }
  if (!names.containsAll(requiredNames)) {
    throw StateError('LiteRT-LM archive is missing required runtime libraries');
  }
  return libraries;
}

Future<void> verifyLiteRtLmArchive(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  if (digest.toString() != liteRtLmWindowsSha256) {
    throw StateError('LiteRT-LM archive checksum mismatch; refusing to bundle');
  }
}
