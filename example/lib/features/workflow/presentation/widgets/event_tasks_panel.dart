import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'dart:convert';

class EventTasksPanel extends StatefulWidget {
  const EventTasksPanel({
    super.key,
    required this.tasks,
    required this.queuedJobs,
    required this.busy,
    this.error,
    this.notice,
    required this.onRefresh,
    required this.onStop,
    required this.onSimulate,
    this.proposals = const [],
    this.jobs = const [],
    this.onAccept,
    this.onTick,
    this.onJobAction,
    this.activeJob,
    this.onCancelActive,
  });
  final List<Map<String, dynamic>> tasks;
  final int queuedJobs;
  final bool busy;
  final String? error, notice;
  final VoidCallback onRefresh;
  final void Function(String) onStop;
  final void Function(String, String) onSimulate;
  final List<Map<String, dynamic>> proposals, jobs;
  final void Function(String)? onAccept;
  final VoidCallback? onTick;
  final void Function(String, String)? onJobAction;
  final String? activeJob;
  final VoidCallback? onCancelActive;
  @override
  State<EventTasksPanel> createState() => _EventTasksPanelState();
}

class _EventTasksPanelState extends State<EventTasksPanel> {
  final sender = TextEditingController(text: 'Alice');
  final message = TextEditingController(
    text: 'Urgent: please call me about tomorrow’s appointment.',
  );
  @override
  void dispose() {
    sender.dispose();
    message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      if (widget.busy) const LinearProgressIndicator(),
      if (widget.error != null)
        SelectableText(
          widget.error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (widget.notice != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(widget.notice!),
        ),
      Text('Proposed plans', style: Theme.of(context).textTheme.headlineSmall),
      const Text(
        'Ask Home: "Propose a task that reads the UTC time twice on a simulated tick." '
        'Review the full plan before accepting. Acceptance enables event admission, '
        'not unrestricted execution. Emit a matching tick, then run the queued workflow. '
        'Only capabilities supplied by this app can execute; no background monitoring is active.',
      ),
      if (widget.proposals.isEmpty) const Text('No plans awaiting acceptance.'),
      for (final proposal in widget.proposals)
        Card.filled(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(proposal['goal'] as String),
                SelectableText(
                  const JsonEncoder.withIndent('  ').convert({
                    'trigger': proposal['trigger'],
                    'plan': proposal['plan'],
                  }),
                ),
                TextButton(
                  onPressed: widget.busy || widget.onAccept == null
                      ? null
                      : () => widget.onAccept!(proposal['id'] as String),
                  child: const Text('Accept supplied plan'),
                ),
              ],
            ),
          ),
        ),
      TextButton(
        onPressed: widget.busy ? null : widget.onTick,
        child: const Text('Emit simulated tick'),
      ),
      Text(
        'Execution evidence',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      for (final job in widget.jobs)
        Card.filled(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${job['id']}${job['cancelled'] == true ? ' (cancelled)' : ''}',
                ),
                Text(
                  _summary(job),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final step in job['steps'] as List)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${step['id']} / ${step['executor']}: ${step['state']}',
                        ),
                        if (step['output'] != null) ...[
                          if (step['output']['value'] is Map &&
                              step['output']['value']['status'] ==
                                  'editor_opened')
                            const Text(
                              'Handoff confirmed: editor or share sheet opened. Sending or saving is not confirmed.',
                            ),
                          ExpansionTile(
                            title: const Text('View saved receipt'),
                            children: [
                              SelectableText(
                                const JsonEncoder.withIndent(
                                  '  ',
                                ).convert(step['output']['value']),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final action in const {
                      'runAll': 'Run workflow',
                      'run': 'Run next step',
                      'recover': 'Recover interrupted step',
                      'cancel': 'Cancel job',
                    }.entries)
                      TextButton(
                        onPressed:
                            widget.busy ||
                                widget.onJobAction == null ||
                                !_canAct(job, action.key)
                            ? null
                            : () => widget.onJobAction!(
                                job['id'] as String,
                                action.key,
                              ),
                        child: Text(action.value),
                      ),
                    if (widget.activeJob == job['id'])
                      TextButton(
                        onPressed: widget.onCancelActive,
                        child: const Text('Stop execution'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      const Divider(),
      Text(
        'Accepted event tasks',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      const Text(
        'Accepted plans and earlier simulation tasks are retained here. No real app monitoring is active.',
      ),
      TextButton(
        onPressed: widget.busy ? null : widget.onRefresh,
        child: const Text('Refresh saved tasks'),
      ),
      if (widget.tasks.isEmpty) const Text('No subscriptions saved yet.'),
      for (final task in widget.tasks)
        Card.filled(
          child: ListTile(
            title: Text(
              '${task['sender']} · ${task['enabled'] == true ? 'Enabled' : 'Stopped'}',
            ),
            subtitle: Text(
              '${task['instructions']}\nHost-supplied event trigger',
            ),
            trailing: TextButton(
              onPressed: widget.busy || task['enabled'] != true
                  ? null
                  : () => widget.onStop(task['id'] as String),
              child: const Text('Stop'),
            ),
          ),
        ),
      const SizedBox(height: 16),
      Text(
        'Simulate an incoming message',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      TextField(
        controller: sender,
        decoration: const InputDecoration(labelText: 'Exact sender'),
      ),
      TextField(
        controller: message,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Incoming message (untrusted content)',
        ),
      ),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: widget.busy
            ? null
            : () => widget.onSimulate(sender.text, message.text),
        child: const Text('Submit simulated message'),
      ),
      Text(
        '${widget.queuedJobs} durable event jobs admitted. See execution evidence above. No message drafts or replies are generated by this example.',
      ),
    ],
  );
  bool _canAct(Map<String, dynamic> job, String action) {
    if (job['cancelled'] == true) return false;
    final remaining = (job['steps'] as List).where(
      (s) => s['state'] != 'Succeeded',
    );
    if (remaining.isEmpty) return false;
    if (action == 'cancel') return true;
    return remaining.first['state'] ==
        (action == 'recover' ? 'Running' : 'Pending');
  }

  String _summary(Map<String, dynamic> job) {
    final steps = job['steps'] as List;
    final done = steps.where((s) => s['state'] == 'Succeeded').length;
    final remaining = steps.where((s) => s['state'] != 'Succeeded');
    final state = job['cancelled'] == true
        ? 'Cancelled'
        : remaining.isEmpty && steps.isNotEmpty
        ? 'Completed'
        : widget.activeJob == job['id']
        ? 'Executing'
        : remaining.isEmpty
        ? 'No steps'
        : remaining.first['state'] == 'Pending'
        ? 'Ready'
        : 'Paused: ${remaining.first['state']}';
    return '$state · $done/${steps.length} steps confirmed';
  }
}

@Preview(name: 'Workflow review (mobile)', size: Size(420, 800))
@Preview(name: 'Workflow review (desktop)', size: Size(1000, 800))
Widget eventTasksPreview() => MaterialApp(
  home: Scaffold(
    body: EventTasksPanel(
      tasks: const [
        {
          'id': 'demo',
          'sender': 'Alice',
          'enabled': true,
          'instructions': 'Draft only if urgent',
        },
      ],
      queuedJobs: 1,
      jobs: const [
        {
          'id': 'clock-job',
          'cancelled': false,
          'steps': [
            {
              'id': 'read',
              'executor': 'host_time',
              'state': 'Succeeded',
              'output': {
                'value': {'status': 'succeeded', 'utc': '2026-10-10T12:00:00Z'},
              },
            },
            {
              'id': 'format',
              'executor': 'host_format_utc',
              'state': 'Pending',
              'output': null,
            },
          ],
        },
      ],
      proposals: const [
        {
          'id': 'clock',
          'goal': 'Read UTC time',
          'trigger': {'source': 'simulation', 'kind': 'tick', 'match': {}},
          'plan': [
            {
              'id': 'read',
              'executor': 'host_time',
              'retry': 'SafeToRepeat',
              'input': {},
            },
          ],
        },
      ],
      busy: false,
      onRefresh: () {},
      onStop: (_) {},
      onSimulate: (_, _) {},
    ),
  ),
);
