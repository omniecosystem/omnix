import 'dart:convert';
import 'dart:io';

import 'package:omnix_storage/omnix_storage.dart';
import 'package:path/path.dart' as p;

Future<String> runNativeDemo() async {
  final directory = await Directory.systemTemp.createTemp(
    'omnix-storage-example-',
  );
  final path = p.join(directory.path, 'history.sqlite');
  final store = OmnixConversationSnapshotStore(path: path);
  final snapshot = jsonEncode({
    'schemaVersion': 1,
    'record': {
      'id': 'example',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    },
    'messages': [
      {'role': 'user', 'text': 'Remember this across reopening.'},
    ],
  });
  try {
    await store.writeSerializedSnapshot(snapshot);
    await store.close();
    final reopened = OmnixConversationSnapshotStore(path: path);
    try {
      final restored = await reopened.readSerializedSnapshot('example');
      if (restored != snapshot) throw StateError('Snapshot recovery failed.');
      return 'Written, closed, and recovered through a fresh native connection.\n\n$restored';
    } finally {
      await reopened.close();
    }
  } finally {
    await store.close();
    await directory.delete(recursive: true);
  }
}
