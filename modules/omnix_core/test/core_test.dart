import 'dart:async';

import 'package:omnix_core/omnix_core.dart';
import 'package:test/test.dart';

class _Transport implements OmnixCoreHistoryTransport {
  bool failRestore = false;
  String history = '{"version":1,"messages":[]}';
  @override
  Future<String> conversationHistory(
    BigInt conversationId,
    String? snapshot,
  ) async {
    if (snapshot != null) {
      if (failRestore) throw StateError('Invalid history');
      history = snapshot;
    }
    return history;
  }

  int loads = 0;
  int sends = 0;
  int modelCloses = 0;
  int chatCloses = 0;
  Completer<void>? block;
  bool failSend = false;
  @override
  Future<List<String>> supportedPlatforms() async => ['windows'];
  @override
  Future<BigInt> loadTrustedModel(
    String libraryPath,
    String modelPath,
    int contextTokens,
  ) async {
    loads++;
    return BigInt.one;
  }

  @override
  Future<BigInt> startConversation(
    BigInt modelId,
    String? systemPrompt,
    int maxOutputTokens,
  ) async => BigInt.two;
  @override
  Future<String> send(BigInt conversationId, String text) async {
    sends++;
    await block?.future;
    if (failSend) throw StateError('backend failure');
    return 'Reply: $text';
  }

  @override
  Future<void> closeModel(BigInt modelId) async {
    modelCloses++;
  }

  @override
  Future<void> closeConversation(BigInt conversationId) async {
    chatCloses++;
  }
}

void main() {
  test(
    'history is delegated and restore failure invalidates the handle',
    () async {
      final transport = _Transport();
      final model = await OmnixCore(
        transport: transport,
      ).loadTrustedLiteRtLm(libraryPath: 'trusted', modelPath: 'model');
      final chat = await model.startConversation();
      const snapshot =
          '{"version":1,"messages":[["user","Hello"],["assistant","Hi"]]}';
      await chat.restoreHistory(snapshot);
      expect(await chat.exportHistory(), snapshot);
      transport.failRestore = true;
      await expectLater(chat.restoreHistory('bad'), throwsStateError);
      await expectLater(chat.send('hello'), throwsStateError);
      await chat.close();
      await model.close();
    },
  );
  Future<OmnixCoreModel> load(_Transport transport) => OmnixCore(
    transport: transport,
  ).loadTrustedLiteRtLm(libraryPath: 'trusted-runtime', modelPath: 'model');
  test(
    'conversations remain usable after the model handle is closed',
    () async {
      final transport = _Transport();
      final model = await load(transport);
      final chat = await model.startConversation();
      await model.close();
      await model.close();
      await expectLater(model.startConversation(), throwsStateError);
      expect(await chat.send('hello'), 'Reply: hello');
      await chat.close();
      await chat.close();
      expect(transport.modelCloses, 1);
      expect(transport.chatCloses, 1);
    },
  );
  test('turns serialize and close waits for accepted work', () async {
    final transport = _Transport()..block = Completer<void>();
    final model = await load(transport);
    final chat = await model.startConversation();
    final first = chat.send('first');
    final second = chat.send('second');
    final closing = chat.close();
    await expectLater(chat.send('too late'), throwsStateError);
    transport.block!.complete();
    expect(await first, 'Reply: first');
    expect(await second, 'Reply: second');
    await closing;
    expect(transport.sends, 2);
    await model.close();
  });
  test(
    'backend failure invalidates subsequent turns without poisoning close',
    () async {
      final transport = _Transport()..failSend = true;
      final model = await load(transport);
      final chat = await model.startConversation();
      await expectLater(chat.send('first'), throwsStateError);
      await expectLater(chat.send('second'), throwsStateError);
      expect(transport.sends, 1);
      await chat.close();
      await model.close();
    },
  );
  test('invalid paths and limits fail before model loading', () async {
    final transport = _Transport();
    await expectLater(
      OmnixCore(
        transport: transport,
      ).loadTrustedLiteRtLm(libraryPath: '', modelPath: 'model'),
      throwsArgumentError,
    );
    expect(transport.loads, 0);
    final model = await load(transport);
    await expectLater(
      model.startConversation(maxOutputTokens: 0),
      throwsArgumentError,
    );
    final chat = await model.startConversation();
    await expectLater(chat.send('  '), throwsArgumentError);
    expect(transport.sends, 0);
    await chat.close();
    await model.close();
  });
}
