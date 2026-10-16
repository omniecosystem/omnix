import 'dart:typed_data';
import 'package:omnix_core/omnix_core.dart';
import 'package:test/test.dart';

void main() {
  test('text retains its exact content and does not invent media', () {
    const input = OmnixEmbeddingInput.text('search this image');
    expect(input.kind, 'text');
    expect(input.text, 'search this image');
    expect(input.bytes, isNull);
  });
  test('media captures immutable bytes before queued execution', () {
    for (final constructor in [
      OmnixEmbeddingInput.image,
      OmnixEmbeddingInput.audio,
    ]) {
      final source = Uint8List.fromList([1, 2, 3]);
      final input = constructor(source);
      source[0] = 9;
      expect(input.bytes, [1, 2, 3]);
      expect(() => input.bytes![0] = 7, throwsUnsupportedError);
      expect(input.text, isEmpty);
    }
  });
}
