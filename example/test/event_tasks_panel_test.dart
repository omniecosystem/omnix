import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_example/features/workflow/presentation/widgets/event_tasks_panel.dart';

void main() {
  testWidgets(
    'message task UI submits host events and distinguishes admission from execution',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? submitted;
      String? stopped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventTasksPanel(
              tasks: const [
                {
                  'id': 'watch1',
                  'sender': 'Alice',
                  'enabled': true,
                  'instructions': 'Draft only if urgent',
                },
              ],
              queuedJobs: 1,
              busy: false,
              onRefresh: () {},
              onStop: (id) {
                stopped = id;
              },
              onSimulate: (sender, text) {
                submitted = '$sender:$text';
              },
            ),
          ),
        ),
      );
      expect(
        find.textContaining('No real app monitoring is active'),
        findsOneWidget,
      );
      await tester.tap(find.text('Stop'));
      expect(stopped, 'watch1');
      await tester.enterText(find.byType(TextField).first, 'Bob');
      await tester.enterText(find.byType(TextField).last, 'Hello');
      await tester.scrollUntilVisible(
        find.text('Submit simulated message'),
        180,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Submit simulated message'));
      expect(submitted, 'Bob:Hello');
      expect(
        find.textContaining('No message drafts or replies are generated'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('plans need explicit acceptance and jobs display host evidence', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? accepted;
    String? action;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventTasksPanel(
            tasks: const [],
            queuedJobs: 1,
            busy: false,
            proposals: const [
              {
                'id': 'clock',
                'goal': 'Read the clock twice',
                'trigger': {
                  'source': 'simulation',
                  'kind': 'tick',
                  'match': {},
                },
                'plan': [
                  {
                    'id': 'one',
                    'executor': 'host_time',
                    'retry': 'SafeToRepeat',
                    'input': {},
                  },
                ],
              },
            ],
            jobs: const [
              {
                'id': 'event-clock-1',
                'cancelled': false,
                'steps': [
                  {
                    'id': 'one',
                    'executor': 'host_time',
                    'state': 'Succeeded',
                    'output': {
                      'value': {
                        'status': 'succeeded',
                        'utc': '2026-10-10T12:00:00Z',
                      },
                    },
                  },
                  {
                    'id': 'two',
                    'executor': 'host_time',
                    'state': 'Pending',
                    'output': null,
                  },
                ],
              },
            ],
            onRefresh: () {},
            onStop: (_) {},
            onSimulate: (_, _) {},
            onAccept: (id) => accepted = id,
            onJobAction: (id, operation) => action = '$id:$operation',
          ),
        ),
      ),
    );
    expect(accepted, isNull);
    await tester.tap(find.text('Accept supplied plan'));
    expect(accepted, 'clock');
    await tester.scrollUntilVisible(
      find.text('Run next step'),
      180,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Run next step'));
    expect(action, 'event-clock-1:run');
    await tester.tap(find.text('Run workflow'));
    expect(action, 'event-clock-1:runAll');
    await tester.tap(find.text('View saved receipt'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-10-10T12:00:00Z'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('completed handoff disables replay and does not claim delivery', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventTasksPanel(
            tasks: const [],
            queuedJobs: 1,
            busy: false,
            jobs: const [
              {
                'id': 'share-job',
                'cancelled': false,
                'steps': [
                  {
                    'id': 'share',
                    'executor': 'host_share_text',
                    'state': 'Succeeded',
                    'output': {
                      'value': {'status': 'editor_opened'},
                    },
                  },
                ],
              },
            ],
            onRefresh: () {},
            onStop: (_) {},
            onSimulate: (_, _) {},
            onJobAction: (_, _) {},
          ),
        ),
      ),
    );
    expect(find.text('Completed · 1/1 steps confirmed'), findsOneWidget);
    expect(
      find.textContaining('Sending or saving is not confirmed'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Run workflow'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Recover interrupted step'),
          )
          .onPressed,
      isNull,
    );
  });
}
