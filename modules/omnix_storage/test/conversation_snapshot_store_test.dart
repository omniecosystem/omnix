import 'dart:async';

import 'package:omnix_storage/omnix_storage.dart';
import 'package:test/test.dart';

class _Transport implements OmnixStorageTransport {
  int opens = 0;
  int closes = 0;
  bool failWrite = false;
  Completer<void>? block;
  final values = <String, String>{};
  @override
  Future<BigInt> open(String path) async {
    opens++;
    return BigInt.one;
  }

  @override
  Future<String> request(BigInt id, String operation, String payload) async {
    await block?.future;
    switch (operation) {
      case 'read':
        return values[payload] ?? 'null';
      case 'records':
        return '[]';
      case 'write':
        if (failWrite) throw StateError('write failed');
        values['chat'] = payload;
        return 'null';
      case 'delete':
        values.remove(payload);
        return 'null';
      default:
        throw StateError('Unexpected operation');
    }
  }

  @override
  Future<void> close(BigInt id) async {
    closes++;
  }
}

void main() {
  test('lazy connection round-trips snapshots and deletes', () async {
    final transport = _Transport();
    final store = OmnixConversationSnapshotStore(
      path: 'test.sqlite',
      transport: transport,
    );
    await store.initialize();
    await store.initialize();
    await store.writeSerializedSnapshot('{"example":true}');
    expect(await store.readSerializedSnapshot('chat'), '{"example":true}');
    expect(await store.readSerializedRecords(), '[]');
    expect(transport.opens, 1);
    await store.delete('chat');
    expect(await store.readSerializedSnapshot('chat'), isNull);
    await store.close();
  });
  test('failure leaves the operation queue usable', () async {
    final transport = _Transport()..failWrite = true;
    final store = OmnixConversationSnapshotStore(
      path: 'test.sqlite',
      transport: transport,
    );
    await expectLater(store.writeSerializedSnapshot('{}'), throwsStateError);
    expect(await store.readSerializedSnapshot('missing'), isNull);
    await store.close();
  });
  test('close drains accepted work and rejects new requests', () async {
    final transport = _Transport()..block = Completer<void>();
    final store = OmnixConversationSnapshotStore(
      path: 'test.sqlite',
      transport: transport,
    );
    final pending = store.readSerializedSnapshot('chat');
    final closing = store.close();
    await expectLater(store.initialize(), throwsStateError);
    transport.block!.complete();
    expect(await pending, isNull);
    await closing;
    await store.close();
    expect(transport.closes, 1);
  });
  test('unused close never opens storage and blank paths fail', () async {
    final transport = _Transport();
    await OmnixConversationSnapshotStore(
      path: 'test.sqlite',
      transport: transport,
    ).close();
    expect(transport.opens, 0);
    expect(() => OmnixConversationSnapshotStore(path: ''), throwsArgumentError);
  });
}
