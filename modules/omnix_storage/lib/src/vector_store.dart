// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'rust/api/vector.dart' as native;
import 'rust_initialization.dart';

final class OmnixVectorProfile {
  OmnixVectorProfile({required this.id, required this.dimension}) {
    if (id.trim().isEmpty || dimension < 1) {
      throw ArgumentError(
        'A nonempty embedding identity and dimension are required.',
      );
    }
  }
  final String id;
  final int dimension;
  Map<String, Object?> toJson() => {'id': id, 'dimension': dimension};
}

final class OmnixVectorHit {
  OmnixVectorHit.fromJson(Map<String, dynamic> json)
    : id = BigInt.parse(json['id'].toString()),
      similarity = (json['score'] as num).toDouble(),
      metadata = Map<String, Object?>.unmodifiable(
        json['metadata'] as Map<String, dynamic>,
      );
  final BigInt id;
  final double similarity;
  final Map<String, Object?> metadata;
}

abstract interface class OmnixVectorTransport {
  Future<BigInt> open(String path, String profile);
  Future<String> request(BigInt handle, String operation, String payload);
  Future<void> close(BigInt handle);
}

final class NativeOmnixVectorTransport implements OmnixVectorTransport {
  @override
  Future<BigInt> open(String path, String profile) async {
    await ensureRustInitialized();
    return native.vectorOpen(path: path, profile: profile);
  }

  @override
  Future<String> request(BigInt handle, String operation, String payload) =>
      native.vectorRequest(id: handle, operation: operation, payload: payload);
  @override
  Future<void> close(BigInt handle) => native.vectorClose(id: handle);
}

final class OmnixVectorStore {
  OmnixVectorStore({
    required this.path,
    required this.profile,
    OmnixVectorTransport? transport,
  }) : _transport = transport ?? NativeOmnixVectorTransport() {
    if (path.trim().isEmpty) throw ArgumentError.value(path, 'path');
  }
  final String path;
  final OmnixVectorProfile profile;
  final OmnixVectorTransport _transport;
  BigInt? _handle;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closing;

  Future<T> _enqueue<T>(Future<T> Function() action) {
    if (_closing != null) {
      return Future<T>.error(StateError('Vector store is closed.'));
    }
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _open() async {
    _handle ??= await _transport.open(path, jsonEncode(profile.toJson()));
  }

  Future<String> _request(String operation, Map<String, Object?> data) async {
    await _open();
    return _transport.request(_handle!, operation, jsonEncode(data));
  }

  List<double> _vector(List<double> vector) {
    if (vector.length != profile.dimension ||
        vector.any((v) => !v.isFinite) ||
        vector.every((v) => v == 0)) {
      throw ArgumentError(
        'Expected a finite, nonzero ${profile.dimension}-dimensional vector.',
      );
    }
    return List<double>.of(vector);
  }

  int _pointId(BigInt id) {
    if (id.isNegative || id > BigInt.parse('18446744073709551615')) {
      throw ArgumentError.value(id, 'id', 'Expected an unsigned 64-bit ID.');
    }
    // Native targets have 64-bit integer JSON support; web is unsupported.
    if (id > BigInt.from(9223372036854775807)) {
      throw ArgumentError.value(
        id,
        'id',
        'Dart API currently supports signed 63-bit nonnegative IDs.',
      );
    }
    return id.toInt();
  }

  Future<void> initialize() => _enqueue(_open);
  Future<void> upsert({
    required BigInt id,
    required List<double> embedding,
    Map<String, Object?> metadata = const {},
  }) {
    final payload = {
      'id': _pointId(id),
      'vector': _vector(embedding),
      'metadata': metadata,
    };
    // Freeze caller-owned collections before enqueueing.
    final encoded = jsonEncode(payload);
    return _enqueue(() async {
      await _open();
      await _transport.request(_handle!, 'upsert', encoded);
    });
  }

  Future<List<OmnixVectorHit>> searchSimilar({
    required List<double> queryEmbedding,
    int topK = 5,
    String? filterField,
    String? filterValue,
  }) {
    if (topK < 1 || topK > 1000) throw ArgumentError.value(topK, 'topK');
    if ((filterField == null) != (filterValue == null)) {
      throw ArgumentError('Both filter field and value are required.');
    }
    final vector = _vector(queryEmbedding);
    return _enqueue(() async {
      final result = await _request('search', {
        'vector': vector,
        'limit': topK,
        if (filterField != null)
          'filter': {'field': filterField, 'value': filterValue},
      });
      return (jsonDecode(result) as List)
          .map((hit) => OmnixVectorHit.fromJson(hit as Map<String, dynamic>))
          .toList(growable: false);
    });
  }

  Future<void> remove(BigInt id) {
    final pointId = _pointId(id);
    return _enqueue(() async {
      await _request('delete', {'id': pointId});
    });
  }

  Future<void> flush() => _enqueue(() async {
    await _request('flush', {});
  });
  Future<Map<String, Object?>?> readMetadata(BigInt id) {
    final pointId = _pointId(id);
    return _enqueue(() async {
      final value = jsonDecode(await _request('metadata', {'id': pointId}));
      return value == null ? null : Map<String, Object?>.from(value as Map);
    });
  }

  Future<void> clear() => _enqueue(() async {
    await _request('clear', {});
  });
  Future<void> close() => _closing ??= _tail.then((_) async {
    final handle = _handle;
    if (handle != null) await _transport.close(handle);
  });
}
