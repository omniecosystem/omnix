// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'dart:io';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:omnix_storage/omnix_storage.dart';
import 'package:omnix_storage/src/rust/frb_generated.dart';
import 'package:test/test.dart';

void main() {
  final library = Platform.environment['OMNIX_STORAGE_VECTOR_LIBRARY'];
  test(
    'generated Dart bridge persists, filters and deletes real Qdrant vectors',
    () async {
      await RustLib.init(externalLibrary: ExternalLibrary.open(library!));
      final directory = await Directory.systemTemp.createTemp(
        'omnix-vector-dart-',
      );
      final profile = OmnixVectorProfile(id: 'isolated-dart-v1', dimension: 2);
      final store = OmnixVectorStore(path: directory.path, profile: profile);
      try {
        await store.upsert(
          id: BigInt.one,
          embedding: [1, 0],
          metadata: {'source': 'note'},
        );
        await store.close();
        final reopened = OmnixVectorStore(
          path: directory.path,
          profile: profile,
        );
        try {
          final hits = await reopened.searchSimilar(
            queryEmbedding: [1, 0],
            filterField: 'source',
            filterValue: 'note',
          );
          expect(hits.single.id, BigInt.one);
          expect(hits.single.metadata['source'], 'note');
          await reopened.remove(BigInt.one);
          expect(await reopened.searchSimilar(queryEmbedding: [1, 0]), isEmpty);
        } finally {
          await reopened.close();
        }
      } finally {
        await store.close();
        await directory.delete(recursive: true);
      }
    },
    skip: library == null
        ? 'Set OMNIX_STORAGE_VECTOR_LIBRARY to a Qdrant-enabled native bridge.'
        : false,
  );
}
