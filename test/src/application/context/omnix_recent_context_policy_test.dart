import 'dart:typed_data';

import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  group('OmnixRecentContextPolicy', () {
    test('preserves system information and the newest contiguous history', () {
      const policy = OmnixRecentContextPolicy(
        budget: OmnixContextBudget(
          contextWindowTokens: 9,
          reservedOutputTokens: 0,
        ),
        estimator: _TextLengthEstimator(),
      );
      final history = [
        _message('sys', kind: OmnixMessageKind.systemInfo),
        _message('1111'),
        _message('2222'),
        _message('33'),
      ];

      final selection = policy.select(history);

      expect(selection.messages.map((message) => message.text), [
        'sys',
        '2222',
        '33',
      ]);
      expect(selection.estimatedInputTokens, 9);
      expect(selection.omittedMessageCount, 1);
      expect(selection.wasTrimmed, isTrue);
    });

    test('reserves capacity for pending input without returning it', () {
      const policy = OmnixRecentContextPolicy(
        budget: OmnixContextBudget(
          contextWindowTokens: 9,
          reservedOutputTokens: 0,
        ),
        estimator: _TextLengthEstimator(),
        preserveSystemInformation: false,
      );

      final selection = policy.select(
        [_message('1111'), _message('2222'), _message('33')],
        additionalMessages: [_message('12345')],
      );

      expect(selection.messages.map((message) => message.text), ['33']);
      expect(selection.estimatedInputTokens, 7);
      expect(selection.omittedMessageCount, 2);
    });

    test('rejects mandatory context that cannot fit', () {
      const policy = OmnixRecentContextPolicy(
        budget: OmnixContextBudget(
          contextWindowTokens: 10,
          reservedOutputTokens: 0,
        ),
        estimator: _TextLengthEstimator(),
      );

      expect(
        () => policy.select(
          [_message('system', kind: OmnixMessageKind.systemInfo)],
          additionalMessages: [_message('12345')],
        ),
        throwsA(
          isA<OmnixContextOverflowException>()
              .having((error) => error.requiredTokens, 'requiredTokens', 11)
              .having((error) => error.availableTokens, 'availableTokens', 10),
        ),
      );
    });

    test('default estimator accounts for attachments', () {
      const estimator = OmnixApproximateTokenEstimator(
        messageOverheadTokens: 4,
        imageTokens: 10,
        audioTokens: 20,
      );
      final plain = _message('1234');
      final multimodal = OmnixMessage(
        text: '1234',
        role: OmnixMessageRole.user,
        imageBytes: Uint8List.fromList([1]),
        images: [
          Uint8List.fromList([2]),
        ],
        audioBytes: Uint8List.fromList([3]),
      );

      expect(estimator.estimateMessage(plain), 5);
      expect(estimator.estimateMessage(multimodal), 45);
    });
  });
}

OmnixMessage _message(
  String text, {
  OmnixMessageKind kind = OmnixMessageKind.text,
}) => OmnixMessage(text: text, role: OmnixMessageRole.user, kind: kind);

final class _TextLengthEstimator implements OmnixTokenEstimator {
  const _TextLengthEstimator();

  @override
  int estimateMessage(OmnixMessage message) => message.text.length;

  @override
  int estimateText(String text) => text.length;
}
