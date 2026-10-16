import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:omnix/omnix.dart';
import 'device_tools.dart';
import 'tool_policy.dart';
import '../../presentation/services/tool_approval.dart';
import 'package:omnix_example/features/workflow/data/repositories/event_task_repository.dart';

EventTaskRepository? _homeTasks;

Future<void> cancelExampleDeviceTools() async {
  _homeTasks?.cancelActive();
  exampleToolApproval.cancel();
  if (!kIsWeb && Platform.isAndroid) {
    await const ExampleDeviceTools().cancelPending();
  }
}

Future<OmnixAgentExtensions> exampleAgentExtensions({
  required bool email,
  bool knowledge = true,
  bool images = false,
  bool audio = false,
  OmnixAutonomyMode autonomy = OmnixAutonomyMode.scopedAssistance,
}) async {
  final tasks = EventTaskRepository(
    executionPolicy: OmnixApprovalPolicy(
      mode: autonomy,
      automaticTools: EventTaskRepository(
        android: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      ).executionContracts.keys.toList(),
    ),
    approve: exampleToolApproval.approve,
  );
  _homeTasks = tasks;
  return OmnixAgentExtensions(
    enableImages: images,
    enableAudio: audio,
    approvalPolicy: exampleToolPolicy(
      mode: autonomy,
      android: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      knowledge: knowledge,
      email: email,
    ),
    approve: (request) async {
      String? details;
      if (request.toolName == 'host_execute_event_task' ||
          request.toolName == 'host_accept_event_task') {
        final saved = await tasks.inspection(request.arguments['id'] as String);
        final plans = saved['tasks'] as List?;
        if (saved['status'] != 'succeeded' ||
            plans == null ||
            plans.length != 1 ||
            (plans.single as Map)['plan'] is! List ||
            (plans.single as Map)['planOmitted'] == true) {
          return false;
        }
        details = const JsonEncoder.withIndent('  ').convert(saved);
      }
      return exampleToolApproval.approve(request, details: details);
    },
    tools: [
      tasks.proposeTool,
      ...tasks.managementTools,
      ...tasks.executionManagementTools,
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        ...const ExampleDeviceTools(engineAuthorized: true).tools,
      EventTaskRepository.clockTool,
    ],
    skills: [
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        OmnixSkill(
          name: 'scheduled-device-report',
          description:
              'Schedule a battery report notification in Android background, including one-minute tests.',
          instructions: await rootBundle.loadString(
            'assets/skills/scheduled-device-report/SKILL.md',
          ),
          requiredTools: [
            'host_propose_event_task',
            'host_schedule_event_task',
            'host_battery_status',
            'host_notify_text',
          ],
        ),
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        OmnixSkill(
          name: 'device-report-workflow',
          description:
              'Propose an Android battery-report-to-share-sheet workflow, using saved native data.',
          instructions: await rootBundle.loadString(
            'assets/skills/device-report-workflow/SKILL.md',
          ),
          requiredTools: [
            'host_propose_event_task',
            'host_battery_status',
            'host_share_text',
          ],
        ),
      OmnixSkill(
        name: 'workflow-management',
        description:
            'Inspect, accept, start and execute saved foreground workflows on request; report durable evidence.',
        instructions: await rootBundle.loadString(
          'assets/skills/workflow-management/SKILL.md',
        ),
        requiredTools: [
          'host_inspect_event_tasks',
          'host_stop_event_task',
          'host_accept_event_task',
          'host_start_event_task',
          'host_run_workflow_job',
          'host_execute_event_task',
        ],
      ),
      OmnixSkill(
        name: 'workflow-planning',
        description:
            'Propose durable event tasks using available host capabilities.',
        instructions: await rootBundle.loadString(
          'assets/skills/workflow-planning/SKILL.md',
        ),
        requiredTools: ['host_propose_event_task'],
      ),
      OmnixSkill(
        name: 'current-time',
        description:
            'Answer current date and time questions using the host clock.',
        instructions: await rootBundle.loadString(
          'assets/skills/current-time/SKILL.md',
        ),
        requiredTools: ['host_time'],
      ),
    ],
    grants: [
      'host_propose_event_task',
      'host_inspect_event_tasks',
      'host_stop_event_task',
      'host_accept_event_task',
      'host_start_event_task',
      'host_run_workflow_job',
      'host_execute_event_task',
      if (knowledge) 'search_knowledge',
      'host_time',
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
        'host_schedule_event_task',
        'host_notify_text',
        'host_device_info',
        'host_battery_status',
        'host_share_text',
        'host_open_app',
        'host_prepare_calendar_event',
      ],
      if (email) 'prepare_email_intent',
    ],
    selectedSkills: [
      'current-time',
      'workflow-planning',
      'workflow-management',
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        'scheduled-device-report',
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        'device-report-workflow',
    ],
  );
}
