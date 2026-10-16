import 'package:omnix/omnix.dart';
import 'package:test/test.dart';

void main() {
  final data = {
    'kind': 'email',
    'recipient': 'alex@example.com',
    'subject': 'Hi & hello',
    'body': 'Bonjour\nHello',
  };
  test('typed proposals round-trip and remain separate from answer text', () {
    final draft = OmnixEmailIntent.fromJson(data);
    expect(draft.toJson(), data);
    final reply = OmnixAgentReply(
      text: 'Draft ready',
      toolCalls: 1,
      sources: [],
      intents: [draft],
    );
    expect(
      OmnixAgentReply.fromJson(reply.toJson()).intents.single.body,
      data['body'],
    );
    expect(() => reply.intents.clear(), throwsUnsupportedError);
    expect(
      OmnixAgentReply.fromJson({
        'text': 'legacy',
        'toolCalls': 0,
        'sources': [],
      }).intents,
      isEmpty,
    );
  });
  test('unsupported or malformed native intents never decode to actions', () {
    for (final recipient in [
      'a@b.com?bcc=evil@example.com',
      'a@b.com\n',
      'mailto:a@b.com',
      'a@b.com,c@d.com',
    ]) {
      expect(
        () => OmnixEmailIntent.fromJson({...data, 'recipient': recipient}),
        throwsFormatException,
      );
    }
    expect(
      () => OmnixEmailIntent.fromJson({...data, 'kind': 'shell'}),
      throwsFormatException,
    );
    expect(
      () => OmnixEmailIntent.fromJson({...data, 'subject': 'bad\nheader'}),
      throwsFormatException,
    );
    expect(
      () => OmnixEmailIntent.fromJson({...data, 'body': '\u0000'}),
      throwsFormatException,
    );
    expect(
      () => OmnixEmailIntent.fromJson({...data, 'body': 'x' * 8193}),
      throwsFormatException,
    );
    final event = OmnixAgentEvent.fromJson({
      'kind': 'toolFinished',
      'toolName': 'prepare_email_intent',
      'toolFailed': true,
    });
    expect(event.toolFailed, isTrue);
    expect(OmnixAgentEvent.fromJson(event.toJson()).toolFailed, isTrue);
  });
}
