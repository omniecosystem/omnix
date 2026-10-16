import 'dart:io';
import 'package:omnix_core/omnix_core.dart';
import 'package:test/test.dart';
import 'native_test_support.dart';

void main() {
  final model = Platform.environment['OMNIX_CORE_TEST_MODEL'];
  final gguf = Platform.environment['OMNIX_GGUF_MODEL'];
  test(
    'llama.cpp shares weights while retaining independent live histories',
    () async {
      await initializeTestBridge();
      final core = OmnixCore();
      final owners = await Future.wait([
        core.loadModel(modelPath: gguf!, shareRuntime: true),
        core.loadModel(modelPath: gguf, shareRuntime: true),
      ]);
      OmnixCoreConversation? first;
      OmnixCoreConversation? second;
      try {
        expect(await core.sharedModelCount(), 1);
        first = await owners[0].startConversation(maxOutputTokens: 16);
        second = await owners[1].startConversation(maxOutputTokens: 16);
        for (final owner in owners) {
          await owner.close();
        }
        expect(await core.sharedModelCount(), 1);
        expect(await first.send('Remember violet. Reply briefly.'), isNotEmpty);
        expect(await first.exportHistory(), contains('violet'));
        expect(await second.exportHistory(), isNot(contains('violet')));
        await first.close();
        expect(await core.sharedModelCount(), 1);
        expect(await second.send('Reply with just hello.'), isNotEmpty);
      } finally {
        await first?.close();
        await second?.close();
        for (final owner in owners) {
          await owner.close();
        }
      }
      expect(await core.sharedModelCount(), 0);
    },
    skip: !Platform.isWindows || gguf == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'native shared owners retain one engine without leaking chat history',
    () async {
      await initializeTestBridge();
      final core = OmnixCore();
      expect(await core.sharedModelCount(), 0);
      final owners = await Future.wait([
        core.loadModel(modelPath: model!, shareRuntime: true),
        core.loadModel(modelPath: model, shareRuntime: true),
      ]);
      OmnixCoreConversation? chat;
      OmnixCoreConversation? other;
      OmnixCoreModel? extra;
      try {
        expect(await core.sharedModelCount(), 1);
        chat = await owners[0].startConversation(maxOutputTokens: 16);
        other = await owners[1].startConversation(maxOutputTokens: 16);
        await owners[0].close();
        await owners[1].close();
        expect(await core.sharedModelCount(), 1);
        extra = await core.loadModel(modelPath: model, shareRuntime: true);
        expect(await core.sharedModelCount(), 1);
        expect(
          await chat.send('Remember violet. Reply with just OK.'),
          isNotEmpty,
        );
        expect(await other.exportHistory(), isNot(contains('violet')));
        expect(await other.send('Remember amber. Reply briefly.'), isNotEmpty);
        expect(await chat.exportHistory(), isNot(contains('amber')));
        expect(await chat.send('Reply with just hello.'), isNotEmpty);
        expect(await chat.exportHistory(), contains('violet'));
        expect(await other.exportHistory(), contains('amber'));
        await other.close();
        await chat.close();
        chat = await extra.startConversation(maxOutputTokens: 16);
        expect(await chat.exportHistory(), isNot(contains('violet')));
        expect(await chat.send('Reply with just hello.'), isNotEmpty);
      } finally {
        await other?.close();
        await chat?.close();
        await extra?.close();
        for (final owner in owners) {
          await owner.close();
        }
      }
      expect(await core.sharedModelCount(), 0);
    },
    skip: !Platform.isWindows || model == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
