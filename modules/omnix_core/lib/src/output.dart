/// The output channel explicitly reported by the native runtime.
enum OmnixCoreOutputKind { text, reasoning }

/// An owned native output fragment, separate from tool dispatch.
final class OmnixCoreOutput {
  const OmnixCoreOutput(this.kind, this.text);
  final OmnixCoreOutputKind kind;
  final String text;
  factory OmnixCoreOutput.fromJson(Map<String, dynamic> json) => switch (json) {
    {'kind': 'text', 'text': final String text} => OmnixCoreOutput(
      OmnixCoreOutputKind.text,
      text,
    ),
    {'kind': 'reasoning', 'text': final String text} => OmnixCoreOutput(
      OmnixCoreOutputKind.reasoning,
      text,
    ),
    _ => throw const FormatException('Invalid Core output event.'),
  };
}
