// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';
import 'infrastructure/rust/rust_initialization.dart';
import 'rust/api/tasks.dart' as native;
import 'agent_extensions.dart';
import 'workflow.dart';

/// A headless adapter for Rust-owned task admission and durable job lookup.
///
/// The host supplies events and retry contracts. Rust validates proposals,
/// matches accepted triggers, deduplicates events and persists admitted plans.
/// Admission does not execute tools or install an OS event listener or scheduler.
/// Close a job owner before accessing its database through [command].
class OmnixEventTasks {
  OmnixEventTasks({required this.databasePath, this.dispatch});
  final String databasePath;
  final Future<String> Function(String path, String command)? dispatch;

  /// Opens an admitted job with freshly supplied tools and execution grants.
  ///
  /// Rust resumes its durable checkpoint without replaying completed steps.
  /// Opening neither runs nor recovers steps; close the returned owner before
  /// issuing catalogue commands against the same database.
  Future<OmnixWorkflow> openJob({
    required String id,
    required OmnixAgentExtensions extensions,
    BigInt? engineId,
    OmnixWorkflowTransport? transport,
  }) async {
    final job = await command({'operation': 'job', 'id': id});
    final definition = OmnixWorkflowDefinition(
      id: job['id'] as String,
      steps: (job['steps'] as List).map((value) {
        final step = value as Map<String, dynamic>;
        final retry = switch (step['retry']) {
          'SafeToRepeat' => OmnixRetrySafety.safeToRepeat,
          'RequiresReconciliation' => OmnixRetrySafety.requiresReconciliation,
          _ => throw const FormatException('Unknown retry contract.'),
        };
        return OmnixWorkflowStep(
          id: step['id'] as String,
          tool: step['executor'] as String,
          arguments: step['input'] as Map<String, dynamic>,
          retry: retry,
          outputBindings:
              ((step['outputBindings'] as Map<String, dynamic>?) ?? {}).map((
                key,
                value,
              ) {
                final binding = value as Map<String, dynamic>;
                return MapEntry(
                  key,
                  OmnixWorkflowOutputBinding(
                    stepId: binding['step'] as String,
                    pointer: binding['pointer'] as String,
                  ),
                );
              }),
        );
      }).toList(),
    );
    return OmnixWorkflow.open(
      databasePath: databasePath,
      definition: definition,
      extensions: extensions,
      engineId: engineId,
      transport: transport,
    );
  }

  /// Submits a task-catalogue command for native validation and persistence.
  ///
  /// `propose` stores an inactive plan; `accept` enables its future triggers.
  /// `event` and `start` admit jobs without executing them. `stop` disables future
  /// triggers but does not cancel admitted jobs. Use [openJob] to execute or
  /// recover an admitted job with freshly supplied tools and grants.
  ///
  /// Reuse an event's source and ID only for identical redelivery. A manual start
  /// and a source event targeting the same task must use distinct IDs.
  Future<Map<String, dynamic>> command(Map<String, Object?> request) async {
    final encoded = jsonEncode(request);
    final send = dispatch;
    final String raw;
    if (send != null) {
      raw = await send(databasePath, encoded);
    } else {
      await ensureRustInitialized();
      raw = await native.taskCommand(
        databasePath: databasePath,
        commandJson: encoded,
      );
    }
    return jsonDecode(raw) as Map<String, dynamic>;
  }
}
