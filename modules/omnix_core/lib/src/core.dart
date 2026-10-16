import 'dart:async';

import 'core_transport.dart';
import 'message.dart';
import 'sampling.dart';
import 'output.dart';

/// A standalone native inference entry point with explicitly selected artifacts.
///
/// The adapters support Windows CPU/text with LiteRT-LM and opt-in llama.cpp.
/// Opt-in LiteRT-LM image/audio input has Windows CPU/Gemma 4 smoke evidence.
/// Models are host-approved, with optional separate native installation.
/// Selected runtimes are bundled at build time.
final class OmnixCore {
  /// Creates an inference entry point with an optional test [transport].
  OmnixCore({OmnixCoreTransport? transport})
    : _transport = transport ?? NativeCoreTransport();
  final OmnixCoreTransport _transport;

  /// Reports the currently qualified native adapter platforms.
  Future<List<String>> supportedPlatforms() => _transport.supportedPlatforms();

  /// Reports engines retained by shared model handles and their conversations.
  ///
  /// Counts only the loaded binding's opt-in pool, not independent loads or
  /// engines in other native libraries or processes. Isolates using the same
  /// native library can observe the same pool.
  Future<int> sharedModelCount() {
    final transport = _transport;
    if (transport is! OmnixCoreSharedTransport) {
      return Future.error(
        UnsupportedError('This transport does not support shared ownership.'),
      );
    }
    return transport.sharedModelCount();
  }

  /// Loads a trusted local model using its container header to select a runtime.
  ///
  /// GGUF requires the opt-in compiled llama.cpp runtime and no [libraryPath].
  /// LiteRT-LM uses its build-time bundle unless [libraryPath] overrides it.
  /// The host owns model integrity and licensing; this method does not download
  /// models or verify an explicitly supplied runtime library.
  /// Windows CPU has model-specific text, image and WAV smoke evidence.
  /// [enableImages] and [enableAudio] opt into experimental LiteRT-LM encoders;
  /// the host must select a model containing them. GGUF media is not implemented.
  /// [cacheDirectory] selects an existing absolute host-owned LiteRT-LM optimized
  /// cache directory. Other runtimes reject it. Omitting it preserves the native
  /// default; this method does not create or migrate cache files. LiteRT-LM CPU
  /// uses at least 1024 context tokens even when a smaller size is requested.
  /// [shareRuntime] opts into Rust-owned compatible-load sharing. Each returned
  /// model is independently closed; conversations retain ownership. It does not
  /// merge histories or bypass LiteRT-LM's one-active-conversation limit.
  Future<OmnixCoreModel> loadModel({
    required String modelPath,
    String? libraryPath,
    int contextTokens = 2048,
    bool enableImages = false,
    bool enableAudio = false,
    String? cacheDirectory,
    bool shareRuntime = false,
  }) async {
    if (modelPath.trim().isEmpty ||
        libraryPath?.trim().isEmpty == true ||
        cacheDirectory?.trim().isEmpty == true ||
        contextTokens < 128 ||
        contextTokens > 32768) {
      throw ArgumentError(
        'Trusted artifacts and a context size from 128 to 32768 are required.',
      );
    }
    final transport = _transport;
    if (shareRuntime && transport is! OmnixCoreSharedTransport) {
      throw UnsupportedError(
        'This transport does not support shared ownership.',
      );
    }
    if (transport is! OmnixCoreRoutedTransport) {
      throw UnsupportedError(
        'This transport does not support runtime routing.',
      );
    }
    if ((enableImages || enableAudio) &&
        transport is! OmnixCoreMediaTransport) {
      throw UnsupportedError('This transport does not support media input.');
    }
    if (cacheDirectory != null && transport is! OmnixCoreConfiguredTransport) {
      throw UnsupportedError(
        'This transport does not support cache configuration.',
      );
    }
    final id = shareRuntime
        ? await (transport as OmnixCoreSharedTransport).loadSharedModel(
            modelPath,
            libraryPath,
            contextTokens,
            enableImages,
            enableAudio,
            cacheDirectory,
          )
        : cacheDirectory != null
        ? await (transport as OmnixCoreConfiguredTransport).loadConfiguredModel(
            modelPath,
            libraryPath,
            contextTokens,
            enableImages,
            enableAudio,
            cacheDirectory,
          )
        : enableImages || enableAudio
        ? await (transport as OmnixCoreMediaTransport).loadMediaModel(
            modelPath,
            libraryPath,
            contextTokens,
            enableImages,
            enableAudio,
          )
        : await transport.loadRoutedModel(
            modelPath,
            libraryPath,
            contextTokens,
          );
    return OmnixCoreModel._(
      id,
      _transport,
      images: enableImages,
      audio: enableAudio,
    );
  }

