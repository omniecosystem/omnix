import 'dart:typed_data';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:omnix_core/omnix_core.dart';
import 'package:omnix_storage/omnix_storage.dart';
import 'package:omnix_example/features/home/data/repositories/chat_repository.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';

class StoreTransport implements OmnixStorageTransport {
  int writes = 0;
  String? saved;
  bool failWrite = false;
  @override
  Future<BigInt> open(String path) async => BigInt.one;
  @override
  Future<void> close(BigInt id) async {}
  @override
  Future<String> request(BigInt id, String operation, String payload) async {
    if (operation == 'write') {
      if (failWrite) throw StateError('Disk full');
      writes++;
      saved = payload;
    }
    if (operation == 'records') return '[]';
    if (operation == 'read') {
      if (saved != null) return saved!;
      return '{"historyVersion":1,"messages":[["user","Saved"]],"record":{"title":"Saved","modelPath":"model"}}';
    }
    return 'null';
  }
}

class DurableTransport extends CoreTransport
    implements OmnixCoreReconfigurationTransport {
  final restores = <String>[];
  final turns = <List<String>>[];
  bool media = false;
  int tokens = 0;
  @override
  Future<void> reconfigureConversation(
    BigInt id,
    int tokens,
    String? sampling,
  ) async {
    this.tokens = tokens;
  }

  @override
  Future<BigInt> loadRoutedModel(String path, String? library, int context) =>
      loadMediaModel(path, library, context, false, false);
  @override
  Future<BigInt> startConversation(
    BigInt id,
    String? prompt,
    int tokens,
  ) async {
    turns.clear();
    media = false;
    this.tokens = tokens;
    return BigInt.two;
  }

  @override
  Stream<String> sendStream(BigInt id, String text) async* {
    turns.addAll([
      ['user', text],
      ['assistant', 'Red'],
    ]);
    yield 'Red';
  }

  @override
  Stream<String> sendMessageStream(
    BigInt id,
    List<OmnixInputPart> parts,
  ) async* {
    if (this.fail) throw StateError('Native failed');
    media = media || parts.any((part) => part.kind != OmnixInputKind.text);
    turns.addAll([
      ['user', 'native-owned input'],
      ['assistant', 'Red'],
    ]);
    yield 'Red';
  }

  @override
  Future<String> conversationHistory(BigInt id, String? snapshot) async {
    if (snapshot != null) {
      restores.add(snapshot);
      final value = jsonDecode(snapshot);
      media = value['version'] == 2;
      final context = media ? jsonDecode(value['context']) : null;
      if (media && context['tokens'] != tokens) {
        throw StateError('Configuration mismatch');
      }
      final pairs = media ? context['turns'] : value['messages'];
      turns.addAll([
        for (final pair in pairs) [pair[0] as String, pair[1] as String],
      ]);
    }
    exports++;
    return jsonEncode(
      media
          ? {
              'version': 2,
              'context': jsonEncode({'turns': turns, 'tokens': tokens}),
            }
          : {'version': 1, 'messages': turns},
    );
  }
}

