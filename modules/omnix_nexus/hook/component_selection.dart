// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

List<String> selectNexusFeatures(
  Map<String, Object?> defines, {
  bool windows = false,
  bool android = false,
}) {
  final override =
      defines[android
          ? 'android'
          : windows
          ? 'windows'
          : 'other'];
  if (override != null) {
    if (override is! Map<String, Object?>) {
      throw ArgumentError('Nexus platform settings must be a map.');
    }
    defines = {...defines, ...override};
  }
  final protocols = defines['protocols'];
  if (defines.containsKey('experimental_matter') ||
      protocols is! List ||
      protocols.isEmpty ||
      protocols.any(
        (value) => value is! String || !{'a2a', 'matter'}.contains(value),
      ) ||
      protocols.toSet().length != protocols.length) {
    throw ArgumentError(
      'Select omnix_nexus.protocols explicitly: [a2a], [matter], or both; remove experimental_matter.',
    );
  }
  final matterBackend = defines['matter_backend'];
  if (matterBackend != null &&
      (!protocols.contains('matter') ||
          !{
            'experimental',
            'windows_qualification',
            'android_host',
          }.contains(matterBackend))) {
    throw ArgumentError(
      'matter_backend requires matter and an explicit supported backend.',
    );
  }
  if (matterBackend == 'windows_qualification' && !windows) {
    throw ArgumentError(
      'windows_qualification is available only on Windows; no platform fallback.',
    );
  }
  if (matterBackend == 'android_host' && !android) {
    throw ArgumentError('android_host requires Android; no platform fallback.');
  }
  return [
    if (protocols.contains('a2a')) 'a2a',
    if (protocols.contains('matter'))
      if (matterBackend == 'windows_qualification')
        'matter-process'
      else if (matterBackend == 'android_host')
        'matter-android'
      else
        'matter',
  ];
}
