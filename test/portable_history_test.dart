import 'dart:convert';
import 'dart:typed_data';
import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  test(
    'portable encoding preserves mixed inputs and has no native state or grants',
    () {
      final turn = OmnixHistoryTurn(
        input: [
          OmnixInteractionInput.text('Historical request'),
          OmnixInteractionInput.image(Uint8List.fromList([1, 2])),
          OmnixInteractionInput.audio(Uint8List.fromList([3, 4])),
        ],
        observations: [
          const OmnixHistoryObservation(
            kind: OmnixHistoryObservationKind.result,
            name: 'old-handler',
            text: 'failed',
          ),
        ],
      );
      final json = jsonDecode(encodeOmnixHistory([turn])) as Map;
      expect(json.keys, unorderedEquals(['version', 'turns']));
      expect(json['version'], 3);
      final value = (json['turns'] as List).single as Map;
      expect(value['answer'], isNull);
      expect(value['input'], [
        {'type': 'text', 'text': 'Historical request'},
        {'type': 'image', 'blob': 'AQI='},
        {'type': 'audio', 'blob': 'AwQ='},
      ]);
      expect(() => turn.input.clear(), throwsUnsupportedError);
      expect(() => turn.observations.clear(), throwsUnsupportedError);
    },
  );
}
