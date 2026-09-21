// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

import '../../domain/workflow/omnix_workflow_event.dart';
import '../../domain/workflow/omnix_workflow_task.dart';

/// Versioned JSON-compatible persistence encoding for Workflow records.
final class OmnixWorkflowCodec {
  const OmnixWorkflowCodec();

  static const int schemaVersion = 1;

  Map<String, Object?> encodeTask(OmnixWorkflowTask task) {
    _validateJsonValue(task.input, 'input');
    return {
      'schemaVersion': schemaVersion,
      'id': task.id,
      'kind': task.kind,
      'title': task.title,
      'description': task.description,
      'input': task.input,
      'status': task.status.name,
      'attempt': task.attempt,
      'maxAttempts': task.maxAttempts,
      'createdAt': task.createdAt.toUtc().toIso8601String(),
      'updatedAt': task.updatedAt.toUtc().toIso8601String(),
      'output': task.output,
      'error': task.error,
    };
  }

  OmnixWorkflowTask decodeTask(Map<String, Object?> json) {
    _requireVersion(json);
    final attempt = _integer(json, 'attempt');
    final maxAttempts = _integer(json, 'maxAttempts');
    if (attempt < 0 || maxAttempts < 1 || attempt > maxAttempts) {
      throw const FormatException('Invalid Workflow attempt counters.');
    }
    return OmnixWorkflowTask(
      id: _nonEmptyString(json, 'id'),
      kind: _nonEmptyString(json, 'kind'),
      title: _nonEmptyString(json, 'title'),
      description: _nullableString(json, 'description'),
      input: _stringMap(json, 'input'),
      status: _enumValue(
        OmnixWorkflowTaskStatus.values,
        _nonEmptyString(json, 'status'),
        'status',
      ),
      attempt: attempt,
      maxAttempts: maxAttempts,
      createdAt: _dateTime(json, 'createdAt'),
      updatedAt: _dateTime(json, 'updatedAt'),
      output: _nullableString(json, 'output'),
      error: _nullableString(json, 'error'),
    );
  }

  Map<String, Object?> encodeEvent(OmnixWorkflowEvent event) {
    _validateJsonValue(event.data, 'data');
    return {
      'schemaVersion': schemaVersion,
      'taskId': event.taskId,
      'kind': event.kind.name,
      'timestamp': event.timestamp.toUtc().toIso8601String(),
      'message': event.message,
      'data': event.data,
    };
  }

  OmnixWorkflowEvent decodeEvent(Map<String, Object?> json) {
    _requireVersion(json);
    return OmnixWorkflowEvent(
      taskId: _nonEmptyString(json, 'taskId'),
      kind: _enumValue(
        OmnixWorkflowEventKind.values,
        _nonEmptyString(json, 'kind'),
        'kind',
      ),
      timestamp: _dateTime(json, 'timestamp'),
      message: _string(json, 'message'),
      data: _stringMap(json, 'data'),
    );
  }

  void _requireVersion(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != schemaVersion) {
      throw FormatException('Unsupported Workflow schema version: $version.');
    }
  }

  T _enumValue<T extends Enum>(List<T> values, String name, String field) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw FormatException('Invalid Workflow $field: $name.');
  }

  int _integer(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is int) return value;
    throw FormatException('Workflow $field must be an integer.');
  }

  String _string(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is String) return value;
    throw FormatException('Workflow $field must be a string.');
  }

  String _nonEmptyString(Map<String, Object?> json, String field) {
    final value = _string(json, field);
    if (value.trim().isNotEmpty) return value;
    throw FormatException('Workflow $field must not be empty.');
  }

  String? _nullableString(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value == null || value is String) return value as String?;
    throw FormatException('Workflow $field must be a string or null.');
  }

  DateTime _dateTime(Map<String, Object?> json, String field) {
    final value = _nonEmptyString(json, field);
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('Workflow $field must be an ISO-8601 timestamp.');
    }
    return parsed.toUtc();
  }

  Map<String, Object?> _stringMap(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is! Map) {
      throw FormatException('Workflow $field must be an object.');
    }
    try {
      final result = Map<String, Object?>.from(value);
      _validateJsonValue(result, field);
      return result;
    } on TypeError {
      throw FormatException('Workflow $field keys must be strings.');
    }
  }

  void _validateJsonValue(Object? value, String field) {
    try {
      jsonEncode(value);
    } on JsonUnsupportedObjectError {
      throw FormatException('Workflow $field must contain JSON-safe values.');
    }
  }
}
