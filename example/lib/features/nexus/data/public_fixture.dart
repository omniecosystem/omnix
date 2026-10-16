import 'dart:convert';

// A deliberately bounded fixture adapter, not the native embedding index.
String answerPublicFixture(String json, String question) {
  final documents = jsonDecode(json);
  if (documents is! List) throw const FormatException('Expected document list');
  final terms = question
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((term) => term.length > 2)
      .toSet();
  for (final entry in documents) {
    if (entry is! Map<String, dynamic> || entry['access'] != 'public') continue;
    final title = entry['title'];
    final content = entry['content'];
    if (title is! String || content is! String) {
      throw const FormatException('Invalid public fixture');
    }
    final words = '$title $content'
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .toSet();
    if (terms.intersection(words).isNotEmpty) return '$content\nSource: $title';
  }
  return '';
}
