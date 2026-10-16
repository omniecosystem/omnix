import 'storage_transport.dart';

/// A serialized, Rust-owned SQLite store for versioned conversation snapshots.
///
/// Uses the existing version-1 JSON snapshot format, not arbitrary SQL or vector
/// storage. The host supplies a private absolute file path. Databases are not
/// encrypted; browsers are unsupported. Existing host databases are not migrated.
final class OmnixConversationSnapshotStore {
  /// Creates a lazy connection to [path] with an optional test transport.
  OmnixConversationSnapshotStore({
    required String path,
    OmnixStorageTransport? transport,
  }) : _path = path,
       _transport = transport ?? NativeOmnixStorageTransport() {
    if (path.trim().isEmpty) throw ArgumentError.value(path, 'path');
  }

  final String _path;
  final OmnixStorageTransport _transport;
  BigInt? _id;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closing;

  Future<T> _enqueue<T>(Future<T> Function() action) {
    if (_closing != null) {
      return Future<T>.error(StateError('Snapshot store is closed.'));
    }
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _open() async {
    _id ??= await _transport.open(_path);
  }

  Future<String> _request(String operation, String payload) async {
    await _open();
    return _transport.request(_id!, operation, payload);
  }

  /// Opens the dedicated database once, before the first operation if requested.
  Future<void> initialize() => _enqueue(_open);

  /// Returns a JSON array of conversation metadata, newest update first.
  Future<String> readSerializedRecords() =>
      _enqueue(() => _request('records', ''));

  /// Returns a complete JSON snapshot, or `null` when [conversationId] is absent.
  Future<String?> readSerializedSnapshot(String conversationId) =>
      _enqueue(() async {
        final result = await _request('read', conversationId);
        return result == 'null' ? null : result;
      });

  /// Atomically writes a version-1 JSON [snapshot], validated by Rust.
  Future<void> writeSerializedSnapshot(String snapshot) => _enqueue(() async {
    await _request('write', snapshot);
  });

  /// Deletes the snapshot for [conversationId], if present.
  Future<void> delete(String conversationId) => _enqueue(() async {
    await _request('delete', conversationId);
  });

  /// Drains accepted operations and releases the connection exactly once.
  Future<void> close() => _closing ??= _tail.then((_) async {
    final id = _id;
    if (id != null) await _transport.close(id);
  });
}
