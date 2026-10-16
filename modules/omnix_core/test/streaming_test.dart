import 'dart:async';

import 'package:omnix_core/omnix_core.dart';
import 'package:test/test.dart';

class _StreamingTransport implements OmnixCoreStreamingTransport {
  final started = Completer<void>();
  final resume = Completer<void>();
  int cancellations = 0;
  int closes = 0;
  bool stopped = false;
  bool fail = false;
  @override
  Future<List<String>> supportedPlatforms() async => ['windows'];
  @override
  Future<BigInt> loadTrustedModel(
    String libraryPath,
    String modelPath,
    int contextTokens,
  ) async => BigInt.one;
  @override
  Future<BigInt> startConversation(
    BigInt modelId,
    String? systemPrompt,
    int maxOutputTokens,
  ) async => BigInt.two;
  @override
  Future<String> send(BigInt conversationId, String text) async => 'follow-up';
  @override
  Stream<String> sendStream(BigInt conversationId, String text) async* {
    started.complete();
    yield 'first ';
    await resume.future;
    if (fail) throw StateError('generation failed');
    if (!stopped) yield 'second';
  }

  @override
  Future<void> cancelGeneration(BigInt conversationId) async {
    cancellations++;
    stopped = true;
    if (!resume.isCompleted) resume.complete();
  }

  @override
  Future<void> closeModel(BigInt modelId) async {}
  @override
  Future<void> closeConversation(BigInt conversationId) async {
    closes++;
  }
}

class _ThinkingTransport extends _StreamingTransport
    implements
        OmnixCoreThinkingTransport,
        OmnixCoreThinkingConfigurationTransport {
  final changes = <bool>[];
  @override
  Future<void> setThinking(BigInt id, bool enabled) async {
    changes.add(enabled);
  }

  bool thinkingOpened = false;
  String? sampler;
  @override
  Future<BigInt> startThinkingConversation(
    BigInt modelId,
    String? systemPrompt,
    int maxOutputTokens,
    String? samplingJson,
  ) async {
    thinkingOpened = true;
    sampler = samplingJson;
    return BigInt.two;
  }

  @override
  Stream<OmnixCoreOutput> sendMessageEvents(
    BigInt id,
    List<OmnixInputPart> parts,
  ) async* {
    started.complete();
    yield const OmnixCoreOutput(
      OmnixCoreOutputKind.reasoning,
      'native reasoning',
    );
    yield const OmnixCoreOutput(OmnixCoreOutputKind.text, 'first ');
    await resume.future;
    if (!stopped) {
      yield const OmnixCoreOutput(OmnixCoreOutputKind.text, 'second');
    }
  }
}

void main() {
  Future<OmnixCoreConversation> open(
    _StreamingTransport transport, {
    bool thinking = false,
  }) async {
    final model = await OmnixCore(
      transport: transport,
    ).loadTrustedLiteRtLm(libraryPath: 'trusted', modelPath: 'model');
    final chat = await model.startConversation(thinking: thinking);
    await model.close();
    return chat;
  }

  test(
    'typed reasoning uses native configuration without implicit sampling',
    () async {
      final transport = _ThinkingTransport();
      final chat = await open(transport, thinking: true);
      final response = chat.sendMessageEvents([
        OmnixInputPart.text('hello'),
      ]).toList();
      await transport.started.future;
      transport.resume.complete();
      final events = await response;
      expect(transport.thinkingOpened, isTrue);
      expect(transport.sampler, isNull);
      expect(events.map((e) => e.kind), [
        OmnixCoreOutputKind.reasoning,
        OmnixCoreOutputKind.text,
        OmnixCoreOutputKind.text,
      ]);
      expect(events.map((e) => e.text), [
        'native reasoning',
        'first ',
        'second',
      ]);
      await chat.close();
    },
  );
  test(
    'text API filters reasoning while preserving native cancellation and follow-up',
    () async {
      final transport = _ThinkingTransport();
      final chat = await open(transport, thinking: true);
      expect(await chat.sendStream('hello').take(1).join(), 'first ');
      expect(transport.cancellations, 1);
      expect(await chat.send('again'), 'follow-up');
      await chat.close();
    },
  );
  test(
    'legacy transports reject unsupported thinking rather than ignoring it',
    () async {
      await expectLater(
        open(_StreamingTransport(), thinking: true),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'normal completion preserves deltas and does not stop the native turn',
    () async {
      final transport = _StreamingTransport();
      final chat = await open(transport);
      final answer = chat.sendStream('hello').join();
      await transport.started.future;
      transport.resume.complete();
      expect(await answer, 'first second');
      await chat.cancelGeneration();
      expect(transport.cancellations, 0);
      expect(await chat.send('again'), 'follow-up');
      await chat.close();
    },
  );
  test(
    'live reasoning changes do not reopen the conversation or drop following work',
    () async {
      final transport = _ThinkingTransport();
      final chat = await open(transport, thinking: true);
      await chat.setThinking(false);
      expect(transport.changes, [false]);
      expect(transport.closes, 0);
      expect(await chat.send('again'), 'follow-up');
      await chat.close();
    },
  );
  test(
    'close stops an active stream and drains it before releasing the handle',
    () async {
      final transport = _StreamingTransport();
      final chat = await open(transport);
      final answer = chat.sendStream('hello').join();
      await transport.started.future;
      await expectLater(chat.sendStream('overlap').join(), throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(
        transport.cancellations,
        0,
        reason: 'A rejected stream must not cancel another turn',
      );
      await chat.close();
      await answer;
      expect(transport.cancellations, 1);
      expect(transport.closes, 1);
      await chat.close();
      expect(transport.closes, 1);
    },
  );
  test('a stopped stream allows a following turn', () async {
    final transport = _StreamingTransport();
    final chat = await open(transport);
    final answer = chat.sendStream('hello').join();
    await transport.started.future;
    await chat.cancelGeneration();
    await answer;
    expect(await chat.send('again'), 'follow-up');
    await chat.close();
  });
  test(
    'cancelling a paused subscription drains native work without resuming',
    () async {
      final transport = _StreamingTransport();
      final chat = await open(transport);
      final subscription = chat.sendStream('hello').listen((_) {});
      await transport.started.future;
      subscription.pause();
      await subscription.cancel();
      expect(transport.cancellations, 1);
      expect(await chat.send('again'), 'follow-up');
      await chat.close();
    },
  );
  test(
    'abandoning after a delta signals stop and keeps follow-up usable',
    () async {
      final transport = _StreamingTransport();
      final chat = await open(transport);
      expect(await chat.sendStream('hello').take(1).join(), 'first ');
      expect(transport.cancellations, 1);
      expect(await chat.send('again'), 'follow-up');
      await chat.close();
    },
  );
  test(
    'backend stream errors invalidate the conversation but not cleanup',
    () async {
      final transport = _StreamingTransport()..fail = true;
      final chat = await open(transport);
      final answer = chat.sendStream('hello').join();
      final assertion = expectLater(answer, throwsStateError);
      await transport.started.future;
      transport.resume.complete();
      await assertion;
      await expectLater(chat.send('again'), throwsStateError);
      await chat.close();
      expect(transport.closes, 1);
    },
  );
}
