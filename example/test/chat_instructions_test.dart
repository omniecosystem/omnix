import 'dart:convert';
import 'package:test/test.dart';
import 'package:omnix_core/omnix_core.dart';
import 'package:omnix_storage/omnix_storage.dart';
import 'package:omnix_example/features/home/data/repositories/chat_repository.dart';
import 'chat_media_repository_test.dart' show CoreTransport;

class InstructionStore implements OmnixStorageTransport {
  String? snapshot;
  @override
  Future<BigInt> open(String path) async => BigInt.one;
  @override
  Future<void> close(BigInt id) async {}
  @override
  Future<String> request(BigInt id, String operation, String payload) async {
    if (operation == 'write') snapshot = payload;
    if (operation == 'read') return snapshot ?? 'null';
    return '[]';
  }
}

class InstructionTransport extends CoreTransport {
  String? prompt;
  @override
  Future<BigInt> loadRoutedModel(
    String path,
    String? library,
    int tokens,
  ) async => BigInt.one;
  @override
  Future<BigInt> startConversation(
    BigInt id,
    String? prompt,
    int tokens,
  ) async {
    this.prompt = prompt;
    return BigInt.two;
  }

  @override
  Future<String> conversationHistory(BigInt id, String? snapshot) async =>
      snapshot ??
      '{"version":1,"messages":[["user","Hello"],["assistant","Red"]]}';
}

void main() {
  test('instructions reach Core and survive saved chat reopening', () async {
    final storage = InstructionStore();
    final transport = InstructionTransport();
    final repository = NativeChatRepository(
      OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
      core: OmnixCore(transport: transport),
    );
    addTearDown(repository.close);
    repository.configureInstructions(' Reply in French. ');
    await repository.generate('model', 'Hello').drain<void>();
    expect(transport.prompt, 'Reply in French.');
    expect(
      jsonDecode(storage.snapshot!)['record']['systemPrompt'],
      'Reply in French.',
    );
    expect(() => repository.configureInstructions('Changed'), throwsStateError);
    await repository.select(null);
    expect(repository.instructions, isEmpty);
    await repository.select('saved');
    expect(repository.instructions, 'Reply in French.');
    await repository.generate('model', 'Again').drain<void>();
    expect(transport.prompt, 'Reply in French.');
  });
  test('old records without instructions remain readable', () async {
    final storage = InstructionStore()
      ..snapshot =
          '{"historyVersion":1,"messages":[],"record":{"title":"Old","modelPath":"model"}}';
    final repository = NativeChatRepository(
      OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
      core: OmnixCore(transport: InstructionTransport()),
    );
    addTearDown(repository.close);
    await repository.select('saved');
    expect(repository.instructions, isEmpty);
  });
}