  /// Loads an explicitly trusted LiteRT-LM runtime and model from absolute paths.
  ///
  /// The host must verify [libraryPath] and its dependencies are trusted and
  /// implement the v0.17.1 C ABI before calling. Loading arbitrary or incompatible
  /// native code can execute malicious code or crash the process. The bridge
  /// validates paths and settings, not provenance or ABI compatibility.
  /// LiteRT-LM CPU uses at least 1024 context tokens.
  Future<OmnixCoreModel> loadTrustedLiteRtLm({
    required String libraryPath,
    required String modelPath,
    int contextTokens = 2048,
  }) async {
    if (libraryPath.trim().isEmpty ||
        modelPath.trim().isEmpty ||
        contextTokens < 128 ||
        contextTokens > 0x7fffffff) {
      throw ArgumentError(
        'Trusted absolute artifact paths and a valid context size are required.',
      );
    }
    final id = await _transport.loadTrustedModel(
      libraryPath,
      modelPath,
      contextTokens,
    );
    return OmnixCoreModel._(id, _transport);
  }
}

/// A loaded native model whose conversations retain their runtime ownership.
final class OmnixCoreModel {
  OmnixCoreModel._(
    this._id,
    this._transport, {
    this.images = false,
    this.audio = false,
  });

  /// Whether image input was explicitly enabled when loading this model.
  final bool images;

  /// Whether audio input was explicitly enabled when loading this model.
  final bool audio;
  final BigInt _id;
  final OmnixCoreTransport _transport;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closing;

