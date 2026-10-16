import 'dart:io';

import 'package:omnix_storage/omnix_storage.dart';
import 'package:path/path.dart' as p;

Future<String> runVectorNativeDemo() async {
  final directory = await Directory.systemTemp.createTemp(
    'omnix-storage-vector-example-',
  );
  final shardPath = p.join(directory.path, 'vectors');
  final profile = OmnixVectorProfile(id: 'fixture-v1', dimension: 3);
  final first = OmnixVectorStore(path: shardPath, profile: profile);
  OmnixVectorStore? reopened;
  try {
    await first.upsert(
      id: BigInt.one,
      embedding: [0.8, 0.6, 0],
      metadata: {'visibility': 'public', 'source': 'Public fixture'},
    );
    await first.upsert(
      id: BigInt.two,
      embedding: [1, 0, 0],
      metadata: {'visibility': 'private', 'source': 'Private fixture'},
    );
    await first.flush();
    await first.close();
    reopened = OmnixVectorStore(path: shardPath, profile: profile);
    final hits = await reopened.searchSimilar(
      queryEmbedding: [1, 0, 0],
      topK: 1,
      filterField: 'visibility',
      filterValue: 'public',
    );
    if (hits.length != 1 ||
        hits.single.id != BigInt.one ||
        hits.single.metadata['source'] != 'Public fixture' ||
        (hits.single.similarity - 0.8).abs() > 0.001) {
      throw StateError('Persisted vector/filter/provenance check failed.');
    }
    await reopened.remove(BigInt.one);
    await reopened.flush();
    await reopened.close();
    reopened = OmnixVectorStore(path: shardPath, profile: profile);
    final remaining = await reopened.searchSimilar(
      queryEmbedding: [1, 0, 0],
      filterField: 'visibility',
      filterValue: 'public',
    );
    if (remaining.isNotEmpty) {
      throw StateError('Deleted vector returned after reopen.');
    }
    return 'Qdrant: insert, flush, reopen, filtered retrieval with source, '
        'and durable deletion passed.';
  } finally {
    await reopened?.close();
    await first.close();
    // Only this invocation's disposable directory is removed.
    await directory.delete(recursive: true);
  }
}
