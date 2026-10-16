// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'agent_extensions.dart';
import 'infrastructure/rust/rust_initialization.dart';
import 'rust/api/workflow.dart' as native;

/// The host's retry contract, never inferred from model instructions.
enum OmnixRetrySafety { safeToRepeat, requiresReconciliation }

/// The durable native state of one sequential step.
enum OmnixWorkflowStepState {
  pending,
  running,
  succeeded,
  failed,
  needsReconciliation,
}

/// A JSON pointer into an earlier successful step's durable output.
final class OmnixWorkflowOutputBinding {
  const OmnixWorkflowOutputBinding({
    required this.stepId,
    required this.pointer,
  });
  final String stepId;
  final String pointer;
  Map<String, Object?> toJson() => {'step': stepId, 'pointer': pointer};
}

/// An explicit host-selected tool invocation.
final class OmnixWorkflowStep {
  OmnixWorkflowStep({
    required this.id,
    required this.tool,
    required Map<String, Object?> arguments,
    required this.retry,
    Map<String, OmnixWorkflowOutputBinding> outputBindings = const {},
  }) : arguments = Map.unmodifiable(
         jsonDecode(jsonEncode(arguments)) as Map<String, dynamic>,
       ),
       outputBindings = Map.unmodifiable(outputBindings);
  final String id;
  final String tool;
  final Map<String, dynamic> arguments;
  final OmnixRetrySafety retry;

  /// The input arguments resolved by Rust from earlier successful receipts.
  final Map<String, OmnixWorkflowOutputBinding> outputBindings;
  Map<String, Object?> toJson() => {
    'id': id,
    'executor': tool,
    'input': arguments,
    if (outputBindings.isNotEmpty)
      'outputBindings': outputBindings.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
    'retry': retry == OmnixRetrySafety.safeToRepeat
        ? 'SafeToRepeat'
        : 'RequiresReconciliation',
    'state': 'Pending',
    'output': null,
  };
}

/// A versioned sequence of explicit tool steps, separate from execution grants.
///
/// The host supplies a validated plan; this definition does not ask a model to
/// plan or schedule work. Each step finishes before the next step is dispatched.
final class OmnixWorkflowDefinition {
  OmnixWorkflowDefinition({
    required this.id,
    required List<OmnixWorkflowStep> steps,
  }) : steps = List.unmodifiable(steps);
  final String id;
  final List<OmnixWorkflowStep> steps;
  Map<String, Object?> toJson() => {
    'version': steps.any((step) => step.outputBindings.isNotEmpty) ? 2 : 1,
    'id': id,
    'cancelled': false,
    'steps': steps.map((s) => s.toJson()).toList(),
  };
}

/// Host-reported output and state, not a model's claim of success.
final class OmnixWorkflowStepProgress {
  OmnixWorkflowStepProgress._(
    this.id,
    this.tool,
    this.state,
    this.hasOutput,
    this.output,
  );
  factory OmnixWorkflowStepProgress.fromJson(Map<String, dynamic> json) {
    final states = {
      'Pending': OmnixWorkflowStepState.pending,
      'Running': OmnixWorkflowStepState.running,
      'Succeeded': OmnixWorkflowStepState.succeeded,
      'Failed': OmnixWorkflowStepState.failed,
      'NeedsReconciliation': OmnixWorkflowStepState.needsReconciliation,
    };
    final state =
        states[json['state']] ??
        (throw const FormatException('Unknown workflow state.'));
    final envelope = json['output'] as Map<String, dynamic>?;
    return OmnixWorkflowStepProgress._(
      json['id'] as String,
      json['executor'] as String,
      state,
      envelope != null,
      envelope?['value'],
    );
  }
  final String id;
  final String tool;
  final OmnixWorkflowStepState state;
  final bool hasOutput;
  final Object? output;
}

/// A snapshot of native progress after a checkpoint.
final class OmnixWorkflowProgress {
  OmnixWorkflowProgress._(this.id, this.cancelled, this.steps);
  factory OmnixWorkflowProgress.decode(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['version'] != 1 && json['version'] != 2) {
      throw const FormatException('Unsupported workflow snapshot.');
    }
    return OmnixWorkflowProgress._(
      json['id'] as String,
      json['cancelled'] as bool,
      List.unmodifiable(
        (json['steps'] as List).map(
          (s) => OmnixWorkflowStepProgress.fromJson(s as Map<String, dynamic>),
        ),
      ),
    );
  }
  final String id;
  final bool cancelled;
  final List<OmnixWorkflowStepProgress> steps;
  bool get completed =>
      steps.isNotEmpty &&
      steps.every((s) => s.state == OmnixWorkflowStepState.succeeded);
}

