// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

List<String> selectStorageFeatures(Map<String, Object?> defines) {
  final engines = defines['engines'];
  if (engines is! List ||
      engines.isEmpty ||
      engines.any(
        (value) => value is! String || !{'sqlite', 'qdrant'}.contains(value),
      ) ||
      engines.toSet().length != engines.length) {
    throw ArgumentError(
      'Select omnix_storage.engines explicitly: [sqlite], [qdrant], or both.',
    );
  }
  return [
    if (engines.contains('sqlite')) 'sqlite',
    if (engines.contains('qdrant')) 'qdrant',
  ];
}
