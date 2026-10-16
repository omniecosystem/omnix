// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

List<String> selectRuntimeFeatures(Map<String, Object?> defines) {
  final selection = defines['runtimes'];
  if (selection == null || defines.containsKey('llamacpp')) {
    throw ArgumentError(
      'Select at least one runtime explicitly with omnix_core.runtimes: '
      '[litertlm], [llamacpp], or [litertlm, llamacpp].',
    );
  }
  if (selection is! List || selection.any((value) => value is! String)) {
    throw ArgumentError('omnix_core.runtimes must be a list of runtime names.');
  }
  final names = selection.cast<String>();
  if (names.isEmpty ||
      names.toSet().length != names.length ||
      names.any((name) => name != 'litertlm' && name != 'llamacpp')) {
    throw ArgumentError('Runtime names must be unique: litertlm, llamacpp.');
  }
  return [
    if (names.contains('litertlm')) 'litertlm',
    if (names.contains('llamacpp')) 'llamacpp',
  ];
}

Map<String, Object?> coreTargetDefines(
  Map<String, Object?> defines,
  String target,
) {
  final override = defines[target];
  if (override == null) return defines;
  if (override is! Map || override.keys.any((key) => key is! String)) {
    throw ArgumentError('omnix_core.$target must be a component map.');
  }
  const allowed = {
    'runtimes',
    'embeddings',
    'embedding_engine',
    'model_installation',
    'litertlm_constraint_assets',
    'litertlm_assets',
    'litertlm_backends',
  };
  if (override.keys.any((key) => !allowed.contains(key))) {
    throw ArgumentError('Unknown omnix_core.$target component setting.');
  }
  return {...defines, ...override.cast<String, Object?>()};
}

bool includeAndroidConstraintProvider(Object? owner) {
  if (owner == null || owner == 'self') return true;
  if (owner == 'external') return false;
  throw ArgumentError('litertlm_constraint_assets must be self or external.');
}

bool includeLiteRtLmAssets(Object? owner) {
  if (owner == null || owner == 'self') return true;
  if (owner == 'external') return false;
  throw ArgumentError('litertlm_assets must be self or external.');
}
