// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:typed_data';

import '../../domain/context/omnix_context.dart';
import '../../domain/inference/omnix_conversation.dart';
import '../../domain/inference/omnix_message.dart';
import '../../domain/persistence/omnix_conversation_store.dart';
import '../omnix_runtime.dart';

/// Owns one durable conversation across bounded native model contexts.
///
/// Complete history is retained in [store]. Before every turn, [contextPolicy]
/// selects only the history that should be replayed into the active model
/// session. A completed user/assistant turn is then written as one atomic
/// snapshot, so context trimming can never become durable message deletion.
final class OmnixConversationCoordinator {
  OmnixConversationCoordinator._(
    this._store,
    this._conversation,
    this._contextPolicy,
    OmnixConversationSnapshot snapshot,
    this._now,
  ) : _record = snapshot.record,
      _history = List.of(snapshot.messages);

  /// Creates or restores a durable conversation and opens its native session.
  static Future<OmnixConversationCoordinator> open({
    required OmnixRuntime runtime,
    required OmnixConversationStore store,
    required OmnixConversationRecord record,
    required OmnixConversationConfiguration configuration,
    required OmnixContextPolicy contextPolicy,
    DateTime Function()? now,
  }) async {
    if (record.modelTemplate != configuration.modelTemplate) {
      throw ArgumentError.value(
        configuration.modelTemplate,
        'configuration',
        'The configuration model must match the conversation record.',
      );
    }

    await store.initialize();
    var snapshot = await store.read(record.id);
    final isNew = snapshot == null;
    if (snapshot == null) {
      snapshot = OmnixConversationSnapshot(record: record, messages: const []);
    } else if (snapshot.record.modelTemplate != configuration.modelTemplate) {
      throw StateError(
        'Stored conversation ${record.id} uses a different model template.',
      );
    }

    final opened = await runtime.openConversation(
      configuration,
      history: snapshot.messages,
      contextPolicy: contextPolicy,
    );
    if (opened is! OmnixContextualConversation) {
      await opened.close();
      throw StateError(
        'The Omnix runtime returned a conversation without atomic context '
        'restoration support.',
      );
    }

    try {
      if (isNew) await store.write(snapshot);
    } catch (_) {
      await opened.close();
      rethrow;
    }

    return OmnixConversationCoordinator._(
      store,
      opened,
      contextPolicy,
      snapshot,
      now ?? DateTime.now,
    );
  }

  final OmnixConversationStore _store;
  final OmnixContextualConversation _conversation;
  final OmnixContextPolicy _contextPolicy;
  final DateTime Function() _now;
  OmnixConversationRecord _record;
  List<OmnixMessage> _history;
  OmnixContextSelection? _lastContextSelection;
  bool _turnActive = false;
  bool _closed = false;

  /// Current durable metadata.
  OmnixConversationRecord get record => _record;

  /// Complete durable history, including messages omitted from active context.
  List<OmnixMessage> get history => List.unmodifiable(_history);

  /// Context chosen for the most recently started turn.
  OmnixContextSelection? get lastContextSelection => _lastContextSelection;

  bool get isGenerating => _turnActive;
  bool get isClosed => _closed;

  /// Generates one turn and atomically persists it after successful completion.
  Stream<OmnixConversationEvent> send(
    String prompt, {
    Uint8List? imageBytes,
    Uint8List? audioBytes,
  }) async* {
    _ensureOpen();
    if (_turnActive) {
      throw StateError('A conversation turn is already active.');
    }
    final userMessage = OmnixMessage(
      text: prompt,
      role: OmnixMessageRole.user,
      imageBytes: imageBytes,
      audioBytes: audioBytes,
    );
    final selection = _contextPolicy.select(
      _history,
      additionalMessages: [userMessage],
    );
    _lastContextSelection = selection;
    _turnActive = true;
    final response = _ResponseMessageCollector();
    try {
      await for (final event in _conversation.sendWithHistory(
        selection.messages,
        prompt,
        imageBytes: imageBytes,
        audioBytes: audioBytes,
      )) {
        response.add(event);
        yield event;
      }

      final completedHistory = <OmnixMessage>[
        ..._history,
        userMessage,
        ...response.messages,
      ];
      final updatedRecord = _record.copyWith(updatedAt: _now());
      await _store.write(
        OmnixConversationSnapshot(
          record: updatedRecord,
          messages: completedHistory,
        ),
      );
      _record = updatedRecord;
      _history = completedHistory;
    } finally {
      _turnActive = false;
    }
  }

  /// Requests cancellation of the active native generation.
  Future<void> stop() {
    if (_closed) return Future.value();
    return _conversation.stop();
  }

  /// Closes this coordinator and its runtime-owned native conversation.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _conversation.close();
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Conversation coordinator is closed.');
  }
}

final class _ResponseMessageCollector {
  final List<OmnixMessage> _messages = [];

  List<OmnixMessage> get messages => List.unmodifiable(_messages);

  void add(OmnixConversationEvent event) {
    switch (event) {
      case OmnixTextDelta(:final text):
        _appendText(OmnixMessageKind.text, text);
      case OmnixThinkingDelta(:final text):
        _appendText(OmnixMessageKind.thinking, text);
      case OmnixToolCall(:final name, :final arguments):
        _messages.add(
          OmnixMessage(
            text: jsonEncode(arguments),
            role: OmnixMessageRole.assistant,
            kind: OmnixMessageKind.toolCall,
            toolName: name,
          ),
        );
    }
  }

  void _appendText(OmnixMessageKind kind, String text) {
    if (text.isEmpty) return;
    if (_messages.isNotEmpty && _messages.last.kind == kind) {
      final previous = _messages.removeLast();
      _messages.add(
        OmnixMessage(
          text: previous.text + text,
          role: OmnixMessageRole.assistant,
          kind: kind,
        ),
      );
      return;
    }
    _messages.add(
      OmnixMessage(text: text, role: OmnixMessageRole.assistant, kind: kind),
    );
  }
}
