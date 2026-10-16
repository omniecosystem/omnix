// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
import 'dart:convert';

/// Executes a granted host tool and returns JSON-encodable evidence.
///
/// The native bridge waits up to 30 seconds for a callback. A timeout or native
/// cancellation does not undo external effects or stop an already running Dart
/// handler. Keep operations bounded and report their actual outcome.
typedef OmnixToolHandler = Future<Object?> Function(OmnixToolRequest request);

/// Reviews one tool request without executing it or granting new capabilities.
typedef OmnixToolApprovalHandler =
    Future<bool> Function(OmnixToolRequest request);

/// The host-selected review mode, separate from tool grants and OS permissions.
enum OmnixAutonomyMode { reviewEveryCall, scopedAssistance, delegatedScope }

/// Review requirements enforced by the Rust tool registry.
///
/// [alwaysReview] overrides [automaticTools]. Delegated scope requires a bounded
/// call budget and lifetime; exhausting either returns calls to host review.
final class OmnixApprovalPolicy {
  OmnixApprovalPolicy({
    required this.mode,
    List<String> automaticTools = const [],
    List<String> alwaysReview = const [],
    this.maxAutomaticCalls,
    this.validForSeconds,
  }) : automaticTools = List.unmodifiable(automaticTools),
       alwaysReview = List.unmodifiable(alwaysReview) {
    if (mode == OmnixAutonomyMode.delegatedScope &&
        (maxAutomaticCalls == null ||
            maxAutomaticCalls! < 1 ||
            maxAutomaticCalls! > 32 ||
            validForSeconds == null ||
            validForSeconds! < 1 ||
            validForSeconds! > 3600)) {
      throw ArgumentError(
        'Delegated scope requires 1–32 automatic calls and a 1–3600 second lifetime.',
      );
    }
    if (mode != OmnixAutonomyMode.delegatedScope &&
        (maxAutomaticCalls != null || validForSeconds != null)) {
      throw ArgumentError('Automatic budgets apply only to delegated scope.');
    }
  }
  final OmnixAutonomyMode mode;
  final List<String> automaticTools;
  final List<String> alwaysReview;
  final int? maxAutomaticCalls;
  final int? validForSeconds;
  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'automaticTools': automaticTools,
    'alwaysReview': alwaysReview,
    if (maxAutomaticCalls != null) 'maxAutomaticCalls': maxAutomaticCalls,
    if (validForSeconds != null) 'validForSeconds': validForSeconds,
  };
}

/// A native request correlated with a host response by [requestId].
final class OmnixToolRequest {
  OmnixToolRequest.fromJson(Map<String, dynamic> json)
    : requestId = json['requestId'] as String,
      callId = json['callId'] as String?,
      toolName = json['toolName'] as String,
      arguments = Map.unmodifiable(json['arguments'] as Map<String, dynamic>);
  final String requestId;

  /// The native call identity, stable across Workflow recovery when supplied.
  final String? callId;
  final String toolName;
  final Map<String, dynamic> arguments;
}

/// A tool declaration paired with its host-supplied executor.
///
/// The native bridge accepts closed object schemas with at most 16 scalar
/// fields: `string`, `boolean`, `integer` or `number`, with optional field
/// descriptions. Nested objects, arrays and additional JSON Schema constraints
/// are unsupported. The executor remains responsible for semantic validation.
final class OmnixHostTool {
  OmnixHostTool({
    required this.name,
    required this.description,
    required Map<String, Object?> parameters,
    required this.execute,
  }) : parameters = Map.unmodifiable(
         jsonDecode(jsonEncode(parameters)) as Map<String, dynamic>,
       );
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final OmnixToolHandler execute;
  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'parameters': parameters,
  };
}

/// Host-supplied instructions and tool dependencies, not executable code.
///
/// Hosts load skill files and any examples into [instructions]. Selecting or
/// loading a skill never grants its [requiredTools].
final class OmnixSkill {
  OmnixSkill({
    required this.name,
    required this.description,
    required this.instructions,
    List<String> requiredTools = const [],
  }) : requiredTools = List.unmodifiable(requiredTools);
  factory OmnixSkill.fromJson(Map<String, dynamic> json) => OmnixSkill(
    name: json['name'] as String,
    description: json['description'] as String,
    instructions: json['instructions'] as String,
    requiredTools: (json['requiredTools'] as List).cast<String>(),
  );
  final String name;
  final String description;
  final String instructions;
  final List<String> requiredTools;
  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'instructions': instructions,
    'requiredTools': requiredTools,
  };
}

