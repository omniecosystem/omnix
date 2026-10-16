import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:omnix/omnix.dart';

class WorkflowPanel extends StatelessWidget {
  const WorkflowPanel({
    super.key,
    required this.progress,
    required this.busy,
    required this.executing,
    this.error,
    required this.onRun,
    required this.onRecover,
    required this.onConfirm,
    required this.onReopen,
    required this.onNew,
    required this.onCancel,
  });
  final OmnixWorkflowProgress? progress;
  final bool busy;
  final bool executing;
  final String? error;
  final VoidCallback onRun, onRecover, onConfirm, onReopen, onNew, onCancel;
  static const labels = {
    'clock': 'Read the host clock',
    'handoff': 'Simulate missing confirmation',
    'finish': 'Create a completion receipt',
  };
  static const stateLabels = {
    OmnixWorkflowStepState.pending: 'Pending',
    OmnixWorkflowStepState.running: 'Interrupted / outcome unknown',
    OmnixWorkflowStepState.succeeded: 'Completed',
    OmnixWorkflowStepState.failed: 'Blocked',
    OmnixWorkflowStepState.needsReconciliation: 'Needs confirmation',
  };
  @override
  Widget build(BuildContext context) {
    final saved = progress;
    final steps = saved?.steps ?? const <OmnixWorkflowStepProgress>[];
    final remaining = steps.where(
      (s) => s.state != OmnixWorkflowStepState.succeeded,
    );
    final next = remaining.isEmpty ? null : remaining.first;
    final enabled = !busy && saved != null && !saved.cancelled;
    final status = executing
        ? 'Executing a step…'
        : saved == null
        ? 'Opening saved progress…'
        : saved.cancelled
        ? 'Cancelled — no further steps will run'
        : saved.completed
        ? 'Workflow completed'
        : 'Saved progress';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Durable work', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
          'Simulation only. These host-supplied tools do not send messages, open apps, or control devices. No model is required.',
        ),
        const SizedBox(height: 16),
        Card.filled(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status, style: Theme.of(context).textTheme.titleMedium),
                if (saved != null)
                  Text(
                    'Job ${saved.id}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SelectableText(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        for (final (index, step) in steps.indexed)
          Card.outlined(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        step.state == OmnixWorkflowStepState.succeeded
                            ? Icons.check_circle_outline
                            : Icons.pending_outlined,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${index + 1}. ${labels[step.id] ?? step.id}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(stateLabels[step.state]!),
                  if (step.hasOutput)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ').convert(step.output),
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              key: const Key('workflow-run'),
              onPressed:
                  enabled && next?.state == OmnixWorkflowStepState.pending
                  ? onRun
                  : null,
              child: const Text('Run next step'),
            ),
            OutlinedButton(
              key: const Key('workflow-recover'),
              onPressed:
                  enabled && next?.state == OmnixWorkflowStepState.running
                  ? onRecover
                  : null,
              child: const Text('Recover interrupted work'),
            ),
            OutlinedButton(
              key: const Key('workflow-confirm'),
              onPressed:
                  enabled &&
                      next?.state == OmnixWorkflowStepState.needsReconciliation
                  ? onConfirm
                  : null,
              child: const Text('Confirm simulated outcome'),
            ),
            OutlinedButton(
              key: const Key('workflow-reopen'),
              onPressed: busy ? null : onReopen,
              child: const Text('Reopen saved job'),
            ),
            TextButton(
              key: const Key('workflow-new'),
              onPressed: busy ? null : onNew,
              child: const Text('New demo'),
            ),
            TextButton(
              key: const Key('workflow-cancel'),
              onPressed:
                  saved != null &&
                      !saved.cancelled &&
                      !saved.completed &&
                      (!busy || executing)
                  ? onCancel
                  : null,
              child: const Text('Cancel job'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Close and reopen this feature, or restart the app: completed steps stay completed. Recovery does not execute actions. Confirm only the simulated outcome in this demo; real actions need host-verified evidence.',
        ),
      ],
    );
  }
}

@Preview(name: 'Workflow awaiting confirmation', size: Size(420, 800))
Widget workflowPreview() => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: WorkflowPanel(
      progress: OmnixWorkflowProgress.decode(
        '{"version":1,"id":"demo-preview","cancelled":false,"steps":[{"id":"clock","executor":"host_workflow_clock","state":"Succeeded","output":{"value":{"status":"succeeded","utc":"2026-10-10T12:00:00Z"}}},{"id":"handoff","executor":"host_workflow_simulation","state":"NeedsReconciliation","output":null},{"id":"finish","executor":"host_workflow_finish","state":"Pending","output":null}]}',
      ),
      busy: false,
      executing: false,
      onRun: () {},
      onRecover: () {},
      onConfirm: () {},
      onReopen: () {},
      onNew: () {},
      onCancel: () {},
    ),
  ),
);
