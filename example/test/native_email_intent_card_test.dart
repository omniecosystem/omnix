import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/home/data/services/native_intent_host.dart';
import 'package:omnix_example/features/home/presentation/widgets/native_email_intent_card.dart';

void main() {
  testWidgets('dismissed review and disposal cannot launch a composer', (
    tester,
  ) async {
    var launches = 0;
    final intent = OmnixEmailIntent.fromJson({
      'kind': 'email',
      'recipient': 'alex@example.com',
      'subject': 'Hi',
      'body': 'Hello',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeEmailIntentCard(
            intent: intent,
            openComposer: (_) async {
              launches++;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Review draft'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(launches, 0);
    await tester.tap(find.text('Review draft'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(launches, 0);
    expect(tester.takeException(), isNull);
  });
  final draft = OmnixEmailIntent.fromJson({
    'kind': 'email',
    'recipient': 'alex@example.com',
    'subject': 'Hi & hello',
    'body': 'One + two\n&bcc=not-a-header',
  });
  test('composer URI encodes fields rather than accepting arbitrary URLs', () {
    final uri = emailComposerUri(draft);
    expect(uri.scheme, 'mailto');
    expect(uri.path, draft.recipient);
    expect(uri.queryParameters['body'], draft.body);
    expect(uri.queryParameters.keys, ['subject', 'body']);
    expect(uri.query, contains('%20'));
    expect(uri.queryParameters.containsKey('bcc'), isFalse);
  });
  testWidgets(
    'cancel and dismiss never launch; explicit approval launches once',
    (tester) async {
      var launches = 0;
      Future<bool> open(Uri uri) async {
        launches++;
        expect(uri, emailComposerUri(draft));
        return true;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeEmailIntentCard(intent: draft, openComposer: open),
          ),
        ),
      );
      expect(launches, 0);
      await tester.tap(find.text('Review draft'));
      await tester.pumpAndSettle();
      expect(find.text(draft.body), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(launches, 0);
      await tester.tap(find.text('Review draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open mail composer'));
      await tester.pumpAndSettle();
      expect(launches, 1);
      expect(find.textContaining('Send status is unknown'), findsOneWidget);
      expect(find.text('Review draft'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeEmailIntentCard(intent: draft, openComposer: open),
          ),
        ),
      );
      await tester.tap(find.text('Dismiss draft'));
      await tester.pumpAndSettle();
      expect(launches, 1);
      expect(find.text('Email draft dismissed'), findsOneWidget);
      expect(find.text('Review draft'), findsNothing);
    },
  );
  testWidgets('launcher failure remains retryable and never reports sent', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeEmailIntentCard(
            intent: draft,
            openComposer: (_) async => false,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Review draft'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open mail composer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No mail composer was opened'), findsOneWidget);
    expect(find.text('Review draft'), findsOneWidget);
    expect(find.textContaining('Send status is unknown'), findsNothing);
  });
}
