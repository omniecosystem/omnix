import 'dart:typed_data';

/// The kind of one ordered input part.
enum OmnixInputKind { text, image, audio }

/// An immutable input part whose encoded bytes survive queued native work.
///
/// Rust enforces input limits. The first audio contract accepts PCM16 mono WAV
/// at 16 kHz, up to 60 seconds. Media inference still needs model qualification.
final class OmnixInputPart {
  OmnixInputPart._(this.kind, this.text, Uint8List bytes)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  /// Creates a text part without inserting separators between adjacent parts.
  OmnixInputPart.text(String text)
    : this._(OmnixInputKind.text, text, Uint8List(0));

  /// Creates an encoded image part, not a file path or textual description.
  OmnixInputPart.image(Uint8List bytes)
    : this._(OmnixInputKind.image, null, bytes);

  /// Creates an encoded WAV audio part.
  OmnixInputPart.audio(Uint8List bytes)
    : this._(OmnixInputKind.audio, null, bytes);

  /// The modality presented to the native provider.
  final OmnixInputKind kind;

  /// The text content, or `null` for media.
  final String? text;

  /// The owned, read-only encoded media bytes.
  final Uint8List bytes;
}
