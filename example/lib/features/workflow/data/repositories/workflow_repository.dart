import 'dart:io';
import 'package:omnix/omnix.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../domain/workflow_backend.dart';

class WorkflowRepository implements WorkflowBackend {
  WorkflowRepository({this.directory});
  final Directory? directory;
  Directory? _root;
  String? _job;
  OmnixWorkflow? _owner;

  Future<Directory> _location() async {
    final root = _root ??=
        directory ??
        Directory(
          p.join(
            (await getApplicationSupportDirectory()).path,
            'workflow-showcase-v1',
          ),
        );
    await root.create(recursive: true);
    return root;
  }

  // This pointer selects the example's current demo; it is not an execution journal.
  Future<void> _select(String id) async {
    final root = await _location();
    final pending = File(p.join(root.path, 'current-job.pending'));
    await pending.writeAsString(id, flush: true);
    await pending.rename(p.join(root.path, 'current-job'));
    _job = id;
  }

  OmnixWorkflowDefinition _definition(String id) => OmnixWorkflowDefinition(
    id: id,
    steps: [
      OmnixWorkflowStep(
        id: 'clock',
        tool: 'host_workflow_clock',
        arguments: {},
        retry: OmnixRetrySafety.safeToRepeat,
      ),
      OmnixWorkflowStep(
        id: 'handoff',
        tool: 'host_workflow_simulation',
        arguments: {},
        retry: OmnixRetrySafety.requiresReconciliation,
      ),
      OmnixWorkflowStep(
        id: 'finish',
        tool: 'host_workflow_finish',
        arguments: {},
        retry: OmnixRetrySafety.safeToRepeat,
      ),
    ],
  );
  OmnixAgentExtensions _extensions() {
    const schema = <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
      'required': <String>[],
      'additionalProperties': false,
    };
    final tools = [
      OmnixHostTool(
        name: 'host_workflow_clock',
        description: 'Read the host clock.',
        parameters: schema,
        execute: (_) async => {
          'status': 'succeeded',
          'utc': DateTime.now().toUtc().toIso8601String(),
        },
      ),
      OmnixHostTool(
        name: 'host_workflow_simulation',
        description:
            'Simulate missing confirmation, without any external action.',
        parameters: schema,
        execute: (_) async {
          await Future<void>.delayed(const Duration(seconds: 2));
          return {
            'status': 'interrupted',
            'reason': 'Simulated lost confirmation. No real action occurred.',
          };
        },
      ),
      OmnixHostTool(
        name: 'host_workflow_finish',
        description: 'Return a local demo completion receipt.',
        parameters: schema,
        execute: (_) async => {
          'status': 'succeeded',
          'note': 'Demo complete. No external action was performed.',
        },
      ),
    ];
    final grants = tools.map((t) => t.name).toList();
    return OmnixAgentExtensions(
      tools: tools,
      grants: grants,
      approvalPolicy: OmnixApprovalPolicy(
        mode: OmnixAutonomyMode.scopedAssistance,
        automaticTools: grants,
      ),
    );
  }

  Future<OmnixWorkflowProgress> _openId(
    String id, {
    bool create = false,
  }) async {
    if (!RegExp(r'^demo-[a-zA-Z0-9_-]{1,100}$').hasMatch(id)) {
      throw const FormatException('Invalid saved demo identity.');
    }
    final root = await _location();
    final jobDirectory = Directory(p.join(root.path, id));
    final databasePath = p.join(jobDirectory.path, 'workflow.sqlite');
    if (!create && !await File(databasePath).exists()) {
      throw StateError(
        'The saved workflow journal is missing. Start a new demo explicitly; missing progress must not replay actions.',
      );
    }
    _owner = await OmnixWorkflow.open(
      databasePath: databasePath,
      definition: _definition(id),
      extensions: _extensions(),
    );
    _job = id;
    return _owner!.progress();
  }

  @override
  Future<OmnixWorkflowProgress> open() async {
    if (_owner != null) return _owner!.progress();
    final root = await _location();
    final pointer = File(p.join(root.path, 'current-job'));
    if (!await pointer.exists()) return newDemo();
    if (await pointer.length() > 128) {
      throw const FormatException('Invalid demo pointer.');
    }
    return _openId((await pointer.readAsString()).trim());
  }

  @override
  Future<OmnixWorkflowProgress> newDemo() async {
    await close();
    final folder = await (await _location()).createTemp('demo-');
    final id = p.basename(folder.path);
    try {
      final result = await _openId(id, create: true);
      await _select(id);
      return result;
    } catch (_) {
      await close();
      rethrow;
    }
  }

  @override
  Future<OmnixWorkflowProgress> reopen() async {
    final id = _job;
    await close();
    return id == null ? open() : _openId(id);
  }

  OmnixWorkflow get _required =>
      _owner ?? (throw StateError('Open the demo first.'));
  @override
  Future<OmnixWorkflowProgress> runNext() => _required.runNext();
  @override
  Future<OmnixWorkflowProgress> recover() => _required.recover();
  @override
  Future<OmnixWorkflowProgress> confirmSimulation() => _required.reconcile(
    stepId: 'handoff',
    succeeded: true,
    evidence: {'simulated': true, 'hostConfirmedDemo': true},
  );
  @override
  void cancel() => _owner?.cancel();
  @override
  Future<void> close() async {
    final owner = _owner;
    if (owner != null) {
      await owner.close();
      _owner = null;
    }
  }
}