/// Host capabilities supplied to the Rust-owned agent loop.
///
/// [tools] provide declarations and executors; [skills] provide guidance.
/// [grants] select accessible tools, and [selectedSkills] select discoverable
/// guidance whose dependencies must be granted. Registration alone grants nothing.
///
/// Without [approvalPolicy], granted tools run without an additional Omnix
/// approval prompt. Host checks and OS permissions still apply. When a policy
/// requests review, a missing or throwing [approve] callback refuses the call.
final class OmnixAgentExtensions {
  OmnixAgentExtensions({
    List<OmnixHostTool> tools = const [],
    List<OmnixSkill> skills = const [],
    required List<String> grants,
    List<String> selectedSkills = const [],
    this.approvalPolicy,
    this.approve,
    this.enableImages = false,
    this.enableAudio = false,
    this.maxRounds = 4,
  }) : tools = List.unmodifiable(tools),
       skills = List.unmodifiable(skills),
       grants = List.unmodifiable(grants),
       selectedSkills = List.unmodifiable(selectedSkills) {
    if (maxRounds < 1 || maxRounds > 32) {
      throw ArgumentError('Agent maxRounds must be from 1 to 32.');
    }
    final names = <String>{};
    for (final tool in tools) {
      if (!names.add(tool.name)) throw ArgumentError('Duplicate host tool.');
    }
  }
  final List<OmnixHostTool> tools;
  final List<OmnixSkill> skills;
  final List<String> grants;
  final List<String> selectedSkills;
  final OmnixApprovalPolicy? approvalPolicy;
  final OmnixToolApprovalHandler? approve;
  final bool enableImages;
  final bool enableAudio;

  /// The maximum tool-bearing model rounds in one native agent turn.
  ///
  /// The native loop also limits the turn to 32 calls, regardless of this budget.
  final int maxRounds;
  String encodeRegistration() => jsonEncode({
    'tools': tools.map((t) => t.toJson()).toList(),
    'skills': skills.map((s) => s.toJson()).toList(),
    'grants': grants,
    'selectedSkills': selectedSkills,
    'maxRounds': maxRounds,
    if (approvalPolicy != null) 'approvalPolicy': approvalPolicy!.toJson(),
    if (enableImages) 'images': true,
    if (enableAudio) 'audio': true,
  });

  /// Dispatches a native callback and sanitizes thrown handler errors.
  ///
  /// This bridge adapter does not run the agent loop or enforce its review policy
  /// independently; the native registry does so before requesting execution.
  Future<String> executeRequest(String raw) => _executeRequest(raw, false);

  /// Reports thrown Workflow handlers as uncertain rather than proven failures.
  ///
  /// A handler may throw after an external effect. Explicit host-returned failure
  /// evidence is still preserved, but an exception cannot prove nothing happened.
  Future<String> executeWorkflowRequest(String raw) =>
      _executeRequest(raw, true);
  Future<String> _executeRequest(String raw, bool durable) async {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final request = OmnixToolRequest.fromJson(decoded);
    if (decoded['phase'] == 'approval') {
      var approved = false;
      if (approvalPolicy != null &&
          (grants.contains(request.toolName) ||
              (request.toolName == 'load_skill' &&
                  selectedSkills.isNotEmpty))) {
        try {
          approved = await approve?.call(request) ?? false;
        } catch (_) {
          approved = false;
        }
      }
      return jsonEncode({
        'requestId': request.requestId,
        'result': {'approved': approved},
      });
    }
    if (decoded['phase'] != null) {
      throw StateError('Unknown host request phase.');
    }
    final matches = tools.where((t) => t.name == request.toolName);
    if (!grants.contains(request.toolName) || matches.length != 1) {
      throw StateError('Host tool is not granted.');
    }
    Object? result;
    try {
      result = await matches.single.execute(request);
      return jsonEncode({'requestId': request.requestId, 'result': result});
    } catch (_) {
      result = {
        'status': durable ? 'interrupted' : 'failed',
        'error': 'Host tool failed.',
      };
    }
    return jsonEncode({'requestId': request.requestId, 'result': result});
  }
}