class CoreTransport
    implements OmnixCoreMediaTransport, OmnixCoreHistoryTransport {
  bool images = false;
  bool audio = false;
  int loads = 0;
  int exports = 0;
  bool fail = false;
  @override
  Future<BigInt> loadMediaModel(
    String modelPath,
    String? libraryPath,
    int contextTokens,
    bool images,
    bool audio,
  ) async {
    loads++;
    this.images = images;
    this.audio = audio;
    return BigInt.one;
  }

  @override
  Future<BigInt> startConversation(
    BigInt id,
    String? prompt,
    int tokens,
  ) async => BigInt.two;
  @override
  Stream<String> sendMessageStream(
    BigInt id,
    List<OmnixInputPart> parts,
  ) async* {
    if (fail) throw StateError('Native failed');
    yield 'Red';
  }

  @override
  Stream<String> sendStream(BigInt id, String text) => Stream.value('Red');
  @override
  Future<void> cancelGeneration(BigInt id) async {}
  @override
  Future<void> closeConversation(BigInt id) async {}
  @override
  Future<void> closeModel(BigInt id) async {}
  @override
  Future<String> conversationHistory(BigInt id, String? snapshot) async {
    exports++;
    throw StateError('Media must never be exported');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final image = ChatAttachment(
    'red.png',
    OmnixInputPart.image(Uint8List.fromList([1])),
  );
  final audio = ChatAttachment(
    'voice.wav',
    OmnixInputPart.audio(Uint8List.fromList([1])),
  );
  late StoreTransport storage;
  late CoreTransport core;
  late NativeChatRepository repository;
  setUp(() {
    storage = StoreTransport();
    core = CoreTransport();
    repository = NativeChatRepository(
      OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
      core: OmnixCore(transport: core),
    );
  });
  tearDown(() => repository.close());
  test(
    'media settings refresh native checkpoint and failed settings saves roll back',
    () async {
      await repository.close();
      final transport = DurableTransport();
      repository = NativeChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
        core: OmnixCore(transport: transport),
        durableMedia: true,
      );
      await repository.generateMessage('model', 'Listen', [
        audio,
      ]).drain<void>();
      await repository.applyGeneration(512, null);
      final saved = storage.saved;
      final value = jsonDecode(saved!);
      expect(value['record']['maxOutputTokens'], 512);
      expect(jsonDecode(value['nativeContext'])['tokens'], 512);
      storage.failWrite = true;
      await expectLater(
        repository.applyGeneration(1024, null),
        throwsStateError,
      );
      expect(transport.tokens, 512);
      expect(repository.maxOutputTokens, 512);
      expect(storage.saved, saved);
      storage.failWrite = false;
      await repository.select(repository.currentId);
      await repository.prepareSaved('model');
      expect(transport.tokens, 512);
      expect(transport.audio, isTrue);
    },
  );
  test(
    'ordinary text voice text persists opaque context and reopens with encoders',
    () async {
      await repository.close();
      final transport = DurableTransport();
      repository = NativeChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
        core: OmnixCore(transport: transport),
        durableMedia: true,
      );
      await repository.generate('model', 'Remember blue').drain<void>();
      final id = repository.currentId!;
      await repository.generateMessage('model', '', [audio]).drain<void>();
      expect(repository.currentId, id);
      expect(transport.loads, 2);
      expect(transport.audio, isTrue);
      expect(transport.restores.single, contains('Remember blue'));
      await repository.generate('model', 'Recall').drain<void>();
      expect(repository.messages.length, 6);
      final saved = jsonDecode(storage.saved!);
      expect(saved['historyVersion'], 2);
      expect(saved['record']['audio'], true);
      expect(saved['messages'][2][1], '[voice.wav]');
      final checkpoint = saved['nativeContext'];
      // Presentation is not the input used to restore native context.
      saved['messages'][0][1] = 'display only';
      storage.saved = jsonEncode(saved);
      await repository.select(id);
      await repository.prepareSaved('model');
      expect(jsonDecode(transport.restores.last)['context'], checkpoint);
      expect(transport.audio, isTrue);
      expect(repository.messages.first.text, 'display only');
      await repository.generateMessage('model', 'Look', [image]).drain<void>();
      expect(transport.images, isTrue);
      expect(transport.audio, isTrue);
      expect(repository.currentId, id);
      expect(repository.messages.length, 8);
    },
  );
  test(
    'failed durable save retains last completed context, not unsaved media',
    () async {
      await repository.close();
      final transport = DurableTransport();
      repository = NativeChatRepository(
        OmnixConversationSnapshotStore(path: 'test.sqlite', transport: storage),
        core: OmnixCore(transport: transport),
        durableMedia: true,
      );
      await repository.generate('model', 'Remember').drain<void>();
      final saved = storage.saved;
      storage.failWrite = true;
      await expectLater(
        repository.generateMessage('model', '', [audio]).drain<void>(),
        throwsStateError,
      );
      expect(storage.saved, saved);
      expect(repository.messages.length, 2);
      storage.failWrite = false;
      await repository.generate('model', 'Continue').drain<void>();
      expect(jsonDecode(transport.restores.last)['version'], 1);
      expect(repository.messages.length, 4);
    },
  );
  test(
    'media and followups remain native but never publish lossy history',
    () async {
      await repository.generateMessage('model', 'Color?', [
        image,
      ]).drain<void>();
      await repository.generate('model', 'Recall?').drain<void>();
      expect(core.images, isTrue);
      expect(core.audio, isFalse);
      expect(core.loads, 1);
      expect(core.exports, 0);
      expect(storage.writes, 0);
      expect(repository.currentId, isNull);
      expect(repository.messages.length, 4);
      await expectLater(
        repository.generateMessage('model', 'Listen', [audio]).drain<void>(),
        throwsStateError,
      );
      expect(core.loads, 1);
    },
  );
  test('saved text is not converted or overwritten by media', () async {
    await repository.select('saved');
    await expectLater(
      repository.generateMessage('model', '', [image]).drain<void>(),
      throwsStateError,
    );
    expect(repository.currentId, 'saved');
    expect(repository.messages.single.text, 'Saved');
    expect(core.loads, 0);
    expect(storage.writes, 0);
  });
  test(
    'failed media context cannot be silently replayed without its bytes',
    () async {
      core.fail = true;
      await expectLater(
        repository.generateMessage('model', 'Color?', [image]).drain<void>(),
        throwsStateError,
      );
      core.fail = false;
      await expectLater(
        repository.generateMessage('model', 'Recall?', []).drain<void>(),
        throwsStateError,
      );
      expect(storage.writes, 0);
      await repository.select(null);
      expect(
        await repository.generateMessage('model', 'Color?', [image]).join(),
        'Red',
      );
    },
  );
}
