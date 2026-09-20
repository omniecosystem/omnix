// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

bool get supportsModelArtifactVerification => true;

Future<void> verifyModelArtifact({
  required String path,
  required int expectedSize,
  required String expectedSha256,
}) async {
  final result = await Isolate.run(() async {
    final file = File(path);
    final length = await file.length();
    if (length != expectedSize) return 'size';
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == expectedSha256.toLowerCase()
        ? 'ok'
        : 'checksum';
  });

  switch (result) {
    case 'ok':
      return;
    case 'size':
      throw StateError('Downloaded model size does not match its manifest.');
    default:
      throw StateError('Downloaded model checksum verification failed.');
  }
}
