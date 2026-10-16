import 'dart:async';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:omnix_core/omnix_core.dart';
import 'package:omnix_example/features/core/domain/structured_draft.dart';

class DraftTransport implements OmnixCoreMediaTransport {
  final replies = <String>[];
  final prompts = <String?>[];
  int loads = 0;
  int closedModels = 0;
  int closedChats = 0;
  bool audioEnabled = false;
  Completer<BigInt>? loading;
  @override
  Future<BigInt> loadRoutedModel(
    String path,
    String? library,
    int tokens,
  ) async {
    loads++;
    return loading == null ? BigInt.one : loading!.future;
  }

  @override
  Future<BigInt> loadMediaModel(
    String path,
    String? library,
    int tokens,
    bool images,
    bool audio,
  ) async {
    audioEnabled = audio;
    return loadRoutedModel(path, library, tokens);
  }

  @override
  Future<BigInt> startConversation(
    BigInt id,
    String? prompt,
    int tokens,
  ) async {
    prompts.add(prompt);
    return BigInt.two;
  }

  @override
  Stream<String> sendStream(BigInt id, String text) =>
      Stream.value(replies.removeAt(0));
  @override
  Stream<String> sendMessageStream(BigInt id, List<OmnixInputPart> parts) =>
      sendStream(id, '');
  @override
  Future<void> closeModel(BigInt id) async {
    closedModels++;
  }

  @override
  Future<void> closeConversation(BigInt id) async {
    closedChats++;
  }

  @override
  Future<void> cancelGeneration(BigInt id) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('schema accepts fenced JSON but refuses invented executable fields', () {
    final note = StructuredNote.parse(
      '```json\n{"title":" Transport ","details":"Pay in 2 days"}\n```',
    );
    expect(note.title, 'Transport');
    for (final invalid in [
      '[]',
      '{"title":"","details":"x"}',
      '{"title":"x","details":"x","execute":true}',
      '{"title":1,"details":"x"}',
      '{"title":"${'x' * 101}","details":"x"}',
    ]) {
      expect(() => StructuredNote.parse(invalid), throwsFormatException);
    }
  });
  test(
    'one correction uses a fresh chat and always releases weights',
    () async {
      final transport = DraftTransport()
        ..replies.addAll([
          'not JSON',
          '{"title":"Transport","details":"90 12 34 56, 2 jours"}',
        ]);
      final backend = NativeStructuredDraftBackend(
        core: OmnixCore(transport: transport),
      );
      final note = await backend.draft(
        'model',
        'Transport, 90 12 34 56, 2 jours',
      );
      expect(note.details, contains('2 jours'));
      expect(transport.prompts, hasLength(2));
      expect(transport.prompts.first, contains('Do not execute'));
      expect(transport.loads, 1);
      expect(transport.closedChats, 2);
      expect(transport.closedModels, 1);
      await backend.close();
    },
  );
  test(
    'invalid second output is rejected, never repaired into an action',
    () async {
      final transport = DraftTransport()..replies.addAll(['bad', 'still bad']);
      final backend = NativeStructuredDraftBackend(
        core: OmnixCore(transport: transport),
      );
      await expectLater(
        backend.draft('model', 'a request'),
        throwsFormatException,
      );
      expect(transport.closedChats, 2);
      expect(transport.closedModels, 1);
      await backend.close();
    },
  );
  test(
    'transcription is separate from drafting and requests the audio encoder',
    () async {
      final transport = DraftTransport()..replies.add('une dette');
      final backend = NativeStructuredDraftBackend(
        core: OmnixCore(transport: transport),
      );
      expect(
        await backend.transcribe('model', OmnixInputPart.audio(Uint8List(1))),
        'une dette',
      );
      expect(transport.audioEnabled, isTrue);
      expect(transport.prompts.single, contains('verbatim'));
      expect(transport.closedModels, 1);
      await backend.close();
    },
  );
  test(
    'close during loading drains cleanup and prevents conversation creation',
    () async {
      final transport = DraftTransport()..loading = Completer<BigInt>();
      final backend = NativeStructuredDraftBackend(
        core: OmnixCore(transport: transport),
      );
      final operation = backend.draft('model', 'a note');
      final failure = expectLater(operation, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      var closed = false;
      final closing = backend.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      transport.loading!.complete(BigInt.one);
      await failure;
      await closing;
      expect(transport.prompts, isEmpty);
      expect(transport.closedModels, 1);
    },
  );
}
