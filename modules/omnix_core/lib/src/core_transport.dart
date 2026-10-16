import 'rust/api/core.dart' as native;
import 'rust_initialization.dart';
import 'message.dart';
import 'dart:convert';
import 'output.dart';

/// Optional support for explicit native reasoning and separate output channels.
abstract interface class OmnixCoreThinkingTransport {
  Future<BigInt> startThinkingConversation(
    BigInt modelId,
    String? systemPrompt,
    int maxOutputTokens,
    String? samplingJson,
  );
  Stream<OmnixCoreOutput> sendMessageEvents(
    BigInt id,
    List<OmnixInputPart> parts,
  );
}

/// Optional transport support for changing future reasoning on a live conversation.
abstract interface class OmnixCoreThinkingConfigurationTransport {
  Future<void> setThinking(BigInt id, bool enabled);
}

/// Optional support for Rust-validated restoration with a future reasoning setting.
abstract interface class OmnixCoreThinkingRestorationTransport {
  Future<String> restoreThinking(BigInt id, String snapshot, bool enabled);
}

/// The replaceable transport to a single native Core handle registry.
abstract interface class OmnixCoreTransport {
  /// Reports the platforms qualified for the compiled runtime adapter.
  Future<List<String>> supportedPlatforms();

  /// Loads host-approved native artifacts implementing the pinned C ABI.
  Future<BigInt> loadTrustedModel(
    String libraryPath,
    String modelPath,
    int contextTokens,
  );

  /// Starts a text conversation on a loaded model.
  Future<BigInt> startConversation(
    BigInt modelId,
    String? systemPrompt,
    int maxOutputTokens,
  );

  /// Sends one text turn and returns its complete response.
  Future<String> send(BigInt conversationId, String text);

  /// Releases one model handle without invalidating existing conversations.
  Future<void> closeModel(BigInt modelId);

  /// Releases one conversation handle.
  Future<void> closeConversation(BigInt conversationId);
}

abstract interface class OmnixCoreSamplingTransport
    implements OmnixCoreTransport {
  Future<BigInt> startSampledConversation(
    BigInt modelId,
    String? systemPrompt,
    int maxOutputTokens,
    String samplingJson,
  );
}

abstract interface class OmnixCoreReconfigurationTransport {
  Future<void> reconfigureConversation(
    BigInt id,
    int tokens,
    String? samplingJson,
  );
}

/// The optional streaming transport with an out-of-band stop signal.
abstract interface class OmnixCoreStreamingTransport
    implements OmnixCoreTransport {
  /// Delivers ordered text deltas until native generation ends.
  Stream<String> sendStream(BigInt conversationId, String text);

  /// Requests stopping the active native turn without waiting on its lock.
  Future<void> cancelGeneration(BigInt conversationId);
}

/// The optional transport for header-based native runtime selection.
abstract interface class OmnixCoreRoutedTransport
    implements OmnixCoreTransport {
  /// Loads a local container using a compiled or explicitly trusted runtime.
  Future<BigInt> loadRoutedModel(
    String modelPath,
    String? libraryPath,
    int contextTokens,
  );
}

/// The optional transport for explicit native optimized cache configuration.
abstract interface class OmnixCoreConfiguredTransport
    implements OmnixCoreRoutedTransport {
  /// Loads a model using an existing host-owned optimized cache directory.
  Future<BigInt> loadConfiguredModel(
    String modelPath,
    String? libraryPath,
    int contextTokens,
    bool images,
    bool audio,
    String cacheDirectory,
  );
}

/// The optional transport for exporting and restoring native text history.
abstract interface class OmnixCoreHistoryTransport
    implements OmnixCoreTransport {
  /// Exports history, or restores [snapshot] into a fresh conversation.
  Future<String> conversationHistory(BigInt conversationId, String? snapshot);
}

