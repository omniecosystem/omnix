// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'omnix_model_manifest.dart';
import 'omnix_model_capabilities.dart';

/// A source from which an inference model can be installed.
sealed class OmnixModelSource {
  const OmnixModelSource();
}

/// An HTTP or HTTPS model artifact.
final class OmnixNetworkModelSource extends OmnixModelSource {
  OmnixNetworkModelSource(this.uri, {this.authToken, this.foreground}) {
    if (!uri.hasScheme || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw ArgumentError.value(uri, 'uri', 'must use HTTP or HTTPS');
    }
    if (uri.host.isEmpty || uri.pathSegments.isEmpty) {
      throw ArgumentError.value(uri, 'uri', 'must identify a model artifact');
    }
  }

  final Uri uri;

  /// Optional source credential. Hosts must not persist this in plain text.
  final String? authToken;

  /// Android foreground-download policy. Null delegates to the adapter.
  final bool? foreground;
}

/// A model packaged as a Flutter asset.
final class OmnixAssetModelSource extends OmnixModelSource {
  OmnixAssetModelSource(this.path) {
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'path', 'must not be empty');
    }
  }

  final String path;
}

/// A model already present at a platform file path.
final class OmnixFileModelSource extends OmnixModelSource {
  OmnixFileModelSource(this.path) {
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'path', 'must not be empty');
    }
  }

  final String path;
}

/// A model packaged as a native platform resource.
final class OmnixBundledModelSource extends OmnixModelSource {
  OmnixBundledModelSource(this.name) {
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
  }

  final String name;
}

/// Everything required to install and activate one inference model.
final class OmnixModelInstallRequest {
  OmnixModelInstallRequest({
    required this.template,
    required this.format,
    required this.source,
    this.capabilities = const OmnixModelCapabilities(),
    this.expectedSizeBytes,
    this.expectedSha256,
  }) {
    if ((expectedSizeBytes == null) != (expectedSha256 == null)) {
      throw ArgumentError(
        'Expected size and SHA-256 must be supplied together.',
      );
    }
    if (expectedSizeBytes case final size? when size < 1) {
      throw ArgumentError.value(size, 'expectedSizeBytes', 'must be positive');
    }
    if (expectedSha256 case final hash?
        when !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash)) {
      throw ArgumentError.value(
        hash,
        'expectedSha256',
        'must contain 64 hexadecimal characters',
      );
    }
  }

  factory OmnixModelInstallRequest.fromManifest(
    OmnixModelManifest manifest, {
    String? authToken,
    bool? foreground,
  }) => OmnixModelInstallRequest(
    template: manifest.template,
    format: manifest.format,
    source: OmnixNetworkModelSource(
      manifest.downloadUri,
      authToken: authToken,
      foreground: foreground,
    ),
    capabilities: manifest.capabilities,
    expectedSizeBytes: manifest.sizeBytes,
    expectedSha256: manifest.sha256,
  );

  final OmnixModelTemplate template;
  final OmnixModelFormat format;
  final OmnixModelSource source;
  final OmnixModelCapabilities capabilities;

  /// Optional integrity requirements. Registry manifests always provide both.
  final int? expectedSizeBytes;
  final String? expectedSha256;

  bool get requiresIntegrityVerification => expectedSizeBytes != null;
}

/// Result of a successful installation.
final class OmnixModelInstallation {
  const OmnixModelInstallation({
    required this.artifactName,
    required this.template,
    required this.format,
    this.capabilities = const OmnixModelCapabilities(),
    this.notes = const [],
  });

  /// Storage identity used by [OmnixModelManager.isInstalled].
  final String artifactName;
  final OmnixModelTemplate template;
  final OmnixModelFormat format;
  final OmnixModelCapabilities capabilities;
  final List<String> notes;
}

/// Host-controlled cancellation for a long-running Omnix operation.
final class OmnixCancellationToken {
  final StreamController<String> _cancellations =
      StreamController<String>.broadcast(sync: true);
  String? _reason;

  bool get isCancelled => _reason != null;
  String? get reason => _reason;
  Stream<String> get cancellations => _cancellations.stream;

  void cancel([String reason = 'Operation cancelled']) {
    if (isCancelled) return;
    _reason = reason;
    _cancellations.add(reason);
    unawaited(_cancellations.close());
  }

  void throwIfCancelled() {
    if (isCancelled) throw OmnixOperationCancelled(_reason!);
  }
}

/// Raised when a host cancels an Omnix operation.
final class OmnixOperationCancelled implements Exception {
  const OmnixOperationCancelled(this.reason);

  final String reason;

  @override
  String toString() => 'OmnixOperationCancelled: $reason';
}

/// Plugin-independent model installation and storage contract.
abstract interface class OmnixModelManager {
  Future<void> initialize();

  Future<OmnixModelInstallation> install(
    OmnixModelInstallRequest request, {
    void Function(int progress)? onProgress,
    OmnixCancellationToken? cancellationToken,
  });

  Future<bool> isInstalled(String artifactName);
  Future<List<String>> listInstalled();
  Future<String> getPath(String artifactName);
  Future<void> clearActiveModel();
  Future<void> uninstall(String artifactName);
  Future<void> cleanup();
}
