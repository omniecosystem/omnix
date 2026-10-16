import 'package:test/test.dart';
import 'package:omnix/omnix.dart';
import 'package:omnix_example/features/home/data/services/tool_policy.dart';

void main() {
  test('scoped navigation and preparation are automatic only when supplied', () {
    final policy = exampleToolPolicy(
      mode: OmnixAutonomyMode.scopedAssistance,
      android: true,
      knowledge: true,
      email: true,
    );
    expect(
      policy.automaticTools,
      containsAll([
        'host_time',
        'host_device_info',
        'host_battery_status',
        'host_share_text',
        'host_open_app',
        'host_prepare_calendar_event',
        'prepare_email_intent',
        'search_knowledge',
      ]),
    );
    expect(policy.alwaysReview, isEmpty);
    expect(policy.automaticTools, isNot(contains('send_email')));
    final minimal = exampleToolPolicy(
      mode: OmnixAutonomyMode.scopedAssistance,
      android: false,
      knowledge: false,
      email: false,
    );
    // Saving an inactive proposal is allowed; accepting/running it is separate.
    expect(minimal.automaticTools, [
      'host_time',
      'host_propose_event_task',
      'host_inspect_event_tasks',
      'host_stop_event_task',
      'host_accept_event_task',
      'host_start_event_task',
      'host_run_workflow_job',
      'host_execute_event_task',
      'load_skill',
    ]);
  });
  test('review-every-call remains available without broadening grants', () {
    final policy = exampleToolPolicy(
      mode: OmnixAutonomyMode.reviewEveryCall,
      android: true,
      knowledge: false,
      email: false,
    );
    expect(policy.mode, OmnixAutonomyMode.reviewEveryCall);
    expect(policy.automaticTools, isNot(contains('search_knowledge')));
    expect(policy.automaticTools, isNot(contains('prepare_email_intent')));
  });
}
