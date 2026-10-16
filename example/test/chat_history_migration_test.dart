import 'dart:convert';
import 'package:omnix_storage/omnix_storage.dart';
import 'package:test/test.dart';
import 'package:omnix_example/features/home/data/services/chat_history_migration.dart';

class MemoryHistory implements OmnixStorageTransport {
  final values = <String, String>{};
  int writes = 0;
  @override
  Future<BigInt> open(String path) async => BigInt.one;
  @override
  Future<void> close(BigInt id) async {}
  @override
  Future<String> request(BigInt id, String operation, String payload) async {
    switch (operation) {
      case 'records':
        return jsonEncode([
          for (final value in values.values) jsonDecode(value)['record'],
        ]);
      case 'read':
        return values[payload] ?? 'null';
      case 'write':
        values[jsonDecode(payload)['record']['id'] as String] = payload;
        writes++;
        return 'null';
      default:
        throw StateError(operation);
    }
  }
}

void main() {
  test(
    'migration preserves originals and imports once without overwriting edits',
    () async {
      final original = jsonEncode({
        'schemaVersion': 1,
        'historyVersion': 1,
        'messages': [
          ['user', 'Bonjour'],
          ['assistant', 'Salut'],
        ],
        'record': {
          'id': '1',
          'title': 'Old chat',
          'modelPath': 'model',
          'systemPrompt': 'French',
        },
      });
      final sourceTransport = MemoryHistory()..values['1'] = original;
      final targetTransport = MemoryHistory()..values['1'] = 'existing';
      final source = OmnixConversationSnapshotStore(
        path: 'old.sqlite',
        transport: sourceTransport,
      );
      final target = OmnixConversationSnapshotStore(
        path: 'new.sqlite',
        transport: targetTransport,
      );
      addTearDown(source.close);
      addTearDown(target.close);
      await importLegacyHomeHistory(source, target);
      expect(sourceTransport.values['1'], original);
      expect(sourceTransport.writes, 0);
      expect(targetTransport.values['1'], 'existing');
      final imported = jsonDecode(targetTransport.values['legacy-home-1']!);
      expect(imported['messages'], jsonDecode(original)['messages']);
      expect(imported['record']['systemPrompt'], 'French');
      targetTransport.values['legacy-home-1'] = 'continued chat';
      await importLegacyHomeHistory(source, target);
      expect(targetTransport.writes, 1);
      expect(targetTransport.values['legacy-home-1'], 'continued chat');
    },
  );
}
