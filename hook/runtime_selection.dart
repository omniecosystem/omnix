List<String> selectRootRuntimes(Object? global, Object? target) {
  if (target != null && target is! Map) {
    throw ArgumentError('Omnix target settings must be a map.');
  }
  final selection = target is Map && target.containsKey('runtimes')
      ? target['runtimes']
      : global;
  if (selection == null) return const [];
  if (selection is! List ||
      selection.any((r) => r != 'litertlm' && r != 'llamacpp') ||
      selection.toSet().length != selection.length) {
    throw ArgumentError(
      'Omnix runtimes must be distinct litertlm/llamacpp names.',
    );
  }
  return List<String>.unmodifiable(selection.cast<String>());
}

String selectLiteRtLmAssetOwner(Object? selection, {required bool android}) {
  final owner = selection ?? 'self';
  if (owner != 'self' && owner != 'omnix_core' && owner != 'external') {
    throw ArgumentError(
      'litertlm_assets must be self, omnix_core or external.',
    );
  }
  return owner as String;
}

bool includeAndroidConstraintProvider(Object? owner) {
  if (owner == null || owner == 'self') return true;
  if (owner == 'external') return false;
  throw ArgumentError('litertlm_constraint_assets must be self or external.');
}

String selectAndroidLiteRtLmLibrary(Object? value) {
  final name = value ?? 'liblitert-lm.so';
  if (name is! String || !RegExp(r'^lib[A-Za-z0-9_-]+\.so$').hasMatch(name)) {
    throw ArgumentError(
      'litertlm_library must be an Android library basename.',
    );
  }
  return name;
}
