import 'package:test/test.dart';
import 'package:omnix_knowledge/omnix_knowledge.dart';

void main() {
  test('record roundtrip retains attribution and defaults private', () {
    const record = OmnixKnowledgeRecord(
      id: 'chunk',
      documentId: 'doc',
      content: 'Équipement',
      title: 'Guide',
    );
    final decoded = OmnixKnowledgeRecord.fromJson(record.toJson());
    expect(decoded.toJson(), record.toJson());
    expect(decoded.public, isFalse);
    expect(decoded.location, isNull);
  });
  test('invalid payload fails rather than adopting public visibility', () {
    expect(
      () => OmnixKnowledgeRecord.fromJson({'id': 'chunk'}),
      throwsA(isA<TypeError>()),
    );
  });
}
