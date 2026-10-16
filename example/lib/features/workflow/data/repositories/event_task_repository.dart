import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:omnix/omnix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../../home/data/services/device_tools.dart';

class EventTaskRepository {
  EventTaskRepository({
    this.taskStore,
    this.android,
    this.executionPolicy,
    this.approve,
    this.backgroundTools,
  });
  final OmnixApprovalPolicy? executionPolicy;
  final OmnixToolApprovalHandler? approve;
  final List<OmnixHostTool>? backgroundTools;
  final _startRequests = <String, String>{};
  final _foregroundRequests = <String, Future<Object?>>{};
  bool _foregroundBusy = false;
  int _cancellationEpoch = 0;
  final bool? android;
  bool get _android =>
      android ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
  Map<String, String> get executionContracts => {
    for (final entry in {
      ...retryContracts,
      if (_android) ...ExampleDeviceTools.workflowRetryContracts,
    }.entries)
      if (backgroundTools == null ||
          backgroundTools!.any((tool) => tool.name == entry.key))
        entry.key: entry.value,
  };
  List<OmnixHostTool> get executionTools =>
      backgroundTools ??
      [
        clockTool,
        formatUtcTool,
        if (_android)
          ...const ExampleDeviceTools(engineAuthorized: true).workflowTools,
      ];
  Map<String, Object?> get executionSchemas => {
    for (final tool in executionTools) tool.name: tool.parameters,
  };
  // One consumer-owned catalogue used at proposal and acceptance boundaries.
  static const retryContracts = {
    'host_time': 'SafeToRepeat',
    'host_format_utc': 'SafeToRepeat',
  };
  final Future<OmnixEventTasks> Function()? taskStore;
  OmnixWorkflow? _active;
  void cancelActive() {
    _cancellationEpoch++;
    _active?.cancel();
  }

