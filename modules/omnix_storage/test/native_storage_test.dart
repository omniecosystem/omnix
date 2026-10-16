import 'dart:convert';
import 'dart:io';

import 'package:omnix_storage/omnix_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'native snapshot survives closing and reopening the standalone bridge',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'omnix-storage-test-',
      );
      final path = p.join(directory.path, 'history.sqlite');
      final snapshot = jsonEncode({
        'schemaVersion': 1,
        'record': {
          'id': 'chat',
          'updatedAt': DateTime.utc(2026).toIso8601String(),
        },
        'messages': [
          {'text': 'Remember this', 'role': 'user'},
        ],
      });
      final store = OmnixConversationSnapshotStore(path: path);
      try {
        await store.writeSerializedSnapshot(snapshot);
        await store.close();
        final reopened = OmnixConversationSnapshotStore(path: path);
        try {
          expect(await reopened.readSerializedSnapshot('chat'), snapshot);
          expect(
            (jsonDecode(await reopened.readSerializedRecords()) as List)
                .single['id'],
            'chat',
          );
          await expectLater(
            reopened.writeSerializedSnapshot('{"schemaVersion":2}'),
            throwsA('Unsupported conversation snapshot'),
          );
          expect(await reopened.readSerializedSnapshot('chat'), snapshot);
          await reopened.delete('chat');
          expect(await reopened.readSerializedSnapshot('chat'), isNull);
        } finally {
          await reopened.close();
        }
      } finally {
        await store.close();
        await directory.delete(recursive: true);
      }
    },
    skip: !Platform.isWindows && !Platform.isLinux && !Platform.isMacOS,
  );
}
