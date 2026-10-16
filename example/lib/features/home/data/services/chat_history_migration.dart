import 'dart:convert';
import 'package:omnix_storage/omnix_storage.dart';

// Consumer history migration only. Both stores use the native version-1 format.
// Leave the original database untouched; prefix IDs and never overwrite imports.
Future<void> importLegacyHomeHistory(
  OmnixConversationSnapshotStore source,
  OmnixConversationSnapshotStore destination,
) async {
  final records = jsonDecode(await source.readSerializedRecords()) as List;
  for (final record in records) {
    final id = record['id'] as String;
    final importedId = 'legacy-home-$id';
    if (await destination.readSerializedSnapshot(importedId) != null) continue;
    final serialized = await source.readSerializedSnapshot(id);
    if (serialized == null) continue;
    final snapshot = jsonDecode(serialized) as Map<String, dynamic>;
    final metadata = Map<String, dynamic>.from(snapshot['record'] as Map);
    snapshot['record'] = {...metadata, 'id': importedId};
    await destination.writeSerializedSnapshot(jsonEncode(snapshot));
  }
}
