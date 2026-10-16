// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

const embeddingEngineWindowsSha256 =
    'eb02dc5d0fc6a894a664cfcc63e3aaf3100973ba2c9a6a7eebf4df8749a01038';
const _url =
    'https://files.pythonhosted.org/packages/2e/a4/842c858a90aac25a2ae6e4744197b22764a38fb35e45b15cf9c3b7570656/litert_lm_api-0.18.0-py3-none-win_amd64.whl';

// Extract only the CPU library from Google's wheel. No Python code or runtime,
// GPU compiler, NPU dispatch library, or model weights enter the app bundle.
Future<List<({String name, Uri file})>> prepareEmbeddingEngineBundle(
  Uri output, {
  File? sourceArchive,
}) async {
  final archive = File.fromUri(output.resolve('litertlm-embedding-0.18.0.whl'));
  await archive.parent.create(recursive: true);
  if (sourceArchive != null) {
    await verifyEmbeddingEngineArchive(sourceArchive);
    await sourceArchive.copy(archive.path);
  }
  if (!await archive.exists()) {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    final temporary = File.fromUri(
      output.resolve('litertlm-embedding.download'),
    );
    try {
      final request = await client
          .getUrl(Uri.parse(_url))
          .timeout(const Duration(seconds: 30));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw StateError(
          'Embedding runtime download failed: HTTP ${response.statusCode}',
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
                  'Embedding runtime download exceeded five minutes',
                );
              },
            );
      } finally {
        await sink.close();
      }
      await verifyEmbeddingEngineArchive(temporary);
      await temporary.rename(archive.path);
    } finally {
      client.close(force: true);
      if (await temporary.exists()) await temporary.delete();
    }
  }
  await verifyEmbeddingEngineArchive(archive);
  final files = ZipDecoder()
      .decodeBytes(await archive.readAsBytes())
      .files
      .where((entry) => entry.name == 'litert_lm/litert-lm.dll')
      .toList();
  if (files.length != 1 ||
      !files.single.isFile ||
      files.single.isSymbolicLink) {
    throw StateError(
      'Embedding runtime archive lacks the expected CPU library',
    );
  }
  final destination = File.fromUri(
    output.resolve('embedding-engine/litert-lm.dll'),
  );
  await destination.parent.create(recursive: true);
  await destination.writeAsBytes(files.single.content);
  return [(name: 'litert-lm.dll', file: destination.uri)];
}

Future<void> verifyEmbeddingEngineArchive(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  if (digest.toString() != embeddingEngineWindowsSha256) {
    throw StateError('Embedding runtime checksum mismatch; refusing to bundle');
  }
}
