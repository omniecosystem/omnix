import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_example/features/knowledge/data/services/text_document_import.dart';

void main() {
  test('imports UTF-8 text and strips BOM without losing Unicode', () {
    final document = decodeKnowledgeText(
      'guide.MD',
      utf8.encode('\uFEFFÉnergie 🔋'),
    );
    expect(document.name, 'guide.MD');
    expect(document.text, 'Énergie 🔋');
  });
  test('rejects unsupported, corrupt, empty and oversized imports', () {
    expect(
      () => decodeKnowledgeText('guide.pdf', [65]),
      throwsUnsupportedError,
    );
    expect(
      () => decodeKnowledgeText('guide.txt', [255]),
      throwsFormatException,
    );
    expect(() => decodeKnowledgeText('guide.txt', [32]), throwsFormatException);
    expect(
      () => decodeKnowledgeText('guide.txt', [0, 65]),
      throwsFormatException,
    );
    expect(
      () => decodeKnowledgeText(
        'guide.txt',
        List.filled(maxKnowledgeTextBytes + 1, 65),
      ),
      throwsStateError,
    );
  });
}
