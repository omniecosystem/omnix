import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/home/data/services/device_tools.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android native agent invokes consumer device tool',
    (tester) async {
      const model = String.fromEnvironment('OMNIX_GENERATION_MODEL');
      expect(Platform.isAndroid, isTrue);
      expect(model, isNotEmpty);
      await tester.runAsync(() async {
        expect(await File(model).exists(), isTrue);
        final deviceTool = const ExampleDeviceTools().tools.first;
        final expected =
            await deviceTool.execute(
                  OmnixToolRequest.fromJson({
                    'requestId': 'preflight',
                    'toolName': deviceTool.name,
                    'arguments': <String, dynamic>{},
                  }),
                )
                as Map;
        final engine = await OmnixCognitiveEngine.open(runtimes: ['litertlm']);
        OmnixAgentSession? agent;
        try {
          agent = await engine.startAgent(
            modelPath: model,
            extensions: OmnixAgentExtensions(
              tools: [deviceTool],
              grants: [deviceTool.name],
            ),
          );
          final events = await agent
              .sendEvents(
                'Call host_device_info and report this device model exactly. Do not guess.',
              )
              .toList();
          expect(
            events.any(
              (e) =>
                  e.kind == OmnixAgentEventKind.toolStarted &&
                  e.toolName == deviceTool.name,
            ),
            isTrue,
          );
          final reply = events
              .singleWhere((e) => e.kind == OmnixAgentEventKind.completed)
              .reply!;
          expect(reply.text, contains(expected['model'] as String));
        } finally {
          await agent?.close();
          await engine.close();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
