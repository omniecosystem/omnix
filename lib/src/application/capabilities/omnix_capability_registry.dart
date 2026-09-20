// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import '../../domain/capabilities/omnix_capability.dart';
import '../../domain/capabilities/omnix_capability_registry_snapshot.dart';

/// Decides whether a capability may use its declared permissions.
abstract interface class OmnixCapabilityPermissionPolicy {
  /// Evaluates the permissions required by [capability].
  Future<bool> allows(OmnixCapabilityMetadata capability);
}

/// Allows capabilities without permissions and denies restricted capabilities.
final class OmnixDenyRestrictedCapabilitiesPolicy
    implements OmnixCapabilityPermissionPolicy {
  const OmnixDenyRestrictedCapabilitiesPolicy();

  @override
  Future<bool> allows(OmnixCapabilityMetadata capability) async =>
      capability.requiredPermissions.isEmpty;
}

/// Stores skills and tools while enforcing enablement and permission policy.
final class OmnixCapabilityRegistry {
  /// Creates an empty registry.
  OmnixCapabilityRegistry({
    this.permissionPolicy = const OmnixDenyRestrictedCapabilitiesPolicy(),
  });

  /// The host policy consulted before a restricted tool executes.
  final OmnixCapabilityPermissionPolicy permissionPolicy;
  final Map<String, _Registration> _registrations = {};
  final StreamController<OmnixCapabilityRegistrySnapshot> _snapshots =
      StreamController<OmnixCapabilityRegistrySnapshot>.broadcast(sync: true);

  int _revision = 0;
  bool _closed = false;

  /// State changes emitted after each effective registry mutation.
  Stream<OmnixCapabilityRegistrySnapshot> get snapshots => _snapshots.stream;

  /// The current immutable registry state.
  OmnixCapabilityRegistrySnapshot get snapshot =>
      OmnixCapabilityRegistrySnapshot(
        revision: _revision,
        capabilities: _registrations.values.map(
          (registration) => OmnixRegisteredCapability(
            capability: registration.capability,
            enabled: registration.enabled,
          ),
        ),
      );

  /// Registers [capability] with its initial enabled state.
  ///
  /// Throws a [StateError] if the registry is closed or the identifier is
  /// already registered.
  void register(OmnixCapability capability, {bool enabled = true}) {
    _ensureOpen();
    final id = capability.metadata.id;
    if (_registrations.containsKey(id)) {
      throw StateError('Capability "$id" is already registered.');
    }
    _registrations[id] = _Registration(capability, enabled);
    _emitMutation();
  }

  /// Removes and returns the capability registered under [id].
  ///
  /// Returns `null` when no matching capability exists.
  OmnixCapability? unregister(String id) {
    _ensureOpen();
    final removed = _registrations.remove(id);
    if (removed == null) return null;
    _emitMutation();
    return removed.capability;
  }

  /// Returns the capability registered under [id], if one exists.
  OmnixCapability? find(String id) => _registrations[id]?.capability;

  /// Returns whether the capability registered under [id] is enabled.
  bool isEnabled(String id) => _registrations[id]?.enabled ?? false;

  /// Changes whether the capability registered under [id] may be used.
  ///
  /// Throws an [ArgumentError] when [id] is not registered.
  void setEnabled(String id, bool enabled) {
    _ensureOpen();
    final registration = _registrations[id];
    if (registration == null) {
      throw ArgumentError.value(id, 'id', 'Capability is not registered.');
    }
    if (registration.enabled == enabled) return;
    registration.enabled = enabled;
    _emitMutation();
  }

  /// Executes an enabled tool after evaluating its permission policy.
  ///
  /// Registry and policy failures are returned as [OmnixToolFailure] values.
  /// Exceptions thrown by the tool are converted to an `executionFailed`
  /// result, while programming errors remain uncaught.
  Future<OmnixToolResult> executeTool(OmnixToolInvocation invocation) async {
    _ensureOpen();
    final registration = _registrations[invocation.toolId];
    final capability = registration?.capability;
    if (capability is! OmnixTool) {
      return OmnixToolFailure(
        code: OmnixToolFailureCode.notFound,
        message: 'Tool "${invocation.toolId}" is not registered.',
      );
    }
    if (!registration!.enabled) {
      return OmnixToolFailure(
        code: OmnixToolFailureCode.disabled,
        message: 'Tool "${invocation.toolId}" is disabled.',
      );
    }
    if (!await permissionPolicy.allows(capability.metadata)) {
      return OmnixToolFailure(
        code: OmnixToolFailureCode.permissionDenied,
        message: 'Tool "${invocation.toolId}" was denied by permission policy.',
      );
    }
    try {
      return await capability.execute(invocation);
    } on Exception catch (error) {
      return OmnixToolFailure(
        code: OmnixToolFailureCode.executionFailed,
        message: 'Tool "${invocation.toolId}" failed: $error',
      );
    }
  }

  /// Releases the registry's state stream.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _snapshots.close();
  }

  void _emitMutation() {
    _revision++;
    _snapshots.add(snapshot);
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Capability registry is closed.');
  }
}

final class _Registration {
  _Registration(this.capability, this.enabled);

  final OmnixCapability capability;
  bool enabled;
}
