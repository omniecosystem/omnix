import 'dart:convert';
import 'package:omnix_storage/omnix_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final class SnapshotRepository {
  Future<String?> reopen({String? note}) async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final file = p.join(directory.path, 'native-showcase-snapshots.sqlite');
    if (note != null) {
      final store = OmnixConversationSnapshotStore(path: file);
      try {
        await store.writeSerializedSnapshot(
          jsonEncode({
            'schemaVersion': 1,
            'record': {
              'id': 'showcase-note',
              'updatedAt': DateTime.now().toUtc().toIso8601String(),
            },
            'messages': [
              {'role': 'user', 'text': note},
            ],
          }),
        );
      } finally {
        await store.close();
      }
    }
    final reopened = OmnixConversationSnapshotStore(path: file);
    try {
      final value = await reopened.readSerializedSnapshot('showcase-note');
      return value == null
          ? null
          : jsonDecode(value)['messages'][0]['text'] as String;
    } finally {
      await reopened.close();
    }
  }
}
