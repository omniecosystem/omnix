import 'dart:convert';

/// The reliability of the runtime's context-cost accounting.
enum OmnixContextAccounting { estimatedText, unavailableMedia }

/// Rust-owned working-context diagnostics for the last admitted input.
///
/// An estimate is not a measured prompt size or a guarantee against native
/// overflow. The bundled LiteRT-LM adapter does not produce these diagnostics;
/// it reports unsupported accounting explicitly.
final class OmnixContextUsage {
  const OmnixContextUsage({
    required this.accounting,
    required this.capacity,
    required this.reservedOutput,
    required this.estimatedInputTokens,
    required this.omittedTurns,
    required this.retainedMessages,
  });

  final OmnixContextAccounting accounting;
  final int capacity;
  final int reservedOutput;
  final int? estimatedInputTokens;
  final int omittedTurns;
  final int retainedMessages;

  /// Decodes a native diagnostic envelope, including an absent diagnostic.
  static OmnixContextUsage? decode(String encoded) {
    final value = jsonDecode(encoded);
    if (value == null) return null;
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid context diagnostics.');
    }
    int number(String key) {
      final number = value[key];
      if (number is! int || number < 0) {
        throw const FormatException('Invalid context diagnostic count.');
      }
      return number;
    }

    final rawAccounting = value['accounting'];
    if (rawAccounting != 'EstimatedText' &&
        rawAccounting != 'UnavailableMedia') {
      throw const FormatException('Unknown context accounting.');
    }
    final accounting = rawAccounting == 'EstimatedText'
        ? OmnixContextAccounting.estimatedText
        : OmnixContextAccounting.unavailableMedia;
    final estimate = value['estimated_input_tokens'];
    if ((estimate != null && (estimate is! int || estimate < 0)) ||
        (accounting == OmnixContextAccounting.estimatedText &&
            estimate == null) ||
        (accounting == OmnixContextAccounting.unavailableMedia &&
            estimate != null)) {
      throw const FormatException('Inconsistent context estimate.');
    }
    return OmnixContextUsage(
      accounting: accounting,
      capacity: number('capacity'),
      reservedOutput: number('reserved_output'),
      estimatedInputTokens: estimate as int?,
      omittedTurns: number('omitted_turns'),
      retainedMessages: number('retained_messages'),
    );
  }
}
