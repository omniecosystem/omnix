// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'dart:async';
import 'dart:convert';
import 'package:omnix_storage/omnix_storage.dart';
import 'package:test/test.dart';

class _Transport implements OmnixVectorTransport {
  int opens = 0;
  int closes = 0;
  bool fail = false;
  final calls = <String>[];
  final payloads = <Map<String, dynamic>>[];
  Completer<void>? block;
  @override
  Future<BigInt> open(String path, String profile) async {
    opens++;
    expect(jsonDecode(profile), {'id': 'test-space-v1', 'dimension': 2});
    return BigInt.one;
  }

  @override
  Future<String> request(
    BigInt handle,
    String operation,
    String payload,
  ) async {
    calls.add(operation);
    payloads.add(jsonDecode(payload) as Map<String, dynamic>);
    await block?.future;
    if (fail) {
      fail = false;
      throw StateError('injected failure');
    }
    return operation == 'search'
        ? '[{"id":1,"score":0.9,"metadata":{"source":"note"}}]'
        : 'null';
  }

  @override
  Future<void> close(BigInt handle) async {
    closes++;
  }
}

OmnixVectorStore _store(_Transport transport) => OmnixVectorStore(
  path: 'isolated-test-shard',
  profile: OmnixVectorProfile(id: 'test-space-v1', dimension: 2),
  transport: transport,
);

void main() {
  test('one connection, owned inputs and filtered typed results', () async {
    final transport = _Transport();
    final store = _store(transport);
    final metadata = <String, Object?>{'source': 'original'};
    final embedding = [1.0, 0.0];
    final write = store.upsert(
      id: BigInt.one,
      embedding: embedding,
      metadata: metadata,
    );
    metadata['source'] = 'modified';
    embedding[0] = 0;
    await write;
    expect(transport.payloads.first['metadata'], {'source': 'original'});
    expect(transport.payloads.first['vector'], [1.0, 0.0]);
    final hits = await store.searchSimilar(
      queryEmbedding: [1, 0],
      filterField: 'source',
      filterValue: 'note',
    );
    expect(hits.single.id, BigInt.one);
    expect(hits.single.similarity, closeTo(0.9, 0.001));
    expect(hits.single.metadata['source'], 'note');
    expect(transport.payloads.last['filter'], {
      'field': 'source',
      'value': 'note',
    });
    await store.remove(BigInt.one);
    await store.flush();
    await store.close();
    await store.close();
    expect(transport.opens, 1);
    expect(transport.closes, 1);
    expect(transport.calls, ['upsert', 'search', 'delete', 'flush']);
    await expectLater(store.initialize(), throwsStateError);
  });
  test(
    'bad dimensions, finite values, zero vectors, IDs and limits are rejected before opening',
    () {
      final transport = _Transport();
      final store = _store(transport);
      for (final vector in <List<double>>[
        [1],
        [double.nan, 1],
        [0, 0],
      ]) {
        expect(
          () => store.searchSimilar(queryEmbedding: vector),
          throwsArgumentError,
        );
      }
      expect(() => store.remove(-BigInt.one), throwsArgumentError);
      expect(
        () => store.searchSimilar(queryEmbedding: [1, 0], topK: 0),
        throwsArgumentError,
      );
      expect(
        () =>
            store.searchSimilar(queryEmbedding: [1, 0], filterField: 'source'),
        throwsArgumentError,
      );
      expect(transport.opens, 0);
    },
  );
  test(
    'close drains accepted work and errors do not poison the queue',
    () async {
      final transport = _Transport();
      final store = _store(transport);
      transport.fail = true;
      await expectLater(store.flush(), throwsStateError);
      transport.block = Completer<void>();
      final write = store.upsert(id: BigInt.one, embedding: [1, 0]);
      final close = store.close();
      await expectLater(store.initialize(), throwsStateError);
      expect(transport.closes, 0);
      transport.block!.complete();
      await write;
      await close;
      expect(transport.closes, 1);
    },
  );
}
