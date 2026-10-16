// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

const androidLiteRtLmSha256 =
    '276d3d50b2b9511e03c1cc136b5ad44d1e09a4e848c9dceefcaf63f8e0f6112b';
const androidLiteRtLmGpuSha256 =
    'f5ee2a511a64ffc4c4fc21bc5bcbb0935a49d6dcda2e528392a5a7e841e15b47';
const androidLiteRtLmLibraries = [
  'liblitert-lm.so',
  'libGemmaModelConstraintProvider.so',
];
const androidLiteRtLmGpuLibraries = [
  ...androidLiteRtLmLibraries,
  'libLiteRtGpuAccelerator.so',
  'libLiteRtOpenClAccelerator.so',
  'libLiteRtTopKOpenClSampler.so',
  'libLiteRtTopKWebGpuSampler.so',
  'libLiteRtWebGpuAccelerator.so',
  'libwebgpu_dawn.so',
];

List<String> androidLiteRtLmBundleLibraries(Object? backends) {
  final selected = backends ?? const ['cpu'];
  if (selected is! List ||
      selected.isEmpty ||
      selected.toSet().length != selected.length ||
      selected.any(
        (value) => value != 'cpu' && value != 'gpu' && value != 'npu',
      )) {
    throw ArgumentError(
      'litertlm_backends must select unique cpu, gpu or npu backends.',
    );
  }
  if (selected.contains('npu')) {
    throw UnsupportedError(
      'Automatic Android NPU packaging requires a separately qualified vendor distribution.',
    );
  }
  return selected.contains('gpu')
      ? androidLiteRtLmGpuLibraries
      : androidLiteRtLmLibraries;
}

Future<void> verifyAndroidLiteRtLmArchive(
  File archive, {
  Object? backends,
}) async {
  final libraries = androidLiteRtLmBundleLibraries(backends);
  final digest = await sha256.bind(archive.openRead()).first;
  _checkDigest(digest, libraries);
}

void _checkDigest(Digest digest, List<String> libraries) {
  final expected = libraries.contains('libLiteRtOpenClAccelerator.so')
      ? androidLiteRtLmGpuSha256
      : androidLiteRtLmSha256;
  if (digest.toString() != expected) {
    throw StateError(
      'Android LiteRT-LM checksum mismatch; refusing to bundle.',
    );
  }
}

Future<List<({String name, Uri file})>> prepareAndroidLiteRtLmBundle(
  Uri output, {
  required File sourceArchive,
  bool includeConstraintProvider = true,
  Object? backends,
}) async {
  // This candidate is not a public release. Never invent a download URL or
  // silently use a different ABI. The host supplies the pinned offline archive.
  final requiredLibraries = androidLiteRtLmBundleLibraries(backends);
  final bytes = await sourceArchive.readAsBytes();
  _checkDigest(sha256.convert(bytes), requiredLibraries);
  final archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
  final result = <({String name, Uri file})>[];
  for (final name in requiredLibraries) {
    if (!includeConstraintProvider &&
        name == 'libGemmaModelConstraintProvider.so') {
      continue;
    }
    final entries = archive.files
        .where(
          (entry) =>
              entry.name == './lib/arm64-v8a/$name' ||
              entry.name == 'lib/arm64-v8a/$name',
        )
        .toList();
    if (entries.length != 1 ||
        !entries.single.isFile ||
        entries.single.isSymbolicLink ||
        entries.single.content.isEmpty) {
      throw StateError('Android runtime archive lacks a regular $name.');
    }
    // Destinations come only from our allowlist, never archive entry paths.
    final destination = File.fromUri(output.resolve('android-runtime/$name'));
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(entries.single.content);
    result.add((name: name, file: destination.uri));
  }
  return result;
}
