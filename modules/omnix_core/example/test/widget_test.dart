import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix_core_example/demo_app.dart';
import 'package:omnix_core_example/demo_controller.dart';

void main() {
  testWidgets('runs once, shows progress and renders a selectable reply', (
    tester,
  ) async {
    final reply = Completer<String>();
    var calls = 0;
    await tester.pumpWidget(
      CoreExampleApp(
        controller: DemoController(() {
          calls++;
          return reply.future;
        }),
      ),
    );
    expect(find.textContaining('GGUF or LiteRT-LM'), findsOneWidget);
    await tester.tap(find.text('Run local demo'));
    await tester.pump();
    expect(calls, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byWidgetPredicate((widget) => widget is FilledButton),
          )
          .onPressed,
      isNull,
    );
    reply.complete('Public answer\nPrivate request refused.');
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('Run local demo'), findsOneWidget);
  });

  testWidgets('shows failure and allows retry', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      CoreExampleApp(
        controller: DemoController(() async {
          if (++calls == 1) throw StateError('Example failure');
          return 'Recovered';
        }),
      ),
    );
    await tester.tap(find.text('Run local demo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Example failure'), findsOneWidget);
    await tester.tap(find.text('Run local demo'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered'), findsOneWidget);
  });

  testWidgets('completion after closing the screen is safe', (tester) async {
    final reply = Completer<String>();
    await tester.pumpWidget(
      CoreExampleApp(controller: DemoController(() => reply.future)),
    );
    await tester.tap(find.text('Run local demo'));
    await tester.pumpWidget(const SizedBox());
    reply.complete('Finished');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