  Future<OmnixEventTasks> _store() async {
    final supplied = taskStore;
    if (supplied != null) return supplied();
    final folder = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'event-tasks-v2'),
    );
    await folder.create(recursive: true);
    return OmnixEventTasks(databasePath: p.join(folder.path, 'tasks.sqlite'));
  }

  static String identity() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<Map<String, dynamic>> list() async =>
      (await _store()).command({'operation': 'list'});
  Future<Map<String, dynamic>> stop(String id) async =>
      (await _store()).command({'operation': 'stop', 'id': id});
  List<OmnixHostTool> get managementTools => [inspectTool, stopTool];
  List<OmnixHostTool> get executionManagementTools => [
    if (_android) scheduleTool,
    executeTaskTool,
    acceptTool,
    startTool,
    runTool,
  ];
  static const backgroundExecutors = {
    'host_battery_status',
    'host_notify_text',
  };
  static bool backgroundCompatible(Object? plan) =>
      plan is List &&
      plan.isNotEmpty &&
      plan.every(
        (step) => step is Map && backgroundExecutors.contains(step['executor']),
      );

  OmnixHostTool get scheduleTool => OmnixHostTool(
    name: 'host_schedule_event_task',
    description:
        'When explicitly requested, accept and schedule a saved battery/notification workflow to run in the Android background after delaySeconds (10–86400). Use 60 for a one-minute test. Android can delay it; not an exact alarm. Do NOT call host_execute_event_task for delayed requests. Only battery reads and notifications are supported in background.',
    parameters: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
        'delaySeconds': {'type': 'integer'},
      },
      'required': ['id', 'delaySeconds'],
      'additionalProperties': false,
    },
    execute: (request) async {
      final delay = request.arguments['delaySeconds'];
      if (delay is! int || delay < 10 || delay > 86400) {
        return {
          'status': 'invalid_arguments',
          'reason': 'delaySeconds must be 10–86400.',
        };
      }
      final policy = executionPolicy;
      if (policy != null &&
          (policy.mode != OmnixAutonomyMode.scopedAssistance ||
              !backgroundExecutors.every(
                (name) =>
                    policy.automaticTools.contains(name) &&
                    !policy.alwaysReview.contains(name),
              ))) {
        return {
          'status': 'blocked',
          'reason':
              'Background tools need scoped automatic authorization. Interactive review/delegation cannot be silently bypassed.',
        };
      }
      final id = request.arguments['id'] as String;
      final saved = await inspection(id);
      final tasks = saved['tasks'];
      if (saved['status'] != 'succeeded' ||
          tasks is! List ||
          tasks.length != 1 ||
          !backgroundCompatible((tasks.single as Map)['plan'])) {
        return {
          'status': 'blocked',
          'reason':
              'Only a complete saved battery/notification plan can run in background.',
        };
      }
      final task = tasks.single as Map;
      if (task['jobsTotal'] != 0) {
        return {
          'status': 'existing_run',
          'reason':
              'A job already exists. Inspect it; no new schedule was created.',
        };
      }
      if (task['phase'] == 'Proposed') {
        final accepted = await accept(id);
        if (accepted['status'] != 'succeeded') return accepted;
      } else if (task['futureTriggersEnabled'] != true) {
        return {'status': 'blocked', 'reason': 'Task is disabled.'};
      }
      final started = await startTool.execute(request) as Map;
      if (started['status'] != 'succeeded') return started;
      final jobs = started['jobIds'] as List;
      if (jobs.length != 1) return {'status': 'blocked'};
      try {
        return await const MethodChannel(
          'xyz.omniecosystem.omnix/agent_host',
        ).invokeMethod<Object?>('scheduleWorkflow', {
          'taskId': id,
          'jobId': jobs.single,
          'delaySeconds': delay,
        });
      } catch (_) {
        return {
          'status': 'unavailable',
          'reason':
              'Scheduling not confirmed; inspect the saved job. Do not start a replacement.',
        };
      }
    },
  );
  Future<Map<String, dynamic>> inspection(String id) =>
      _managementCommand({'operation': 'inspect', 'id': id});

  // A consumer convenience boundary, not a second workflow executor. Each
  // catalogue transition is validated/persisted by Rust; runTool delegates the
  // complete step loop, checkpoints and per-action approval to Rust too.
  OmnixHostTool get executeTaskTool => OmnixHostTool(
    name: 'host_execute_event_task',
    description:
        'When the user asks to create AND RUN a workflow, call this immediately after saving its proposal, in the SAME turn. Accepts that exact plan and runs it now; no follow-up prompt, simulated tick or Workflow screen is required. Also resumes one existing pending job without starting a replacement. Never use for propose-only requests. Existing completed, failed or uncertain runs are reported without replay. Individual actions retain host approval and device permissions.',
    parameters: _idSchema('Exact saved proposal or task ID, never a job ID.'),
    execute: (request) {
      final key = jsonEncode([
        request.callId,
        request.requestId,
        request.arguments['id'],
      ]);
      if (!_foregroundRequests.containsKey(key) &&
          _foregroundRequests.length >= 64) {
        return Future.value({
          'status': 'unavailable',
          'reason': 'Conversation run limit reached. Inspect saved jobs.',
        });
      }
      return _foregroundRequests.putIfAbsent(
        key,
        () => _foregroundRun(request),
      );
    },
  );

  Future<Object?> _foregroundRun(OmnixToolRequest request) async {
    if (_foregroundBusy || _active != null) {
      return {
        'status': 'blocked',
        'reason': 'A foreground run is already active.',
      };
    }
    _foregroundBusy = true;
    try {
      return await _executeTask(request, _cancellationEpoch);
    } catch (_) {
      return {
        'status': 'unavailable',
        'reason': 'Outcome not confirmed. Inspect saved jobs before retrying.',
      };
    } finally {
      _foregroundBusy = false;
    }
  }

  Future<Object?> _executeTask(OmnixToolRequest request, int epoch) async {
    bool cancelled() => epoch != _cancellationEpoch;
    const cancelledReceipt = {
      'status': 'cancelled',
      'reason': 'Execution stopped. Inspect saved state before continuing.',
    };
    final details = await inspection(request.arguments['id'] as String);
    if (cancelled()) return cancelledReceipt;
    if (details['status'] != 'succeeded') return details;
    final tasks = details['tasks'] as List;
    if (tasks.length != 1) {
      return {'status': 'not_found', 'reason': 'Exact saved plan not found.'};
    }
    final task = tasks.single as Map;
    if (task['planOmitted'] == true || task['plan'] is! List) {
      return {
        'status': 'blocked',
        'reason':
            'Full plan unavailable. Review it in Workflow before running.',
      };
    }
    final jobs = task['jobs'] as List;
    String? jobId;
    if (task['jobsTotal'] != 0) {
      // Never turn an uncertain response into another external action. The
      // explicit start tool remains available for an intentional *new* run.
      if (task['jobsTotal'] == 1 &&
          jobs.length == 1 &&
          (jobs.single as Map)['state'] == 'Pending') {
        jobId = (jobs.single as Map)['id'] as String;
      } else {
        return {
          'status': 'existing_run',
          'taskId': task['id'],
          'jobs': jobs,
          'jobsOmitted': task['jobsOmitted'],
          'reason':
              'A run already exists. Report its saved evidence; no replacement was started. Use explicit job management for further work.',
        };
      }
    }
    if (task['phase'] == 'Proposed') {
      final accepted = await acceptTool.execute(request) as Map;
      if (cancelled()) return cancelledReceipt;
      if (accepted['status'] != 'succeeded') return accepted;
    } else if (task['futureTriggersEnabled'] != true) {
      return {'status': 'blocked', 'reason': 'This task is disabled.'};
    }
    if (jobId == null) {
      final started = await startTool.execute(request) as Map;
      if (cancelled()) return cancelledReceipt;
      if (started['status'] != 'succeeded') return started;
      final ids = started['jobIds'] as List;
      if (ids.length != 1) {
        return {
          'status': 'blocked',
          'reason': 'One admitted job was expected.',
        };
      }
      jobId = ids.single as String;
    }
    if (cancelled()) return cancelledReceipt;
    return runTool.execute(
      OmnixToolRequest.fromJson({
        'requestId': request.requestId,
        'callId': request.callId,
        'toolName': runTool.name,
        'arguments': {'id': jobId},
      }),
    );
  }

  static Map<String, Object?> _idSchema(String description) => {
    'type': 'object',
    'properties': {
      'id': {'type': 'string', 'description': description},
    },
    'required': ['id'],
    'additionalProperties': false,
  };
  OmnixHostTool get acceptTool => OmnixHostTool(
    name: 'host_accept_event_task',
    description:
        'Accept the exact saved proposal only when the user asks to activate it. Inspect its full plan first; ask if ambiguous or omitted. Acceptance enables future host events, not a listener or execution.',
    parameters: _idSchema(
      'Exact proposal ID returned by proposal or inspection.',
    ),
    execute: (request) async {
      final result = await _managementCommand({
        'operation': 'accept',
        'id': request.arguments['id'],
        'contracts': executionContracts,
        'schemas': executionSchemas,
      });
      if (result['status'] != 'succeeded') return result;
      return {
        'status': 'succeeded',
        'accepted': result['accepted'],
        'taskId': (result['task'] as Map?)?['id'] ?? request.arguments['id'],
        'executionStarted': false,
        'backgroundListenerInstalled': false,
      };
    },
  );
  OmnixHostTool get startTool => OmnixHostTool(
    name: 'host_start_event_task',
    description:
        'Queue ONE manual foreground run of an accepted enabled task, only when requested. This does not start a timer or trigger other tasks. Returns job IDs; then use host_run_workflow_job. Inspect existing jobs first; do not queue another run to retry a failed/uncertain action.',
    parameters: _idSchema(
      'Exact accepted task ID from inspection or acceptance.',
    ),
    execute: (request) async {
      // Re-delivery of the same callback uses the same native admission identity.
      final key = jsonEncode([
        request.callId,
        request.requestId,
        request.arguments['id'],
      ]);
      if (!_startRequests.containsKey(key) && _startRequests.length >= 64) {
        return {
          'status': 'unavailable',
          'reason':
              'This conversation has reached its manual admission limit. Inspect saved jobs.',
        };
      }
      final eventId = _startRequests.putIfAbsent(key, identity);
      final result = await _managementCommand({
        'operation': 'start',
        'id': eventId,
        'taskId': request.arguments['id'],
      });
      if (result['status'] != 'succeeded') return result;
      return {
        'status': 'succeeded',
        'duplicate': result['duplicate'],
        'taskId': request.arguments['id'],
        'jobIds': (result['jobs'] as List)
            .map((job) => (job as Map)['id'])
            .toList(),
        'executionStarted': false,
        'backgroundListenerInstalled': false,
      };
    },
  );
  OmnixHostTool get runTool => OmnixHostTool(
    name: 'host_run_workflow_job',
    description:
        'Run ready steps of an exact admitted job in the foreground, waiting for and saving each result before the next step. Completed steps are not repeated. Failed/uncertain jobs pause without automatic recovery. Report actual receipts, never claim sharing or saving merely from editor_opened.',
    parameters: _idSchema(
      'Exact job ID returned by starting or inspecting a task, not the task ID.',
    ),
    execute: (request) async {
      try {
        final progress = await act(request.arguments['id'] as String, 'runAll');
        return {
          'status': progress.cancelled
              ? 'cancelled'
              : progress.completed
              ? 'succeeded'
              : 'blocked',
          'jobId': progress.id,
          'completed': progress.completed,
          'cancelled': progress.cancelled,
          'steps': progress.steps
              .map(
                (step) => {
                  'id': step.id,
                  'tool': step.tool,
                  'state': step.state.name,
                  'hasOutput': step.hasOutput,
                  if (step.hasOutput &&
                      utf8.encode(jsonEncode(step.output)).length <= 1000)
                    'output': step.output,
                  if (step.hasOutput &&
                      utf8.encode(jsonEncode(step.output)).length > 1000)
                    'outputOmitted': true,
                },
              )
              .toList(),
          'evidenceScope':
              'Host receipts only. editor_opened confirms handoff, not saving or sending.',
        };
      } catch (_) {
        return {
          'status': 'unavailable',
          'reason':
              'Execution outcome was not confirmed. Inspect the saved job before retrying; do not queue a replacement run.',
        };
      }
    },
  );

  OmnixHostTool get inspectTool => OmnixHostTool(
    name: 'host_inspect_event_tasks',
    description:
        'Read saved proposals, tasks and durable job evidence. Use empty id to discover IDs, then an exact returned id for details. Does not execute work. Load workflow-management for evidence semantics.',
    parameters: {
      'type': 'object',
      'properties': {
        'id': {
          'type': 'string',
          'description': 'Exact saved task ID, or empty string to list tasks.',
        },
        'offset': {
          'type': 'integer',
          'description': 'Optional pagination offset returned by inspection.',
        },
      },
      'required': ['id'],
      'additionalProperties': false,
    },
    execute: (request) => _managementCommand({
      'operation': 'inspect',
      'id': request.arguments['id'],
      if (request.arguments.containsKey('offset'))
        'offset': request.arguments['offset'],
    }),
  );

  OmnixHostTool get stopTool => OmnixHostTool(
    name: 'host_stop_event_task',
    description:
        'Disable future triggers for an accepted task only when the user requests it. Does not cancel existing jobs or undo effects. Use an exact ID obtained from inspection, never guess.',
    parameters: {
      'type': 'object',
      'properties': {
        'id': {
          'type': 'string',
          'description': 'Exact accepted task ID from inspection.',
        },
      },
      'required': ['id'],
      'additionalProperties': false,
    },
    execute: (request) => _managementCommand({
      'operation': 'stop',
      'id': request.arguments['id'],
    }),
  );

  Future<Map<String, dynamic>> _managementCommand(
    Map<String, Object?> command,
  ) async {
    try {
      return await (await _store()).command(command);
    } catch (_) {
      return {
        'status': 'unavailable',
        'reason':
            'Task service unavailable. No status or stop confirmation was obtained; refresh Workflow before retrying.',
      };
    }
  }

  Future<Map<String, dynamic>> accept(String id) async =>
      (await _store()).command({
        'operation': 'accept',
        'id': id,
        'contracts': executionContracts,
        'schemas': executionSchemas,
      });
  Future<Map<String, dynamic>> tick() async => (await _store()).command({
    'operation': 'event',
    'id': identity(),
    'source': 'simulation',
    'kind': 'tick',
    'metadata': <String, Object?>{},
    'payload': <String, Object?>{},
  });

  // Qualification capability supplied by this consumer. No model is required
  // to execute it; the existing Rust agent can propose plans using it.
  static OmnixHostTool get clockTool => OmnixHostTool(
    name: 'host_time',
    description: 'Read the current UTC time. Read-only.',
    parameters: {
      'type': 'object',
      'properties': <String, Object?>{},
      'required': <String>[],
      'additionalProperties': false,
    },
    execute: (_) async => {
      'status': 'succeeded',
      'utc': DateTime.now().toUtc().toIso8601String(),
    },
  );
  // Harmless formatting callback supplied by the consumer, not a Rust builtin.
  static OmnixHostTool get formatUtcTool => OmnixHostTool(
    name: 'host_format_utc',
    description:
        'Format a UTC value from a prior clock receipt. Does not read the clock or perform external actions.',
    parameters: {
      'type': 'object',
      'properties': {
        'utc': {'type': 'string'},
      },
      'required': ['utc'],
      'additionalProperties': false,
    },
    execute: (request) async {
      final utc = DateTime.tryParse(request.arguments['utc'] as String);
      if (utc == null || !utc.isUtc) {
        return {
          'status': 'invalid_arguments',
          'reason': 'Expected an ISO UTC timestamp.',
          'executionStarted': false,
        };
      }
      return {
        'status': 'succeeded',
        'text': 'Saved UTC reading: ${utc.toIso8601String()}',
        'utc': utc.toIso8601String(),
      };
    },
  );
  Future<OmnixWorkflowProgress> act(String id, String operation) async {
    if (_active != null) throw StateError('A workflow is already running.');
    final epoch = _cancellationEpoch;
    final store = await _store();
    final owner = await store.openJob(
      id: id,
      extensions: OmnixAgentExtensions(
        tools: executionTools,
        grants: executionContracts.keys.toList(),
        approve: approve,
        approvalPolicy:
            executionPolicy ??
            OmnixApprovalPolicy(
              mode: OmnixAutonomyMode.scopedAssistance,
              automaticTools: executionContracts.keys.toList(),
            ),
      ),
    );
    _active = owner;
    try {
      if (epoch != _cancellationEpoch) {
        owner.cancel();
        return await owner.progress();
      }
      if (operation == 'recover') return await owner.recover();
      if (operation == 'cancel') {
        owner.cancel();
        return await owner.progress();
      }
      if (operation == 'runAll') return await owner.runUntilBlocked();
      if (operation != 'run') throw ArgumentError.value(operation);
      return await owner.runNext();
    } finally {
      _active = null;
      await owner.close();
    }
  }

  OmnixHostTool get proposeTool => OmnixHostTool(
    name: 'host_propose_event_task',
    description:
        'Save an inactive durable workflow proposal. For propose-only requests stop here. If the user already asked to create and run it, continue with host_execute_event_task using the returned task ID in this same turn; do not ask for a second prompt. '
        'Available execution capabilities: host_time with empty input; host_format_utc requires a utc string. '
        '${_android ? 'Android also provides host_battery_status with empty input returning report; host_notify_text requires text and posts a notification; host_share_text requires text and opens a chooser only; host_open_app takes application=settings. Bind text from /report on the battery step. For delayed battery notifications load scheduled-device-report, then call host_schedule_event_task instead of executing now. ' : ''}'
        'For a test trigger use {"source":"simulation","kind":"tick","match":{}}. '
        'planJson is a JSON array of steps, each with id, executor and input. '
        'Do not supply retry: the host determines recovery safety. '
        'For saved data flow use outputBindings: {"utc":{"step":"read","pointer":"/utc"}} on a later step with empty input. '
        'Load the workflow-planning skill for exact examples. '
        'Use distinct step IDs. No app monitoring or timers are enabled.',
    parameters: {
      'type': 'object',
      'properties': {
        'goal': {'type': 'string', 'description': 'The requested goal.'},
        'triggerJson': {
          'type': 'string',
          'description': 'JSON trigger object with source, kind and match.',
        },
        'planJson': {
          'type': 'string',
          'description':
              'JSON array of steps: [{"id":"one","executor":"host_time","input":{}}]. Omit retry.',
        },
      },
      'required': ['goal', 'triggerJson', 'planJson'],
      'additionalProperties': false,
    },
    execute: (request) async {
      final Object? trigger, plan;
      try {
        trigger = jsonDecode(request.arguments['triggerJson'] as String);
        plan = jsonDecode(request.arguments['planJson'] as String);
      } on FormatException {
        return {
          'status': 'invalid_arguments',
          'reason':
              'triggerJson must be a JSON object and planJson a JSON array. No plan was saved.',
        };
      }
      try {
        return await (await _store()).command({
          'operation': 'propose',
          'contracts': executionContracts,
          'schemas': executionSchemas,
          'task': {
            'id': identity(),
            'goal': request.arguments['goal'],
            'trigger': trigger,
            'plan': plan,
          },
        });
      } catch (_) {
        // Native/OS errors may include private paths. Do not return them to
        // the model or console, and do not mislabel them as invalid arguments.
        return {
          'status': 'unavailable',
          'code': 'TASK_PROPOSAL_SERVICE_UNAVAILABLE',
          'reason':
              'Task storage or native service unavailable. Proposal persistence was not confirmed; refresh saved plans before retrying.',
        };
      }
    },
  );
  Future<Map<String, dynamic>> simulate(String sender, String text) async =>
      (await _store()).command({
        'operation': 'event',
        'id': identity(),
        'source': 'simulation',
        'kind': 'message',
        'metadata': {'sender': sender},
        'payload': {'text': text},
      });
}
