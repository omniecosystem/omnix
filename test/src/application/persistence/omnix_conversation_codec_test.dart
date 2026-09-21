import 'dart:typed_data';

import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  const codec = OmnixConversationCodec();

  group('OmnixConversationCodec', () {
    test('round-trips metadata, ordering, and multimodal messages', () {
      final snapshot = OmnixConversationSnapshot(
        record: OmnixConversationRecord(
          id: 'conversation-1',
          title: 'Example',
          modelTemplate: OmnixModelTemplate.gemma4,
          createdAt: DateTime.parse('2026-09-21T12:00:00+02:00'),
          updatedAt: DateTime.parse('2026-09-21T12:01:00+02:00'),
          metadata: const {
            'language': 'en',
            'labels': ['test'],
          },
        ),
        messages: [
          OmnixMessage.text(text: 'hello', role: OmnixMessageRole.user),
          OmnixMessage(
            text: 'result',
            role: OmnixMessageRole.assistant,
            kind: OmnixMessageKind.toolResponse,
            toolName: 'clock',
            imageBytes: Uint8List.fromList([1, 2]),
            images: [
              Uint8List.fromList([3, 4]),
            ],
            audioBytes: Uint8List.fromList([5, 6]),
          ),
        ],
      );

      final encoded = codec.encode(snapshot);
      final decoded = codec.decode(encoded);

      expect(encoded['schemaVersion'], OmnixConversationCodec.schemaVersion);
      expect(decoded.record.id, snapshot.record.id);
      expect(decoded.record.modelTemplate, OmnixModelTemplate.gemma4);
      expect(decoded.record.createdAt, DateTime.utc(2026, 9, 21, 10));
      expect(decoded.record.metadata, snapshot.record.metadata);
      expect(decoded.messages.map((message) => message.text), [
        'hello',
        'result',
      ]);
      expect(decoded.messages.last.toolName, 'clock');
      expect(decoded.messages.last.imageBytes, [1, 2]);
      expect(decoded.messages.last.images.single, [3, 4]);
      expect(decoded.messages.last.audioBytes, [5, 6]);
    });

    test('rejects unknown versions, enum values, and invalid base64', () {
      final encoded = codec.encode(_snapshot());

      expect(
        () => codec.decode({...encoded, 'schemaVersion': 2}),
        throwsFormatException,
      );
      final invalidRole = _copyMessage(encoded, {'role': 'operator'});
      expect(() => codec.decode(invalidRole), throwsFormatException);
      final invalidBytes = _copyMessage(encoded, {'audioBytes': '!'});
      expect(() => codec.decode(invalidBytes), throwsFormatException);
    });

    test('rejects metadata that is not JSON safe', () {
      final snapshot = OmnixConversationSnapshot(
        record: OmnixConversationRecord(
          id: 'conversation-1',
          modelTemplate: OmnixModelTemplate.general,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          metadata: {'invalid': Object()},
        ),
        messages: const [],
      );

      expect(() => codec.encode(snapshot), throwsFormatException);
    });
  });
}

OmnixConversationSnapshot _snapshot() => OmnixConversationSnapshot(
  record: OmnixConversationRecord(
    id: 'conversation-1',
    modelTemplate: OmnixModelTemplate.general,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  ),
  messages: [OmnixMessage.text(text: 'hello', role: OmnixMessageRole.user)],
);

Map<String, Object?> _copyMessage(
  Map<String, Object?> encoded,
  Map<String, Object?> changes,
) {
  final messages = List<Object?>.from(encoded['messages']! as List);
  messages[0] = {...Map<String, Object?>.from(messages[0]! as Map), ...changes};
  return {...encoded, 'messages': messages};
}