  /// Starts a conversation with explicit output limits.
  ///
  /// LiteRT-LM retains up to 16 logical conversations and switches between them
  /// on its owning thread, replaying the selected history when necessary. GGUF
  /// permits isolated conversations sharing model weights. Histories remain
  /// separate; this does not guarantee parallel generation or a memory budget.
  Future<OmnixCoreConversation> startConversation({
    String? systemPrompt,
    int maxOutputTokens = 128,
    OmnixCoreSamplingOptions? sampling,
    bool thinking = false,
  }) {
    if (_closing != null) return Future.error(StateError('Model is closed.'));
    if (maxOutputTokens <= 0 || maxOutputTokens > 0x7fffffff) {
      return Future.error(
        ArgumentError.value(maxOutputTokens, 'maxOutputTokens'),
      );
    }
    final result = _tail.then((_) async {
      final id = await (thinking
          ? (_transport is OmnixCoreThinkingTransport
                ? (_transport as OmnixCoreThinkingTransport)
                      .startThinkingConversation(
                        _id,
                        systemPrompt,
                        maxOutputTokens,
                        sampling?.encode(),
                      )
                : throw UnsupportedError(
                    'Transport does not support thinking.',
                  ))
          : sampling != null
          ? (_transport is OmnixCoreSamplingTransport
                ? _transport.startSampledConversation(
                    _id,
                    systemPrompt,
                    maxOutputTokens,
                    sampling.encode(),
                  )
                : throw UnsupportedError(
                    'Transport does not support sampling settings.',
                  ))
          : _transport.startConversation(_id, systemPrompt, maxOutputTokens));
      return OmnixCoreConversation._(id, _transport, images, audio);
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Drains accepted creation requests and releases this model handle once.
  ///
  /// Existing conversations remain usable and must be closed separately.
  Future<void> close() =>
      _closing ??= _tail.then((_) => _transport.closeModel(_id));
}

/// A serialized multi-turn native conversation producing textual responses.
final class OmnixCoreConversation {
  /// Changes future reasoning between completed turns without discarding history.
  Future<void> setThinking(bool enabled) {
    if (_closing != null || _failed || _streaming) {
      return Future.error(StateError('Conversation unavailable or busy.'));
    }
    final transport = _transport;
    if (transport is! OmnixCoreThinkingConfigurationTransport) {
      return Future.error(
        UnsupportedError('Live thinking settings unsupported.'),
      );
    }
    final result = _tail.then((_) {
      if (_failed) throw StateError('Conversation failed.');
      return (transport as OmnixCoreThinkingConfigurationTransport).setThinking(
        _id,
        enabled,
      );
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> reconfigure({
    required int maxOutputTokens,
    OmnixCoreSamplingOptions? sampling,
  }) {
    if (_closing != null || _failed || _streaming) {
      return Future.error(StateError('Conversation unavailable or busy.'));
    }
    final transport = _transport;
    if (transport is! OmnixCoreReconfigurationTransport) {
      return Future.error(UnsupportedError('Live settings unsupported.'));
    }
    if (maxOutputTokens < 1) {
      return Future.error(ArgumentError('Invalid response budget.'));
    }
    final encoded = sampling?.encode();
    final result = _tail.then((_) {
      if (_failed) throw StateError('Conversation failed.');
      return (transport as OmnixCoreReconfigurationTransport)
          .reconfigureConversation(_id, maxOutputTokens, encoded);
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  OmnixCoreConversation._(this._id, this._transport, this._images, this._audio);
  final bool _images;
  final bool _audio;
  final BigInt _id;
  final OmnixCoreTransport _transport;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closing;
  bool _failed = false;
  bool _streaming = false;
  bool _nativeStreaming = false;
  bool _stopRequested = false;
  Object? _activeStream;

  /// Delivers ordered text deltas from a Rust-owned streaming turn.
  ///
  /// Empty input, overlapping streams and closed conversations are rejected.
  /// A stopped turn ends normally; Rust restores the recorded text history
  /// before the next turn. Backend errors invalidate it.
  /// Native completion keeps draining when the subscription pauses; buffered
  /// output is bounded by the host-selected generation/context limits.
  Stream<String> sendStream(String text) => _sendStream(text, null);

  /// Streams a text response to ordered text and encoded image/audio parts.
  ///
  /// Media must be enabled at model load. Native history keeps the original
  /// content for cancellation replay; exporting media history is not supported.
  Stream<String> sendMessageStream(List<OmnixInputPart> parts) {
    try {
      final input = _admitParts(parts);
      if (input.every((part) => part.kind == OmnixInputKind.text)) {
        return sendStream(input.map((part) => part.text!).join());
      }
      return _sendStream(null, input);
    } catch (error, stack) {
      return Stream.error(error, stack);
    }
  }

  List<OmnixInputPart> _admitParts(List<OmnixInputPart> parts) {
    final input = List<OmnixInputPart>.unmodifiable(parts);
    if (input.isEmpty || input.length > 16) {
      throw ArgumentError('One to sixteen input parts are required.');
    }
    if (input.any(
      (part) =>
          (part.kind == OmnixInputKind.image && !_images) ||
          (part.kind == OmnixInputKind.audio && !_audio),
    )) {
      throw UnsupportedError(
        'This input modality was not enabled for the model.',
      );
    }
    return input;
  }

  Stream<String> _sendStream(String? text, List<OmnixInputPart>? parts) {
    return _sendEvents(text, parts)
        .where((event) => event.kind == OmnixCoreOutputKind.text)
        .map((event) => event.text);
  }

  /// Streams runtime-reported reasoning separately from visible answer text.
  Stream<OmnixCoreOutput> sendMessageEvents(List<OmnixInputPart> parts) {
    try {
      return _sendEvents(null, _admitParts(parts));
    } catch (error, stack) {
      return Stream.error(error, stack);
    }
  }

  Stream<OmnixCoreOutput> _sendEvents(
    String? text,
    List<OmnixInputPart>? parts,
  ) {
    late StreamController<OmnixCoreOutput> controller;
    Future<void>? running;
    var abandoned = false;
    final token = Object();
    Future<void> pump() async {
      if (_closing != null || _failed || _streaming) {
        controller.addError(StateError('Conversation is unavailable or busy.'));
        unawaited(controller.close());
        return;
      }
      final transport = _transport;
      if (text?.trim().isEmpty == true ||
          transport is! OmnixCoreStreamingTransport) {
        controller.addError(
          text?.trim().isEmpty == true
              ? ArgumentError.value(text, 'text')
              : UnsupportedError('The transport does not support streaming.'),
        );
        unawaited(controller.close());
        return;
      }
      _streaming = true;
      _activeStream = token;
      _stopRequested = false;
      final previous = _tail;
      final done = Completer<void>();
      _tail = done.future;
      try {
        await previous;
        if (_failed) throw StateError('Conversation failed; open a new one.');
        if (_stopRequested) return;
        _nativeStreaming = true;
        // Drain native completion even when the UI pauses/cancels consumption.
        // This keeps stop and close independent from a paused subscription.
        final updates = transport is OmnixCoreThinkingTransport
            ? (transport as OmnixCoreThinkingTransport).sendMessageEvents(
                _id,
                parts ?? [OmnixInputPart.text(text!)],
              )
            : (parts == null
                      ? transport.sendStream(_id, text!)
                      : (transport as OmnixCoreMediaTransport)
                            .sendMessageStream(_id, parts))
                  .map(
                    (text) => OmnixCoreOutput(OmnixCoreOutputKind.text, text),
                  );
        await for (final delta in updates) {
          if (!abandoned) controller.add(delta);
        }
      } catch (error, stack) {
        _failed = true;
        if (!abandoned) controller.addError(error, stack);
      } finally {
        _nativeStreaming = false;
        _streaming = false;
        _activeStream = null;
        done.complete();
        unawaited(controller.close());
      }
    }

    controller = StreamController<OmnixCoreOutput>(
      onListen: () {
        running = pump();
      },
      onCancel: () async {
        abandoned = true;
        if (identical(_activeStream, token)) await cancelGeneration();
        await running;
      },
    );
    return controller.stream;
  }

  /// Requests stopping this conversation's active streaming turn.
  ///
  /// This signal is not queued behind generation. Cancelling after normal
  /// completion is a no-op and does not cause unnecessary history recovery.
  Future<void> cancelGeneration() async {
    if (!_streaming || _stopRequested) return;
    _stopRequested = true;
    final transport = _transport;
    if (_nativeStreaming && transport is OmnixCoreStreamingTransport) {
      await transport.cancelGeneration(_id);
    }
  }

  /// Sends [text] and returns the complete response without streaming.
  ///
  /// A backend failure invalidates this conversation to avoid reusing partially
  /// mutated native history. Close it before opening another conversation.
  Future<String> send(String text) {
    if (_closing != null) {
      return Future.error(StateError('Conversation is closed.'));
    }
    if (text.trim().isEmpty) {
      return Future.error(ArgumentError.value(text, 'text'));
    }
    final result = _tail.then((_) async {
      if (_failed) {
        throw StateError('Conversation failed; open a new conversation.');
      }
      try {
        return await _transport.send(_id, text);
      } catch (_) {
        _failed = true;
        rethrow;
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Sends ordered parts and returns the complete textual model response.
  ///
  /// Encoded media remains owned through completion. Rust validates size and
  /// format, and rejects unsupported modalities rather than ignoring them.
  Future<String> sendMessage(List<OmnixInputPart> parts) {
    late final List<OmnixInputPart> input;
    try {
      input = _admitParts(parts);
    } catch (error, stack) {
      return Future.error(error, stack);
    }
    if (input.every((part) => part.kind == OmnixInputKind.text)) {
      return send(input.map((part) => part.text!).join());
    }
    if (_closing != null) {
      return Future.error(StateError('Conversation is closed.'));
    }
    final result = _tail.then((_) async {
      if (_failed) throw StateError('Conversation failed; open a new one.');
      try {
        return await (_transport as OmnixCoreMediaTransport).sendMessage(
          _id,
          input,
        );
      } catch (_) {
        _failed = true;
        rethrow;
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Exports a versioned snapshot of the Rust-owned completed context.
  ///
  /// Version 1 contains text history. LiteRT-LM media uses version 2 with an
  /// opaque native context, which can contain private recordings and images.
  /// Keep it private and restore with the same model, instructions, sampling,
  /// response budget, and required input encoders. Other runtimes may reject
  /// media snapshots rather than export a lossy text approximation.
  Future<String> exportHistory() => _history(null);

  /// Restores [snapshot] into a fresh conversation using the native runtime.
  ///
  /// Restore failures invalidate this handle. Close it before trying again.
  /// Host display transcripts must not replace a native media snapshot.
  Future<void> restoreHistory(String snapshot, {bool? thinking}) async {
    await _history(snapshot, thinking: thinking);
  }

  Future<String> _history(String? snapshot, {bool? thinking}) {
    if (_closing != null || _failed || _streaming) {
      return Future.error(StateError('Conversation is unavailable or busy.'));
    }
    final transport = _transport;
    if (transport is! OmnixCoreHistoryTransport) {
      return Future.error(UnsupportedError('History is not supported.'));
    }
    if (thinking != null &&
        transport is! OmnixCoreThinkingRestorationTransport) {
      return Future.error(
        UnsupportedError('Thinking history transition unsupported.'),
      );
    }
    final result = _tail.then((_) async {
      if (_failed) throw StateError('Conversation failed.');
      try {
        return thinking != null
            ? await (transport as OmnixCoreThinkingRestorationTransport)
                  .restoreThinking(_id, snapshot!, thinking)
            : await transport.conversationHistory(_id, snapshot);
      } catch (_) {
        if (snapshot != null) _failed = true;
        rethrow;
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Drains accepted turns and releases this conversation handle exactly once.
  Future<void> close() {
    final existing = _closing;
    if (existing != null) return existing;
    final closing = _closing = _tail.then(
      (_) => _transport.closeConversation(_id),
    );
    if (_streaming) unawaited(cancelGeneration());
    return closing;
  }
}
