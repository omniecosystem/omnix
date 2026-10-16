import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_example/features/home/domain/agent_activity.dart';
import 'package:omnix_example/features/home/presentation/widgets/agent_activity_timeline.dart';

void main() {
  testWidgets('host outcome and reason are visible, not generic completion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentActivityTimeline(
            activities: [
              AgentActivity(
                'host_prepare_calendar_event',
                AgentActivityState.failed,
                outcomeStatus: 'invalid_arguments',
                reason: 'Explicit timezone required',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Tool activity'));
    await tester.pumpAndSettle();
    expect(find.text('invalid_arguments'), findsOneWidget);
    expect(find.text('Explicit timezone required'), findsOneWidget);
    expect(find.text('Completed'), findsNothing);
  });
  testWidgets('completed timeline expands and collapses', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentActivityTimeline(
            activities: [
              AgentActivity('search_knowledge', AgentActivityState.completed),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Tool activity'), findsOneWidget);
    expect(find.text('Completed').hitTestable(), findsNothing);
    await tester.tap(find.text('Tool activity'));
    await tester.pumpAndSettle();
    expect(find.text('Search local Knowledge').hitTestable(), findsOneWidget);
    expect(find.text('Completed').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Tool activity'));
    await tester.pumpAndSettle();
    expect(find.text('Completed').hitTestable(), findsNothing);
  });
  testWidgets('repeated tools have distinct ordered states on narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentActivityTimeline(
            activities: [
              AgentActivity('search_knowledge', AgentActivityState.completed),
              AgentActivity('search_knowledge', AgentActivityState.running),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Search local Knowledge'), findsNWidgets(2));
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('cancelled and failed activities never appear completed', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentActivityTimeline(
            activities: [
              AgentActivity('search_knowledge', AgentActivityState.cancelled),
              AgentActivity('search_knowledge', AgentActivityState.failed),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Tool activity'));
    await tester.pumpAndSettle();
    expect(find.text('Stopped before completion'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Completed'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
