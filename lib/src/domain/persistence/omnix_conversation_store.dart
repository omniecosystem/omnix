// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import '../inference/omnix_message.dart';
import '../models/omnix_model_manifest.dart';

/// Durable metadata for one conversation, independent of an active session.
final class OmnixConversationRecord {
  OmnixConversationRecord({
    required this.id,
    required this.modelTemplate,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    Map<String, Object?> metadata = const {},
  }) : metadata = Map.unmodifiable(metadata) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Conversation id must not be empty.');
    }
  }

  final String id;
  final String? title;
  final OmnixModelTemplate modelTemplate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, Object?> metadata;

  OmnixConversationRecord copyWith({
    String? title,
    DateTime? updatedAt,
    Map<String, Object?>? metadata,
  }) => OmnixConversationRecord(
    id: id,
    title: title ?? this.title,
    modelTemplate: modelTemplate,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    metadata: metadata ?? this.metadata,
  );
}

/// An immutable durable conversation snapshot.
final class OmnixConversationSnapshot {
  OmnixConversationSnapshot({
    required this.record,
    required List<OmnixMessage> messages,
  }) : messages = List.unmodifiable(messages);

  final OmnixConversationRecord record;
  final List<OmnixMessage> messages;
}

/// Host-implemented durable storage for complete conversation history.
///
/// [write] must atomically persist metadata and ordered messages. Active model
/// context trimming must never remove messages from the durable snapshot.
abstract interface class OmnixConversationStore {
  Future<void> initialize();

  Future<List<OmnixConversationRecord>> readConversations();

  Future<OmnixConversationSnapshot?> read(String conversationId);

  Future<void> write(OmnixConversationSnapshot snapshot);

  Future<void> delete(String conversationId);
}
