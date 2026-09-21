// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:typed_data';

import '../../domain/inference/omnix_message.dart';
import '../../domain/models/omnix_model_manifest.dart';
import '../../domain/persistence/omnix_conversation_store.dart';

/// Versioned JSON-compatible encoding for durable conversation snapshots.
final class OmnixConversationCodec {
  const OmnixConversationCodec();

  static const int schemaVersion = 1;

  Map<String, Object?> encode(OmnixConversationSnapshot snapshot) {
    _validateJsonValue(snapshot.record.metadata, 'metadata');
    return {
      'schemaVersion': schemaVersion,
      'record': {
        'id': snapshot.record.id,
        'title': snapshot.record.title,
        'modelTemplate': snapshot.record.modelTemplate.name,
        'createdAt': snapshot.record.createdAt.toUtc().toIso8601String(),
        'updatedAt': snapshot.record.updatedAt.toUtc().toIso8601String(),
        'metadata': snapshot.record.metadata,
      },
      'messages': snapshot.messages.map(_encodeMessage).toList(growable: false),
    };
  }

  OmnixConversationSnapshot decode(Map<String, Object?> json) {
    final version = json['schemaVersion'];
    if (version != schemaVersion) {
      throw FormatException(
        'Unsupported conversation schema version: $version.',
      );
    }
    final recordJson = _map(json['record'], 'record');
    final rawMessages = json['messages'];
    if (rawMessages is! List) {
      throw const FormatException('Conversation messages must be an array.');
    }
    return OmnixConversationSnapshot(
      record: OmnixConversationRecord(
        id: _nonEmptyString(recordJson, 'id'),
        title: _nullableString(recordJson, 'title'),
        modelTemplate: _enumValue(
          OmnixModelTemplate.values,
          _nonEmptyString(recordJson, 'modelTemplate'),
          'modelTemplate',
        ),
        createdAt: _dateTime(recordJson, 'createdAt'),
        updatedAt: _dateTime(recordJson, 'updatedAt'),
        metadata: _map(recordJson['metadata'], 'metadata'),
      ),
      messages: rawMessages
          .map((message) => _decodeMessage(_map(message, 'message')))
          .toList(growable: false),
    );
  }

  Map<String, Object?> _encodeMessage(OmnixMessage message) => {
    'text': message.text,
    'role': message.role.name,
    'kind': message.kind.name,
    'toolName': message.toolName,
    'imageBytes': _encodeBytes(message.imageBytes),
    'images': message.images.map(base64Encode).toList(growable: false),
    'audioBytes': _encodeBytes(message.audioBytes),
  };

  OmnixMessage _decodeMessage(Map<String, Object?> json) {
    final rawImages = json['images'];
    if (rawImages is! List) {
      throw const FormatException(
        'Conversation message images must be an array.',
      );
    }
    return OmnixMessage(
      text: _string(json, 'text'),
      role: _enumValue(
        OmnixMessageRole.values,
        _nonEmptyString(json, 'role'),
        'role',
      ),
      kind: _enumValue(
        OmnixMessageKind.values,
        _nonEmptyString(json, 'kind'),
        'kind',
      ),
      toolName: _nullableString(json, 'toolName'),
      imageBytes: _decodeBytes(json['imageBytes'], 'imageBytes'),
      images: rawImages
          .map((value) => _decodeRequiredBytes(value, 'images'))
          .toList(growable: false),
      audioBytes: _decodeBytes(json['audioBytes'], 'audioBytes'),
    );
  }

  String? _encodeBytes(Uint8List? bytes) =>
      bytes == null ? null : base64Encode(bytes);

  Uint8List? _decodeBytes(Object? value, String field) =>
      value == null ? null : _decodeRequiredBytes(value, field);

  Uint8List _decodeRequiredBytes(Object? value, String field) {
    if (value is! String) {
      throw FormatException('Conversation $field must be base64 text.');
    }
    try {
      return base64Decode(value);
    } on FormatException {
      throw FormatException('Conversation $field contains invalid base64.');
    }
  }

  Map<String, Object?> _map(Object? value, String field) {
    if (value is! Map) {
      throw FormatException('Conversation $field must be an object.');
    }
    try {
      final result = Map<String, Object?>.from(value);
      _validateJsonValue(result, field);
      return result;
    } on TypeError {
      throw FormatException('Conversation $field keys must be strings.');
    }
  }

  String _string(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value is String) return value;
    throw FormatException('Conversation $field must be a string.');
  }

  String _nonEmptyString(Map<String, Object?> json, String field) {
    final value = _string(json, field);
    if (value.trim().isNotEmpty) return value;
    throw FormatException('Conversation $field must not be empty.');
  }

  String? _nullableString(Map<String, Object?> json, String field) {
    final value = json[field];
    if (value == null || value is String) return value as String?;
    throw FormatException('Conversation $field must be a string or null.');
  }

  DateTime _dateTime(Map<String, Object?> json, String field) {
    final parsed = DateTime.tryParse(_nonEmptyString(json, field));
    if (parsed == null) {
      throw FormatException(
        'Conversation $field must be an ISO-8601 timestamp.',
      );
    }
    return parsed.toUtc();
  }

  T _enumValue<T extends Enum>(List<T> values, String name, String field) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw FormatException('Invalid conversation $field: $name.');
  }

  void _validateJsonValue(Object? value, String field) {
    try {
      jsonEncode(value);
    } on JsonUnsupportedObjectError {
      throw FormatException(
        'Conversation $field must contain JSON-safe values.',
      );
    }
  }
}
