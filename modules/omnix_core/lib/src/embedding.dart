import 'dart:typed_data';
import 'rust/api/embedding.dart' as native;
import 'rust_initialization.dart';

/// The explicitly selected tokenizer and task convention.
enum OmnixEmbeddingConvention {
  gemma,
  legacyGecko,
  embeddingGemma2,
  embeddingGemma2Multimodal,
}

/// An ordered text or encoded media input supplied by the host.
///
/// Video containers must be decoded into frame images by the host. Image and
/// admitted images are PNG/JPEG (up to 8 MB each); audio is mono 16 kHz PCM16 WAV
/// (up to 60 seconds each). Requests contain at most 128 parts and 64 MB total.
/// Longer recordings must be chunked by the host. Limits are admission bounds,
/// not a promise that every input fits the model's context.
final class OmnixEmbeddingInput {
  const OmnixEmbeddingInput.text(this.text) : kind = 'text', bytes = null;
  OmnixEmbeddingInput.image(Uint8List data)
    : kind = 'image',
      text = '',
      bytes = Uint8List.fromList(data).asUnmodifiableView();
  OmnixEmbeddingInput.audio(Uint8List data)
    : kind = 'audio',
      text = '',
      bytes = Uint8List.fromList(data).asUnmodifiableView();
  final String kind;
  final String text;
  final Uint8List? bytes;
  native.EmbeddingPart _native() => native.EmbeddingPart(
    kind: kind,
    text: text,
    bytes: bytes ?? Uint8List(0),
  );
}

/// A Rust-owned CPU encoder with serialized requests and explicit disposal.
final class OmnixEmbeddingModel {
  OmnixEmbeddingModel._(
    this._handle,
    this.profile,
    this.dimension,
    this.sequenceLength,
  );
  final BigInt _handle;

  /// The weights, tokenizer and convention fingerprint.
  final String profile;

  /// The final vector width.
  final int dimension;

  /// The encoder input width, including prefixes and special tokens.
  final int sequenceLength;
  Future<void> _tail = Future.value();
  Future<void>? _closing;

  /// Opens trusted immutable local files with the selected bundled runtime.
  ///
  /// Tensor encoders require `omnix_core.embeddings: true` and [tokenizerPath].
  /// [OmnixEmbeddingConvention.embeddingGemma2] instead uses its bundled
  /// tokenizer and requires `omnix_core.embedding_engine: true`.
  /// [OmnixEmbeddingConvention.embeddingGemma2Multimodal] additionally requires
  /// the full bundle and explicitly enables CPU vision/audio encoders.
  /// Both require an explicit `litertlm` runtime selection. Windows CPU is
  /// the currently qualified target. No model is downloaded by this method.
  static Future<OmnixEmbeddingModel> open({
    required String modelPath,
    String tokenizerPath = '',
    required OmnixEmbeddingConvention convention,
  }) async {
    await ensureRustInitialized();
    final info = await native.embeddingOpen(
      model: modelPath,
      tokenizer: tokenizerPath,
      convention: switch (convention) {
        OmnixEmbeddingConvention.gemma => 'gemma',
        OmnixEmbeddingConvention.legacyGecko => 'gecko-legacy',
        OmnixEmbeddingConvention.embeddingGemma2 => 'gemma2',
        OmnixEmbeddingConvention.embeddingGemma2Multimodal =>
          'gemma2-multimodal',
      },
    );
    return OmnixEmbeddingModel._(
      info.handle,
      info.profile,
      info.dimension,
      info.sequenceLength,
    );
  }

  /// Encodes text using the document or query task without truncation.
  Future<List<double>> generateEmbedding(
    String text, {
    required bool document,
  }) {
    if (_closing != null) {
      return Future.error(StateError('Encoder closed.'));
    }
    final pending = _tail.then(
      (_) async => (await native.embeddingGenerate(
        handle: _handle,
        text: text,
        document: document,
      )).toList(),
    );
    _tail = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return pending;
  }

  /// Encodes ordered inputs into one normalized vector without dropping media.
  ///
  /// Media requires the full model and the explicit multimodal convention.
  /// Unsupported encoders reject the request. No files are opened by this call.
  Future<List<double>> generateMultimodalEmbedding(
    List<OmnixEmbeddingInput> inputs, {
    required bool document,
  }) {
    if (_closing != null) return Future.error(StateError('Encoder closed.'));
    final parts = inputs.map((part) => part._native()).toList(growable: false);
    final pending = _tail.then(
      (_) async => (await native.embeddingGenerateMultimodal(
        handle: _handle,
        parts: parts,
        document: document,
      )).toList(),
    );
    _tail = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return pending;
  }

  /// Drains accepted work and releases the native encoder once.
  Future<void> close() =>
      _closing ??= _tail.then((_) => native.embeddingClose(handle: _handle));
}
