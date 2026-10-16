import 'dart:convert';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';
import 'package:omnix_example/features/home/data/services/agent_chat_snapshot.dart';
import 'package:omnix_example/features/home/domain/agent_activity.dart';
import 'package:omnix_example/features/knowledge/presentation/controllers/knowledge_demo_controller.dart';
import 'package:test/test.dart';

void main() {
  AgentChatSnapshot snapshot() => AgentChatSnapshot(
    id: 'agent-test',
    title: 'Read clock',
    model: 'model',
    instructions: 'Host',
    email: false,
    autonomy: OmnixAutonomyMode.reviewEveryCall,
    checkpoint: 'opaque native context',
    maxOutputTokens: 1536,
    entries: [
      const ChatEntry('user', 'Read clock'),
      const ChatEntry(
        'assistant',
        '12:00',
        [],
        [KnowledgePassage('Clock', '12:00', null)],
        [
          AgentActivity(
            'clock',
            AgentActivityState.completed,
            outcomeStatus: 'ok',
          ),
        ],
      ),
    ],
  );
  test('agent display metadata roundtrips separately from runtime context', () {
    final reopened = AgentChatSnapshot.decode(snapshot().encode());
    expect(reopened.checkpoint, 'opaque native context');
    expect(reopened.maxOutputTokens, 1536);
    expect(reopened.autonomy, OmnixAutonomyMode.reviewEveryCall);
    expect(reopened.entries.last.activities.single.outcomeStatus, 'ok');
    expect(reopened.entries.last.sources.single.title, 'Clock');
    expect(reopened.entries.last.intents, isEmpty);
  });
  test('display history beyond the old 200-message limit is retained', () {
    final original = snapshot();
    final value = jsonDecode(original.encode()) as Map<String, dynamic>;
    final pair = value['messages'] as List<dynamic>;
    value['messages'] = [for (var i = 0; i < 150; i++) ...pair];
    final reopened = AgentChatSnapshot.decode(jsonEncode(value));
    expect(reopened.entries.length, 300);
    expect(reopened.checkpoint, original.checkpoint);
  });
  test('unsupported, unbalanced and empty checkpoints are not reopened', () {
    for (final edit in <void Function(Map<String, dynamic>)>[
      (v) => (v['record'] as Map)['agentVersion'] = 2,
      (v) => v['checkpoint'] = '',
      (v) => v['messages'] = [(v['messages'] as List).first],
      (v) => (v['messages'] as List).first['role'] = 'system',
      (v) => (v['record'] as Map)['autonomy'] = 'delegatedScope',
      (v) => (v['record'] as Map)['maxOutputTokens'] = 0,
      (v) => (v['record'] as Map)['maxOutputTokens'] = 4097,
      (v) => (v['record'] as Map)['maxOutputTokens'] = '1024',
      (v) => (v['record'] as Map)['audio'] = 'true',
      (v) => (v['record'] as Map)['images'] = 1,
      (v) => (v['record'] as Map)['toolsEnabled'] = 'false',
    ]) {
      final value = jsonDecode(snapshot().encode()) as Map<String, dynamic>;
      edit(value);
      expect(
        () => AgentChatSnapshot.decode(jsonEncode(value)),
        throwsFormatException,
      );
    }
  });
  test('disabled tools roundtrip, old snapshots default enabled', () {
    final value = jsonDecode(snapshot().encode()) as Map<String, dynamic>;
    value['record']['toolsEnabled'] = false;
    expect(AgentChatSnapshot.decode(jsonEncode(value)).toolsEnabled, isFalse);
    (value['record'] as Map).remove('toolsEnabled');
    expect(AgentChatSnapshot.decode(jsonEncode(value)).toolsEnabled, isTrue);
  });
}
