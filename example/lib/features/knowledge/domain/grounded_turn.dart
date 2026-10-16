import 'package:omnix_example/features/knowledge/presentation/controllers/knowledge_demo_controller.dart';

// Display metadata only. Native history remains authoritative for model replay.
class GroundedTurn {
  GroundedTurn(
    this.userIndex,
    this.question,
    List<KnowledgePassage> sources, {
    this.nativePrompt,
  }) : sources = List.unmodifiable(sources) {
    if (userIndex < 0 ||
        question.trim().isEmpty ||
        question.length > (nativePrompt == null ? 200 : 8192) ||
        sources.isEmpty ||
        sources.length > 3 ||
        sources.any(
          (source) =>
              source.title.length > 120 ||
              source.content.length > 600 ||
              source.content.trim().isEmpty ||
              (source.score != null && !source.score!.isFinite),
        )) {
      throw const FormatException('Invalid saved retrieval evidence.');
    }
    if (nativePrompt != null &&
        (nativePrompt!.isEmpty ||
            nativePrompt!.length > 65536 ||
            !nativePrompt!.endsWith('\nUser request:\n$question') ||
            sources.indexed.any(
              (entry) => !nativePrompt!.contains(
                '\nReference ${entry.$1 + 1}: ${entry.$2.title}\n${entry.$2.content}\n',
              ),
            ))) {
      throw const FormatException('Invalid native retrieval prompt.');
    }
  }
  final int userIndex;
  final String question;
  final List<KnowledgePassage> sources;
  final String? nativePrompt;
  factory GroundedTurn.fromJson(Map<String, dynamic> json) => GroundedTurn(
    json['userIndex'] as int,
    json['question'] as String,
    (json['sources'] as List)
        .map(
          (value) => KnowledgePassage(
            value['title'] as String,
            value['content'] as String,
            (value['score'] as num?)?.toDouble(),
          ),
        )
        .toList(),
    nativePrompt: json['nativePrompt'] as String?,
  );
  Map<String, dynamic> toJson() => {
    'userIndex': userIndex,
    'question': question,
    if (nativePrompt != null) 'nativePrompt': nativePrompt,
    'sources': [
      for (final source in sources)
        {
          'title': source.title,
          'content': source.content,
          'score': source.score,
        },
    ],
  };
}
