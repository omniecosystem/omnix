// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

/// The host-approved identity of a single model artifact.
final class OmnixModelSpec {
  const OmnixModelSpec({
    required this.filename,
    required this.sha256,
    required this.bytes,
    required this.role,
  });
  final String filename;
  final String sha256;
  final int bytes;
  final String role;
  factory OmnixModelSpec.fromJson(Map<String, dynamic> json) => OmnixModelSpec(
    filename: json['filename'] as String,
    sha256: json['sha256'] as String,
    bytes: json['bytes'] as int,
    role: json['role'] as String,
  );
  Map<String, Object> toJson() => {
    'filename': filename,
    'sha256': sha256,
    'bytes': bytes,
    'role': role,
  };
}

/// A verified installation record, independent of inference activation.
final class OmnixInstalledModel {
  const OmnixInstalledModel({required this.spec, required this.path});
  final OmnixModelSpec spec;
  final String path;
  factory OmnixInstalledModel.fromJson(Map<String, dynamic> json) =>
      OmnixInstalledModel(
        spec: OmnixModelSpec.fromJson(json['spec'] as Map<String, dynamic>),
        path: json['path'] as String,
      );
}

/// A durable destination for an independently scheduled platform transfer.
///
/// This is not an installed model or proof that a platform task is running.
final class OmnixTransferReservation {
  const OmnixTransferReservation({
    required this.id,
    required this.spec,
    required this.path,
  });

  final String id;
  final OmnixModelSpec spec;
  final String path;

  factory OmnixTransferReservation.fromJson(Map<String, dynamic> json) =>
      OmnixTransferReservation(
        id: json['id'] as String,
        spec: OmnixModelSpec.fromJson(json['spec'] as Map<String, dynamic>),
        path: json['path'] as String,
      );

  Map<String, Object> toJson() => {
    'id': id,
    'spec': spec.toJson(),
    'path': path,
  };
}

/// A bounded native installation progress snapshot.
final class OmnixInstallationProgress {
  const OmnixInstallationProgress({
    required this.phase,
    required this.received,
    required this.total,
    this.path,
    this.error,
  });
  final String phase;
  final int received;
  final int total;
  final String? path;
  final String? error;
  bool get terminal =>
      const ['installed', 'failed', 'cancelled'].contains(phase);
  factory OmnixInstallationProgress.fromJson(Map<String, dynamic> json) =>
      OmnixInstallationProgress(
        phase: json['phase'] as String,
        received: json['received'] as int,
        total: json['total'] as int,
        path: json['path'] as String?,
        error: json['error'] as String?,
      );
}