/// The transport boundary for native Workflow ownership and execution.
abstract interface class OmnixWorkflowTransport {
  Future<BigInt> open(
    String path,
    String definition,
    String registration,
    BigInt? engine,
    Future<String> Function(String) execute,
  );
  Future<String> progress(BigInt id);
  Future<String> runNext(BigInt id);
  Future<String> runUntilBlocked(BigInt id);
  Future<String> recover(BigInt id);
  Future<String> reconcile(
    BigInt id,
    String step,
    bool succeeded,
    String evidence,
  );
  void cancel(BigInt id);
  Future<void> close(BigInt id);
}

/// Delegates durable step transitions and authorization to root Rust.
final class NativeOmnixWorkflowTransport implements OmnixWorkflowTransport {
  @override
  Future<BigInt> open(
    String path,
    String definition,
    String registration,
    BigInt? engine,
    Future<String> Function(String) execute,
  ) async {
    await ensureRustInitialized();
    return native.workflowOpen(
      databasePath: path,
      definitionJson: definition,
      registrationJson: registration,
      engineId: engine,
      execute: execute,
    );
  }

  @override
  Future<String> progress(BigInt id) => native.workflowProgress(workflowId: id);
  @override
  Future<String> runNext(BigInt id) => native.workflowRunNext(workflowId: id);
  @override
  Future<String> runUntilBlocked(BigInt id) =>
      native.workflowRunUntilBlocked(workflowId: id);
  @override
  Future<String> recover(BigInt id) => native.workflowRecover(workflowId: id);
  @override
  Future<String> reconcile(
    BigInt id,
    String step,
    bool succeeded,
    String evidence,
  ) => native.workflowReconcile(
    workflowId: id,
    stepId: step,
    succeeded: succeeded,
    evidenceJson: evidence,
  );
  @override
  void cancel(BigInt id) => native.workflowCancel(workflowId: id);
  @override
  Future<void> close(BigInt id) => native.workflowClose(workflowId: id);
}

/// An exclusive, durable workflow owner using freshly supplied tools and policy.
///
/// Opening does not execute or recover steps. The database must be dedicated to
/// Workflow and stored in a host-selected private location. Closing releases
/// ownership without cancelling persisted work. Cancellation cannot undo effects.
///
/// Persistence does not keep a process alive or schedule background execution.
/// The host supplies wakeups and calls [runNext] or [runUntilBlocked]. Executors
/// must return explicit outcome evidence; skill guidance alone is not a completed
/// action. Unknown outcomes remain uncertain and may require [recover] followed
/// by host-attested [reconcile] evidence before further execution.
final class OmnixWorkflow {
  OmnixWorkflow._(this._id, this._transport);
  static Future<OmnixWorkflow> open({
    required String databasePath,
    required OmnixWorkflowDefinition definition,
    required OmnixAgentExtensions extensions,
    BigInt? engineId,
    OmnixWorkflowTransport? transport,
  }) async {
    final selected = transport ?? NativeOmnixWorkflowTransport();
    final id = await selected.open(
      databasePath,
      jsonEncode(definition.toJson()),
      extensions.encodeRegistration(),
      engineId,
      extensions.executeWorkflowRequest,
    );
    return OmnixWorkflow._(id, selected);
  }

  final BigInt _id;
  final OmnixWorkflowTransport _transport;
  bool _closed = false;
  void _checkOpen() {
    if (_closed) throw StateError('Workflow is closed.');
  }

  Future<OmnixWorkflowProgress> progress() async {
    _checkOpen();
    return OmnixWorkflowProgress.decode(await _transport.progress(_id));
  }

  /// Executes at most one step under the native grants and approval guard.
  Future<OmnixWorkflowProgress> runNext() async {
    _checkOpen();
    return OmnixWorkflowProgress.decode(await _transport.runNext(_id));
  }

  /// Executes ready steps sequentially until completion, cancellation or blockage.
  Future<OmnixWorkflowProgress> runUntilBlocked() async {
    _checkOpen();
    return OmnixWorkflowProgress.decode(await _transport.runUntilBlocked(_id));
  }

  /// Resolves interrupted states without dispatching any tool.
  Future<OmnixWorkflowProgress> recover() async {
    _checkOpen();
    return OmnixWorkflowProgress.decode(await _transport.recover(_id));
  }

  /// Records host-attested evidence, not an instruction to replay the action.
  Future<OmnixWorkflowProgress> reconcile({
    required String stepId,
    required bool succeeded,
    required Object? evidence,
  }) async {
    _checkOpen();
    return OmnixWorkflowProgress.decode(
      await _transport.reconcile(_id, stepId, succeeded, jsonEncode(evidence)),
    );
  }

  /// Requests cooperative cancellation; active execution checkpoints on return.
  void cancel() {
    _checkOpen();
    _transport.cancel(_id);
  }

  /// Releases ownership after execution has settled, without cancelling the job.
  Future<void> close() async {
    if (_closed) return;
    await _transport.close(_id);
    _closed = true;
  }
}
