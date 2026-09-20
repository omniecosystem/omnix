import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix/src/infrastructure/flutter_gemma/flutter_gemma_inference_backend.dart';
import 'package:test/test.dart';

void main() {
  group('Flutter Gemma message mapping', () {
    test('round-trips replayable message content', () {
      final providerMessage = Message(
        text: '{"ok":true}',
        isUser: true,
        type: MessageType.toolResponse,
        toolName: 'lookup',
      );

      final omnixMessage = mapFlutterGemmaMessage(providerMessage);
      final roundTrip = mapOmnixMessage(omnixMessage);

      expect(omnixMessage.role, OmnixMessageRole.user);
      expect(omnixMessage.kind, OmnixMessageKind.toolResponse);
      expect(roundTrip, providerMessage);
    });
  });

  group('Flutter Gemma response mapping', () {
    test('preserves text and thinking separately', () {
      final text = mapFlutterGemmaResponse(const TextResponse('hello')).single;
      final thinking = mapFlutterGemmaResponse(
        const ThinkingResponse('considering'),
      ).single;

      expect(text, isA<OmnixTextDelta>());
      expect((text as OmnixTextDelta).text, 'hello');
      expect(thinking, isA<OmnixThinkingDelta>());
      expect((thinking as OmnixThinkingDelta).text, 'considering');
    });

    test('preserves one function call', () {
      final event = mapFlutterGemmaResponse(
        const FunctionCallResponse(name: 'get_time', args: {'zone': 'UTC'}),
      ).single;

      expect(event, isA<OmnixToolCall>());
      expect((event as OmnixToolCall).name, 'get_time');
      expect(event.arguments, {'zone': 'UTC'});
    });

    test('expands parallel function calls without dropping order', () {
      final events = mapFlutterGemmaResponse(
        const ParallelFunctionCallResponse(
          calls: [
            FunctionCallResponse(name: 'first', args: {}),
            FunctionCallResponse(name: 'second', args: {'value': 2}),
          ],
        ),
      ).whereType<OmnixToolCall>().toList();

      expect(events.map((event) => event.name), ['first', 'second']);
      expect(events.last.arguments, {'value': 2});
    });
  });
}
