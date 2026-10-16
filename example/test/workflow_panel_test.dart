import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/workflow/presentation/widgets/workflow_panel.dart';

void main() {
  for (final state in [
    'Pending',
    'Running',
    'NeedsReconciliation',
    'Succeeded',
  ]) {
    testWidgets('Workflow displays native $state controls', (tester) async {
      var runs = 0;
      final progress = OmnixWorkflowProgress.decode(
        jsonEncode({
          'version': 1,
          'id': 'demo-test',
          'cancelled': false,
          'steps': [
            {
              'id': 'handoff',
              'executor': 'host_workflow_simulation',
              'state': state,
              'output': null,
            },
          ],
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkflowPanel(
              progress: progress,
              busy: false,
              executing: false,
              onRun: () {
                runs++;
              },
              onRecover: () {},
              onConfirm: () {},
              onReopen: () {},
              onNew: () {},
              onCancel: () {},
            ),
          ),
        ),
      );
      ButtonStyleButton button(String name) =>
          tester.widget(find.byKey(Key(name)));
      expect(button('workflow-run').onPressed != null, state == 'Pending');
      expect(button('workflow-recover').onPressed != null, state == 'Running');
      expect(
        button('workflow-confirm').onPressed != null,
        state == 'NeedsReconciliation',
      );
      expect(button('workflow-cancel').onPressed != null, state != 'Succeeded');
      if (state == 'Pending') {
        await tester.ensureVisible(find.byKey(const Key('workflow-run')));
        await tester.tap(find.byKey(const Key('workflow-run')));
        expect(runs, 1);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