/// The optional transport for explicitly enabled native media input.
abstract interface class OmnixCoreMediaTransport
    implements OmnixCoreStreamingTransport, OmnixCoreRoutedTransport {
  /// Loads a model with the requested encoder backends enabled.
  Future<BigInt> loadMediaModel(
    String modelPath,
    String? libraryPath,
    int contextTokens,
    bool images,
    bool audio,
  );

  /// Sends ordered text and encoded media parts.
  Future<String> sendMessage(BigInt conversationId, List<OmnixInputPart> parts);

  /// Streams a response to ordered text and encoded media parts.
  Stream<String> sendMessageStream(
    BigInt conversationId,
    List<OmnixInputPart> parts,
  );
}

List<native.CoreInputPart> _nativeParts(List<OmnixInputPart> parts) => [
  for (final part in parts)
    native.CoreInputPart(
      kind: native.CoreInputKind.values[part.kind.index],
      text: part.text,
      bytes: part.bytes,
    ),
];

/// The optional transport for independently owned leases on compatible engines.
abstract interface class OmnixCoreSharedTransport
    implements OmnixCoreMediaTransport, OmnixCoreConfiguredTransport {
  /// Acquires an engine without sharing conversation histories or permissions.
  Future<BigInt> loadSharedModel(
    String modelPath,
    String? libraryPath,
    int contextTokens,
    bool images,
    bool audio,
    String? cacheDirectory,
  );

  /// Reports shared engines retained in this native binding registry.
  Future<int> sharedModelCount();
}

