import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_knowledge_example/knowledge_demo_controller.dart';

class Backend implements KnowledgeDemoBackend {
  final calls = <String>[];
  bool noMatches = false;
  bool failIndex = false;
  @override
  Future<void> indexAndReopen({
    required String encoder,
    required String tokenizer,
    required bool legacyGecko,
    required String title,
    required String content,
  }) async {
    calls.add('index/reopen');
    if (failIndex) throw StateError('index failed');
  }

  @override
  Future<List<KnowledgePassage>> retrieve(String question) async {
    calls.add('retrieve');
    return noMatches
        ? []
        : [const KnowledgePassage('Guide', 'Press reset.', 0.85)];
  }

  @override
  Future<String> answer(String model, String prompt) async {
    calls.add('answer');
    expect(prompt, contains('Press reset.'));
    return 'Press reset.';
  }

  @override
  Future<void> close() async {
    calls.add('close');
  }
}

Future<void> index(KnowledgeDemoController controller) => controller.index(
  encoder: 'encoder',
  tokenizer: 'tokenizer',
  legacyGecko: true,
  title: 'Guide',
  content: 'Press reset.',
);
void main() {
  test('indexes/reopens before retrieval and sourced generation', () async {
    final backend = Backend();
    final controller = KnowledgeDemoController(backend);
    await index(controller);
    await controller.ask(model: 'model', question: 'How?');
    expect(backend.calls, ['index/reopen', 'retrieve', 'answer']);
    expect(controller.answer, 'Press reset.');
    expect(controller.passages.single.title, 'Guide');
    expect(controller.error, isNull);
    await controller.close();
    controller.dispose();
  });
  test(
    'no matches never invokes generation; failed indexing disables query',
    () async {
      final backend = Backend()..noMatches = true;
      final controller = KnowledgeDemoController(backend);
      await index(controller);
      await controller.ask(model: 'model', question: 'How?');
      expect(backend.calls, ['index/reopen', 'retrieve']);
      expect(controller.answer, isNull);
      backend.failIndex = true;
      await index(controller);
      expect(controller.indexed, isFalse);
      expect(controller.error, contains('index failed'));
      controller.dispose();
    },
  );
  test('context is bounded and keeps Unicode and source attribution', () {
    final prompt = buildKnowledgePrompt('Comment?', [
      const KnowledgePassage('Équipement', 'Appuyez sur réinitialiser.', 0.8),
    ]);
    expect(prompt, contains('[1] Équipement'));
    expect(prompt, contains('untrusted reference data'));
    expect(
      () => buildKnowledgePrompt('How?', [
        KnowledgePassage('Too long', 'a' * 601, 1),
      ]),
      throwsStateError,
    );
  });
}
