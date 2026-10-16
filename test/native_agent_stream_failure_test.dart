import 'dart:convert';
import 'dart:io';
import 'package:omnix/omnix_session.dart';
import 'package:omnix/src/rust/api/agent.dart' as native;
import 'package:test/test.dart';

void main() {
  final bridge = Platform.environment['OMNIX_AGENT_TEST_BRIDGE'];
  test(
    'real bridge delivers failed preflight in stream, not an unhandled Future',
    () async {
      await initializeOmnixSessionLibrary(bridge!);
      final events = await native
          .agentStream(agentId: BigInt.from(999999), text: 'test')
          .timeout(const Duration(seconds: 10))
          .toList();
      expect(events, hasLength(1));
      final event = OmnixAgentEvent.fromJson(
        jsonDecode(events.single) as Map<String, dynamic>,
      );
      expect(event.kind, OmnixAgentEventKind.failed);
      expect(event.text, isNotEmpty);
    },
    skip: bridge == null,
  );
}