final class NativeCoreTransport
    implements
        OmnixCoreThinkingTransport,
        OmnixCoreThinkingConfigurationTransport,
        OmnixCoreThinkingRestorationTransport,
        OmnixCoreReconfigurationTransport,
        OmnixCoreSamplingTransport,
        OmnixCoreStreamingTransport,
        OmnixCoreRoutedTransport,
        OmnixCoreMediaTransport,
        OmnixCoreConfiguredTransport,
        OmnixCoreSharedTransport,
        OmnixCoreHistoryTransport {
  @override
  Future<void> reconfigureConversation(
    BigInt id,
    int tokens,
    String? samplingJson,
  ) => native.coreReconfigureConversation(
    conversationId: id,
    maxOutputTokens: tokens,
    samplingJson: samplingJson,
  );
  @override
  Future<void> setThinking(BigInt id, bool enabled) async {
    await ensureRustInitialized();
    await native.coreSetThinking(conversationId: id, enabled: enabled);
  }

  @override
  Future<String> restoreThinking(
    BigInt id,
    String snapshot,
    bool enabled,
  ) async {
    await ensureRustInitialized();
    return native.coreConversationHistory(
      conversationId: id,
      snapshot: snapshot,
      thinking: enabled,
    );
  }

  @override
  Future<BigInt> loadSharedModel(
    String modelPath,
    String? libraryPath,
    int contextTokens,
    bool images,
    bool audio,
    String? cacheDirectory,
  ) async {
    await ensureRustInitialized();
    return native.coreLoadSharedModel(
      modelPath: modelPath,
      libraryPath: libraryPath,
      contextTokens: contextTokens,
      images: images,
      audio: audio,
      cacheDirectory: cacheDirectory,
    );
  }

  @override
  Future<int> sharedModelCount() async {
    await ensureRustInitialized();
    return native.coreSharedModelCount();
  }

  @override
  Future<BigInt> startSampledConversation(
    BigInt modelId,
    String? systemPrompt,
    int maxOutputTokens,
    String samplingJson,
  ) async {
    await ensureRustInitialized();
    return native.coreStartSampledConversation(
      modelId: modelId,
      systemPrompt: systemPrompt,
      maxOutputTokens: maxOutputTokens,
      samplingJson: samplingJson,
      thinking: false,
    );
  }

  @override
  Future<BigInt> startThinkingConversation(
    BigInt modelId,
    String? systemPrompt,
    int maxOutputTokens,
    String? samplingJson,
  ) async {
    await ensureRustInitialized();
    return native.coreStartSampledConversation(
      modelId: modelId,
      systemPrompt: systemPrompt,
      maxOutputTokens: maxOutputTokens,
      samplingJson: samplingJson,
      thinking: true,
    );
  }

  @override
  Stream<OmnixCoreOutput> sendMessageEvents(
    BigInt id,
    List<OmnixInputPart> parts,
  ) async* {
    await ensureRustInitialized();
    var terminal = false;
    await for (final raw in native.coreSendMessageEvents(
      conversationId: id,
      parts: _nativeParts(parts),
    )) {
      final event = jsonDecode(raw) as Map<String, dynamic>;
      if (terminal) throw StateError('Invalid Core stream lifecycle.');
      switch (event['kind']) {
        case 'text':
        case 'reasoning':
          yield OmnixCoreOutput.fromJson(event);
        case 'completed':
          terminal = true;
        case 'cancelled':
          terminal = true;
        case 'failed':
          throw StateError('Native Core failed: ${event['text']}');
        default:
          throw const FormatException('Unknown Core stream event.');
      }
    }
    if (!terminal) throw StateError('Core stream ended without completion.');
  }

  @override
  Future<BigInt> loadConfiguredModel(
    String modelPath,
    String? libraryPath,
    int contextTokens,
    bool images,
    bool audio,
    String cacheDirectory,
  ) async {
    await ensureRustInitialized();
    return native.coreLoadConfiguredModel(
      modelPath: modelPath,
      libraryPath: libraryPath,
      contextTokens: contextTokens,
      images: images,
      audio: audio,
      cacheDirectory: cacheDirectory,
    );
  }

  @override
  Future<BigInt> loadMediaModel(
    String modelPath,
    String? libraryPath,
    int contextTokens,
    bool images,
    bool audio,
  ) async {
    await ensureRustInitialized();
    return native.coreLoadMediaModel(
      modelPath: modelPath,
      libraryPath: libraryPath,
      contextTokens: contextTokens,
      images: images,
      audio: audio,
    );
  }

  @override
  Future<String> sendMessage(
    BigInt conversationId,
    List<OmnixInputPart> parts,
  ) => native.coreSendMessage(
    conversationId: conversationId,
    parts: _nativeParts(parts),
  );

  @override
  Stream<String> sendMessageStream(
    BigInt conversationId,
    List<OmnixInputPart> parts,
  ) => native.coreSendMessageStream(
    conversationId: conversationId,
    parts: _nativeParts(parts),
  );
  @override
  Future<String> conversationHistory(BigInt conversationId, String? snapshot) =>
      native.coreConversationHistory(
        conversationId: conversationId,
        snapshot: snapshot,
      );

  @override
  Future<BigInt> loadRoutedModel(
    String modelPath,
    String? libraryPath,
    int contextTokens,
  ) async {
    await ensureRustInitialized();
    return native.coreLoadRoutedModel(
      modelPath: modelPath,
      libraryPath: libraryPath,
      contextTokens: contextTokens,
    );
  }

  @override
  Stream<String> sendStream(BigInt conversationId, String text) =>
      native.coreSendStream(conversationId: conversationId, text: text);

  @override
  Future<void> cancelGeneration(BigInt conversationId) =>
      native.coreCancelGeneration(conversationId: conversationId);

  @override
  Future<List<String>> supportedPlatforms() async {
    await ensureRustInitialized();
    return native.coreSupportedPlatforms();
  }

  @override
  Future<BigInt> loadTrustedModel(
    String libraryPath,
    String modelPath,
    int contextTokens,
  ) async {
    await ensureRustInitialized();
    return native.coreLoadTrustedModel(
      libraryPath: libraryPath,
      modelPath: modelPath,
      contextTokens: contextTokens,
    );
  }

  @override
  Future<BigInt> startConversation(
    BigInt modelId,
    String? systemPrompt,
    int maxOutputTokens,
  ) => native.coreStartConversation(
    modelId: modelId,
    systemPrompt: systemPrompt,
    maxOutputTokens: maxOutputTokens,
  );

  @override
  Future<String> send(BigInt conversationId, String text) =>
      native.coreSend(conversationId: conversationId, text: text);

  @override
  Future<void> closeModel(BigInt modelId) =>
      native.coreCloseModel(modelId: modelId);

  @override
  Future<void> closeConversation(BigInt conversationId) =>
      native.coreCloseConversation(conversationId: conversationId);
}
