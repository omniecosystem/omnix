import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/home/presentation/services/tool_approval.dart';

void main() {
  OmnixToolRequest request() => OmnixToolRequest.fromJson({
    'requestId': '1',
    'toolName': 'host_time',
    'arguments': <String, dynamic>{},
  });
  for (final allow in [false, true]) {
    testWidgets('one-call approval returns $allow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(navigatorKey: exampleNavigatorKey, home: const Scaffold()),
      );
      final approval = ExampleToolApproval();
      final result = approval.approve(request());
      await tester.pumpAndSettle();
      expect(find.text('Allow host_time?'), findsOneWidget);
      await tester.tap(find.text(allow ? 'Allow once' : 'Deny'));
      await tester.pumpAndSettle();
      expect(await result, allow);
      expect(find.text('Allow host_time?'), findsNothing);
    });
  }
  testWidgets('workflow approval displays saved plan and resumes inline', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: exampleNavigatorKey,
        home: const Scaffold(body: Text('Home')),
      ),
    );
    final approval = ExampleToolApproval();
    var continued = false;
    final pending = approval
        .approve(
          OmnixToolRequest.fromJson({
            'requestId': 'workflow',
            'toolName': 'host_execute_event_task',
            'arguments': {'id': 'saved-plan'},
          }),
          details: 'Saved plan: read battery, then share its saved report.',
        )
        .then((allowed) => continued = allowed);
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.textContaining('Saved plan: read battery'), findsOneWidget);
    expect(continued, false);
    await tester.tap(find.text('Allow once'));
    await tester.pumpAndSettle();
    await pending;
    expect(continued, true);
    expect(find.text('Allow once'), findsNothing);
  });
  testWidgets('approval expires and cancellation prevents a late allow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(navigatorKey: exampleNavigatorKey, home: const Scaffold()),
    );
    final approval = ExampleToolApproval();
    final result = approval.approve(request());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();
    expect(await result, false);
    final second = approval.approve(request());
    await tester.pumpAndSettle();
    approval.cancel();
    await tester.pumpAndSettle();
    expect(await second, false);
    expect(find.text('Allow once'), findsNothing);
  });
  testWidgets('backgrounding dismisses approval and denies the call', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(navigatorKey: exampleNavigatorKey, home: const Scaffold()),
    );
    final approval = ExampleToolApproval();
    final result = approval.approve(request());
    await tester.pumpAndSettle();
    approval.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(await result, false);
    expect(find.text('Allow once'), findsNothing);
  });
}
