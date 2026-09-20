import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_gemma_agent/flutter_gemma_agent.dart' as agent;
import 'package:omnix/omnix.dart';
import 'package:omnix/omnix_flutter_gemma_agent.dart';
import 'package:test/test.dart';

void main() {
  group('Flutter Gemma Agent event mapping', () {
    test('preserves orchestration and terminal events', () {
      expect(
        mapFlutterGemmaAgentEvent(
          const agent.SkillLoadEvent('clock', found: false),
        ),
        isA<OmnixAgentSkillLoad>()
            .having((event) => event.skillId, 'skillId', 'clock')
            .having((event) => event.found, 'found', isFalse),
      );

      expect(
        mapFlutterGemmaAgentEvent(
          const agent.ToolCallEvent(
            toolName: 'runIntent',
            args: {'intent': 'clock'},
          ),
        ),
        isA<OmnixAgentToolCall>()
            .having((event) => event.name, 'name', 'runIntent')
            .having((event) => event.arguments, 'arguments', {
              'intent': 'clock',
            }),
      );

      expect(
        mapFlutterGemmaAgentEvent(const agent.TextChunkEvent('hello')),
        isA<OmnixAgentTextDelta>().having(
          (event) => event.text,
          'text',
          'hello',
        ),
      );
      expect(
        mapFlutterGemmaAgentEvent(const agent.DoneEvent('done')),
        isA<OmnixAgentCompleted>().having(
          (event) => event.text,
          'text',
          'done',
        ),
      );
      expect(
        mapFlutterGemmaAgentEvent(const agent.MaxIterationsEvent(4)),
        isA<OmnixAgentStepLimitReached>().having(
          (event) => event.steps,
          'steps',
          4,
        ),
      );
      expect(
        mapFlutterGemmaAgentEvent(
          const agent.AgentErrorEvent('failed', toolName: 'runSkill'),
        ),
        isA<OmnixAgentFailure>()
            .having((event) => event.message, 'message', 'failed')
            .having((event) => event.toolName, 'toolName', 'runSkill'),
      );
    });

    test('maps every provider result to a headless output', () {
      expect(
        mapFlutterGemmaSkillResult(const agent.TextResult('result')),
        isA<OmnixAgentTextOutput>().having(
          (output) => output.text,
          'text',
          'result',
        ),
      );
      expect(
        mapFlutterGemmaSkillResult(
          agent.ImageResult(Uint8List.fromList([1, 2, 3])),
        ),
        isA<OmnixAgentImageOutput>().having((output) => output.bytes, 'bytes', [
          1,
          2,
          3,
        ]),
      );
      expect(
        mapFlutterGemmaSkillResult(
          const agent.WebviewResult('https://example.com', iframe: false),
        ),
        isA<OmnixAgentWebOutput>()
            .having(
              (output) => output.uri,
              'uri',
              Uri.parse('https://example.com'),
            )
            .having((output) => output.embed, 'embed', isFalse),
      );
      expect(
        mapFlutterGemmaSkillResult(const agent.WebviewResult('not a web uri')),
        isA<OmnixAgentErrorOutput>(),
      );
      expect(
        mapFlutterGemmaSkillResult(const agent.ErrorResult('no access')),
        isA<OmnixAgentErrorOutput>().having(
          (output) => output.message,
          'message',
          'no access',
        ),
      );
      expect(
        mapFlutterGemmaSkillResult(const agent.WidgetResult(SizedBox.shrink())),
        isA<OmnixAgentUnavailableOutput>().having(
          (output) => output.kind,
          'kind',
          'native-view',
        ),
      );
    });

    test('maps tool results through their structured result', () {
      final event = mapFlutterGemmaAgentEvent(
        const agent.ToolResultEvent(
          toolName: 'runSkill',
          result: agent.TextResult('12:00'),
        ),
      );

      expect(
        event,
        isA<OmnixAgentToolResult>()
            .having((value) => value.name, 'name', 'runSkill')
            .having(
              (value) => value.output,
              'output',
              isA<OmnixAgentTextOutput>().having(
                (output) => output.text,
                'text',
                '12:00',
              ),
            ),
      );
    });
  });
}
