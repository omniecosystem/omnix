// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

/// One violation of a tool's declared input schema.
final class OmnixToolInputIssue {
  const OmnixToolInputIssue({required this.path, required this.message});

  /// The argument path, rooted at `$`.
  final String path;

  /// The human-readable validation failure.
  final String message;

  @override
  String toString() => '$path: $message';
}

/// The immutable result of validating tool arguments.
final class OmnixToolInputValidation {
  OmnixToolInputValidation(Iterable<OmnixToolInputIssue> issues)
    : issues = List.unmodifiable(issues);

  /// The violations found in deterministic traversal order.
  final List<OmnixToolInputIssue> issues;

  /// Whether the supplied arguments satisfy the supported schema subset.
  bool get isValid => issues.isEmpty;
}

/// Validates tool arguments against Omnix's supported JSON Schema subset.
abstract final class OmnixToolInputValidator {
  /// Validates [arguments] against [schema].
  ///
  /// The supported subset includes `type`, `properties`, `required`, `items`,
  /// `enum`, and `additionalProperties: false`. Unknown schema keywords are
  /// ignored so providers may preserve richer declarations without making
  /// them unusable.
  static OmnixToolInputValidation validate(
    Map<String, Object?> schema,
    Map<String, Object?> arguments,
  ) {
    if (schema.isEmpty) return OmnixToolInputValidation(const []);
    final issues = <OmnixToolInputIssue>[];
    _validateValue(schema, arguments, r'$', issues);
    return OmnixToolInputValidation(issues);
  }

  static void _validateValue(
    Map<String, Object?> schema,
    Object? value,
    String path,
    List<OmnixToolInputIssue> issues,
  ) {
    final expectedType = schema['type'];
    if (expectedType is String && !_matchesType(expectedType, value)) {
      issues.add(
        OmnixToolInputIssue(
          path: path,
          message: 'Expected $expectedType but received ${_typeName(value)}.',
        ),
      );
      return;
    }

    final allowed = schema['enum'];
    if (allowed is List && !allowed.contains(value)) {
      issues.add(
        OmnixToolInputIssue(
          path: path,
          message: 'Value is not one of the allowed enum values.',
        ),
      );
    }

    if (value is Map<String, Object?>) {
      _validateObject(schema, value, path, issues);
    } else if (value is List) {
      final itemSchema = _asSchema(schema['items']);
      if (itemSchema != null) {
        for (var index = 0; index < value.length; index++) {
          _validateValue(itemSchema, value[index], '$path[$index]', issues);
        }
      }
    }
  }

  static void _validateObject(
    Map<String, Object?> schema,
    Map<String, Object?> value,
    String path,
    List<OmnixToolInputIssue> issues,
  ) {
    final properties = _asSchemaMap(schema['properties']);
    final required = schema['required'];
    if (required is List) {
      for (final name in required.whereType<String>()) {
        if (!value.containsKey(name)) {
          issues.add(
            OmnixToolInputIssue(
              path: '$path.$name',
              message: 'Required argument is missing.',
            ),
          );
        }
      }
    }

    for (final entry in value.entries) {
      final propertySchema = properties[entry.key];
      if (propertySchema != null) {
        _validateValue(
          propertySchema,
          entry.value,
          '$path.${entry.key}',
          issues,
        );
      } else if (schema['additionalProperties'] == false) {
        issues.add(
          OmnixToolInputIssue(
            path: '$path.${entry.key}',
            message: 'Additional arguments are not allowed.',
          ),
        );
      }
    }
  }

  static bool _matchesType(String type, Object? value) => switch (type) {
    'null' => value == null,
    'object' => value is Map<String, Object?>,
    'array' => value is List,
    'string' => value is String,
    'number' => value is num,
    'integer' => value is int,
    'boolean' => value is bool,
    _ => true,
  };

  static String _typeName(Object? value) => switch (value) {
    null => 'null',
    Map() => 'object',
    List() => 'array',
    String() => 'string',
    int() => 'integer',
    num() => 'number',
    bool() => 'boolean',
    _ => value.runtimeType.toString(),
  };

  static Map<String, Object?>? _asSchema(Object? value) {
    if (value is! Map) return null;
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  static Map<String, Map<String, Object?>> _asSchemaMap(Object? value) {
    final map = _asSchema(value);
    if (map == null) return const {};
    return {
      for (final entry in map.entries) entry.key: ?_asSchema(entry.value),
    };
  }
}
