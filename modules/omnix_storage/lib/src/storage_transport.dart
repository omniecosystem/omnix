import 'rust/api/storage.dart' as native;
import 'rust_initialization.dart';

/// The transport to a single native Storage bridge and its handle registry.
///
/// Handles must not be transferred between different bridge libraries.
abstract interface class OmnixStorageTransport {
  /// Opens a dedicated, absolute database file path.
  Future<BigInt> open(String path);

  /// Executes a snapshot operation without exposing SQL.
  Future<String> request(BigInt id, String operation, String payload);

  /// Releases a handle owned by this transport.
  Future<void> close(BigInt id);
}

/// The native transport used by standalone and coordinated Storage consumers.
final class NativeOmnixStorageTransport implements OmnixStorageTransport {
  @override
  Future<BigInt> open(String path) async {
    await ensureRustInitialized();
    return native.storageOpen(path: path);
  }

  @override
  Future<String> request(BigInt id, String operation, String payload) =>
      native.storageRequest(id: id, operation: operation, payload: payload);

  @override
  Future<void> close(BigInt id) => native.storageClose(id: id);
}
