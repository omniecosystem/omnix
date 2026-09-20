// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

/// Stable, implementation-independent identity of an Omnix runtime.
final class OmnixRuntimeInfo {
  const OmnixRuntimeInfo({
    required this.apiVersion,
    required this.engineName,
    required this.engineVersion,
  });

  /// Version of the public native compatibility contract.
  final int apiVersion;

  /// Human-readable engine name.
  final String engineName;

  /// Version of the active engine implementation.
  final String engineVersion;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OmnixRuntimeInfo &&
          apiVersion == other.apiVersion &&
          engineName == other.engineName &&
          engineVersion == other.engineVersion;

  @override
  int get hashCode => Object.hash(apiVersion, engineName, engineVersion);

  @override
  String toString() =>
      'OmnixRuntimeInfo(apiVersion: $apiVersion, '
      'engineName: $engineName, engineVersion: $engineVersion)';
}
