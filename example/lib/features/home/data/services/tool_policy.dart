import 'package:omnix/omnix.dart';

// Consumer choices, not engine defaults. Rust enforces this supplied policy.
OmnixApprovalPolicy exampleToolPolicy({
  required OmnixAutonomyMode mode,
  required bool android,
  required bool knowledge,
  required bool email,
}) => OmnixApprovalPolicy(
  mode: mode,
  automaticTools: [
    'host_time',
    'host_propose_event_task',
    'host_inspect_event_tasks',
    'host_stop_event_task',
    'host_accept_event_task',
    'host_start_event_task',
    'host_run_workflow_job',
    'host_execute_event_task',
    'load_skill',
    if (knowledge) 'search_knowledge',
    if (email) 'prepare_email_intent',
    if (android) ...[
      'host_schedule_event_task',
      'host_notify_text',
      'host_device_info',
      'host_battery_status',
      'host_share_text',
      'host_open_app',
      'host_prepare_calendar_event',
    ],
  ],
);
