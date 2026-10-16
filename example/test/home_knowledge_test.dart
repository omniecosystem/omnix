import 'dart:async';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:omnix_core/omnix_core.dart';
import 'package:omnix_storage/omnix_storage.dart';
import 'package:omnix_example/features/home/data/repositories/chat_repository.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';
import 'package:omnix_example/features/knowledge/domain/grounded_turn.dart';
import 'package:omnix_example/features/knowledge/presentation/controllers/knowledge_demo_controller.dart';
import 'chat_instructions_test.dart'
    show InstructionStore, InstructionTransport;

class GroundedTransport extends InstructionTransport {
  final pairs = <List<String>>[];
  int generations = 0;
  String? systemPrompt;
  @override
  Future<BigInt> startConversation(
    BigInt id,
    String? prompt,
    int tokens,
  ) async {
    systemPrompt = prompt;
    return BigInt.two;
  }

  @override
  Stream<String> sendStream(BigInt id, String text) async* {
    generations++;
    pairs.addAll([
      ['user', text],
      ['assistant', 'Wait for blue.'],
    ]);
    yield 'Wait for blue.';
  }

  @override
  Future<String> conversationHistory(BigInt id, String? snapshot) async {
    if (snapshot != null) {
      pairs.clear();
      pairs.addAll(
        (jsonDecode(snapshot)['messages'] as List).map(
          (pair) => (pair as List).cast<String>(),
        ),
      );
    }
    return jsonEncode({'version': 1, 'messages': pairs});
  }
}

class RetrievalBackend implements KnowledgeDemoBackend {
  List<KnowledgePassage> hits = [
    const KnowledgePassage(
      'Router manual',
      'Hold reset for ten seconds and wait for blue.',
      0.95,
    ),
  ];
  Completer<List<KnowledgePassage>>? pending;
  @override
  Future<List<KnowledgePassage>> retrieve(String question) async =>
      pending == null ? hits : pending!.future;
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late InstructionStore store;
  late GroundedTransport transport;
  late NativeChatRepository repository;
  late RetrievalBackend retrieval;
  late KnowledgeDemoController knowledge;
  late CoreController home;
  setUp(() {
    store = InstructionStore();
    transport = GroundedTransport();
    repository = NativeChatRepository(
      OmnixConversationSnapshotStore(path: 'test.sqlite', transport: store),
      core: OmnixCore(transport: transport),
    );
    retrieval = RetrievalBackend();
    knowledge = KnowledgeDemoController(retrieval)..indexed = true;
    home = CoreController(repository, knowledge: knowledge)
      ..configureKnowledge(true);
  });
  tearDown(() async {
    await home.close();
    home.dispose();
    knowledge.dispose();
  });
  test(
    'Home retrieves before generation and preserves sources across replay',
    () async {
      await home.send('model', 'How do I reset?');
      expect(home.error, isNull);
      expect(home.messages.first.text, 'How do I reset?');
      expect(home.messages.last.sources.single.title, 'Router manual');
      expect(transport.pairs.first.last, contains('PASSAGES'));
      expect(transport.systemPrompt, contains('untrusted data'));
      final record = ChatRecord(home.selectedId!, 'Reset', 'model');
      await home.select(null);
      await home.select(record);
      expect(home.useKnowledge, isTrue);
      expect(
        home.messages.last.sources.single.content,
        contains('ten seconds'),
      );
      expect(home.messages.first.text, 'How do I reset?');
      await home.send('model', 'What color?');
      expect(home.error, isNull);
      expect(home.messages, hasLength(4));
      expect(home.messages.last.sources, hasLength(1));
    },
  );
  test(
    'no hit never loads/generates or writes a made-up grounded answer',
    () async {
      retrieval.hits = [];
      await home.send('model', 'Unknown?');
      expect(transport.generations, 0);
      expect(store.snapshot, isNull);
      expect(home.error, contains('No answer was generated'));
    },
  );
  test(
    'stop during retrieval prevents generation after its eventual result',
    () async {
      retrieval.pending = Completer<List<KnowledgePassage>>();
      final work = home.send('model', 'How do I reset?');
      await Future<void>.delayed(Duration.zero);
      await home.stop();
      retrieval.pending!.complete(retrieval.hits);
      await work;
      expect(transport.generations, 0);
      expect(home.busy, isFalse);
    },
  );
  test(
    'missing index refuses a grounded request without changing the chat',
    () async {
      knowledge.indexed = false;
      await home.send('model', 'Reset?');
      expect(home.messages, isEmpty);
      expect(transport.generations, 0);
      expect(home.error, contains('Open Knowledge first'));
    },
  );
  test(
    'stored evidence must match native history, not silently relabel it',
    () async {
      await home.send('model', 'Reset?');
      final original = repository.messages;
      final value = jsonDecode(store.snapshot!);
      value['record']['groundedTurns'][0]['question'] = 'Changed question';
      store.snapshot = jsonEncode(value);
      await expectLater(repository.select('saved'), throwsFormatException);
      expect(repository.messages, same(original));
    },
  );
  test('retrieval metadata round trips and rejects oversized evidence', () {
    final turn = GroundedTurn(0, 'Reset?', retrieval.hits);
    expect(
      GroundedTurn.fromJson(
        jsonDecode(jsonEncode(turn.toJson())),
      ).sources.single.score,
      0.95,
    );
    expect(
      () => GroundedTurn(0, 'Reset?', [
        KnowledgePassage('Manual', 'x' * 601, 0.9),
      ]),
      throwsFormatException,
    );
  });
}
