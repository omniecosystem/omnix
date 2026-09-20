// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import '../domain/agents/omnix_agent.dart';
import '../domain/engine/omnix_engine.dart';
import '../domain/engine/omnix_runtime_info.dart';
import '../domain/inference/omnix_conversation.dart';
import '../domain/inference/omnix_message.dart';
import '../domain/models/omnix_model_manager.dart';
import 'capabilities/omnix_capability_registry.dart';

/// Application-level owner of an Omnix engine and its conversations.
///
/// Product applications use this boundary instead of coordinating engine and
/// conversation lifecycles independently. Feature modules can be added behind
/// the same runtime as their contracts become part of Omnix.
final class OmnixRuntime {
  OmnixRuntime({
    required OmnixEngine engine,
    required OmnixInferenceBackend inferenceBackend,
    OmnixModelManager? modelManager,
    OmnixCapabilityRegistry? capabilityRegistry,
    OmnixAgentBackend? agentBackend,
  }) : this._(
         engine,
         inferenceBackend,
         modelManager,
         capabilityRegistry ?? OmnixCapabilityRegistry(),
         agentBackend,
       );

  OmnixRuntime._(
    this._engine,
    this._inferenceBackend,
    this._modelManager,
    this.capabilities,
    this._agentBackend,
  );

  final OmnixEngine _engine;
  final OmnixInferenceBackend _inferenceBackend;
  final OmnixModelManager? _modelManager;
  final OmnixAgentBackend? _agentBackend;
  final Set<_ManagedConversation> _conversations = {};
  final Set<_ManagedAgentSession> _agentSessions = {};

  /// The shared capability registry used by conversations and workflows.
  final OmnixCapabilityRegistry capabilities;

  Future<OmnixRuntimeInfo>? _initialization;
  Future<void>? _closeFuture;
  bool _closing = false;
  bool _closed = false;

  /// Whether this runtime was composed with model-management support.
  bool get supportsModelManagement => _modelManager != null;

  /// Whether this runtime was composed with agent-session support.
  bool get supportsAgents => _agentBackend != null;

  /// Model installation and storage operations configured for this runtime.
  OmnixModelManager get models =>
      _modelManager ??
      (throw UnsupportedError(
        'This Omnix runtime has no model manager. Supply one when composing it.',
      ));

  /// Initializes the native engine once and returns compatibility information.
  Future<OmnixRuntimeInfo> initialize() {
    _ensureOpen();
    final pending = _initialization;
    if (pending != null) return pending;
    final initialization = _initializeOnce();
    _initialization = initialization;
    return initialization;
  }

  Future<OmnixRuntimeInfo> _initializeOnce() async {
    try {
      final info = await _engine.initialize();
      await _modelManager?.initialize();
      return info;
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  /// Opens a conversation owned by this runtime.
  ///
  /// Initialization is automatic. Every opened conversation is closed when
  /// the runtime closes, even when the caller has not closed it explicitly.
  Future<OmnixConversation> openConversation(
    OmnixConversationConfiguration configuration,
  ) async {
    _ensureOpen();
    await initialize();
    _ensureOpen();

    final conversation = await _inferenceBackend.openConversation(
      configuration,
    );
    if (_closing || _closed) {
      await conversation.close();
      throw StateError(
        'The Omnix runtime closed while opening a conversation.',
      );
    }

    late final _ManagedConversation managed;
    managed = _ManagedConversation(
      conversation,
      onClosed: () => _conversations.remove(managed),
    );
    _conversations.add(managed);
    return managed;
  }

  /// Opens an agent session over the current capability snapshot.
  ///
  /// Capability changes affect subsequently opened sessions. Initialization is
  /// automatic, and the runtime owns every returned session until it is closed.
  Future<OmnixAgentSession> openAgent(
    OmnixAgentConfiguration configuration,
  ) async {
    _ensureOpen();
    final backend = _agentBackend;
    if (backend == null) {
      throw UnsupportedError(
        'This Omnix runtime has no agent backend. Supply one when composing it.',
      );
    }
    await initialize();
    _ensureOpen();

    final session = await backend.openAgent(
      configuration,
      capabilities.snapshot,
    );
    if (_closing || _closed) {
      await session.close();
      throw StateError('The Omnix runtime closed while opening an agent.');
    }

    late final _ManagedAgentSession managed;
    managed = _ManagedAgentSession(
      session,
      onClosed: () => _agentSessions.remove(managed),
    );
    _agentSessions.add(managed);
    return managed;
  }

  /// Stops active work, closes every owned conversation, then closes the
  /// native engine. Calling this more than once is safe.
  Future<void> close() => _closeFuture ??= _closeOnce();

  Future<void> _closeOnce() async {
    if (_closed) return;
    _closing = true;
    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      final conversations = _conversations.toList(growable: false);
      final agentSessions = _agentSessions.toList(growable: false);
      try {
        await Future.wait(<Future<void>>[
          ...agentSessions.map((session) => session.close()),
          ...conversations.map((conversation) => conversation.close()),
        ]);
      } catch (error, stackTrace) {
        firstError = error;
        firstStackTrace = stackTrace;
      }

      try {
        await capabilities.close();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }

      try {
        await _engine.close();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }

      if (firstError != null) {
        Error.throwWithStackTrace(firstError, firstStackTrace!);
      }
    } finally {
      _closed = true;
      _closing = false;
    }
  }

  void _ensureOpen() {
    if (_closing || _closed) {
      throw StateError('The Omnix runtime is closed.');
    }
  }
}

final class _ManagedAgentSession implements OmnixAgentSession {
  _ManagedAgentSession(this._session, {required this.onClosed});

  final OmnixAgentSession _session;
  final void Function() onClosed;
  bool _closed = false;

  @override
  List<OmnixMessage> get history {
    if (_closed) throw StateError('Agent session is closed.');
    return _session.history;
  }

  @override
  Future<void> replaceHistory(List<OmnixMessage> messages) {
    if (_closed) throw StateError('Agent session is closed.');
    return _session.replaceHistory(messages);
  }

  @override
  Stream<OmnixAgentEvent> ask(String prompt, {Uint8List? imageBytes}) {
    if (_closed) throw StateError('Agent session is closed.');
    return _session.ask(prompt, imageBytes: imageBytes);
  }

  @override
  Future<void> stop() {
    if (_closed) return Future.value();
    return _session.stop();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _session.close();
    } finally {
      onClosed();
    }
  }
}

final class _ManagedConversation implements OmnixConversation {
  _ManagedConversation(this._conversation, {required this.onClosed});

  final OmnixConversation _conversation;
  final void Function() onClosed;
  bool _closed = false;

  @override
  List<OmnixMessage> get history {
    if (_closed) throw StateError('Conversation is closed.');
    return _conversation.history;
  }

  @override
  Future<void> replaceHistory(List<OmnixMessage> messages) {
    if (_closed) throw StateError('Conversation is closed.');
    return _conversation.replaceHistory(messages);
  }

  @override
  Stream<OmnixConversationEvent> send(String prompt) {
    if (_closed) throw StateError('Conversation is closed.');
    return _conversation.send(prompt);
  }

  @override
  Future<void> stop() {
    if (_closed) return Future.value();
    return _conversation.stop();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _conversation.close();
    } finally {
      onClosed();
    }
  }
}
