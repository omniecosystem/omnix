import 'dart:io';

import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  final bridge = Platform.environment['OMNIX_SESSION_TEST_BRIDGE'];
  final runtime = Platform.environment['OMNIX_SESSION_TEST_RUNTIME'];
  final model = Platform.environment['OMNIX_SESSION_TEST_MODEL'];
  test(
    'native agent checkpoint survives engine closure without reexecuting tools',
    () async {
      await initializeOmnixSessionLibrary(bridge!);
      var executions = 0;
      OmnixAgentExtensions extensions() => OmnixAgentExtensions(
        tools: [
          OmnixHostTool(
            name: 'qualification_lookup',
            description: 'Returns the public qualification code.',
            parameters: {
              'type': 'object',
              'properties': <String, Object?>{},
              'required': <String>[],
              'additionalProperties': false,
            },
            execute: (_) async {
              executions++;
              return {'status': 'ok', 'code': 'violet-73921'};
            },
          ),
        ],
        grants: ['qualification_lookup'],
        approvalPolicy: OmnixApprovalPolicy(
          mode: OmnixAutonomyMode.scopedAssistance,
          automaticTools: ['qualification_lookup'],
        ),
      );
      Future<OmnixCognitiveEngine> open() => OmnixCognitiveEngine.open(
        runtimes: ['litertlm'],
        libraryPath: runtime!,
        contextTokens: 4096,
      );
      const instructions =
          'Call qualification_lookup to obtain the qualification code. '
          'Never invent the code. After receiving it, answer briefly.';
      final first = await open();
      OmnixAgentSession? agent;
      late String checkpoint;
      try {
        agent = await first.startAgent(
          modelPath: model!,
          instructions: instructions,
          extensions: extensions(),
        );
        final reply = await agent.send(
          'Look up the public qualification code.',
        );
        expect(reply.toolCalls, greaterThan(0));
        expect(executions, greaterThan(0));
        checkpoint = await agent.exportCheckpoint();
        expect(checkpoint, contains('violet-73921'));
      } finally {
        await agent?.close();
        await first.close();
      }
      final beforeRestore = executions;
      final second = await open();
      OmnixAgentSession? restored;
      try {
        restored = await second.startAgent(
          modelPath: model,
          instructions: instructions,
          extensions: extensions(),
        );
        await restored.restoreCheckpoint(checkpoint);
        expect(executions, beforeRestore);
        expect(await restored.exportCheckpoint(), checkpoint);
        await restored.send(
          'Use the code already obtained; do not call tools again.',
        );
        // The model might decide to call a tool on a new turn. That is distinct
        // from executing historical calls during restoration above.
      } finally {
        await restored?.close();
        await second.close();
      }
    },
    skip:
        !Platform.isWindows ||
        bridge == null ||
        runtime == null ||
        model == null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
