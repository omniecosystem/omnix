import 'dart:async';
import 'dart:typed_data';

import 'package:omnix_core/omnix_core.dart';
import 'package:test/test.dart';

class MediaTransport implements OmnixCoreMediaTransport {
  List<OmnixInputPart>? received;
  bool images = false;
  bool audio = false;
  int cancellations = 0;
  int textCalls = 0;
  final started = Completer<void>();
  final finish = Completer<void>();

  @override
  Future<BigInt> loadMediaModel(
    String modelPath,
    String? libraryPath,
    int contextTokens,
    bool images,
    bool audio,
  ) async {
    this.images = images;
    this.audio = audio;
    return BigInt.one;
  }

  @override
  Future<BigInt> loadRoutedModel(
    String modelPath,
    String? libraryPath,
    int contextTokens,
  ) async => BigInt.one;

  @override
  Future<BigInt> startConversation(
    BigInt modelId,
    String? systemPrompt,
    int maxOutputTokens,
  ) async => BigInt.two;

  @override
  Future<String> send(BigInt conversationId, String text) async {
    textCalls++;
    return text;
  }

  @override
  Future<String> sendMessage(
    BigInt conversationId,
    List<OmnixInputPart> parts,
  ) async {
    received = parts;
    return 'media answer';
  }

  @override
  Stream<String> sendMessageStream(
    BigInt conversationId,
    List<OmnixInputPart> parts,
  ) async* {
    received = parts;
    started.complete();
    yield 'first ';
    await finish.future;
    if (cancellations == 0) yield 'second';
  }

  @override
  Future<void> cancelGeneration(BigInt conversationId) async {
    cancellations++;
    if (!finish.isCompleted) finish.complete();
  }

  @override
  Future<void> closeConversation(BigInt conversationId) async {}
  @override
  Future<void> closeModel(BigInt modelId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('input owns immutable bytes independent of caller mutations', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final part = OmnixInputPart.image(bytes);
    bytes[0] = 99;
    expect(part.bytes, [1, 2, 3]);
    expect(() => part.bytes[0] = 99, throwsUnsupportedError);
  });

  test(
    'ordered media reaches the transport only after explicit enablement',
    () async {
      final transport = MediaTransport();
      final model = await OmnixCore(
        transport: transport,
      ).loadModel(modelPath: 'trusted', enableImages: true, enableAudio: true);
      final chat = await model.startConversation();
      final parts = [
        OmnixInputPart.text('describe'),
        OmnixInputPart.image(Uint8List.fromList([1])),
        OmnixInputPart.audio(Uint8List.fromList([2])),
      ];
      final response = chat.sendMessage(parts);
      parts.clear();
      expect(await response, 'media answer');
      expect(transport.images, isTrue);
      expect(transport.audio, isTrue);
      expect(transport.received!.map((part) => part.kind), [
        OmnixInputKind.text,
        OmnixInputKind.image,
        OmnixInputKind.audio,
      ]);
      await chat.close();
      await model.close();
    },
  );

  test(
    'unsupported media is rejected without poisoning text conversation',
    () async {
      final transport = MediaTransport();
      final model = await OmnixCore(
        transport: transport,
      ).loadModel(modelPath: 'trusted');
      final chat = await model.startConversation();
      await expectLater(
        chat.sendMessage([
          OmnixInputPart.image(Uint8List.fromList([1])),
        ]),
        throwsUnsupportedError,
      );
      await expectLater(
        chat.sendMessageStream([
          OmnixInputPart.audio(Uint8List.fromList([1])),
        ]).toList(),
        throwsUnsupportedError,
      );
      expect(transport.received, isNull);
      expect(
        await chat.sendMessage([
          OmnixInputPart.text('hello '),
          OmnixInputPart.text('world'),
        ]),
        'hello world',
      );
      expect(transport.textCalls, 1);
      await chat.close();
      await model.close();
    },
  );

  test('empty parts fail before native work', () async {
    final transport = MediaTransport();
    final model = await OmnixCore(
      transport: transport,
    ).loadModel(modelPath: 'trusted');
    final chat = await model.startConversation();
    await expectLater(chat.sendMessage([]), throwsArgumentError);
    expect(transport.received, isNull);
    await chat.close();
    await model.close();
  });

  test(
    'media cancellation drains native completion and allows next text turn',
    () async {
      final transport = MediaTransport();
      final model = await OmnixCore(
        transport: transport,
      ).loadModel(modelPath: 'trusted', enableImages: true);
      final chat = await model.startConversation();
      final results = chat.sendMessageStream([
        OmnixInputPart.image(Uint8List.fromList([1])),
      ]).toList();
      await transport.started.future;
      await chat.cancelGeneration();
      expect(await results, ['first ']);
      expect(transport.cancellations, 1);
      expect(await chat.send('follow up'), 'follow up');
      await chat.close();
      await model.close();
    },
  );
}
