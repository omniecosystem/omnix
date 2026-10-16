import 'dart:convert';
import 'package:omnix_example/features/home/data/services/response_budget.dart';
import 'package:omnix_example/features/home/data/services/agent_chat_snapshot.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/core/presentation/controllers/core_controller.dart';
import 'package:test/test.dart';

void main() {
  test('Home response budget accepts context-bounded values', () {
    expect(validateHomeResponseTokens(1), 1);
    expect(validateHomeResponseTokens(1024), 1024);
    expect(validateHomeResponseTokens(4096), 4096);
    for (final tokens in [-1, 0, 4097]) {
      expect(() => validateHomeResponseTokens(tokens), throwsArgumentError);
    }
  });
  test('legacy saved agent budget remains 256', () {
    final snapshot = AgentChatSnapshot(
      id: 'legacy',
      title: 'Legacy',
      model: 'model',
      instructions: '',
      email: false,
      autonomy: OmnixAutonomyMode.scopedAssistance,
      checkpoint: 'opaque',
      entries: const [ChatEntry('user', 'Hello'), ChatEntry('assistant', 'Hi')],
    );
    final value = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
    (value['record'] as Map).remove('maxOutputTokens');
    expect(AgentChatSnapshot.decode(jsonEncode(value)).maxOutputTokens, 256);
  });
}
