import 'package:omnix_core/omnix_core.dart';
import 'package:test/test.dart';

void main() {
  test('native output channels stay distinct without prose heuristics', () {
    final thought = OmnixCoreOutput.fromJson({
      'kind': 'reasoning',
      'text': 'reason',
    });
    expect(thought.kind, OmnixCoreOutputKind.reasoning);
    expect(thought.text, 'reason');
    expect(
      OmnixCoreOutput.fromJson({
        'kind': 'text',
        'text': '<think>literal</think>',
      }).kind,
      OmnixCoreOutputKind.text,
    );
    for (final value in [
      <String, dynamic>{'kind': 'reasoning'},
      <String, dynamic>{'kind': 'reasoning', 'text': 17},
      <String, dynamic>{'kind': 'tool', 'text': 'reason'},
    ]) {
      expect(() => OmnixCoreOutput.fromJson(value), throwsFormatException);
    }
  });
}
