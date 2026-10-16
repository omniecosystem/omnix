// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'rust/api/matter.dart' as native;
import 'rust_initialization.dart';

/// A persisted pairing to a disposable Matter software device.
final class OmnixMatterDevice {
  /// Creates an immutable device record.
  const OmnixMatterDevice({
    required this.nodeId,
    required this.name,
    required this.endpoint,
    this.operational = true,
  });

  /// The fabric-local device identifier, encoded without numeric precision loss.
  final String nodeId;

  /// The host-supplied display name.
  final String name;

  /// The on/off cluster endpoint.
  final int endpoint;

  /// Whether secure commissioning completed successfully.
  final bool operational;

  /// Decodes a native device record.
  factory OmnixMatterDevice.fromJson(Map<String, dynamic> json) {
    final id = json['node_id'];
    final name = json['name'];
    final endpoint = json['endpoint'];
    final operational = json['operational'];
    if (id is! String ||
        BigInt.tryParse(id) == null ||
        name is! String ||
        endpoint is! int ||
        endpoint < 0 ||
        endpoint > 65535 ||
        operational is! bool) {
      throw const FormatException('Invalid Matter device record.');
    }
    return OmnixMatterDevice(
      nodeId: id,
      name: name,
      endpoint: endpoint,
      operational: operational,
    );
  }

  /// Encodes this record without controller secrets.
  Map<String, Object> toJson() => {
    'node_id': nodeId,
    'name': name,
    'endpoint': endpoint,
    'operational': operational,
  };
}

/// A replaceable native boundary for controller lifecycle and simulator commands.
abstract interface class OmnixMatterTransport {
  /// Opens the single-owner private state directory.
  Future<BigInt> open(String directory);

  /// Executes one bounded native command.
  Future<String> request(BigInt id, String operation, String arguments);

  /// Stops sockets and releases directory ownership.
  Future<void> close(BigInt id);
}

/// An opt-in, persistent controller for disposable software lights only.
///
/// Select `protocols: [matter]` with `matter_backend: experimental` in the
/// consuming application's `omnix_nexus` build-hook settings.
/// Production device attestation and OS-keychain storage are not implemented.
/// The state directory must be in private app storage, not a shared folder.
/// Hosts own Android multicast permission/lock management and must close on shutdown.
final class OmnixMatterController {
  OmnixMatterController._(this._transport, this._id);
  final OmnixMatterTransport _transport;
  final BigInt _id;
  Future<void> _tail = Future.value();
  Future<void>? _closing;

  /// Opens or restores simulator credentials without silently replacing them.
  static Future<OmnixMatterController> open({
    required String directory,
    OmnixMatterTransport? transport,
  }) async {
    if (directory.trim().isEmpty) {
      throw ArgumentError.value(directory, 'directory');
    }
    final backend = transport ?? _NativeMatterTransport();
    return OmnixMatterController._(backend, await backend.open(directory));
  }

  Future<T> _command<T>(
    String operation,
    Map<String, Object> arguments,
    T Function(Object?) decode,
  ) {
    if (_closing != null) {
      return Future.error(StateError('Matter controller is closed.'));
    }
    final result = _tail.then(
      (_) async => decode(
        jsonDecode(
          await _transport.request(_id, operation, jsonEncode(arguments)),
        ),
      ),
    );
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Lists persisted operational and pending pairings.
  Future<List<OmnixMatterDevice>> devices() => _command(
    'list',
    {},
    (json) => List.unmodifiable(
      (json as List<dynamic>).map(
        (item) => OmnixMatterDevice.fromJson(item as Map<String, dynamic>),
      ),
    ),
  );

  /// Commissions a disposable simulator after explicit host consent.
  ///
  /// [address] is a literal IPv6 address or a bracketed IPv6 socket address.
  /// The only supported fixture passcode is `20202021`. This operation bypasses
  /// attestation and must never be used as production device onboarding.
  Future<OmnixMatterDevice> commissionSimulator({
    required String address,
    required int passcode,
    required String name,
    bool simulatorConsent = false,
  }) {
    if (!simulatorConsent) {
      return Future.error(
        StateError('Explicit simulator consent is required.'),
      );
    }
    if (passcode != 20202021 || name.trim().isEmpty || name.length > 128) {
      return Future.error(
        ArgumentError('Use the disposable test fixture and a valid name.'),
      );
    }
    final socket = address.trim().startsWith('[')
        ? address.trim()
        : '[${address.trim()}]:5540';
    return _command(
      'commission',
      {
        'address': socket,
        'passcode': passcode,
        'name': name.trim(),
        'simulatorConsent': true,
      },
      (json) => OmnixMatterDevice.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Reads the actual reported state of an operational pairing.
  Future<bool> readOnOff(OmnixMatterDevice device) {
    if (!device.operational) {
      return Future.error(StateError('Pairing is incomplete.'));
    }
    return _command('read', {'nodeId': device.nodeId}, (json) => json as bool);
  }

  /// Sends an explicit On or Off command, rather than an ambiguous Toggle.
  Future<void> setOnOff(OmnixMatterDevice device, bool on) {
    if (!device.operational) {
      return Future.error(StateError('Pairing is incomplete.'));
    }
    return _command('set', {'nodeId': device.nodeId, 'on': on}, (_) {});
  }

  /// Drains accepted commands and stops the native worker exactly once.
  Future<void> close() => _closing ??= _tail.then((_) => _transport.close(_id));
}

final class _NativeMatterTransport implements OmnixMatterTransport {
  @override
  Future<BigInt> open(String directory) async {
    await ensureRustInitialized();
    return native.matterOpen(directory: directory);
  }

  @override
  Future<String> request(BigInt id, String operation, String arguments) =>
      native.matterRequest(id: id, operation: operation, arguments: arguments);
  @override
  Future<void> close(BigInt id) => native.matterClose(id: id);
}
