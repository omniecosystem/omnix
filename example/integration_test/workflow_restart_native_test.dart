import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/workflow/data/repositories/workflow_repository.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Workflow survives a separate app process', (tester) async {
    const run = String.fromEnvironment('WORKFLOW_QUALIFICATION_ID');
    expect(RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(run), isTrue);
    await tester.runAsync(() async {
      final root = Directory(
        p.join(
          (await getApplicationSupportDirectory()).path,
          'workflow-qualification-$run',
        ),
      );
      await root.create(recursive: true);
      final marker = File(p.join(root.path, 'phase'));
      final repository = WorkflowRepository(directory: root);
      try {
        if (!await marker.exists()) {
          await repository.open();
          final clock = await repository.runNext();
          expect(clock.steps.first.state, OmnixWorkflowStepState.succeeded);
          final interrupted = await repository.runNext();
          expect(interrupted.steps[1].state, OmnixWorkflowStepState.running);
          await marker.writeAsString('prepared', flush: true);
          // The next launch must happen after force-stopping this process.
          debugPrint('[WorkflowQualification] PREPARED $run');
        } else {
          expect(await marker.readAsString(), 'prepared');
          final reopened = await repository.open();
          expect(reopened.steps.first.state, OmnixWorkflowStepState.succeeded);
          expect(reopened.steps[1].state, OmnixWorkflowStepState.running);
          final recovered = await repository.recover();
          expect(
            recovered.steps[1].state,
            OmnixWorkflowStepState.needsReconciliation,
          );
          await repository.confirmSimulation();
          expect((await repository.runNext()).completed, isTrue);
          expect((await repository.reopen()).completed, isTrue);
          await marker.writeAsString('passed', flush: true);
          debugPrint('[WorkflowQualification] PASSED $run');
        }
      } finally {
        await repository.close();
      }
    });
  });
}
