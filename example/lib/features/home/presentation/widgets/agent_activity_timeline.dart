import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:omnix_example/features/home/domain/agent_activity.dart';

class AgentActivityTimeline extends StatelessWidget {
  const AgentActivityTimeline({super.key, required this.activities});
  final List<AgentActivity> activities;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final running = activities.any(
      (a) => a.state == AgentActivityState.running,
    );
    return ExpansionTile(
      initiallyExpanded: running,
      tilePadding: EdgeInsets.zero,
      leading: Icon(Icons.account_tree_outlined, color: colors.primary),
      title: const Text('Tool activity'),
      subtitle: Text(
        running ? 'Working on your request' : '${activities.length} tool steps',
      ),
      children: [
        for (var index = 0; index < activities.length; index++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 32,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child:
                            activities[index].state ==
                                AgentActivityState.running
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                switch (activities[index].state) {
                                  AgentActivityState.completed =>
                                    Icons.check_circle_outline,
                                  AgentActivityState.cancelled =>
                                    Icons.stop_circle_outlined,
                                  AgentActivityState.failed =>
                                    Icons.error_outline,
                                  AgentActivityState.running =>
                                    Icons.pending_outlined,
                                },
                                size: 18,
                                color:
                                    activities[index].state ==
                                        AgentActivityState.failed
                                    ? colors.error
                                    : colors.primary,
                              ),
                      ),
                      if (index < activities.length - 1)
                        Expanded(
                          child: VerticalDivider(color: colors.outlineVariant),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activities[index].label,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        Text(
                          activities[index].outcomeStatus ??
                              switch (activities[index].state) {
                                AgentActivityState.running => 'Running',
                                AgentActivityState.completed => 'Completed',
                                AgentActivityState.cancelled =>
                                  'Stopped before completion',
                                AgentActivityState.failed => 'Failed',
                              },
                          style: TextStyle(
                            color:
                                activities[index].state ==
                                    AgentActivityState.failed
                                ? colors.error
                                : colors.onSurfaceVariant,
                          ),
                        ),
                        if (activities[index].reason != null)
                          Text(activities[index].reason!),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

@Preview(name: 'Agent tool timeline', size: Size(420, 350))
Widget agentActivityPreview() => MaterialApp(
  theme: ThemeData.dark(),
  home: const Scaffold(
    body: Padding(
      padding: EdgeInsets.all(16),
      child: AgentActivityTimeline(
        activities: [
          AgentActivity(
            'host_prepare_calendar_event',
            AgentActivityState.failed,
            outcomeStatus: 'invalid_arguments',
            reason: 'Explicit timezone required',
          ),
          AgentActivity(
            'host_prepare_calendar_event',
            AgentActivityState.running,
          ),
        ],
      ),
    ),
  ),
);
