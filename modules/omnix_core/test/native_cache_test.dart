import 'dart:io';

import 'package:omnix_core/omnix_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'native_test_support.dart';

void main() {
  final model = Platform.environment['OMNIX_CORE_TEST_MODEL'];
  final cache = Platform.environment['OMNIX_CORE_TEST_CACHE'];
  test(
    'public Dart cache configuration survives close and reload',
    () async {
      await initializeTestBridge();
      Map<String, (int, DateTime)> cacheFiles() => {
        for (final file in Directory(cache!).listSync().whereType<File>())
          if (p.extension(file.path) == '.xnnpack_cache')
            file.path: (file.lengthSync(), file.lastModifiedSync()),
      };
      Future<void> turn() async {
        final loaded = await OmnixCore().loadModel(
          modelPath: model!,
          cacheDirectory: cache,
          contextTokens: 128,
        );
        OmnixCoreConversation? chat;
        try {
          chat = await loaded.startConversation(maxOutputTokens: 16);
          expect(await chat.send('Reply with just hello.'), isNotEmpty);
        } finally {
          await chat?.close();
          await loaded.close();
        }
      }

      await turn();
      final first = cacheFiles();
      expect(first, isNotEmpty);
      await turn();
      expect(cacheFiles(), first);
    },
    skip: !Platform.isWindows || model == null || cache == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
